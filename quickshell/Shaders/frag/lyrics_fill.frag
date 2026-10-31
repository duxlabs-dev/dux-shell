#version 450

// Lights a row of lyric glyphs up to a soft edge.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 restColor;
    vec4 fillColor;
    float edge;
    float feather;
    float rtl;
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    float x = mix(qt_TexCoord0.x, 1.0 - qt_TexCoord0.x, ubuf.rtl);
    float lit = 1.0 - smoothstep(ubuf.edge - ubuf.feather, ubuf.edge, x);
    vec4 color = mix(ubuf.restColor, ubuf.fillColor, lit);
    fragColor = color * texture(source, qt_TexCoord0).a * ubuf.qt_Opacity;
}
