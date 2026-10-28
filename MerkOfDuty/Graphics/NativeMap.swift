import Foundation
import simd

// Native mesh formats:
// MERKMAP1 : 40 packed bytes/vertex (position3 normal3 RGBA4)
// MERKMAP2 : 64 packed bytes/vertex (above + uv2 + atlasRect4)
// Loader expands both into Metal-compatible GPUVertex structs.
enum NativeMap {
    static var isPresent: Bool {
        Bundle.main.url(forResource: "MerkMap", withExtension: "meshbin") != nil
    }

    static func load(resource: String = NativeLevel.selected.resource("MerkMap")) -> [GPUVertex]? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "meshbin"),
              let data = try? Data(contentsOf: url), data.count >= 12 else { return nil }
        let bytes = [UInt8](data)
        let magic = String(decoding: bytes[0..<8], as: UTF8.self)
        guard magic == "MERKMAP1" || magic == "MERKMAP2" else { return nil }
        let vertexBytes = magic == "MERKMAP2" ? 64 : 40
        let n = UInt32(bytes[8]) | UInt32(bytes[9]) << 8 | UInt32(bytes[10]) << 16 | UInt32(bytes[11]) << 24
        guard n <= 3_000_000, UInt64(n) * UInt64(vertexBytes) + 12 == UInt64(bytes.count) else { return nil }
        func floatAt(_ i: Int) -> Float {
            let bits = UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
            return Float(bitPattern: bits)
        }
        var vertices = [GPUVertex]()
        vertices.reserveCapacity(Int(n))
        for index in 0..<Int(n) {
            let i = 12 + vertexBytes * index
            let uv = vertexBytes == 64 ? SIMD2<Float>(floatAt(i+40),floatAt(i+44)) : SIMD2<Float>(0,0)
            let rect = vertexBytes == 64
                ? SIMD4<Float>(floatAt(i+48),floatAt(i+52),floatAt(i+56),floatAt(i+60))
                : SIMD4<Float>(0.5,0.5,0,0)
            vertices.append(GPUVertex(
                position: SIMD3<Float>(floatAt(i),floatAt(i+4),floatAt(i+8)),
                normal: SIMD3<Float>(floatAt(i+12),floatAt(i+16),floatAt(i+20)),
                color: SIMD4<Float>(floatAt(i+24),floatAt(i+28),floatAt(i+32),floatAt(i+36)),
                uv: uv, atlasRect: rect
            ))
        }
        return vertices
    }
}
