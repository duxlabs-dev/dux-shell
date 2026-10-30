import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const A = loadScript(new URL("../Common/IslandArrival.js", import.meta.url));
const G = loadScript(new URL("../Common/IslandArrivalGestures.js", import.meta.url));

test("wheel: notches add up to one page, a pause starts over, a page locks the next notches briefly", () => {
    let w = G.wheel(G.wheelIdle(), 15, 0);
    assert.equal(w.step, 0);
    w = G.wheel(w, 15, 50);
    assert.equal(w.step, 0);
    w = G.wheel(w, 15, 100);
    assert.equal(w.step, 1);
    const locked = G.wheel(w, 120, 150);
    assert.equal(locked.step, 0);
    assert.equal(G.wheel(w, -120, 100 + 400).step, -1);
    // A long pause forgets what was turned.
    const paused = G.wheel(G.wheel(G.wheelIdle(), 30, 0), 30, 1000);
    assert.equal(paused.step, 0);
});

test("wheelDelta: the larger axis wins, pixels before notches (÷3), the wheel turned up goes to the next info", () => {
    assert.equal(G.wheelDelta({ "x": 0, "y": 0 }, { "x": 0, "y": 120 }), 40);
    assert.equal(G.wheelDelta({ "x": 0, "y": 0 }, { "x": 0, "y": -120 }), -40);
    assert.equal(G.wheelDelta({ "x": 0, "y": 9 }, { "x": 0, "y": -120 }), 9);
    assert.equal(G.wheelDelta({ "x": -12, "y": 3 }, { "x": 0, "y": 0 }), -12);
});

test("swipe: sideways turns pages, up tidies away, down opens the full card; short or diagonal does nothing", () => {
    assert.equal(G.swipe(-60, 5, 36), "next");
    assert.equal(G.swipe(60, -5, 36), "prev");
    assert.equal(G.swipe(4, -50, 36), "tidy");
    assert.equal(G.swipe(-3, 50, 36), "open");
    assert.equal(G.swipe(20, 10, 36), "");
    // On a bottom bar the island hangs from below: away from the edge is up.
    assert.equal(G.swipe(4, 50, 36, true), "tidy");
    assert.equal(G.swipe(4, -50, 36, true), "open");
});

test("content stays in the middle of the springing shape: equal room above and below, whole pixels", () => {
    assert.equal(A.centered(40, 40), 0);
    // A swell (40 -> 53): the face moves down half the growth instead of staying pinned to the top.
    assert.equal(A.centered(53, 40), 7);
    // The card bigger than the island early in its growth: centred, cut evenly by both edges.
    assert.equal(A.centered(60, 108), -24);
});

test("grow reads the island's spring between compact and card, unclamped so content rides the bounce", () => {
    assert.equal(A.grow(40, 40, 108), 0);
    assert.equal(A.grow(108, 40, 108), 1);
    assert.equal(A.grow(74, 40, 108), 0.5);
    assert.ok(A.grow(110, 40, 108) > 1);
    // No card to grow into: nothing flies.
    assert.equal(A.grow(60, 40, 40.5), 0);
    // Reduced motion: only the two layouts, nothing in between.
    assert.equal(A.grow(60, 40, 108, true), 0);
    assert.equal(A.grow(80, 40, 108, true), 1);
});

test("fly: a shared element goes from its own place to the other layout's, both centred in the island", () => {
    // Card 300x100, icon centre (30, 30) size 40; compact face 200x40, icon centre (22, 20) size 24.
    const card = { "x": 30, "y": 30, "size": 40, "w": 300, "h": 100 };
    const compact = { "x": 22, "y": 20, "size": 24, "w": 200, "h": 40 };
    assert.deepEqual({ ...A.fly(card, compact, 0) }, { "x": 0, "y": 0, "scale": 1 });
    // At the other end the card's icon sits exactly on the compact one: (22 + 50, 20 + 30) in card coordinates.
    const end = A.fly(card, compact, 1);
    assert.equal(30 + end.x, 72);
    assert.equal(30 + end.y, 50);
    assert.equal(end.scale, 0.6);
    // The compact icon flies the other way and meets it.
    const back = A.fly(compact, card, 1);
    assert.equal(22 + back.x, -20);
    assert.equal(20 + back.y, 0);
    assert.ok(Math.abs(back.scale - 40 / 24) < 1e-9);
    // Halfway, both are at the same spot in the island.
    const a = A.fly(card, compact, 0.5), b = A.fly(compact, card, 0.5);
    assert.equal(30 + a.x - 50, 22 + b.x);
    assert.equal(30 + a.y - 30, 20 + b.y);
});

test("handover: shared elements cross-fade midway (sum 1), the card's own come late, the compact's own leave early", () => {
    for (const t of [-0.1, 0, 0.2, 0.35, 0.5, 0.8, 1, 1.05]) {
        const o = A.handover(t, 0.35);
        assert.ok(o.shared >= 0 && o.shared <= 1);
        assert.ok(o.cardOwn <= o.shared + 1e-9, "the card's own never before the shared ones");
        assert.ok(o.compactOwn <= 1 - o.shared + 1e-9, "the compact's own gone before the shared ones");
    }
    assert.deepEqual({ ...A.handover(0, 0.35) }, { "shared": 0, "cardOwn": 0, "compactOwn": 1 });
    assert.deepEqual({ ...A.handover(1, 0.35) }, { "shared": 1, "cardOwn": 1, "compactOwn": 0 });
    const mid = A.handover(0.35, 0.35);
    assert.ok(mid.shared > 0.5 && mid.cardOwn === 0 && mid.compactOwn === 0);
    // The card's extra lines leave in the first part of the fold, while the icon and title are still near their card place.
    assert.equal(A.handover(0.6, 0.35).cardOwn, 0);
    assert.ok(A.handover(0.85, 0.35).cardOwn > 0.5);
});

test("a click on an info in the island grows it where it is: folded its card opens again, open it opens whole", () => {
    assert.equal(G.click("compact", 2), "reopen");
    assert.equal(G.click("big", 1), "open");
    // Nothing of a burst left: the click keeps the island's own role.
    assert.equal(G.click("rest", 0), "");
    assert.equal(G.click("compact", 0), "");
});

test("a face that swelled on arrival swells again while hovered once folded, never another face, a notification, open or upright", () => {
    const s = { "hovered": true, "owner": "dms:code2fa:1", "face": "dms:code2fa:1", "notification": false, "expanded": false, "vertical": false };
    assert.equal(G.hoverSwell(s), true);
    for (const [k, v] of [["hovered", false], ["owner", ""], ["face", "volume"], ["notification", true], ["expanded", true], ["vertical", true]])
        assert.equal(G.hoverSwell(Object.assign({}, s, { [k]: v })), false, k);
});

test("the keyboard's arrival calls open, turn and tidy as the gestures do, and say when the island cannot", () => {
    const calls = [];
    const arrival = can => ({
        open: () => (calls.push("open"), can),
        step: d => (calls.push("step " + d), can),
        tidy: () => (calls.push("tidy"), can)
    });
    assert.equal(G.ipcArrival(arrival(true), "open", "DANK_ISLAND"), "DANK_ISLAND_ARRIVAL_OPEN");
    assert.equal(G.ipcArrival(arrival(true), "next", "DANK_ISLAND"), "DANK_ISLAND_ARRIVAL_NEXT");
    assert.equal(G.ipcArrival(arrival(true), "prev", "DANK_ISLAND"), "DANK_ISLAND_ARRIVAL_PREV");
    assert.equal(G.ipcArrival(arrival(false), "tidy", "DANK_ISLAND"), "DANK_ISLAND_ARRIVAL_UNAVAILABLE: tidy");
    assert.equal(G.ipcArrival(arrival(true), "shake", "DANK_ISLAND"), "DANK_ISLAND_ARRIVAL_ACTION_UNKNOWN: shake");
    assert.deepEqual(calls, ["open", "step 1", "step -1", "tidy"]);
    // A swipe too short or diagonal names no action: nothing runs.
    assert.equal(G.runArrival(arrival(true), G.swipe(4, 0, undefined, false)), undefined);
    assert.equal(calls.length, 4);
});
