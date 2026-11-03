import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const history = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Modules/DBar/Popouts/BatteryHistory.js", import.meta.url), "utf8"), history);
const plain = value => JSON.parse(JSON.stringify(value));

test("history rejects missing, malformed, and out-of-range readings", () => {
    assert.deepEqual(plain(history.normalize(null, 100, 200)), []);
    const rows = [[100, 0, 3], [200, 100, 4], [99, 50, 2], [201, 50, 2], [150, -1, 2], [150, 101, 2], [150, NaN, 2], [150, Infinity, 2], [150, "50", 2], [150], null];
    assert.deepEqual(plain(history.normalize(rows, 100, 200)), [[100, 0, 3], [200, 100, 4]]);
});

test("history sorts timestamps and retains the last reading at a duplicate timestamp", () => {
    const rows = [[180, 70, 2], [120, 90, 2], [120, 85, 2], [160, 80, 2]];
    assert.deepEqual(plain(history.normalize(rows, 100, 200)), [[120, 85, 2], [160, 80, 2], [180, 70, 2]]);
    assert.equal(rows[0][0], 180);
});

test("unknown device states break the chart instead of joining across missing readings", () => {
    const rows = [[100, 90, 2], [120, 85, 2], [140, 0, 0], [160, 65, 2], [180, 60, 2]];
    assert.deepEqual(plain(history.segments(rows, 20)), [
        { kind: "normal", samples: [[100, 90, 2], [120, 85, 2]] },
        { kind: "normal", samples: [[160, 65, 2], [180, 60, 2]] }
    ]);
});

test("low charge and charging transitions share an endpoint without inventing samples", () => {
    const rows = [[100, 30, 2], [120, 20, 2], [140, 15, 1], [160, 25, 1]];
    assert.deepEqual(plain(history.segments(rows, 20)), [
        { kind: "normal", samples: [[100, 30, 2], [120, 20, 2]] },
        { kind: "low", samples: [[120, 20, 2], [140, 15, 1]] },
        { kind: "plugged", samples: [[140, 15, 1], [160, 25, 1]] }
    ]);
});

test("empty and entirely unknown history produce no chart segments", () => {
    assert.deepEqual(plain(history.segments([], 20)), []);
    assert.deepEqual(plain(history.segments([[100, 0, 0], [200, 0, 0]], 20)), []);
});

test("an unchanged charge retains its last recorded level at the window boundary", () => {
    assert.deepEqual(plain(history.windowSamples([[10, 99, 2], [20, 100, 4]], 100, 200, [200, 100, 4])), [[100, 100, 4], [200, 100, 4]]);
});

test("the current charge replaces an older reading at the same timestamp", () => {
    assert.deepEqual(plain(history.windowSamples([[100, 90, 2], [200, 80, 2]], 100, 200, [200, 78, 2])), [[100, 90, 2], [200, 78, 2]]);
});

test("unknown history at the window boundary stays a gap", () => {
    const rows = history.windowSamples([[10, 90, 2], [20, 0, 0]], 100, 200, [200, 80, 2]);
    assert.deepEqual(plain(history.segments(rows, 20)), [{ kind: "normal", samples: [[200, 80, 2]] }]);
});
