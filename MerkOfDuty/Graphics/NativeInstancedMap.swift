import Foundation
import simd

/// Repeated scenery from EXT_mesh_gpu_instancing. Geometry appears once per
/// source node; native Metal draws many placements from a transform buffer.
/// MERKINS1 is a private build-time format, not a generic glTF parser.
enum NativeInstancedMap {
    struct Group {
        let vertices: [GPUVertex]
        let instances: [GPUInstance]
    }

    static func load() -> [Group] {
        guard let url = Bundle.main.url(forResource: NativeLevel.selected.resource("MerkInstances"), withExtension: "bin"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        return decode(data) ?? []
    }

    private static func decode(_ data: Data) -> [Group]? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data)
        guard String(decoding: bytes[0..<8], as: UTF8.self) == "MERKINS1" else { return nil }
        func u32(_ i: Int) -> UInt32 {
            UInt32(bytes[i]) | UInt32(bytes[i+1]) << 8 |
                UInt32(bytes[i+2]) << 16 | UInt32(bytes[i+3]) << 24
        }
        func f32(_ i: Int) -> Float { Float(bitPattern: u32(i)) }
        let count = Int(u32(8))
        guard count <= 1024 else { return nil }
        var cursor = 12
        var groups: [Group] = []
        groups.reserveCapacity(count)
        for _ in 0..<count {
            guard cursor <= bytes.count - 8 else { return nil }
            let n = Int(u32(cursor))
            let m = Int(u32(cursor + 4))
            cursor += 8
            guard n > 0, n <= 3_000_000, m > 0, m <= 100_000 else { return nil }
            let needed = n * 64 + m * 80
            guard needed <= bytes.count - cursor else { return nil }
            var verts: [GPUVertex] = []
            verts.reserveCapacity(n)
            for i in 0..<n {
                let a = cursor + i*64
                verts.append(GPUVertex(
                    position: SIMD3<Float>(f32(a),f32(a+4),f32(a+8)),
                    normal: SIMD3<Float>(f32(a+12),f32(a+16),f32(a+20)),
                    color: SIMD4<Float>(f32(a+24),f32(a+28),f32(a+32),f32(a+36)),
                    uv: SIMD2<Float>(f32(a+40),f32(a+44)),
                    atlasRect: SIMD4<Float>(f32(a+48),f32(a+52),f32(a+56),f32(a+60))
                ))
            }
            cursor += n*64
            var transforms: [GPUInstance] = []
            transforms.reserveCapacity(m)
            for i in 0..<m {
                let a = cursor + i*80
                let matrix = simd_float4x4(columns: (
                    SIMD4<Float>(f32(a),f32(a+4),f32(a+8),f32(a+12)),
                    SIMD4<Float>(f32(a+16),f32(a+20),f32(a+24),f32(a+28)),
                    SIMD4<Float>(f32(a+32),f32(a+36),f32(a+40),f32(a+44)),
                    SIMD4<Float>(f32(a+48),f32(a+52),f32(a+56),f32(a+60))
                ))
                let color = SIMD4<Float>(f32(a+64),f32(a+68),f32(a+72),f32(a+76))
                transforms.append(GPUInstance(model: matrix, tint: color))
            }
            cursor += m*80
            groups.append(Group(vertices: verts, instances: transforms))
        }
        return cursor == bytes.count ? groups : nil
    }
}
