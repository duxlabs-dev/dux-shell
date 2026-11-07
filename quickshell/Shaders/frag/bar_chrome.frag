#version 450

// The bar or its satellites + the popout opened from them as one SDF, so the join never depends on two surfaces agreeing.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float widthPx;
    float heightPx;
    vec4 surfaceColor;  // straight (non-premultiplied) rgba
    vec4 shadowColor;   // straight rgba; a = 0 disables both shadow terms
    vec4 shadowParam;   // key: x = blur px, y = spread px, z,w = offset px
    vec4 ambientParam;  // ambient: x = blur px, y = spread px, z = alpha
    vec4 edgeParam;     // x = bar side (0 top, 1 bottom, 2 left, 3 right), y = edge fillet k, z,w = popout fillet k at its start and end
    vec4 leadRect;      // x, y, w, h px; w = 0 disables a shape
    vec4 leadCorner;    // topLeft, topRight, bottomRight, bottomLeft
    vec4 trailRect;
    vec4 trailCorner;
    vec4 bodyRect;
    vec4 bodyCorner;
} ubuf;

float sdRoundBox4(vec2 p, vec4 rect, vec4 r) {
    vec2 hs = rect.zw * 0.5;
    p -= rect.xy + hs;
    float rr = (p.x >= 0.0) ? (p.y >= 0.0 ? r.z : r.y) : (p.y >= 0.0 ? r.w : r.x);
    rr = min(rr, min(hs.x, hs.y));
    vec2 q = abs(p) - hs + rr;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - rr;
}

float smin(float a, float b, float k) {
    if (k <= 0.0)
        return min(a, b);
    return max(k, min(a, b)) - length(max(vec2(k) - vec2(a, b), vec2(0.0)));
}

float bandDist(vec2 px) {
    float d = 1e5;
    if (ubuf.leadRect.z > 0.0)
        d = sdRoundBox4(px, ubuf.leadRect, ubuf.leadCorner);
    if (ubuf.trailRect.z > 0.0)
        d = min(d, sdRoundBox4(px, ubuf.trailRect, ubuf.trailCorner));
    return d;
}

float shapesDist(vec2 px, float band) {
    float d = band;
    if (ubuf.bodyRect.z > 0.0 && ubuf.bodyRect.w > 0.0) {
        bool alongX = ubuf.edgeParam.x < 1.5;
        float along = alongX ? px.x : px.y;
        float center = alongX ? ubuf.bodyRect.x + ubuf.bodyRect.z * 0.5 : ubuf.bodyRect.y + ubuf.bodyRect.w * 0.5;
        d = smin(d, sdRoundBox4(px, ubuf.bodyRect, ubuf.bodyCorner), along < center ? ubuf.edgeParam.z : ubuf.edgeParam.w);
    }
    return d;
}

// The screen edges only round the shapes into the edge. They sit a pixel off screen so their antialiasing paints nothing,
// and they cast no shadow.
float sceneDist(vec2 px, float shapes, float band) {
    float side = ubuf.edgeParam.x;
    float dEdge = 1.0 + (side < 0.5 ? px.y : side < 1.5 ? (ubuf.heightPx - px.y) : side < 2.5 ? px.x : (ubuf.widthPx - px.x));
    float dEnds = 1.0 + (side < 1.5 ? min(px.x, ubuf.widthPx - px.x) : min(px.y, ubuf.heightPx - px.y));
    float k = ubuf.edgeParam.y;
    float d = smin(shapes, dEdge, k);
    // Only the bar or satellite rounds into the screen end: elsewhere the two edges would fill the corner.
    return band > k ? d : smin(d, dEnds, k);
}

void main() {
    vec2 px = qt_TexCoord0 * vec2(ubuf.widthPx, ubuf.heightPx);
    float band = bandDist(px);
    float shapes = shapesDist(px, band);
    float d = sceneDist(px, shapes, band);
    float fw = max(fwidth(d), 1e-4);
    float reach = max(ubuf.shadowParam.x + ubuf.shadowParam.y + length(ubuf.shadowParam.zw), ubuf.ambientParam.x + ubuf.ambientParam.y) + fw;
    if (d > reach) {
        fragColor = vec4(0.0);
        return;
    }
    float cov = 1.0 - smoothstep(-fw, fw, d);
    vec4 col = vec4(ubuf.surfaceColor.rgb, 1.0) * cov;
    if (ubuf.shadowColor.a > 0.0) {
        vec2 shadowPx = px - ubuf.shadowParam.zw;
        float dk = shapesDist(shadowPx, bandDist(shadowPx)) - ubuf.shadowParam.y;
        float bk = max(ubuf.shadowParam.x, fw);
        float covK = 1.0 - smoothstep(-bk, bk, dk);
        float ba = max(ubuf.ambientParam.x, fw);
        float covA = 1.0 - smoothstep(-ba, ba, shapes - ubuf.ambientParam.y);
        float sh = 1.0 - (1.0 - covK * ubuf.shadowColor.a) * (1.0 - covA * ubuf.ambientParam.z);
        col += vec4(ubuf.shadowColor.rgb, 1.0) * (sh * (1.0 - col.a));
    }
    fragColor = col * (ubuf.surfaceColor.a * ubuf.qt_Opacity);
}
