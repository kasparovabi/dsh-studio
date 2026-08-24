#include <metal_stdlib>
using namespace metal;

struct BgUniforms {
    float time;
    float activity;
    float dark;
    float2 resolution;
    float2 mouse;
};

struct PointOut {
    float4 position [[position]];
    float size [[point_size]];
    float4 color;
    float softness;
};

struct LineOut {
    float4 position [[position]];
    float4 color;
};

// On paper these are pigments laid over white; on a dark ground they are
// lights added to it, which needs both a hotter palette and much lower alpha.
// Multiply blending looked like the right fit for the paper case and turned
// every overlap to mud, so that pass is ordinary alpha instead.
constant float3 paperPalette[8] = {
    float3(0.86, 0.22, 0.28),
    float3(0.10, 0.66, 0.72),
    float3(0.34, 0.26, 0.82),
    float3(0.60, 0.28, 0.76),
    float3(0.92, 0.52, 0.16),
    float3(0.16, 0.60, 0.46),
    float3(0.90, 0.34, 0.56),
    float3(0.42, 0.46, 0.58)
};

constant float3 nightPalette[8] = {
    float3(1.00, 0.16, 0.22),
    float3(0.09, 0.88, 0.82),
    float3(0.30, 0.17, 0.92),
    float3(0.62, 0.17, 0.82),
    float3(0.95, 0.42, 0.10),
    float3(0.12, 0.62, 0.48),
    float3(0.98, 0.30, 0.55),
    float3(0.86, 0.94, 1.00)
};

static float hash11(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

static float3 hash31(float n) {
    return float3(hash11(n * 1.13), hash11(n * 2.71 + 5.1), hash11(n * 3.37 + 11.7));
}

static float3 curl3(float3 p) {
    return float3(
        sin(p.y * 1.7 + p.z * 0.9) - cos(p.z * 1.1),
        sin(p.z * 1.3 + p.x * 1.1) - cos(p.x * 0.7),
        sin(p.x * 1.9 + p.y * 0.7) - cos(p.y * 1.3)
    );
}

static float3 spin(float3 p, float a) {
    float c = cos(a), s = sin(a);
    return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

static float3 clusterCentre(float cluster, float clusters, float t) {
    float rise = cluster / clusters;
    float sway = t * 0.11 + cluster * 2.17;
    float lift = fract(rise + t * 0.010);
    return float3(
        sin(sway) * (0.18 + 0.42 * hash11(cluster * 4.9)),
        -0.78 + lift * 1.56,
        cos(sway * 0.83) * (0.14 + 0.32 * hash11(cluster * 6.3))
    );
}

vertex PointOut bg_vertex(uint vid [[vertex_id]], constant BgUniforms &u [[buffer(0)]]) {
    PointOut out;
    const float clusters = 30.0;
    const float hazeCount = 900.0;

    float n = float(vid);
    float t = u.time;
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 mouse = float2(u.mouse.x * 2.0 - 1.0, 1.0 - u.mouse.y * 2.0);
    mouse.x *= aspect;

    bool night = u.dark > 0.5;
    bool haze = n < hazeCount;
    float3 p;
    float3 tint;
    float size;
    float alpha;
    float softness = 1.0;

    if (haze) {
        float3 r = hash31(n * 0.37) - 0.5;
        p = float3(r.x * 2.10, r.y * 1.80 - 0.05, r.z * 1.15);
        p += curl3(p * 1.2 + t * 0.05) * 0.10;
        tint = night
            ? mix(float3(0.52, 0.40, 0.17), float3(0.22, 0.42, 0.26), hash11(n * 0.91))
            : mix(float3(0.72, 0.66, 0.48), float3(0.52, 0.66, 0.60), hash11(n * 0.91));
        size = 220.0 + 240.0 * hash11(n * 1.77);
        alpha = (night ? 0.030 : 0.032) * (0.6 + 0.4 * u.activity);
    } else {
        float m = n - hazeCount;
        float cluster = floor(fmod(m, clusters));
        float3 seed = hash31(m * 0.011 + 3.0);

        float radius = 0.15 + 0.28 * hash11(cluster * 3.11);
        float3 dir = normalize(hash31(m * 0.053 + 17.0) - 0.5 + 1e-4);
        float fill = pow(hash11(m * 0.019), 0.55);
        float3 local = dir * fill * radius;

        float3 centre = clusterCentre(cluster, clusters, t);
        local += curl3(local * 6.0 + centre * 3.0 + t * 0.32) * radius * 0.55;
        local.y += sin(t * 0.7 + cluster * 1.9) * radius * 0.20;

        p = centre + local;
        int slot = int(hash11(cluster * 5.71) * 7.999);
        tint = night ? nightPalette[slot] : paperPalette[slot];

        float kind = hash11(m * 0.0091);
        if (kind < 0.30) {
            size = 24.0 + 44.0 * seed.x;
            alpha = night ? 0.052 : 0.058;
            if (night) tint *= 0.95;
        } else if (kind < 0.93) {
            size = 1.2 + 1.9 * seed.y;
            alpha = night ? 0.44 : 0.42;
            softness = 0.25;
        } else {
            size = 1.6 + 2.2 * seed.z;
            alpha = night ? 0.62 : 0.42;
            tint = night ? mix(tint, float3(1.0), 0.75) : tint * 0.55;
            softness = 0.15;
        }
        alpha *= 0.45 + 0.55 * u.activity;
    }

    p = spin(p, t * 0.075);

    float2 flatPull = mouse - p.xy;
    float grab = exp(-length(flatPull) * 2.2);
    p.xy += flatPull * grab * (0.10 + 0.22 * u.activity);

    float perspective = 2.55 - p.z * 0.62;
    float2 flat = p.xy * (1.62 / perspective); flat.x *= 1.34;

    float blur = abs(p.z + 0.10) * 2.4;
    size *= (1.0 + blur * 1.5) * (1.7 / perspective);
    alpha /= (1.0 + blur * 1.1);

    out.position = float4(flat.x / aspect, flat.y, 0.0, 1.0);
    out.size = clamp(size, 1.0, 460.0);
    out.color = float4(tint, alpha);
    out.softness = haze ? 1.0 : softness;
    return out;
}

fragment float4 bg_fragment(PointOut in [[stage_in]],
                            float2 pc [[point_coord]],
                            constant BgUniforms &u [[buffer(0)]]) {
    float d = length(pc - 0.5) * 2.0;
    float mask = pow(max(1.0 - d, 0.0), mix(1.4, 5.0, in.softness));
    float a = in.color.a * mask;
    // The additive pass ignores the alpha channel, so it gets premultiplied.
    if (u.dark > 0.5) return float4(in.color.rgb * a, 1.0);
    return float4(in.color.rgb, a);
}

vertex LineOut bg_trace_vertex(uint vid [[vertex_id]], constant BgUniforms &u [[buffer(0)]]) {
    LineOut out;
    const float steps = 54.0;

    float segment = floor(float(vid) / 2.0);
    float endpoint = fmod(float(vid), 2.0);
    float strand = floor(segment / (steps - 1.0));
    float k = fmod(segment, steps - 1.0) + endpoint;

    float t = u.time;
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);

    float3 p = (hash31(strand * 7.3 + 41.0) - 0.5) * float3(0.9, 1.4, 0.7);
    p.y += 0.28;
    for (int i = 0; i < 54; i++) {
        if (float(i) >= k) break;
        p += normalize(curl3(p * 2.6 + t * 0.22 + strand) + 1e-4) * 0.026;
    }

    p = spin(p, t * 0.075);
    float perspective = 2.55 - p.z * 0.62;
    float2 flat = p.xy * (1.62 / perspective); flat.x *= 1.34;

    float head = k / steps;
    float pulse = fract(t * 0.13 + strand * 0.29);
    float visible = smoothstep(0.0, 0.12, pulse) * smoothstep(1.0, 0.62, pulse);

    out.position = float4(flat.x / aspect, flat.y, 0.0, 1.0);
    bool night = u.dark > 0.5;
    float alpha = (night ? 0.30 : 0.20) * visible * (1.0 - head * 0.5) * (0.35 + 0.65 * u.activity);
    float3 c = night ? float3(0.92, 0.96, 1.00) : float3(0.22, 0.26, 0.34);
    out.color = night ? float4(c * alpha, 1.0) : float4(c, alpha);
    return out;
}

fragment float4 bg_trace_fragment(LineOut in [[stage_in]]) {
    return in.color;
}
