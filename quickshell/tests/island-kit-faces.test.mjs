import assert from "node:assert/strict";
import test from "node:test";
import { K } from "./island-kit-load.mjs";

test("an alert's rings, read off their clock: two leave a gap apart, each is gone after its span, then it is over", () => {
    const span = 1300, gap = K.beat("ringGap", 250), pause = K.beat("ringPause", 250);
    assert.ok(gap > 0 && gap < span && pause > gap);
    // One ring: it grows from 0, is gone at its span (1 = not out).
    assert.equal(K.ringT(0, span, gap, 1, pause, 1, 0), 0);
    assert.equal(K.ringT(span / 2, span, gap, 1, pause, 1, 0), 0.5);
    assert.equal(K.ringT(span, span, gap, 1, pause, 1, 0), 1);
    assert.ok(!K.ringsOver(span - 1, span, gap, 1, pause, 1));
    assert.ok(K.ringsOver(span, span, gap, 1, pause, 1));
    // Two rings: the second leaves one gap later, while the first still grows.
    assert.equal(K.ringT(gap / 2, span, gap, 2, pause, 1, 1), 1);
    assert.equal(K.ringT(gap, span, gap, 2, pause, 1, 0), gap / span);
    assert.equal(K.ringT(gap, span, gap, 2, pause, 1, 1), 0);
    assert.equal(K.ringT(span + 1, span, gap, 2, pause, 1, 0), 1);
    assert.ok(K.ringsOver(span + gap, span, gap, 2, pause, 1));
    // No animations: over at once.
    assert.ok(K.ringsOver(0, 0, 0, 2, 0, 1));
    assert.equal(K.ringT(0, 0, 0, 2, 0, 1, 0), 1);
    assert.equal(K.beat("ringGap", 0), 0);
});

test("a ringing call rings again after a pause, forever, and its shape swings on each ring, still in the pause", () => {
    const span = 1300, gap = K.beat("ringGap", 250), pause = K.beat("ringPause", 250);
    const cycle = gap + span + pause;
    // cycles 0: never over; the next cycle's rings leave as the first's did.
    assert.ok(!K.ringsOver(100 * cycle, span, gap, 2, pause, 0));
    assert.equal(K.ringT(cycle + gap, span, gap, 2, pause, 0, 1), 0);
    assert.equal(K.ringT(gap + span + pause / 2, span, gap, 2, pause, 0, 0), 1);
    assert.equal(K.ringT(gap + span + pause / 2, span, gap, 2, pause, 0, 1), 1);
    // The swing (-1..1) on the wing's entry spring: at rest as a ring leaves, kicked right after, settled in the pause.
    const swing = ms => K.ringSwing(ms, span, gap, 2, pause, 0, 220, 0.6, 1);
    assert.equal(swing(0), 0);
    const peak = Math.max(...Array.from({ length: 40 }, (_, i) => Math.abs(swing(i * 10))));
    assert.ok(peak > 0.9 && peak <= 1.2);
    assert.ok(Math.abs(swing(cycle - 1)) < 0.01);
    assert.equal(swing(cycle + 50), swing(50));
    // Over (one cycle done) or no animations: still.
    assert.equal(K.ringSwing(cycle * 2, span, gap, 2, pause, 1, 220, 0.6, 1), 0);
    assert.equal(K.ringSwing(50, 0, 0, 2, 0, 0, 220, 0.6, 1), 0);
    // A negative damping ratio would grow: still, as without stiffness.
    assert.equal(K.ringSwing(50, span, gap, 2, pause, 0, 220, -0.5, 1), 0);
});
