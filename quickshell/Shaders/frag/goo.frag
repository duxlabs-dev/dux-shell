#version 450

// A closing bubble's shape (the source) melting into the island's edge, drawn above the island. Outside the island, shape
// and island are blurred into one field and cut at half, so they bridge as they meet, and the island's edge swells
// near the contact; inside it, the shape is hidden, as if it went under the island, and a halo in the shape's color
// spreads from the contact point like a wave (its front at wavePx), paling with the distance (fallPx).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float blurPx;
    float islandRadius;
    float glow;
    float glowPx;
    float wavePx;
    float fallPx;
    float swell;
    vec2 sizePx;
    vec2 contact;
    vec4 island;
    vec4 islandColor;
    vec4 blobColor;
} ubuf;

layout(binding = 1) uniform sampler2D source;

float sdIsland(vec2 p, vec4 rect) {
    vec2 hs = rect.zw * 0.5;
    float r = min(ubuf.islandRadius, min(hs.x, hs.y));
    vec2 q = abs(p - rect.xy - hs) - hs + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

// The shape's alpha over a centre and two staggered rings of six taps (weights sum to 1), so the melt stays round, never
// starred; the half-size layer's linear filtering smooths between them.
float blobField(vec2 uv) {
    vec2 r = vec2(ubuf.blurPx) / ubuf.sizePx;
    float a = texture(source, uv).a * 0.2;
    for (int i = 0; i < 6; i++) {
        float t = float(i) * 1.0471976;
        a += texture(source, uv + vec2(cos(t + 0.5235988), sin(t + 0.5235988)) * r * 0.45).a * 0.08;
        a += texture(source, uv + vec2(cos(t), sin(t)) * r * 0.9).a * 0.0533333;
    }
    return a;
}

void main() {
    vec2 p = qt_TexCoord0 * ubuf.sizePx;
    float w = max(ubuf.blurPx, 1.0);
    float sd = sdIsland(p, ubuf.island);
    float d = length(p - ubuf.contact);
    float near = exp(-pow(d / max(2.0 * ubuf.glowPx, 1.0), 2.0));
    float blob = blobField(qt_TexCoord0);
    float isle = clamp(0.5 - (sd - ubuf.swell * near) / (2.0 * w), 0.0, 1.0);
    float total = blob + isle;
    // Cut at half with a one-pixel ramp: the melted field reads as one smooth outline.
    float goo = clamp((total - 0.5) * 2.0 * w + 0.5, 0.0, 1.0);
    float outside = clamp(0.5 + sd, 0.0, 1.0);
    // The bridge takes the shape's color as soon as the shape is part of it, so it reads on any wallpaper.
    vec4 tint = mix(ubuf.islandColor, ubuf.blobColor, smoothstep(0.0, 0.45, blob / max(total, 1e-4)));
    float gooA = goo * tint.a;
    // Inside: the island covers the shape; only the halo, its front moving out as it pales (premultiplied).
    float front = exp(-pow(d / max(ubuf.wavePx, 1.0), 2.0));
    float glowA = ubuf.glow * front * exp(-d / max(ubuf.fallPx, 1.0)) * ubuf.blobColor.a;
    vec4 inner = vec4(ubuf.blobColor.rgb * glowA, glowA);
    fragColor = (vec4(tint.rgb * gooA, gooA) * outside + inner * (1.0 - outside)) * ubuf.qt_Opacity;
}
