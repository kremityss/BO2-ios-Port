#include <metal_stdlib>
using namespace metal;

struct GPUVertex {
    float3 position;
    float3 normal;
    float4 color;
    float2 uv;
    float4 atlasRect;
};
struct GPUInstance {
    float4x4 model;
    float4 tint;
};
struct GPUUniforms {
    float4x4 viewProjection;
    float4 sunDirection;
};
struct Out {
    float4 position [[position]];
    float4 color;
    float3 normal;
    float2 uv;
    float4 atlasRect;
};

vertex Out sceneVertex(uint id [[vertex_id]], uint instanceID [[instance_id]],
                       device const GPUVertex *v [[buffer(0)]],
                       constant GPUUniforms &uniforms [[buffer(1)]],
                       device const GPUInstance *instances [[buffer(2)]]) {
    GPUVertex a = v[id];
    GPUInstance inst = instances[instanceID];
    Out o;
    float4 world = inst.model * float4(a.position, 1.0);
    o.position = uniforms.viewProjection * world;
    o.color = a.color * inst.tint;
    o.normal = normalize((inst.model * float4(a.normal, 0.0)).xyz);
    o.uv = a.uv;
    o.atlasRect = a.atlasRect;
    return o;
}

fragment float4 sceneFragment(Out in [[stage_in]],
                              constant GPUUniforms &uniforms [[buffer(1)]],
                              texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    // glTF's repeat wrapping happens inside the assigned atlas tile, not across
    // adjacent materials. Repeat may not match non-default clamp samplers.
    float2 repeatUV = fract(in.uv);
    float2 atlasUV = in.atlasRect.xy + repeatUV * in.atlasRect.zw;
    float3 albedo = atlas.sample(linearSampler, atlasUV).rgb;
    float diffuse = max(0.0, dot(normalize(in.normal), normalize(uniforms.sunDirection.xyz)));
    float ambient = 0.31;
    float brightness = ambient + diffuse * 0.69;
    return float4(in.color.rgb * albedo * brightness, 1.0);
}
