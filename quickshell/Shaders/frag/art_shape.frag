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
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 p = qt_TexCoord0 - 0.5;
    float a = (atan(p.y, p.x) - ubuf.spinAngle) * ubuf.lobes;
    float cookie = ubuf.terms.x + ubuf.terms.y * cos(a) + ubuf.terms.z * cos(2.0 * a) + ubuf.terms.w * cos(3.0 * a);
    float edge = mix(0.5, cookie, ubuf.morph);
    float mask = clamp((edge - length(p)) * ubuf.sizePx + 0.5, 0.0, 1.0);
    fragColor = texture(source, qt_TexCoord0) * mask * ubuf.qt_Opacity;
}
