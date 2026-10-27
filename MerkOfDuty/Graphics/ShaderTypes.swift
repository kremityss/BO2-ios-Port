import simd

// Caution: Metal's float3 is 16-byte aligned, matching Swift SIMD3<Float>.
struct GPUVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var color: SIMD4<Float>
    var uv: SIMD2<Float>
    // Normalized sub-rectangle within the map texture atlas.
    var atlasRect: SIMD4<Float>
}

struct GPUInstance {
    var model: simd_float4x4
    var tint: SIMD4<Float>
}

struct GPUUniforms {
    var viewProjection: simd_float4x4
    var sunDirection: SIMD4<Float>
}

extension simd_float4x4 {
    static func translation(_ v: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1,0,0,0), SIMD4<Float>(0,1,0,0),
            SIMD4<Float>(0,0,1,0), SIMD4<Float>(v,1)
        ))
    }
    static func scale(_ v: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4<Float>(v,1))
    }
    static func rotateY(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(columns: (
            SIMD4<Float>(c,0,-s,0), SIMD4<Float>(0,1,0,0),
            SIMD4<Float>(s,0,c,0), SIMD4<Float>(0,0,0,1)
        ))
    }
    static func rotateX(_ a: Float) -> simd_float4x4 {
        let c = cos(a), s = sin(a)
        return simd_float4x4(columns: (
            SIMD4<Float>(1,0,0,0), SIMD4<Float>(0,c,s,0),
            SIMD4<Float>(0,-s,c,0), SIMD4<Float>(0,0,0,1)
        ))
    }
    static func perspective(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fov / 2)
        let x = y / max(0.01, aspect)
        return simd_float4x4(columns: (
            SIMD4<Float>(x,0,0,0), SIMD4<Float>(0,y,0,0),
            SIMD4<Float>(0,0,far/(near-far),-1), SIMD4<Float>(0,0,near*far/(near-far),0)
        ))
    }
}
