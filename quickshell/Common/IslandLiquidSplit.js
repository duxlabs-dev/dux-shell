.pragma library
.import "IslandKit.js" as Kit

// Liquid launcher transition: the pill parts into its icon's end (head) and the rest (tail). The part that has to leave rides
// the wing's tile spring, the other sticks; the thread between them thins (its area kept) and snaps, the stuck part flies after
// on a softer spring and a bridge reaches across, growing like an inertial neck, with a short swell at the junction. Only
// that junction is liquid: the parts stay rigid boxes, the neck reaches no further into them than its own radius. Pure
// geometry and physics in frame px: x from the wing's island-side edge outward, y down from the flat pill's top. Springs are
// ratios of the wing's spring, times are shares of its period, lengths are in pill thicknesses. Nothing is allocated per frame.

var params = {
    // The follower's spring: stiffness ratio and damping ratio.
    "lag": 1.0,
    "lagZeta": 0.6,
    // The thread snaps at this gap, this thin.
    "breakGap": 0.9,
    "snapRadius": 0.08,
    // The bridge reaches across under this gap, grows over this share of the period (by this power of time), then swells by
    // this much at the junction over as long again.
    "reach": 0.45,
    "bridgeShare": 0.14,
    "bridgeLaw": 0.5,
    "bulge": 0.04,
    // The smooth union's reach (neck and swell into the parts) while split.
    "goo": 0.25,
    // A hover taking over mid-trip, and the value showing again at rest, fade over this share of the period.
    "fadeShare": 0.25
};

// The leader catches the wing's spring this many times stiffer, critically damped, after a reversal.
var leadCatch = 8;
// Seam corners and the smooth union close over this gap (pill thicknesses).
var seamGap = 0.15;
// Integration step (s) and the largest frame taken at once.
var subStep = 1 / 240;
var maxFrame = 1 / 20;

// The wing spring's period (s), and the times drawn from it.
function period(env) {
    return 2 * Math.PI * Math.sqrt(env.mass / env.k);
}
function bridgeTime(env) {
    return params.bridgeShare * period(env);
}
function fadeTime(env) {
    return params.fadeShare * period(env);
}

function thick(u, env) {
    return Kit.mix(env.s, env.up, Kit.unit(u * env.shapeLead));
}

// How far down the wing's box has moved at tile progress u (on a bottom bar it grows up instead).
function drop(u, env) {
    if (!env.far)
        return env.drop * u;
    return -(env.drop * u + thick(u, env) - thick(0, env));
}

// A part's box at progress u, into out (its place moves with u, overshoot included; its size with u held to 0..1). Flat, the
// head is the icon's end [cut, L] and the tail the rest; upright, the head is the top square and the tail the rest below.
function part(head, u, env, out) {
    const s = env.s, c = Kit.unit(u), cut = Math.max(0, env.L - s - env.sh);
    const x0 = head ? cut : 0, x1 = head ? env.L : cut, y0 = head ? 0 : s, y1 = head ? s : env.up;
    out.cx = Kit.mix((x0 + x1) / 2, s / 2, u);
    out.cy = Kit.mix(s / 2, (y0 + y1) / 2, u) + drop(u, env);
    out.hx = Kit.mix((x1 - x0) / 2, s / 2, c);
    out.hy = Kit.mix(s / 2, (y1 - y0) / 2, c);
    return out;
}

// Distance between two boxes (0 when they touch or overlap).
function gap(a, b) {
    const dx = Math.max(0, Math.abs(a.cx - b.cx) - a.hx - b.hx), dy = Math.max(0, Math.abs(a.cy - b.cy) - a.hy - b.hy);
    return Math.sqrt(dx * dx + dy * dy);
}

// How far two boxes are from meeting edge to edge: how deep one sinks into the other, plus how far the ends of the edge
// they share are off each other (0 for the pill's own seam).
function misfit(a, b) {
    const ox = a.hx + b.hx - Math.abs(a.cx - b.cx), oy = a.hy + b.hy - Math.abs(a.cy - b.cy);
    const depth = Math.min(Math.max(0, ox), Math.max(0, oy));
    if (ox < oy)
        return depth + Math.abs(a.cy - a.hy - b.cy + b.hy) + Math.abs(a.cy + a.hy - b.cy - b.hy);
    return depth + Math.abs(a.cx - a.hx - b.cx + b.hx) + Math.abs(a.cx + a.hx - b.cx - b.hx);
}

function middle(ca, ha, cb, hb) {
    return (Math.max(ca - ha, cb - hb) + Math.min(ca + ha, cb + hb)) / 2;
}

// j held within c ± h (h below 0 counts as 0).
function toward(j, c, h) {
    const r = Math.max(0, h);
    return Math.max(c - r, Math.min(c + r, j));
}

// Thread radius at a gap, its area kept, never thicker than the parts allow.
function threadRadius(s, g, rMax) {
    return Math.min(rMax, params.breakGap * params.snapRadius * s * s / Math.max(1e-6, g));
}

function box() {
    return {
        "cx": 0,
        "cy": 0,
        "hx": 0,
        "hy": 0
    };
}

function create(target) {
    // Filled by IslandLiquidPose.pose on the first frame drawn, then rewritten in place.
    const pose = [];
    return {
        "target": target,
        "u": [target, target], // head, tail
        "v": [0, 0],
        "e": 0,
        "ve": 0,
        "lead": target > 0.5 ? 1 : 0,
        "held": false,
        "bond": "bridge",
        "tb": 1e9,
        "settled": true,
        "rest": box(),
        // What the shader and the icon need (shape), and the shader's uniforms (pose), rewritten in place.
        "sh": {
            "head": box(),
            "tail": box(),
            "gap": 0,
            "neck": 0,
            // The neck's ends: each part's point nearest the junction, a neck radius inside it.
            "ax": 0,
            "ay": 0,
            "bx": 0,
            "by": 0,
            "closure": 1,
            "apart": false,
            "goo": 0,
            "jx": 0,
            "jy": 0,
            "jr": 0,
            "iconX": 0,
            "iconY": 0
        },
        "pose": pose
    };
}

// The open target changed: the part that has to leave its place leads (the tail going up, the head coming back).
function start(st, target, tile) {
    st.target = target;
    const lead = target > 0.5 ? 1 : 0;
    if (lead !== st.lead) {
        st.e = st.u[lead] - tile;
        st.ve = 0;
    }
    st.lead = lead;
    st.held = true;
    if (st.bond !== "free")
        st.bond = "thread";
    st.settled = false;
}

// Both boxes, the gap, the neck, how closed the seam is (1 = one pill), the union's reach and the junction's swell, into st.sh.
function shape(st, env) {
    const p = params, s = env.s, sh = st.sh, h = part(true, st.u[0], env, sh.head), t = part(false, st.u[1], env, sh.tail);
    const g = gap(h, t), rMax = Math.min(h.hx, h.hy, t.hx, t.hy), bt = bridgeTime(env);
    let neck = 0, jr = 0;
    if (st.bond === "thread")
        neck = threadRadius(s, g, rMax);
    else if (st.bond === "bridge") {
        neck = rMax * Math.min(1, Math.pow(Math.max(0, st.tb) / bt, p.bridgeLaw));
        const x = st.tb / (2 * bt);
        if (x < 1)
            jr = neck + p.bulge * s * Math.sin(Math.PI * x);
    }
    sh.gap = g;
    sh.neck = neck;
    // The seam is shut only where the parts meet edge to edge, lined up: a gap, a slide or a sink (bottom bar) opens it.
    const off = g + misfit(h, t);
    sh.closure = Kit.unit(1 - off / (seamGap * s)) * (rMax > 0 ? neck / rMax : 1);
    // Outlined while visibly split: half a pixel off before the bridge, until the bridge is full (the settling seam wobbles).
    sh.apart = st.bond === "bridge" ? st.tb < bt : off >= 0.5;
    sh.goo = p.goo * s * (1 - sh.closure);
    sh.jx = middle(h.cx, h.hx, t.cx, t.hx);
    sh.jy = middle(h.cy, h.hy, t.cy, t.hy);
    sh.jr = jr;
    sh.ax = toward(sh.jx, h.cx, h.hx - neck);
    sh.ay = toward(sh.jy, h.cy, h.hy - neck);
    sh.bx = toward(sh.jx, t.cx, t.hx - neck);
    sh.by = toward(sh.jy, t.cy, t.hy - neck);
    sh.iconX = h.cx - h.hx + s / 2;
    sh.iconY = h.cy - h.hy + s / 2;
    return sh;
}

function settledAt(st, env) {
    const s = env.s, sh = st.sh, r = st.rest;
    let dev = 0;
    part(true, st.target, env, r);
    dev = Math.max(dev, Math.abs(sh.head.cx - r.cx), Math.abs(sh.head.cy - r.cy), Math.abs(sh.head.hx - r.hx), Math.abs(sh.head.hy - r.hy));
    part(false, st.target, env, r);
    dev = Math.max(dev, Math.abs(sh.tail.cx - r.cx), Math.abs(sh.tail.cy - r.cy), Math.abs(sh.tail.hx - r.hx), Math.abs(sh.tail.hy - r.hy));
    // Still = both boxes within a quarter pixel of rest, every part too slow to leave it (a tile unit spans at most 4 s px).
    const slow = 1 / s;
    return dev < 0.25 && Math.abs(env.tile - st.target) * 4 * s < 0.25 && Math.abs(st.v[1 - st.lead]) < slow && Math.abs(st.ve) < slow && sh.gap < 0.5 && !st.held && (st.bond === "thread" || st.bond === "bridge" && st.tb >= 2 * bridgeTime(env));
}

// One drawn frame: env holds tile (the wing's spring, which the leader rides), k and mass (that spring), and the geometry.
function step(st, frame, env) {
    const p = params, s = env.s, fol = 1 - st.lead;
    const dt = Math.min(maxFrame, Math.max(0, frame));
    const kf = env.k * p.lag, cf = 2 * p.lagZeta * Math.sqrt(kf * env.mass), we = Math.sqrt(env.k * leadCatch / env.mass);
    let left = dt;
    while (left > 1e-9) {
        const h = Math.min(subStep, left);
        left -= h;
        st.ve += (-we * we * st.e - 2 * we * st.ve) * h;
        st.e += st.ve * h;
        if (!st.held) {
            st.v[fol] += (kf * (st.target - st.u[fol]) - cf * st.v[fol]) / env.mass * h;
            st.u[fol] += st.v[fol] * h;
        }
    }
    st.u[st.lead] = env.tile + st.e;
    const g = shape(st, env).gap;
    if (st.bond === "thread" && g > p.breakGap * s) {
        st.bond = "free";
        st.held = false;
    } else if (st.bond === "free" && !st.held && g < p.reach * s) {
        st.bond = "bridge";
        st.tb = 0;
    } else if (st.bond === "bridge")
        st.tb += dt;
    // A short trip never snaps the thread: let the stuck part go once the leader has nearly arrived.
    if (st.held && Math.abs(env.tile - st.target) < 0.05)
        st.held = false;
    st.settled = settledAt(st, env);
    if (st.settled) {
        st.u[0] = st.target;
        st.u[1] = st.target;
        st.v[0] = 0;
        st.v[1] = 0;
        st.e = 0;
        st.ve = 0;
        st.bond = "bridge";
        st.tb = 1e9;
    }
    shape(st, env);
}

// The frame box the drawing covers for a whole trip (overshoot and the junction's swell included).
function bounds(env) {
    const m = 0.7 * env.s, d = drop(1.3, env);
    return {
        "x0": -m,
        "x1": Math.max(env.L, env.s) + m,
        "y0": Math.min(0, d) - m,
        "y1": Math.max(env.s, d + env.up) + m
    };
}
