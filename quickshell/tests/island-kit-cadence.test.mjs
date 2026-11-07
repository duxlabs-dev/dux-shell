import assert from "node:assert/strict";
import test from "node:test";
import { K, KC } from "./island-kit-load.mjs";

test("a costly frame is drawn once its refreshes are counted, and only once it moved half a pixel", () => {
    assert.equal(K.cadenceDue(1, 4, 4), false);
    assert.equal(K.cadenceDue(4, 4, 4), true);
    assert.equal(K.cadenceDue(4, 4, 0.2), false);
    assert.equal(K.cadenceDue(9, 4, 0.5), true);
    // Counted in time (refreshes gone by, not ticks), within half a refresh: a timer's ticks off the vsync still land.
    assert.equal(K.cadenceDue(3.4, 4, 4), false);
    assert.equal(K.cadenceDue(3.6, 4, 4), true);
});

test("a screen's refresh is read from niri's outputs, its current mode, 0 when unknown", () => {
    const outputs = {
        "DP-2": { "current_mode": 1, "modes": [{ "refresh_rate": 60000 }, { "refresh_rate": 240084 }] },
        "HDMI-A-1": { "current_mode": 0, "modes": [{ "refresh_rate": 59951 }] }
    };
    assert.ok(Math.abs(K.screenRefresh(outputs, "DP-2") - 240.084) < 1e-9);
    assert.ok(Math.abs(K.screenRefresh(outputs, "HDMI-A-1") - 59.951) < 1e-9);
    assert.equal(K.screenRefresh(outputs, "eDP-1"), 0);
    assert.equal(K.screenRefresh(null, "DP-2"), 0);
    // A decor paced on a timer ticking ~260 times a second, at 240 Hz and 4 refreshes apart: one frame per ~16.7 ms.
    let refreshes = 0, frames = 0;
    for (let i = 0; i < 2600; i++) {
        refreshes += 240.084 / 260;
        if (K.cadenceDue(refreshes, 4, 1)) {
            frames += 1;
            refreshes = K.cadenceCarry(refreshes, 4);
        }
    }
    assert.ok(frames >= 59 * 10 && frames <= 61 * 10, `${frames}`);
    assert.ok(Math.abs(K.cadenceCarry(4.3, 4) - 0.3) < 1e-9);
    assert.equal(K.cadenceCarry(9, 4), 0.5);
});

test("a decor's rate always divides the screen's, from 24 to 120 per second", () => {
    const rates = { "240": [120, 80, 60, 48, 40, 30, 24], "60": [60, 30], "144": [72, 48, 36, 28.8, 24] };
    for (const hz of [240, 60, 144])
        for (let speed = 0; speed < 2000; speed += 7) {
            const k = K.framesBetween(hz, speed, 0);
            assert.ok(Number.isInteger(k) && k >= 1, `${hz} Hz ${speed} px/s`);
            assert.ok(rates[hz].includes(hz / k), `${hz} Hz ${speed} px/s gives ${hz / k}`);
        }
});

test("a decor is drawn as seldom as keeps each step within a pixel", () => {
    // 60 px/s on 240 Hz: 60 per second (4 refreshes) is a pixel a frame.
    assert.equal(K.framesBetween(240, 60, 0), 4);
    assert.equal(K.framesBetween(240, 80, 0), 3);
    assert.equal(K.framesBetween(240, 100, 0), 2);
    // Slow drift rests at 24, fast rain stops at 120; a 60 Hz screen gives 30 and 60.
    assert.equal(K.framesBetween(240, 5, 0), 10);
    assert.equal(K.framesBetween(240, 470, 0), 2);
    assert.equal(K.framesBetween(60, 5, 0), 2);
    assert.equal(K.framesBetween(60, 470, 0), 1);
    // A measured refresh a little off still lands on the same steps.
    assert.equal(K.framesBetween(239.6, 470, 0), 2);
    assert.equal(K.framesBetween(121, 470, 0), 1);
    assert.equal(K.framesBetween(59.9, 5, 0), 2);
});

test("a decor speeds up at once but slows one refresh at a time, and never flaps on the edge", () => {
    assert.equal(K.framesBetween(240, 200, 10), 2);
    assert.equal(K.framesBetween(240, 5, 2), 3);
    // 60 px/s fits 4 refreshes, but 3 is kept: a step would not stay well under the pixel.
    assert.equal(K.framesBetween(240, 60, 3), 3);
    assert.equal(K.framesBetween(240, 60, 4), 4);
    assert.equal(K.framesBetween(240, 60, 5), 4);
    // The screen slowed under it (240 to 60 Hz): back within its range at once.
    assert.equal(K.framesBetween(60, 5, 10), 2);
});

test("a 144 Hz or 59.95 Hz screen reads as itself", () => {
    assert.equal(K.framesBetween(143.2, 5.7, 0), 6);
    assert.equal(K.framesBetween(59.95, 5.7, 0), 2);
});

// A test oracle: the cadence rule written the plain way, with arrays and its numbers spelled out (120, 0.05, 24, 0.8),
// so a change to the kit's allocation-free constants or loops fails here.
const plain = {
    panelRates: [24, 30, 48, 50, 60, 72, 75, 85, 90, 100, 120, 144, 165, 170, 175, 180, 200, 240, 280, 300, 360, 480],
    panelRate(refresh) {
        return plain.panelRates.reduce((best, r) => Math.abs(r - refresh) < Math.abs(best - refresh) ? r : best, plain.panelRates[0]);
    },
    framesBetween(refresh, speed, prev) {
        const hz = plain.panelRate(refresh);
        const fewest = Math.max(1, Math.ceil(hz / 120 - 0.05));
        const most = Math.max(fewest, Math.floor(hz / 24 + 0.05));
        const fit = px => Math.max(fewest, Math.min(most, Math.floor(px * hz / (speed > 1e-3 ? speed : 1e-3))));
        const k = fit(1);
        if (!(prev > 0) || k < prev)
            return k;
        return Math.max(fewest, Math.min(most, fit(0.8) > prev ? prev + 1 : prev));
    }
};

// A wing's card written the plain way, carded as a plain value.
function oldCardOpen(w) {
    if (!w.has || w.vertical)
        return false;
    if (w.tileOpen && w.tileOpenable)
        return true;
    const asked = w.hovered && w.dwelt || w.heldOpen;
    return !!asked && (!(w.cardness >= 0.5) || w.carded);
}
const near = (a, b, what) => assert.ok(a === b || Math.abs(a - b) <= 1e-12, `${what}: ${a} != ${b}`);

test("the decors' cadence matches the plain rule on 60, 120, 144 and 240 Hz screens, 0 to 5000 px/s", () => {
    for (const base of [60, 120, 144, 240])
        for (const hz of [base - 0.4, base, base + 0.084, base + 0.4])
            for (let speed = 0; speed <= 5000; speed += speed < 50 ? 0.25 : 3.7)
                for (const prev of [0, 1, 2, 3, 4, 5, 6, 8, 10, 12, -1, NaN])
                    near(K.framesBetween(hz, speed, prev), plain.framesBetween(hz, speed, prev), `${hz} Hz ${speed} px/s prev ${prev}`);
    for (const r of [NaN, 0, 23, 27, 59.95, 61, 122, 143.2, 239.6, 1000])
        near(K.panelRate(r), plain.panelRate(r), `rate ${r}`);
});

test("a wing's card opens exactly as before, from its plain values", () => {
    const keys = ["has", "vertical", "tileOpen", "tileOpenable", "hovered", "dwelt", "heldOpen", "carded"];
    for (let bits = 0; bits < 1 << keys.length; bits++)
        for (const cardness of [0, 0.49, 0.5, 1, NaN]) {
            const w = { cardness };
            keys.forEach((k, i) => w[k] = (bits >> i & 1) === 1);
            assert.equal(K.cardOpen({ ...w, "carded": () => w.carded }), oldCardOpen(w), JSON.stringify(w));
        }
});

test("a window's clock steps one screen period, or the periods gone by when an image was skipped", () => {
    const p = 1 / 240;
    assert.equal(KC.clockStep(p, 0.0041), p);
    // The first step after a start, or a late wall clock within half a period: one period, never a fraction.
    assert.equal(KC.clockStep(p, 0), p);
    assert.equal(KC.clockStep(p, p * 1.49), p);
    assert.equal(KC.clockStep(p, p * 2.9), 3 * p);
    assert.equal(KC.clockStep(p, 0.0167), 4 * p);
    assert.equal(KC.clockStep(1 / 60, 0.0167), 1 / 60);
    // No period (a screen not read yet): the elapsed time itself, never NaN.
    assert.equal(KC.clockStep(0, 0.0167), 0.0167);
    assert.equal(KC.clockStep(0, -1), 0);
    assert.equal(KC.clockStep(NaN, 0.01), 0.01);
});

test("a decor's clock ticks 60 times a second on any screen: one refresh apart at 60 Hz, four at 240, a 17 ms Timer", () => {
    assert.equal(KC.clockEvery(240.084), 4);
    assert.equal(KC.clockEvery(59.951), 1);
    assert.equal(KC.clockEvery(144), 2);
    assert.equal(KC.clockEvery(0), 1);
    for (const hz of [59.951, 240.084])
        assert.equal(Math.round(1000 * KC.clockEvery(hz) / hz), 17);
    // The Timer's whole milliseconds (16 to 18 for 17) fold to the clock's refreshes, never to a fraction or a double step.
    for (const ms of [0.016, 0.017, 0.018]) {
        assert.ok(Math.abs(KC.clockStep(1 / 240.084, ms) - 4 / 240.084) < 1e-12, `${ms} at 240`);
        assert.ok(Math.abs(KC.clockStep(1 / 59.951, ms) - 1 / 59.951) < 1e-12, `${ms} at 60`);
    }
});

test("a decor's clock counts a refresh that is no positive number (NaN, 0, below) at the fallback rate", () => {
    for (const r of [NaN, 0, -60, undefined])
        assert.equal(KC.clockRate(r), K.fallbackHz, `${r}`);
    assert.equal(KC.clockRate(143.9), 143.9);
});

test("a decor's clock counts a refresh past the fastest panel (Infinity, huge) at that panel's rate, its Timer above 0 ms", () => {
    const fastest = K.panelRates[K.panelRates.length - 1];
    for (const r of [Infinity, 1e308, 2e11, 4294967.295]) {
        const hz = KC.clockRate(r);
        assert.equal(hz, fastest, `${r}`);
        assert.equal(Math.round(1000 * KC.clockEvery(hz) / hz), 17, `${r}`);
    }
    assert.equal(KC.clockRate(fastest), fastest);
});

test("a decor holds its cadence five frames before stepping down, and forgets its vote after 750 ms without a frame", () => {
    // Fast (2 apart at 240 Hz, its fewest), then slow: framesBetween alone steps down one notch a frame; held under 5 frames, it stays.
    assert.equal(K.framesBetween(240, 2000, 2), 2);
    assert.equal(K.framesBetween(240, 10, 2), 3);
    assert.equal(KC.framesHeld(240, 10, 2, 4, 100), 2);
    assert.equal(KC.framesHeld(240, 10, 2, 5, 100), 3);
    // Speeding up is never held.
    assert.equal(KC.framesHeld(240, 2000, 8, 0, 100), 2);
    // No frame for 750 ms: the vote is forgotten, the measured speed alone decides (no gradual step).
    assert.equal(KC.framesHeld(240, 10, 2, 0, 750), K.framesBetween(240, 10, 0));
    assert.ok(KC.framesHeld(240, 10, 2, 0, 750) > 2);
    assert.equal(KC.framesHeld(240, 10, 2, 0, 749), 2);
});
