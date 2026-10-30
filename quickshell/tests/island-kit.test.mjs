import assert from "node:assert/strict";
import test from "node:test";
import { K } from "./island-kit-load.mjs";

test("the button row fills the width exactly, by weight, whole pixels", () => {
    for (const [total, weights, gap] of [[368, [1, 1, 2, 2], 8], [400, [1], 8], [401, [1, 1, 1], 4], [333, [2, 1], 8]]) {
        const cells = K.rowLayout(total, weights, gap);
        const last = cells[cells.length - 1];
        assert.equal(last.x + last.width, total, `${weights} in ${total}`);
        cells.forEach(c => assert.ok(Number.isInteger(c.width) && Number.isInteger(c.x)));
    }
    const call = K.rowLayout(368, [1, 1, 2, 2], 8);
    assert.ok(Math.abs(call[2].width - 2 * call[0].width) <= 1);
    assert.ok(Math.abs(call[0].width - call[1].width) <= 1);
});

test("no weight or a bad weight still gives equal parts, never a negative width", () => {
    const cells = K.rowLayout(300, [0, 0, 0], 0);
    assert.deepEqual(cells.map(c => c.width), [100, 100, 100]);
    assert.equal(K.rowLayout(0, [1, 1], 8).length, 0);
    assert.ok(K.rowLayout(10, [1, 1, 1, 1], 8).every(c => c.width >= 0));
});

test("the liquid front is mirrored, flat without amplitude, and its slope matches it", () => {
    assert.equal(K.wave(0.3, 0, 1.2), 0);
    assert.ok(Math.abs(K.wave(0, 5, 0)) < 1e-9);
    assert.ok(Math.abs(K.wave(0.5, 5, 0) - 5) < 1e-9);
    const h = 1e-6;
    for (const d of [0, 0.25, 0.5, 0.9]) {
        const num = (K.wave(d + h, 4, 0.7) - K.wave(d - h, 4, 0.7)) / (2 * h);
        assert.ok(Math.abs(num - K.waveSlope(d, 4, 0.7)) < 1e-4, `slope at ${d}`);
    }
});

test("springs slow down with DMS's animation speed and keep their damping ratio", () => {
    const ratio = s => s.damping / (2 * Math.sqrt(s.stiffness * s.mass));
    const normal = K.spring("cell", 250);
    const slow = K.spring("cell", 1000);
    assert.ok(Math.abs(ratio(normal) - ratio(slow)) < 1e-9);
    assert.ok(Math.abs(Math.sqrt(normal.stiffness / slow.stiffness) - 4) < 1e-9);
    assert.deepEqual(K.spring("nope", 250), K.spring("cell", 250));
});

test("content beats follow DMS's animation speed and stop at speed 0", () => {
    assert.equal(K.beat("ringPause", 250), 1000);
    assert.equal(K.beat("ringPause", 500), 2000);
    assert.equal(K.beat("ringPause", 0), 0);
    assert.equal(K.beat("nope", 250), 250);
});

test("a cubic bezier easing matches the CSS curve: ends pinned, monotone, known midpoints", () => {
    assert.equal(K.bezier(0.2, 0, 0, 1, 0), 0);
    assert.equal(K.bezier(0.2, 0, 0, 1, 1), 1);
    // ease-in-out (.42,0,.58,1) is symmetric about the middle.
    assert.ok(Math.abs(K.bezier(0.42, 0, 0.58, 1, 0.5) - 0.5) < 1e-4);
    assert.ok(Math.abs(K.bezier(0.42, 0, 0.58, 1, 0.25) + K.bezier(0.42, 0, 0.58, 1, 0.75) - 1) < 1e-4);
    // Accelerate starts slow, emphasized starts fast.
    assert.ok(K.bezier(0.5, 0, 0.75, 0, 0.5) < 0.2);
    assert.ok(K.bezier(0.2, 0, 0, 1, 0.3) > 0.6);
    let last = 0;
    for (let x = 0.02; x <= 1; x += 0.02) {
        const y = K.bezier(0.5, 0, 0.75, 0, x);
        assert.ok(y >= last - 1e-9);
        last = y;
    }
});
