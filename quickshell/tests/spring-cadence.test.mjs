import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

// The surface springs run their frame loop through this fold, driven here as VectorSpringMotion
// drives it, with a steady screen, counting the steps it takes and the time they carry.
const cadence = loadScript(new URL("../Common/FrameCadence.js", import.meta.url));

function frame(pending, frameTime) {
    const t = cadence.fold(pending, frameTime);
    return { "step": Math.max(0, t), "pending": Math.max(0, -t) };
}

function run(hz, frames) {
    const steps = [];
    let pending = 0;
    for (let i = 0; i < frames; i++) {
        const f = frame(pending, 1 / hz);
        pending = f.pending;
        if (f.step > 0)
            steps.push(f.step);
    }
    return { steps, carried: steps.reduce((a, b) => a + b, 0) + pending };
}

test("a frame time that is not a number, or negative, neither steps nor spoils the time folded so far", () => {
    for (const bad of [NaN, Infinity, -0.003]) {
        assert.deepEqual(frame(0.004, bad), { "step": 0, "pending": 0.004 });
    }
    assert.ok(Math.abs(frame(frame(0.004, NaN).pending, 0.005).step - 0.009) < 1e-12);
});

test("a spring steps on every frame up to 120 Hz, at 120 a second at most above", () => {
    for (const [hz, every] of [[60, 1], [120, 1], [144, 2], [165, 2], [240, 2], [480, 4]]) {
        const { steps, carried } = run(hz, 480);
        assert.equal(steps.length, 480 / every, `${hz} Hz`);
        assert.ok(Math.abs(carried - 480 / hz) < 1e-9, `${hz} Hz: no time lost`);
    }
});
