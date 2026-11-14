import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const visuals = loadScript(new URL("../Modules/DDash/Weather/WeatherVisuals.js", import.meta.url));

// The WHO's Global Solar UV Index: 0-2 low, 3-5 moderate, 6-7 high, 8-10 very high,
// 11+ extreme, for the index rounded to a whole number.
test("uvCategory rounds the index before the WHO categories", () => {
    const values = [0, 2.4, 2.5, 5.4, 5.5, 7.4, 7.5, 10.4, 10.5, 14];
    assert.deepEqual(values.map(visuals.uvCategory), [0, 0, 1, 1, 2, 2, 3, 3, 4, 4]);
});

test("uvIndex is the whole number shown, null without a reading", () => {
    assert.deepEqual([2.15, 2.6, 0, 11.49].map(visuals.uvIndex), [2, 3, 0, 11]);
    assert.equal(visuals.uvIndex(null), null);
    assert.equal(visuals.uvIndex(NaN), null);
    assert.equal(visuals.uvIndex(-1), null);
    // A provider rounding error just below zero is still 0, not -0 or missing.
    assert.ok(Object.is(visuals.uvIndex(-0.3), 0));
    assert.equal(visuals.uvIndex("3"), null);
    assert.equal(visuals.uvIndex(undefined), null);
    assert.equal(visuals.uvCategory(null), -1);
});
