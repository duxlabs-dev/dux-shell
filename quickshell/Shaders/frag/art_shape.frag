#version 450

// The cookie's polar radius is a short cosine series, so rotating or morphing it only changes uniforms.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float morph;
    float spinAngle;
    float sizePx;
    float lobes;
    vec4 terms;
    float disc;
} ubuf;

layout(binding = 1) uniform sampler2D source;

const float holeRadius = 0.03;
const float grooveRadius = 0.32;
const float grooveShade = 0.35;

void main() {
    vec2 p = qt_TexCoord0 - 0.5;
    float r = length(p);
    if (ubuf.disc > 0.5) {
        float c = cos(ubuf.spinAngle);
        float s = sin(ubuf.spinAngle);
        // The morph spring may undershoot, which would turn the groove into a light ring.
        float reveal = clamp(ubuf.morph, 0.0, 1.0);
        vec2 uv = vec2(c * p.x + s * p.y, -s * p.x + c * p.y) + 0.5;
        float rim = clamp((0.5 - r) * ubuf.sizePx + 0.5, 0.0, 1.0);
        float hole = clamp((r - holeRadius * reveal) * ubuf.sizePx + 0.5, 0.0, 1.0);
        float groove = 1.0 - grooveShade * reveal * clamp(1.0 - abs(r - grooveRadius) * ubuf.sizePx, 0.0, 1.0);
        vec4 color = texture(source, uv);
        fragColor = vec4(color.rgb * groove, color.a) * rim * hole * ubuf.qt_Opacity;
        return;
    }
    float a = (atan(p.y, p.x) - ubuf.spinAngle) * ubuf.lobes;
    float cookie = ubuf.terms.x + ubuf.terms.y * cos(a) + ubuf.terms.z * cos(2.0 * a) + ubuf.terms.w * cos(3.0 * a);
    float edge = mix(0.5, cookie, ubuf.morph);
    float mask = clamp((edge - r) * ubuf.sizePx + 0.5, 0.0, 1.0);
    fragColor = texture(source, qt_TexCoord0) * mask * ubuf.qt_Opacity;
}
