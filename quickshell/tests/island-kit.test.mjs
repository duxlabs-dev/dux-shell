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
    // The island's own spring, from its settings, stretches the same way.
    const own = K.stretch([400, 20, 1], 500);
    assert.deepEqual([own.stiffness, own.damping, own.mass], [100, 10, 1]);
});

test("content beats follow DMS's animation speed and stop at speed 0", () => {
    assert.equal(K.beat("ringPause", 250), 1000);
    assert.equal(K.beat("ringPause", 500), 2000);
    assert.equal(K.beat("ringPause", 0), 0);
    assert.equal(K.beat("nope", 250), 250);
});

test("a face row is centred on its ink, not on its glyph boxes, to the whole pixel", () => {
    // A 16 px icon box holding a 12 px-advance glyph whose ink starts 1 px in: 3 px of air before the ink.
    assert.equal(K.boxBearing(16, 12, 1), 3);
    assert.equal(K.boxBearing(16, 16, 0), 0);
    // 3 px of air before, 1 px after in a 100 px row of a 120 px face: x 9 so both sides show 12 px of air.
    assert.equal(K.inkCentredX(120, 100, 3, 1), 9);
    assert.equal(K.inkCentredX(120, 100, 1, 5), 12);
    assert.equal(K.inkCentredX(120, 100, 2, 2), 10);
    // The row's own fractional width counts too: one rounding, on the final x.
    assert.equal(K.inkCentredX(282, 199.53, 1.5, 0.37), 41);
    for (const [w, row, lead, trail] of [[120, 100, 3, 0], [120, 100, 0, 3], [282, 199.53, 4.6, 1.2], [281, 124.58, 3.37, 0.37]]) {
        const x = K.inkCentredX(w, row, lead, trail);
        assert.ok(Number.isInteger(x) && Math.abs((x + lead) - (w - x - row + trail)) <= 1, `${w}/${row}/${lead}/${trail}`);
    }
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

test("the fusion runs on one spring: gathered, then one continuous flow that stretches, thins and lands softly", () => {
    // wt = ω·t of the wing's exit spring (critically damped); the shape touches the island halfway along its way.
    const at = wt => K.fusionPhases(wt, 0.5);
    const p0 = at(0);
    assert.deepEqual([p0.text, p0.gather, p0.along, p0.glow, p0.swell, p0.flowing, p0.done], [1, 0, 0, 0, 0, false, false]);
    assert.ok(at(1.2).text === 0 && at(1.2).gather > 0.99);
    // Its speed never jumps: no step between two frames is far from the one before (gather, flow, melt alike).
    const dt = 0.05;
    let prev = 0, last = at(0);
    for (let wt = dt; wt < 12; wt += dt) {
        const p = at(wt);
        const step = p.along - last.along;
        assert.ok(step >= 0 && Math.abs(step - prev) < 0.01, `speed jumps at ${wt.toFixed(2)}`);
        assert.ok(p.gather >= last.gather && p.text <= last.text);
        // Moving, it stretches along its way and thins across, more the faster it goes; at rest it is round.
        assert.ok(p.scaleAlong >= p.scaleCross - 1e-9);
        prev = step;
        last = p;
    }
    // It lands with no jolt: barely moving at the end.
    assert.ok(at(9).along - at(8.95).along < 1e-3);
    assert.ok(at(12).done);
});

test("a critically damped step waits for its release, then rises to its target without overshoot", () => {
    assert.equal(K.criticalStep(-1), 0);
    assert.equal(K.criticalStep(0), 0);
    assert.ok(Math.abs(K.criticalStep(1) - (1 - 2 / Math.E)) < 1e-12);
    const xs = [0.25, 1, 2, 4, 8, 30];
    xs.slice(1).forEach((x, i) => assert.ok(K.criticalStep(x) > K.criticalStep(xs[i]), `rises at ${x}`));
    assert.ok(K.criticalStep(30) < 1 && K.criticalStep(30) > 1 - 1e-9);
});

test("a tone laid over a surface mixes them by its alpha, channel by channel", () => {
    const tone = { "r": 1, "g": 0.5, "b": 0 }, surface = { "r": 0, "g": 0.5, "b": 1 };
    assert.deepEqual({ ...K.laidOver(tone, surface, 0) }, surface);
    assert.deepEqual({ ...K.laidOver(tone, surface, 1) }, tone);
    assert.deepEqual({ ...K.laidOver(tone, surface, 0.25) }, { "r": 0.25, "g": 0.5, "b": 0.75 });
});

test("the fusion's glow: a halo born at the contact, spreading like a wave on the island's spring, fading out", () => {
    const at = wt => K.fusionPhases(wt, 0.5);
    let contact = -1;
    for (let wt = 0; wt < 12 && contact < 0; wt += 0.01)
        if (at(wt).along >= 0.5)
            contact = wt;
    assert.ok(contact > 0);
    // Nothing lights before the shape touches the island.
    assert.equal(at(contact - 0.05).glow, 0);
    assert.equal(at(contact - 0.05).wave, 0);
    // Then a halo from the contact point, its front moving out while it pales, and gone at the end.
    let last = at(contact);
    for (let t = 0.1; t < 8; t += 0.1) {
        const p = at(contact + t);
        assert.ok(p.wave >= last.wave && p.glow <= last.glow + 1e-9, `at ${t.toFixed(1)}`);
        last = p;
    }
    assert.ok(at(contact + 1).wave > 0.2 && at(contact + 1).glow > 0.2);
    assert.ok(at(contact + 8).glow < 0.01 && at(contact + 8).swell < 0.02);
});

test("a bubble is opaque two thirds into its birth and grows from half its size, overshoot held", () => {
    assert.deepEqual([0, 1 / 3, 2 / 3, 1, 1.2].map(p => K.appearOpacity(p)), [0, 0.5, 1, 1, 1]);
    assert.deepEqual([0, 0.5, 1, 1.2, NaN].map(p => K.appearScale(p)), [0.5, 0.75, 1, 1, 0.5]);
});

test("the fusion lights the island's edge with the launcher closed too: flat pill or tile, both sides", () => {
    // The shape flows from where the wing gathered (beside the island, one gap away), never from where its icon sat on the
    // long open pill: measured from there, a flat pill's shape never reached the island and its edge never lit.
    const size = 32, reach = 1.5;
    for (const gap of [4, 12]) {
        const contact = K.fuseContact(gap, size, reach);
        assert.ok(contact > 0 && contact < 1, `gap ${gap}: contact ${contact}`);
        let lit = 0;
        for (let wt = 0; wt < 12; wt += 0.05)
            lit = Math.max(lit, K.fusionPhases(wt, contact).glow);
        assert.ok(lit > 0.5, `gap ${gap}: glow ${lit}`);
    }
    // A flat pill on a quiet island (the clock) fuses.
    assert.equal(K.closeStyle({ "inPlace": true, "reduced": false, "occupantBefore": "home|", "occupantNow": "home|" }), "fuse");
});
