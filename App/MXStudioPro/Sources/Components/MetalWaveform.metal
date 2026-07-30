#include <metal_stdlib>
using namespace metal;

struct WaveVertexOut {
    float4 position [[position]];
    float2 uv;
};

struct WaveUniforms {
    float time;
    float level;
    float clipping;
    float active;
    float sampleCount;
    float2 resolution;
    float _pad;
};

vertex WaveVertexOut wave_vertex(uint vid [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    float2 p = positions[vid];
    WaveVertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

static float sampleAmp(constant float *amps, float count, float x) {
    float f = clamp(x, 0.0, 1.0) * max(count - 1.0, 1.0);
    int i0 = int(floor(f));
    int i1 = min(i0 + 1, int(count) - 1);
    int i2 = min(i0 + 2, int(count) - 1);
    float t = f - float(i0);
    // Catmull-ish smooth for continuous DAW-style envelope
    float a = amps[max(i0 - 1, 0)];
    float b = amps[i0];
    float c = amps[i1];
    float d = amps[i2];
    float t2 = t * t;
    float t3 = t2 * t;
    return 0.5 * ((2.0 * b) +
                  (-a + c) * t +
                  (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 +
                  (-a + 3.0 * b - 3.0 * c + d) * t3);
}

static float3 palette(float amp, float height, float clipping, float time) {
    float3 deep   = float3(0.08, 0.35, 0.32);
    float3 mid    = float3(0.494, 0.851, 0.396); // #7ED965
    float3 bright = float3(0.396, 0.851, 0.835); // #65D9D5
    float3 lilac  = float3(0.678, 0.396, 0.851); // light purple accent
    float3 hot    = float3(0.992, 0.427, 0.208); // #FD6D35
    float3 clipC  = float3(0.910, 0.353, 0.361); // #E85A5C

    float shimmer = 0.5 + 0.5 * sin(time * 3.5 + amp * 7.0);
    float3 cool = mix(deep, mid, saturate(amp * 1.15));
    cool = mix(cool, bright, saturate(height * 0.7 + shimmer * 0.2));
    cool = mix(cool, lilac, saturate(amp - 0.75) * 0.35);
    float heat = smoothstep(0.58, 0.96, amp);
    float3 warm = mix(cool, hot, heat);
    return mix(warm, clipC, saturate(clipping));
}

fragment float4 wave_fragment(WaveVertexOut in [[stage_in]],
                              constant WaveUniforms &u [[buffer(0)]],
                              constant float *amps [[buffer(1)]]) {
    float2 uv = in.uv;

    float amp = max(sampleAmp(amps, u.sampleCount, uv.x), 0.0);
    // High-frequency detail layer (oscilloscope teeth)
    float teeth = 0.55 + 0.45 * abs(sin(uv.x * 70.0 + u.time * 6.0 + amp * 10.0));
    float localAmp = clamp(amp * mix(0.85, 1.15, teeth), 0.0, 1.0);

    float halfH = max(localAmp * 0.58, 0.04);
    float cy = 0.5;
    float d = abs(uv.y - cy) / halfH;

    // Sharp filled envelope with sample-bar texture (DAW track signal)
    float body = 1.0 - smoothstep(0.72, 0.98, d);
    float core = 1.0 - smoothstep(0.0, 0.35, d);
    float rim  = exp(-pow(d - 0.9, 2.0) * 110.0);
    float glow = exp(-d * d * 2.6) * (0.22 + 0.28 * localAmp);

    // Vertical “sample bar” feel inside the envelope
    float barPhase = fract(uv.x * min(u.sampleCount * 0.55, 110.0));
    float bar = smoothstep(0.0, 0.18, barPhase) * smoothstep(1.0, 0.55, barPhase);
    float barShade = mix(0.72, 1.0, bar);
    // Peak glitter on loud columns
    float peakSpark = step(0.78, localAmp) * step(0.85, bar) * 0.55;

    float heightNorm = saturate(abs(uv.y - cy) / 0.5);
    float3 col = palette(localAmp, heightNorm, u.clipping, u.time);

    // Soft lower mirror
    float mirrorAmp = localAmp * 0.62;
    float mirrorD = abs(uv.y - 0.5) / max(mirrorAmp * 0.42, 0.01);
    float mirror = (uv.y > 0.5)
        ? (1.0 - smoothstep(0.55, 1.05, mirrorD)) * 0.28 * saturate(1.15 - (uv.y - 0.5) * 1.8)
        : 0.0;

    float alpha = saturate(body * 0.98 + core * 0.25 + rim * 0.85 + glow * 0.45 + mirror);
    float3 rgb = col * barShade;
    rgb += float3(0.95, 1.0, 0.92) * rim * 0.55;
    rgb += col * core * 0.3;
    rgb += col * glow;
    rgb += float3(1.0, 0.95, 0.85) * peakSpark;
    rgb += col * mirror;

    // Center hairline
    float guide = exp(-pow((uv.y - 0.5) * u.resolution.y, 2.0) * 0.05) * 0.22;
    rgb += float3(0.55, 0.95, 0.75) * guide;
    alpha = max(alpha, guide * 0.55);

    // Recording energy sweep
    float sweep = 0.06 * sin(uv.x * 28.0 - u.time * 7.0) * u.active * (0.4 + localAmp);
    rgb += float3(sweep * 0.6, sweep, sweep * 0.85);

    float vig = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
    alpha *= mix(0.8, 1.0, vig);

    return float4(rgb, saturate(alpha));
}
