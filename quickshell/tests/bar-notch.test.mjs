import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const geometry = loadScript(new URL("../Common/NotchGeometry.js", import.meta.url));
const center = loadScript(new URL("../Modules/DBar/CenterLayout.js", import.meta.url));
const overflow = loadScript(new URL("../Modules/DBar/OverflowLayout.js", import.meta.url));
const plain = value => JSON.parse(JSON.stringify(value));
const apple = ["apple,j514s", "apple,t6030", "apple,arm-platform"];

test("a notch is found only on an Apple device tree at a native notched mode", () => {
    const cases = [
        [apple, 1512, 982, 2, { start: 664, end: 848, height: 32 }],
        [apple, 3024, 1964, 1, { start: 1328, end: 1696, height: 64 }],
        [["apple,j314s", "apple,t6000", "apple,arm-platform"], 1728, 1122, 1.75, { start: 864 - 368 / 3.5, end: 864 + 368 / 3.5, height: 64 / 1.75 }],
        [apple, 1512, 945, 2, null],
        [apple, 982, 1512, 2, null],
        [apple, 1920, 1080, 1, null],
        [["raspberrypi,4-model-b", "brcm,bcm2711"], 1512, 982, 2, null],
        [[], 1512, 982, 2, null],
        [undefined, 1512, 982, 2, null],
        [apple, 0, 0, 2, null]
    ];
    for (const [compatible, width, height, scale, expected] of cases)
        assert.deepEqual(plain(geometry.cutout(compatible, width, height, scale)), expected, `${width}x${height}@${scale}`);
});

test("a split center keeps its order and never enters the gap", () => {
    const gap = { start: 656, end: 856 };
    const cases = [
        [[30, 80, 60], [542, 576, 856], 2],
        [[30, null, 60, 20], [562, null, 596, 856], 3],
        [[10, 20, 30, 40], [622, 636, 856, 890], 2],
        [[50], [606], -1]
    ];
    for (const mode of ["geometric", "index"]) {
        for (const [sizes, positions, split] of cases) {
            const result = center.resolve(sizes, 1512, 4, mode, { min: 700, max: 800 }, undefined, gap);
            assert.deepEqual(plain(result.positions), positions, `${mode} ${sizes}`);
            assert.equal(result.split, split);
            const live = sizes.map((size, index) => [result.positions[index], size]).filter(([position]) => position !== null);
            for (let index = 0; index < live.length; index++) {
                const [position, size] = live[index];
                assert.ok(position + size <= gap.start || position >= gap.end, `${sizes} widget ${index} enters the gap`);
                if (index > 0)
                    assert.ok(position >= live[index - 1][0] + live[index - 1][1] + 4, `${sizes} widget ${index} overlaps its neighbour`);
            }
            assert.equal(result.totalSize, Math.max(live.at(-1)[0] + live.at(-1)[1], gap.end) - live[0][0], `${sizes} extent stops short of the gap`);
        }
    }
    assert.deepEqual(plain(center.resolve([30, 80, 60], 600, 4, "index", null, undefined, null)), plain(center.resolve([30, 80, 60], 600, 4, "index")));
});

const entry = (size, mode = "bar") => ({ size, mode, priority: 0 });
const solve = (left, middle, right, extra = {}) => overflow.resolve({ left, center: middle, right }, { length: 400, spacing: 4, triggerSize: 30, restoreMargin: 8, notch: { start: 180, end: 220 }, ...extra });

test("side widgets reaching under the notch overflow", () => {
    const result = solve([entry(100), entry(90, "auto")], [], []);
    assert.deepEqual(plain(result.hidden), { left: [1], center: [], right: [] });
    assert.equal(result.fits, true);
});

test("a split center is measured as two runs beside the notch", () => {
    const alone = solve([], [entry(60, "auto"), entry(60, "auto")], []);
    assert.deepEqual(plain(alone.hidden.center), []);
    assert.deepEqual(plain(alone.intervals.center), { start: 120, end: 280, size: 160 });
    const crowded = solve([], [entry(60), entry(60)], [entry(100, "auto"), entry(20)]);
    assert.deepEqual(plain(crowded.hidden), { left: [], center: [], right: [0] });
    assert.equal(crowded.fits, true);
});

test("the notch and an island reserve both push widgets out", () => {
    const result = solve([entry(140), entry(40, "auto")], [], [entry(60, "auto"), entry(20)], { reserve: { start: 300, end: 340 } });
    assert.deepEqual(plain(result.hidden), { left: [1], center: [], right: [0] });
    assert.equal(result.fits, true);
});

test("a fitted bar packs its right section past the notch even with nothing after it", () => {
    const fitted = { confineCenter: true };
    const lone = solve([], [entry(40)], [entry(40)], fitted);
    assert.deepEqual(plain(lone.intervals.center), { start: 140, end: 220, size: 80 });
    const tight = solve([], [entry(40)], [entry(144, "auto"), entry(30)], fitted);
    assert.deepEqual(plain(tight.hidden), { left: [], center: [], right: [0] });
    assert.equal(tight.fits, true);
});

test("a gap without room for the overflow holder on both sides is not used", () => {
    const cases = [
        [{ start: 656, end: 856 }, 0, 1512, true],
        [{ start: -24, end: 176 }, 0, 152, false],
        [{ start: 20, end: 220 }, 0, 400, false],
        [{ start: 40, end: 220 }, 12, 400, false],
        [{ start: 180, end: 375 }, 0, 400, false],
        [null, 0, 400, false]
    ];
    for (const [gap, min, max, usable] of cases)
        assert.equal(center.usableGap(gap, min, max, 30), usable ? gap : null, JSON.stringify(gap));
});
