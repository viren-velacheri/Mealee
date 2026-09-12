#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

constant half3 kMist = half3(0.969, 1.000, 0.965);
constant half3 kMint = half3(0.737, 0.922, 0.796);
constant half3 kLeaf = half3(0.529, 0.839, 0.553);
constant half3 kSage = half3(0.576, 0.706, 0.545);

static float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Slow mint aurora: three soft blobs drifting on the mist ground. Used as the app
// background so every screen breathes a little.
[[ stitchable ]] half4 aurora(float2 position, half4 color, float time, float4 bounds) {
    float2 uv = (position - bounds.xy) / bounds.zw;
    float2 p1 = float2(0.25 + 0.18 * sin(time * 0.11), 0.22 + 0.14 * cos(time * 0.09));
    float2 p2 = float2(0.78 + 0.14 * cos(time * 0.07), 0.55 + 0.18 * sin(time * 0.12));
    float2 p3 = float2(0.45 + 0.22 * sin(time * 0.05), 0.92 + 0.08 * cos(time * 0.13));
    float d1 = exp(-9.0 * dot(uv - p1, uv - p1));
    float d2 = exp(-7.0 * dot(uv - p2, uv - p2));
    float d3 = exp(-6.0 * dot(uv - p3, uv - p3));
    half3 c = kMist;
    c = mix(c, kMint, half(d1 * 0.85));
    c = mix(c, kLeaf, half(d2 * 0.30));
    c = mix(c, kSage, half(d3 * 0.22));
    float grain = (valueNoise(uv * 180.0 + time) - 0.5) * 0.012;
    return half4(c + half3(grain), 1.0);
}

// A soft highlight band sliding along a filled meter, so bars look like liquid.
[[ stitchable ]] half4 shimmer(float2 position, half4 color, float time, float4 bounds) {
    float x = (position.x - bounds.x) / max(bounds.z, 1.0);
    float sweep = fract(time * 0.28) * 1.6 - 0.3;
    float band = smoothstep(0.16, 0.0, abs(x - sweep)) * 0.22;
    float y = (position.y - bounds.y) / max(bounds.w, 1.0);
    float gloss = smoothstep(0.0, 0.45, 0.5 - abs(y - 0.3)) * 0.10;
    return half4(color.rgb + half3(band + gloss) * color.a, color.a);
}

// Eats a layer from the edges inward. progress 0 keeps everything, 1 removes it. The
// vanishing rim glows leaf green so the bite reads as deliberate, not a fade.
[[ stitchable ]] half4 dissolve(float2 position, half4 color, float progress, float4 bounds) {
    float2 uv = (position - bounds.xy) / bounds.zw;
    float n = valueNoise(uv * 7.0) * 0.6 + valueNoise(uv * 23.0) * 0.4;
    float toCentre = 1.0 - distance(uv, float2(0.5, 0.5)) * 1.35;
    float life = n * 0.5 + toCentre * 0.5;
    float p = progress * 1.15;
    float alive = smoothstep(p - 0.10, p + 0.02, life);
    float rim = smoothstep(p - 0.10, p, life) * (1.0 - smoothstep(p, p + 0.05, life));
    half3 rgb = mix(color.rgb, kLeaf * color.a, half(rim));
    return half4(rgb * half(alive), color.a * half(alive));
}

// Radial ripple used by the liquid transition. progress runs the wave outward,
// amplitude is in points.
[[ stitchable ]] float2 ripple(float2 position, float progress, float4 bounds, float amplitude) {
    float2 centre = bounds.xy + bounds.zw * 0.5;
    float2 delta = position - centre;
    float radius = length(delta);
    float maxRadius = max(length(bounds.zw) * 0.5, 1.0);
    float phase = radius / maxRadius - progress;
    float wave = sin(phase * 22.0) * exp(-7.0 * abs(phase));
    float2 direction = delta / max(radius, 0.001);
    return position + direction * wave * amplitude;
}
