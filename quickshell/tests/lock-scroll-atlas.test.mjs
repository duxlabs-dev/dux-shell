import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const atlas = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/LockScrollAtlas.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), atlas);

test("the scroll window follows the axis the lock shader scrolls", () => {
    const cases = [
        ["tall image scrolls vertically", 1000, 3000, 2000, 1000, 0, 0, { x: 0, y: 0, width: 1, height: 1 / 6 }],
        ["tall image at the last workspace", 1000, 3000, 2000, 1000, 100, 100, { x: 0, y: 5 / 6, width: 1, height: 1 / 6 }],
        ["wide image scrolls horizontally", 6000, 1000, 2000, 1000, 50, 0, { x: 1 / 3, y: 0, width: 1 / 3, height: 1 }],
        ["matching aspect stays centred", 4000, 2000, 2000, 1000, 100, 100, { x: 0, y: 0, width: 1, height: 1 }]
    ];
    for (const [name, iw, ih, sw, sh, sx, sy, expected] of cases) {
        const view = atlas.scrollWindow(iw, ih, sw, sh, sx, sy);
        for (const key of ["x", "y", "width", "height"])
            assert.ok(Math.abs(view[key] - expected[key]) < 1e-9, `${name}: ${key} ${view[key]} != ${expected[key]}`);
    }
});

test("crops pick the atlas rows the lock shows at each scroll position", () => {
    const size = atlas.atlasSize(1000, 3000, 2000, 1000, 4, 2);
    assert.deepEqual({ ...size }, { width: 4, height: 12 });
    const rows = Array.from({ length: size.width * size.height }, (_, i) => Math.floor(i / size.width));
    const sampleAt = scroll => atlas.crop(rows, size.width, size.height, atlas.scrollWindow(1000, 3000, 2000, 1000, 0, scroll), 4, 2);
    assert.deepEqual([...sampleAt(0)], [0, 0, 0, 0, 1, 1, 1, 1]);
    assert.deepEqual([...sampleAt(100)], [10, 10, 10, 10, 11, 11, 11, 11]);
});
