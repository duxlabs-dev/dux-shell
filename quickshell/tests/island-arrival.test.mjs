import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const A = loadScript(new URL("../Common/IslandArrival.js", import.meta.url));
const G = loadScript(new URL("../Common/IslandArrivalGestures.js", import.meta.url));

const item = (id, tier = 1) => ({ id, tier });

test("a countdown steps once a half pixel of its dot, running or draining, never faster than 60 times a second", () => {
    const cd = A.countdown(4000, 0);
    // A 20 px dot: a quantum is 1/40 of the fill, 100 ms of a 4 s countdown.
    assert.equal(A.stepMs(cd, 20), 100);
    // Frozen at half, it drains over 450 ms: a quantum is 1/20 of what is left, 22.5 ms.
    assert.equal(A.stepMs(A.freeze(cd, 2000), 20), 23);
    assert.equal(A.stepMs(A.countdown(100, 0), 20), 16);
    assert.equal(A.stepMs(A.freezeEmpty(cd, 0), 20), 450);
});

test("a call never takes the alert shape, a critical or important info does", () => {
    assert.equal(A.alertOf({ "call": true, "critical": true }), "");
    assert.equal(A.alertOf({ "critical": true, "important": true }), "critical");
    assert.equal(A.alertOf({ "important": true }), "important");
    assert.equal(A.alertOf({}), "");
    assert.equal(A.alertOf(null), "");
});

test("an info's tier, in the activities' tiers: normal, important when critical or urgent", () => {
    const tiers = A.Activities.tiers;
    assert.equal(A.tierOf({}), tiers.normal);
    assert.equal(A.tierOf({ brief: true }), tiers.normal, "no caller asks for a brief info");
    assert.equal(A.tierOf({ critical: true }), tiers.important);
    assert.equal(A.tierOf({ urgent: true }), tiers.important);
});

test("a notification takes the island when free or already showing one; a critical one (a call) over any open face but the launcher", () => {
    assert.ok(A.takesIsland(false, false, false, "home"));
    assert.ok(A.takesIsland(true, true, false, "launcher"));
    assert.ok(!A.takesIsland(false, true, false, "controlcenter"));
    assert.ok(A.takesIsland(false, true, true, "controlcenter"));
    // Launcher open: it stands as a bubble beside it, like every other info.
    assert.ok(!A.takesIsland(false, true, true, "launcher"));
});

test("an incoming call rings (its freedesktop category), not one that ended or went unanswered", () => {
    assert.ok(A.ringing("call.incoming"));
    assert.ok(A.ringing("call"));
    for (const c of ["call.ended", "call.unanswered", "im.received", "", undefined, null])
        assert.ok(!A.ringing(c), String(c));
});

test("an info goes by itself after its time, a ringing call never (big, folded or in its bubble)", () => {
    assert.equal(A.expires({ tier: 1 }), true);
    assert.equal(A.expires({ tier: 2, critical: true }), true);
    assert.equal(A.expires({ tier: 2, critical: true, call: true }), false);
    assert.equal(A.expires(null), true);
});

test("B + C: a card grows big, 1.4 s normal, 2 s important; a brief one only swells", () => {
    const normal = A.pulse("bc", 1, true);
    assert.equal(normal.big, true);
    assert.equal(normal.holdMs, 1400);
    assert.equal(A.pulse("bc", 2, true).holdMs, 2000);
    const brief = A.pulse("bc", 0, true);
    assert.equal(brief.holdMs, 400);
    assert.equal(brief.big, false);
    assert.ok(brief.swell[0] > 0 && brief.swell[0] < normal.swell[0] + 1);
    // Without a card (a system face, a glance) it swells instead, harder the more it matters.
    const faceN = A.pulse("bc", 1, false), faceI = A.pulse("bc", 2, false);
    assert.equal(faceN.big, false);
    assert.ok(faceI.swell[1] > faceN.swell[1] && faceN.swell[1] > brief.swell[1]);
});

test("C and A never open the card; A has no bounce and no tint", () => {
    for (const tier of [0, 1, 2]) {
        assert.equal(A.pulse("c", tier, true).big, false);
        const a = A.pulse("a", tier, true, ["strong", "strong", "strong"], ["strong", "strong", "strong"]);
        assert.equal(a.big, false);
        assert.equal(a.ratio, 1);
        assert.equal(a.tint, 0);
    }
});

test("bounce and tint are set per tier, defaults light, light, medium and stronger for the important", () => {
    const [b, n, i] = [0, 1, 2].map(t => A.pulse("bc", t, true));
    assert.ok(b.ratio < 1 && b.ratio === n.ratio && i.ratio < n.ratio);
    assert.ok(i.tint > n.tint && n.tint >= b.tint && b.tint > 0);
    const custom = A.pulse("bc", 1, true, ["none", "strong", "none"], ["none", "none", "none"]);
    assert.ok(custom.ratio < i.ratio);
    assert.equal(custom.tint, 0);
    assert.equal(A.pulse("bc", 0, true, ["none", "none", "none"]).ratio, 1);
    // Reduced motion: big at once, never a bounce; the lifetime stays.
    const reduced = A.pulse("bc", 2, true, undefined, undefined, true);
    assert.equal(reduced.ratio, 1);
    assert.equal(reduced.big, true);
    assert.equal(reduced.holdMs, 2000);
});

test("burst: each newcomer rolls in from below; one arriving while held waits as a dot", () => {
    let s = A.arrive(A.emptyBurst(), item("a"), false);
    assert.deepEqual([s.index, s.dir, s.items.length], [0, 0, 1]);
    s = A.arrive(s, item("b"), false);
    assert.deepEqual([s.index, s.dir, s.axis], [1, 1, "y"]);
    const held = A.arrive(s, item("c"), true);
    assert.deepEqual([held.index, held.dir, held.items.length], [1, 0, 3]);
});

test("burst: going back rolls the other way; out of range or the same page goes nowhere", () => {
    const s = ["a", "b", "c"].reduce((b, id) => A.arrive(b, item(id), false), A.emptyBurst());
    const back = A.go(s, 0);
    assert.deepEqual([back.index, back.dir, back.axis], [0, -1, "x"]);
    assert.equal(A.go(s, 2), null);
    assert.equal(A.go(s, 3), null);
    assert.equal(A.go(s, -1), null);
    assert.deepEqual([A.go(back, 1).index, A.go(back, 1).dir], [1, 1]);
});

test("burst: a full countdown moves to the next info left, else folds", () => {
    let s = ["a", "b", "c"].reduce((b, id) => A.arrive(b, item(id), true), A.emptyBurst());
    assert.equal(s.index, 0);
    s = A.afterCountdown(s);
    assert.deepEqual([s.index, s.dir, s.axis], [1, 1, "x"]);
    s = A.afterCountdown(A.afterCountdown(s) ?? s);
    assert.equal(s, null);
});

test("burst: the read info leaves and the next one takes its page; the last read leaves none", () => {
    const s = ["a", "b", "c"].reduce((b, id) => A.arrive(b, item(id), true), A.emptyBurst());
    const on = index => Object.assign({}, s, { index });
    const ids = b => [...b.items.map(i => i.id), b.index];
    assert.deepEqual(ids(A.drop(on(1))), ["a", "c", 1]);
    assert.deepEqual(ids(A.drop(on(2))), ["a", "b", 1]);
    assert.equal(A.drop(A.arrive(A.emptyBurst(), item("a"), false)), null);
});

test("a swell grows the face along and across the bar, turned with a vertical bar", () => {
    const target = { "width": 100, "height": 30, "radius": 15 };
    assert.deepEqual({ ...A.swollen(target, [0.5, 0.25], 20, false) }, { "width": 110, "height": 35, "radius": 15 });
    assert.deepEqual({ ...A.swollen(target, [0.5, 0.25], 20, true) }, { "width": 105, "height": 40, "radius": 15 });
    assert.equal(target.width, 100, "the face's own target is left as it was");
});

test("burst: an important info anywhere in the burst sizes the island", () => {
    const s = [item("a", 1), item("call", 2), item("b", 0)].reduce((b, i) => A.arrive(b, i, false), A.emptyBurst());
    assert.equal(A.topTier(s.items), 2);
    assert.equal(A.topTier([]), -1);
});

test("pager: five dots at most, the row slides and the dots at a hidden end shrink", () => {
    assert.deepEqual([...A.pager(1, 0).dots], ["on"]);
    assert.deepEqual([...A.pager(3, 1).dots], ["dot", "on", "dot"]);
    const eight = A.pager(8, 5);
    assert.equal(eight.dots.filter(d => d !== "gone").length, 5);
    assert.equal(eight.dots[5], "on");
    assert.equal(eight.start, 3);
    assert.equal(eight.dots[3], "edge");
    assert.equal(eight.dots[7], "dot");
    const first = A.pager(8, 0);
    assert.equal(first.start, 0);
    assert.equal(first.dots[0], "on");
    assert.equal(first.dots[4], "edge");
    assert.equal(first.dots[5], "gone");
    // The active dot never shrinks, even at the edge.
    assert.equal(A.pager(8, 7).dots[7], "on");
});

test("countdown: the active dot fills over the hold, then it is done", () => {
    const cd = A.countdown(1400, 1000);
    assert.equal(A.fill(cd, 1000), 0);
    assert.equal(A.fill(cd, 1700), 0.5);
    assert.equal(A.done(cd, 2399), false);
    assert.equal(A.done(cd, 2400), true);
    assert.equal(A.remaining(cd, 1700), 700);
});

test("freeze: the dot empties gently, nothing ticks once it is empty", () => {
    const frozen = A.freeze(A.countdown(1400, 0), 700, 450);
    assert.equal(A.fill(frozen, 700), 0.5);
    assert.ok(A.fill(frozen, 925) > 0 && A.fill(frozen, 925) < 0.5);
    assert.equal(A.fill(frozen, 1150), 0);
    assert.equal(A.done(frozen, 99999), false);
    assert.equal(A.remaining(frozen, 800), -1);
    assert.equal(A.ticking(frozen, 1000), true);
    assert.equal(A.ticking(frozen, 1150), false);
    // A second hold (focus on top of the pointer) keeps the drain where it is.
    assert.equal(A.freeze(frozen, 900), frozen);
    // A page turned or a fold reopened while held starts empty, and still.
    const empty = A.freezeEmpty(A.countdown(1400, 0), 300, 450);
    assert.equal(A.fill(empty, 300), 0);
    assert.equal(A.ticking(empty, 300), false);
});

test("fill steps are at least half a pixel of the dot", () => {
    assert.equal(A.quantum(20), 0.025);
    assert.equal(A.shown(0.5, 0.51, 20), 0.5);
    assert.equal(A.shown(0.5, 0.53, 20), 0.53);
    assert.equal(A.shown(0.5, 1, 20), 1);
    assert.equal(A.shown(0.01, 0, 20), 0);
});
