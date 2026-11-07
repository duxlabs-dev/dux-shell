import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { K as kit } from "./island-kit-load.mjs";

// The geometry and its drawing in one context, as QML links them (the drawing reads the geometry as Split).
const load = name => readFileSync(new URL(`../Common/${name}`, import.meta.url), "utf8").replace(/^\.(pragma|import).*$/gm, "");
const source = load("IslandLiquidSplit.js") + load("IslandLiquidPose.js") + load("IslandTileSprings.js");
const K = vm.createContext({});
K.Split = K;
K.Kit = kit;
vm.runInContext(source, K);

const s = 32;
const env = { s, L: 4 * s, sh: 0, up: 3 * s, drop: s + 8, far: false, shapeLead: 1.25, k: 56, mass: 1, tile: 0 };
const drawn = { side: 1, radius: s / 2, inset: 4, trackGap: 3, level: 0.55 };

// The wing's tile spring, as the island runs it, for one trip drawn at 60 frames a second; returns every frame's shape.
function trip(from, to, over = {}) {
    const e = Object.assign({}, env, drawn, over), st = K.create(from), frames = [];
    e.area = K.bounds(e);
    let tile = from, v = 0;
    const zeta = 0.55, dt = 1 / 60;
    K.start(st, to, tile);
    for (let t = dt; t < 6; t += dt) {
        for (let i = 0; i < 4; i++) {
            v += (e.k * (to - tile) - 2 * zeta * Math.sqrt(e.k * e.mass) * v) / e.mass * dt / 4;
            tile += v * dt / 4;
        }
        e.tile = tile;
        K.step(st, dt, e);
        const sh = st.sh, o = K.pose(st, e), n = K.slot.neck;
        // The neck's ends, back in frame px (side 1).
        const ends = [[o[n] + e.area.x0, o[n + 1] + e.area.y0], [o[n + 2] + e.area.x0, o[n + 3] + e.area.y0]];
        frames.push({ t, bond: st.bond, settled: st.settled, u: st.u.slice(), gap: sh.gap, neck: sh.neck, closure: sh.closure, apart: sh.apart, tb: st.tb, goo: sh.goo, jx: sh.jx, jy: sh.jy, jr: sh.jr, ends, head: Object.assign({}, sh.head), tail: Object.assign({}, sh.tail), rMax: Math.min(sh.head.hx, sh.head.hy, sh.tail.hx, sh.tail.hy) });
        // The variant stops drawing there; the wing's own body takes over.
        if (st.settled)
            break;
    }
    return frames;
}

const near = (a, b, tol = 0.01) => Math.abs(a - b) <= tol;

test("at rest the two parts make the pill exactly, flat and upright", () => {
    for (const [u, box] of [[0, [0, 4 * s, 0, s]], [1, [0, s, env.drop, env.drop + 3 * s]]]) {
        const st = K.create(u), sh = K.shape(st, Object.assign({}, env, { tile: u })), b = [sh.head, sh.tail];
        const xs = b.flatMap(x => [x.cx - x.hx, x.cx + x.hx]), ys = b.flatMap(x => [x.cy - x.hy, x.cy + x.hy]);
        assert.ok(near(Math.min(...xs), box[0]) && near(Math.max(...xs), box[1]), `x at ${u}`);
        assert.ok(near(Math.min(...ys), box[2]) && near(Math.max(...ys), box[3]), `y at ${u}`);
        assert.equal(sh.gap, 0);
        assert.equal(sh.closure, 1);
        assert.equal(sh.goo, 0);
        assert.equal(sh.jr, 0);
    }
});

test("the icon's part is on top and the rest below once upright, the icon's end outward when flat", () => {
    const flat = K.shape(K.create(0), env);
    assert.ok(flat.head.cx > flat.tail.cx);
    const up = K.shape(K.create(1), Object.assign({}, env, { tile: 1 }));
    assert.ok(up.head.cy < up.tail.cy && near(up.head.hy * 2, s) && near(up.tail.hy * 2, 2 * s));
});

for (const [from, to] of [[0, 1], [1, 0]])
    test(`${from ? "closing" : "opening"}: the parts split well apart, merge through a bridge that swells briefly, and settle`, () => {
        const f = trip(from, to);
        const snap = f.findIndex(x => x.bond === "free");
        assert.ok(snap > 0, "the thread snaps");
        assert.ok(f[snap].gap >= 0.85 * s, `snaps at ${(f[snap].gap / s).toFixed(2)} s`);
        // Clearly apart: past half a thickness for a good while.
        const apart = f.filter(x => x.gap > 0.5 * s).length / 60;
        assert.ok(apart >= 0.15, `apart for ${apart.toFixed(2)} s`);
        const bridge = f.findIndex((x, i) => i > snap && x.bond === "bridge");
        assert.ok(bridge > snap, "a bridge forms after the snap");
        const last = f[f.length - 1];
        assert.ok(last.settled, "it settles");
        assert.ok(last.u[0] === to && last.u[1] === to);
        assert.ok(last.t < 4, `settled in ${last.t.toFixed(2)} s`);
        // No frames past the point where nothing is more than half a pixel from rest (the swell counts).
        const off = x => Math.max(x.jr > 0 ? x.jr - x.rMax : 0, ...["head", "tail"].flatMap(k => ["cx", "cy", "hx", "hy"].map(c => Math.abs(x[k][c] - last[k][c]))));
        let still = f.length - 1;
        while (still > 0 && off(f[still - 1]) < 0.5)
            still--;
        assert.ok(last.t - f[still].t < 0.15, `settled ${(last.t - f[still].t).toFixed(2)} s after the last half pixel`);
        // While split, the seam's corners are round and the union is soft; the bridge only thickens.
        assert.ok(f[snap].closure < 0.05 && f[snap].goo > 0);
        for (let i = bridge + 1; i < f.length && f[i].bond === "bridge"; i++)
            assert.ok(f[i].neck >= f[i - 1].neck - 1e-6 || f[i].gap < 1);
        // The junction swells about 4 % of the thickness past the pill's edge, then goes back.
        const swell = Math.max(...f.slice(bridge).map(x => x.jr - x.rMax));
        assert.ok(swell > 0.03 * s && swell < 0.05 * s, `swell ${(swell / s).toFixed(3)} s`);
        assert.equal(last.jr, 0);
    });

for (const [from, to] of [[0, 1], [1, 0]])
    test(`${from ? "closing" : "opening"}: outlined only while visibly split, never again once the bridge is full`, () => {
        const f = trip(from, to), full = f.findIndex(x => x.bond === "bridge" && x.tb >= K.bridgeTime(env));
        assert.ok(f.filter(x => x.gap > 0.5 * s).every(x => x.apart), "outlined while apart");
        assert.ok(full > 0 && f.slice(full).every(x => !x.apart), "no outline once merged, even as the seam wobbles");
        assert.equal(K.shape(K.create(to), Object.assign({}, env, { tile: to })).apart, false);
    });

for (const far of [false, true])
    for (const [from, to] of [[0, 1], [1, 0]])
        test(`${far ? "bottom" : "top"} bar, ${from ? "closing" : "opening"}: the neck stays at the junction, the parts away from it stay hard`, () => {
            const f = trip(from, to, { far }).filter(x => x.neck > 0);
            assert.ok(f.length > 0);
            const off = f.filter(x => x.ends.some(([ex, ey]) => Math.hypot(ex - x.jx, ey - x.jy) > x.gap / 2 + x.neck * Math.SQRT2 + 0.01));
            assert.equal(off.length, 0, `${off.length} frames reach into a part, first at ${off[0]?.t.toFixed(2)} s`);
        });

test("every time comes from the wing spring's period: four times stiffer, twice as fast", () => {
    const soft = trip(0, 1), stiff = trip(0, 1, { k: 4 * env.k });
    const ratio = soft[soft.length - 1].t / stiff[stiff.length - 1].t;
    assert.ok(ratio > 1.7 && ratio < 2.3, `settle ratio ${ratio.toFixed(2)}`);
    assert.ok(near(K.bridgeTime(env), 2 * K.bridgeTime(Object.assign({}, env, { k: 4 * env.k })), 1e-9));
    assert.ok(near(K.period(env), 2 * Math.PI / Math.sqrt(env.k), 1e-9));
    // The tile's fades (TileLiquid.fadeMs) take their share of that period too.
    assert.ok(near(K.fadeTime(env), K.params.fadeShare * K.period(env), 1e-9));
    assert.ok(near(K.fadeTime(env), 2 * K.fadeTime(Object.assign({}, env, { k: 4 * env.k })), 1e-9));
});

test("the thread keeps its area: thinner as it stretches, the snap radius at the break", () => {
    const p = K.params, r = g => K.threadRadius(s, g, s / 2);
    assert.ok(r(4) > r(8) && r(8) > r(16));
    assert.ok(near(r(p.breakGap * s), p.snapRadius * s, 1e-9));
    assert.equal(r(0), s / 2);
});

test("the drawing's box holds both parts and the swell for the whole trip", () => {
    for (const [from, to] of [[0, 1], [1, 0]]) {
        const bb = K.bounds(env);
        for (const x of trip(from, to)) {
            for (const b of [x.head, x.tail]) {
                assert.ok(b.cx - b.hx >= bb.x0 && b.cx + b.hx <= bb.x1, "x");
                assert.ok(b.cy - b.hy >= bb.y0 && b.cy + b.hy <= bb.y1, "y");
            }
        }
    }
});

test("on a bottom bar the box grows up: the upright parts sit above the flat pill", () => {
    const up = K.shape(K.create(1), Object.assign({}, env, { far: true, tile: 1 }));
    assert.ok(up.tail.cy + up.tail.hy <= s + 0.01 && up.head.cy < up.tail.cy);
});

for (const [from, to] of [[0, 1], [1, 0]])
    test(`on a bottom bar, ${from ? "closing" : "opening"}: parts sliding into each other open the seam (round, outlined)`, () => {
        const f = trip(from, to, { far: true });
        const depth = x => Math.min(Math.max(0, x.head.hx + x.tail.hx - Math.abs(x.head.cx - x.tail.cx)), Math.max(0, x.head.hy + x.tail.hy - Math.abs(x.head.cy - x.tail.cy)));
        const deep = f.filter(x => x.bond !== "bridge" && depth(x) > 0.15 * s);
        assert.ok(deep.every(x => x.closure < 0.5 && x.apart), `${deep.filter(x => x.closure >= 0.5).length} frames square`);
        assert.ok(f[f.length - 1].settled);
    });

for (const far of [false, true])
    for (const [from, to] of [[0, 1], [1, 0]])
        test(`${far ? "bottom" : "top"} bar, ${from ? "closing" : "opening"}: square seam corners only where the parts meet edge to edge, lined up`, () => {
            const f = trip(from, to, { far });
            const slide = x => {
                const a = x.head, b = x.tail, ox = a.hx + b.hx - Math.abs(a.cx - b.cx), oy = a.hy + b.hy - Math.abs(a.cy - b.cy);
                return ox < oy ? Math.abs(a.cy - a.hy - b.cy + b.hy) + Math.abs(a.cy + a.hy - b.cy - b.hy) : Math.abs(a.cx - a.hx - b.cx + b.hx) + Math.abs(a.cx + a.hx - b.cx - b.hx);
            };
            const bad = f.filter(x => x.closure > 0.5 && slide(x) > 0.15 * s);
            assert.equal(bad.length, 0, `${bad.length} frames square while slid, first at ${bad[0]?.t.toFixed(2)} s`);
        });

test("the pose mirrors exactly on the island's leading side", () => {
    const e = Object.assign({}, env, drawn, { tile: 0.4 }), st = K.create(0);
    K.start(st, 1, 0);
    K.step(st, 1 / 60, e);
    e.area = K.bounds(e);
    const right = Array.from(K.pose(st, e)), left = Array.from(K.pose(st, Object.assign({}, e, { side: -1 })));
    const w = e.area.x1 - e.area.x0, S = K.slot;
    for (const b of ["head", "tail", "track", "fill"]) {
        assert.ok(near(right[S[b]] + left[S[b]], w, 1e-9), b);
        for (let i = 1; i < 4; i++)
            assert.equal(right[S[b] + i], left[S[b] + i]);
    }
    for (const r of ["headR", "tailR"])
        assert.deepEqual([left[S[r] + 1], left[S[r]], left[S[r] + 3], left[S[r] + 2]], right.slice(S[r], S[r] + 4));
    assert.equal(K.uniforms.length, right.length);
});

test("no frame allocates: the shape and the pose are rewritten in place", () => {
    const e = Object.assign({}, env, drawn, { tile: 0.3 }), st = K.create(0);
    e.area = K.bounds(e);
    K.start(st, 1, 0);
    const sh = st.sh, head = sh.head, pose = st.pose;
    K.step(st, 1 / 60, e);
    assert.ok(K.shape(st, e) === sh && sh.head === head && K.pose(st, e) === pose);
    // The per-frame functions build no array, object or closure.
    for (const fn of ["thick", "drop", "part", "gap", "middle", "toward", "threadRadius", "shape", "settledAt", "step", "ix", "putBox", "putCorners", "pose", "period", "bridgeTime"]) {
        const body = source.match(new RegExp(`\\nfunction ${fn}\\([^)]*\\) \\{[\\s\\S]*?\\n\\}`))[0];
        assert.ok(!/=>|\bnew\b|[=(,:]\s*[[{]|\.(slice|map|concat|filter|every|some)\(/.test(body), fn);
    }
});

test("a tile's delayed spring waits for its delay, never jumps on a stalled frame, then settles on its target", () => {
    const sims = { "a": { "x": 0, "v": 0, "t": 0, "next": 1, "at": 0.05 } };
    const springs = { "a": [300, 0.55] };
    let clock = K.stepDelayed(sims, springs, ["a"], 0, 0.04);
    assert.equal(sims.a.x, 0);
    clock = K.stepDelayed(sims, springs, ["a"], clock, 5);
    assert.ok(Math.abs(clock - (0.04 + K.maxFrame)) < 1e-9);
    assert.ok(sims.a.x > 0 && sims.a.x < 1);
    for (let i = 0; i < 300 && !K.settled(sims.a); i++)
        clock = K.stepDelayed(sims, springs, ["a"], clock, 1 / 60);
    assert.equal(sims.a.x, 1);
    assert.equal(sims.a.v, 0);
});

test("slosh: a push takes over up to its cap, then it rings down by its decay, under rest in a few seconds", () => {
    assert.equal(K.slosh(0, 1 / 60, 2), 2);
    assert.equal(K.slosh(0, 1 / 60, 99), K.sloshMax);
    assert.ok(Math.abs(K.slosh(4, 1, 0) - 4 * Math.exp(-K.sloshDecay)) < 1e-12);
    assert.equal(K.slosh(4, 0, 1), 4, "a weaker push never cuts it short");
    let s = K.sloshMax, t = 0;
    for (; s > K.sloshRest && t < 10; t += 1 / 60)
        s = K.slosh(s, 1 / 60, 0);
    assert.ok(t > 1 && t < 2.5, `rests after ${t.toFixed(2)} s`);
});

test("misfit: 0 for boxes meeting edge to edge, else how deep one sinks plus how far their shared edge's ends are off", () => {
    const a = { cx: 0, cy: 0, hx: 1, hy: 1 }, box = (cx, cy, hx, hy) => ({ cx, cy, hx, hy });
    assert.equal(K.misfit(a, box(2, 0, 1, 1)), 0, "side by side");
    assert.equal(K.misfit(a, box(0, 2, 1, 1)), 0, "stacked");
    assert.equal(K.misfit(a, box(1.5, 0, 1, 1)), 0.5, "sunk half a unit");
    assert.equal(K.misfit(a, box(2, 0.25, 1, 1)), 0.5, "slid a quarter along the edge");
    assert.equal(K.misfit(a, box(2, 0, 1, 0.5)), 1, "a shorter edge");
    assert.equal(K.misfit(box(2, 0.25, 1, 1), a), K.misfit(a, box(2, 0.25, 1, 1)));
});

test("the model only uses what the shell's JavaScript engine has (a missing method fails silently there)", () => {
    for (const m of ["flatMap", ".flat(", "?.", "??", "structuredClone", ".at("])
        assert.ok(!source.includes(m), m);
});
