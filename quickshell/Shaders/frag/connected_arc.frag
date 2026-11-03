#version 450

// Connected frame silhouette: frame ring + chrome bodies as one SDF with elevation shadow.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float widthPx;
    float heightPx;
    float cutoutRadius;
    vec4 cutout;        // inner cutout edges in px: x=left y=top z=right w=bottom
    vec4 surfaceColor;  // straight (non-premultiplied) rgba
    vec4 shadowColor;   // straight rgba; a = 0 disables both shadow terms
    vec4 shadowParam;   // key: x = blur px, y = spread px, z,w = offset px
    vec4 ambientParam;  // ambient: x = blur px, y = spread px, z = alpha
    // Six chrome slots: rect = x,y,w,h px; corner and k = per-corner radii and junction fillets (TL, TR, BR, BL),
    // a corner is sharp exactly where its k > 0; param.x = active.
    vec4 chromeRect0;
    vec4 chromeCorner0;
    vec4 chromeK0;
    vec4 chromeParam0;
    vec4 chromeRect1;
    vec4 chromeCorner1;
    vec4 chromeK1;
    vec4 chromeParam1;
    vec4 chromeRect2;
    vec4 chromeCorner2;
    vec4 chromeK2;
    vec4 chromeParam2;
    vec4 chromeRect3;
    vec4 chromeCorner3;
    vec4 chromeK3;
    vec4 chromeParam3;
    vec4 chromeRect4;
    vec4 chromeCorner4;
    vec4 chromeK4;
    vec4 chromeParam4;
    vec4 chromeRect5;
    vec4 chromeCorner5;
    vec4 chromeK5;
    vec4 chromeParam5;
} ubuf;

float sdRoundBox(vec2 p, vec2 c, vec2 hs, float r) {
    r = min(r, min(hs.x, hs.y));
    vec2 q = abs(p - c) - hs + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

float sdRoundBox4(vec2 p, vec2 c, vec2 hs, vec4 r) {
    p -= c;
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

float chromeDist(vec2 px, vec4 rect, vec4 corner) {
    vec2 c = rect.xy + rect.zw * 0.5;
    return sdRoundBox4(px, c, rect.zw * 0.5, corner);
}

float chromeK(vec2 px, vec4 rect, vec4 ks) {
    vec2 p = px - (rect.xy + rect.zw * 0.5);
    return (p.x >= 0.0) ? (p.y >= 0.0 ? ks.z : ks.y) : (p.y >= 0.0 ? ks.w : ks.x);
}

float sceneDist(vec2 px) {
    vec2 cutC = vec2((ubuf.cutout.x + ubuf.cutout.z) * 0.5, (ubuf.cutout.y + ubuf.cutout.w) * 0.5);
    vec2 cutH = vec2((ubuf.cutout.z - ubuf.cutout.x) * 0.5, (ubuf.cutout.w - ubuf.cutout.y) * 0.5);
    float d = -sdRoundBox(px, cutC, cutH, ubuf.cutoutRadius);

    if (ubuf.chromeParam0.x > 0.5)
        d = smin(d, chromeDist(px, ubuf.chromeRect0, ubuf.chromeCorner0), chromeK(px, ubuf.chromeRect0, ubuf.chromeK0));
    if (ubuf.chromeParam1.x > 0.5)
        d = smin(d, chromeDist(px, ubuf.chromeRect1, ubuf.chromeCorner1), chromeK(px, ubuf.chromeRect1, ubuf.chromeK1));
    if (ubuf.chromeParam2.x > 0.5)
        d = smin(d, chromeDist(px, ubuf.chromeRect2, ubuf.chromeCorner2), chromeK(px, ubuf.chromeRect2, ubuf.chromeK2));
    if (ubuf.chromeParam3.x > 0.5)
        d = smin(d, chromeDist(px, ubuf.chromeRect3, ubuf.chromeCorner3), chromeK(px, ubuf.chromeRect3, ubuf.chromeK3));
    if (ubuf.chromeParam4.x > 0.5)
        d = smin(d, chromeDist(px, ubuf.chromeRect4, ubuf.chromeCorner4), chromeK(px, ubuf.chromeRect4, ubuf.chromeK4));
    if (ubuf.chromeParam5.x > 0.5)
        d = smin(d, chromeDist(px, ubuf.chromeRect5, ubuf.chromeCorner5), chromeK(px, ubuf.chromeRect5, ubuf.chromeK5));
    return d;
}

void main() {
    vec2 px = qt_TexCoord0 * vec2(ubuf.widthPx, ubuf.heightPx);
    float d = sceneDist(px);
    float fw = max(fwidth(d), 1e-4);
    // Most of the screen is the cutout interior, far from any edge: skip the shadow pass (a second sceneDist) there.
    float reach = max(ubuf.shadowParam.x + ubuf.shadowParam.y + length(ubuf.shadowParam.zw), ubuf.ambientParam.x + ubuf.ambientParam.y) + fw;
    if (d > reach) {
        fragColor = vec4(0.0);
        return;
    }
    float cov = 1.0 - smoothstep(-fw, fw, d);
    vec4 col = vec4(ubuf.surfaceColor.rgb, 1.0) * cov;
    if (ubuf.shadowColor.a > 0.0) {
        float dk = sceneDist(px - ubuf.shadowParam.zw) - ubuf.shadowParam.y;
        float bk = max(ubuf.shadowParam.x, fw);
        float covK = 1.0 - smoothstep(-bk, bk, dk);
        float ba = max(ubuf.ambientParam.x, fw);
        float covA = 1.0 - smoothstep(-ba, ba, d - ubuf.ambientParam.y);
        float sh = 1.0 - (1.0 - covK * ubuf.shadowColor.a) * (1.0 - covA * ubuf.ambientParam.z);
        col += vec4(ubuf.shadowColor.rgb, 1.0) * (sh * (1.0 - col.a));
    }
    fragColor = col * (ubuf.surfaceColor.a * ubuf.qt_Opacity);
}
