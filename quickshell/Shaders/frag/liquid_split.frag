#version 450

// Two rigid rounded boxes (the icon's part and the rest) joined by a neck and a swell at their junction; only those melt
// into the boxes (smooth union), the boxes meet each other hard. With a bubble's edge and, in the second box, a level's track and liquid. Every length is in item px. The vectors come as
// scalars so the item sets them without building a value per frame.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float head0, head1, head2, head3;         // center xy, half size
    float headR0, headR1, headR2, headR3;     // top-left, top-right, bottom-right, bottom-left
    float tail0, tail1, tail2, tail3;
    float tailR0, tailR1, tailR2, tailR3;
    float neck0, neck1, neck2, neck3;         // from, to
    float neckRadius;
    float goo;
    float bulge0, bulge1, bulge2;             // junction swell: center, radius
    float track0, track1, track2, track3;
    float trackRadius;
    float fill0, fill1, fill2, fill3;
    float fillRadius;
    float trackUnder;
    float trackGap;
    float gaugeOpacity;
    float edgeWidth;
    vec4 fillColor;
    vec4 edgeColor;
    vec4 trackColor;
    vec4 liquidColor;
} ubuf;

float box(vec2 p, vec4 b, vec4 r) {
    p -= b.xy;
    float rr = p.x < 0.0 ? (p.y < 0.0 ? r.x : r.w) : (p.y < 0.0 ? r.y : r.z);
    vec2 q = abs(p) - b.zw + rr;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rr;
}

float capsule(vec2 p, vec2 a, vec2 b, float r) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// Polynomial smooth minimum: k = 0 is a plain union.
float smin(float a, float b, float k) {
    if (k <= 0.0)
        return min(a, b);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

float cover(float d) {
    return clamp(0.5 - d, 0.0, 1.0);
}

vec4 over(vec4 top, vec4 under) {
    return top + under * (1.0 - top.a);
}

vec4 premul(vec4 c, float a) {
    return vec4(c.rgb * c.a * a, c.a * a);
}

void main() {
    vec2 p = qt_TexCoord0 * ubuf.itemSize;
    vec4 headBox = vec4(ubuf.head0, ubuf.head1, ubuf.head2, ubuf.head3);
    vec4 headRadii = vec4(ubuf.headR0, ubuf.headR1, ubuf.headR2, ubuf.headR3);
    vec4 tailBox = vec4(ubuf.tail0, ubuf.tail1, ubuf.tail2, ubuf.tail3);
    vec4 tailRadii = vec4(ubuf.tailR0, ubuf.tailR1, ubuf.tailR2, ubuf.tailR3);
    float d = min(box(p, headBox, headRadii), box(p, tailBox, tailRadii));
    if (ubuf.neckRadius > 0.0)
        d = smin(d, capsule(p, vec2(ubuf.neck0, ubuf.neck1), vec2(ubuf.neck2, ubuf.neck3), ubuf.neckRadius), ubuf.goo);
    if (ubuf.bulge2 > 0.0)
        d = smin(d, length(p - vec2(ubuf.bulge0, ubuf.bulge1)) - ubuf.bulge2, ubuf.goo);

    float body = cover(d);
    float inner = cover(d + ubuf.edgeWidth);
    vec4 c = premul(ubuf.fillColor, inner) + premul(ubuf.edgeColor, body - inner);

    if (ubuf.gaugeOpacity > 0.0) {
        float track = box(p, vec4(ubuf.track0, ubuf.track1, ubuf.track2, ubuf.track3), vec4(ubuf.trackRadius));
        float fill = box(p, vec4(ubuf.fill0, ubuf.fill1, ubuf.fill2, ubuf.fill3), vec4(ubuf.fillRadius));
        float empty = max(cover(max(track, ubuf.trackGap - fill)), ubuf.trackUnder * cover(track));
        float liquid = cover(max(track, fill));
        c = over(premul(ubuf.trackColor, empty * ubuf.gaugeOpacity * inner), c);
        c = over(premul(ubuf.liquidColor, liquid * ubuf.gaugeOpacity * inner), c);
    }
    fragColor = c * ubuf.qt_Opacity;
}
