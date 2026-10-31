.pragma library
.import "IslandKit.js" as Kit
.import "IslandLiquidSplit.js" as Split

// The liquid launcher transition's drawing (IslandLiquidSplit.js holds its geometry and physics): the shape of one frame
// (st.sh) turned into the shader's uniforms, in the drawing's own px, mirrored on the island's leading side.

// The shader's uniforms, in the order pose() writes them (a box is center xy, half size; radii go top-left clockwise).
var layout = [["head", 4], ["headR", 4], ["tail", 4], ["tailR", 4], ["neck", 4], ["neckRadius", 1], ["goo", 1], ["bulge", 3], ["track", 4], ["trackRadius", 1], ["fill", 4], ["fillRadius", 1], ["trackUnder", 1], ["trackGap", 1]];
var uniforms = [];
var slot = {};
for (var li = 0; li < layout.length; li++) {
    slot[layout[li][0]] = uniforms.length;
    for (var lj = 0; lj < layout[li][1]; lj++)
        uniforms.push(layout[li][1] > 1 ? layout[li][0] + lj : layout[li][0]);
}

// Frame px to the drawing's own px (mirrored on the island's leading side).
function ix(x, env) {
    return env.side < 0 ? env.area.x1 - x : x - env.area.x0;
}
function putBox(o, at, cx, cy, hx, hy, env) {
    o[at] = ix(cx, env);
    o[at + 1] = cy - env.area.y0;
    o[at + 2] = hx;
    o[at + 3] = hy;
}
// Corner radii (top-left, top-right, bottom-right, bottom-left) from the frame's near and far sides.
function putCorners(o, at, nearTop, farTop, farBottom, nearBottom, env) {
    const m = env.side < 0;
    o[at] = m ? farTop : nearTop;
    o[at + 1] = m ? nearTop : farTop;
    o[at + 2] = m ? nearBottom : farBottom;
    o[at + 3] = m ? farBottom : nearBottom;
}

// The shader's uniforms, into st.pose. env adds side, area (the drawing's frame box), radius (the pill's corners), inset,
// trackGap and level (-1 for none).
function pose(st, env) {
    const sh = st.sh, h = sh.head, t = sh.tail, o = st.pose, q = sh.closure;
    const ch = Kit.unit(st.u[0]), ct = Kit.unit(st.u[1]);
    // The seam's corners: on the near side of the icon's part flat, under it upright (and the rest's facing ones).
    const rh = Math.min(env.radius, h.hx, h.hy), rt = Math.min(env.radius, t.hx, t.hy);
    putBox(o, slot.head, h.cx, h.cy, h.hx, h.hy, env);
    putCorners(o, slot.headR, rh * (1 - q * (1 - ch)), rh, rh * (1 - q * ch), rh * (1 - q), env);
    putBox(o, slot.tail, t.cx, t.cy, t.hx, t.hy, env);
    putCorners(o, slot.tailR, rt * (1 - q * ct), rt * (1 - q), rt * (1 - q * (1 - ct)), rt, env);
    o[slot.neck] = ix(sh.ax, env);
    o[slot.neck + 1] = sh.ay - env.area.y0;
    o[slot.neck + 2] = ix(sh.bx, env);
    o[slot.neck + 3] = sh.by - env.area.y0;
    o[slot.neckRadius] = sh.neck;
    o[slot.goo] = sh.goo;
    o[slot.bulge] = ix(sh.jx, env);
    o[slot.bulge + 1] = sh.jy - env.area.y0;
    o[slot.bulge + 2] = sh.jr;
    // The level's track: the rest inset (by the gap on the icon's side), its liquid from the icon's side flat, from the
    // bottom upright.
    const farIn = Kit.mix(env.trackGap, env.inset, ct), topIn = Kit.mix(env.inset, env.trackGap, ct);
    const x0 = t.cx - t.hx + env.inset, x1 = t.cx + t.hx - farIn, y0 = t.cy - t.hy + topIn, y1 = t.cy + t.hy - env.inset;
    const tw = Math.max(0, x1 - x0), th = Math.max(0, y1 - y0), lv = Kit.unit(env.level);
    const trackRadius = Math.min(Math.max(0, rt - env.inset), tw / 2, th / 2);
    putBox(o, slot.track, (x0 + x1) / 2, (y0 + y1) / 2, tw / 2, th / 2, env);
    o[slot.trackRadius] = trackRadius;
    const fx0 = Kit.mix(x1 - lv * tw, x0, ct), fy0 = Kit.mix(y0, y1 - lv * th, ct), fhy = Math.max(0, y1 - fy0) / 2;
    putBox(o, slot.fill, (fx0 + x1) / 2, (fy0 + y1) / 2, Math.max(0, x1 - fx0) / 2, fhy, env);
    o[slot.fillRadius] = ct * Math.min(trackRadius, fhy);
    o[slot.trackUnder] = ct;
    o[slot.trackGap] = env.trackGap * (1 - ct);
    return o;
}
