#include <metal_stdlib>
using namespace metal;

struct BgUniforms {
    float time;
    float activity;
    float2 resolution;
    float2 mouse;
};

vertex float4 bg_vertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    return float4(pos[vid], 0.0, 1.0);
}

static float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        v += amp * vnoise(p);
        p = p * 2.03 + float2(17.3, 9.1);
        amp *= 0.5;
    }
    return v;
}

fragment float4 bg_fragment(float4 pos [[position]], constant BgUniforms &u [[buffer(0)]]) {
    float2 uv = pos.xy / u.resolution;
    float2 p = (pos.xy - 0.5 * u.resolution) / u.resolution.y;
    float t = u.time * (0.035 + 0.055 * u.activity);
    float2 m = (u.mouse - 0.5);

    float2 q = float2(
        fbm(p * 1.5 + float2(t * 0.55, -t * 0.35)),
        fbm(p * 1.5 + float2(-t * 0.4, t * 0.5) + 3.7)
    );
    float warp = 1.0 + 0.8 * u.activity;
    float2 r = p * 1.5 + warp * q + m * 0.6 + float2(t * 0.25, -t * 0.18);
    float f = fbm(r);

    float3 col = float3(0.958, 0.961, 0.968);
    col = mix(col, float3(0.80, 0.68, 0.98), smoothstep(0.30, 0.90, f) * 0.15);
    col = mix(col, float3(0.99, 0.80, 0.58), smoothstep(0.42, 0.95, q.x) * 0.11);
    col = mix(col, float3(0.62, 0.86, 0.97), smoothstep(0.42, 0.95, q.y) * 0.11);
    col = mix(col, float3(0.78, 0.94, 0.83), smoothstep(0.55, 1.0, f * q.y) * 0.07);

    float grain = fract(sin(dot(uv * u.resolution, float2(12.9898, 78.233))) * 43758.5453);
    col += (grain - 0.5) * 0.008;
    return float4(col, 1.0);
}
