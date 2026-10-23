#version 450

// Fades the lyrics out towards the top and bottom edge. MultiEffect thresholds a gradient mask into
// a hard edge, so the ramp is computed here.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float edgeFade;
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    float fade = max(ubuf.edgeFade, 0.0001);
    float edge = smoothstep(0.0, fade, qt_TexCoord0.y) * smoothstep(0.0, fade, 1.0 - qt_TexCoord0.y);
    fragColor = texture(source, qt_TexCoord0) * edge * ubuf.qt_Opacity;
}
