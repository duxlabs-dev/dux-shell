import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const layout = loadScript(new URL("../Modules/DBar/OverflowLayout.js", import.meta.url));
const entry = (size, mode = "bar", priority = 0) => ({ size, mode, priority });
const options = { length: 400, spacing: 4, triggerSize: 30, restoreMargin: 8 };
const plain = value => JSON.parse(JSON.stringify(value));
const solve = (left, center, right, extra = {}, previous = {}) => layout.resolve({ left, center, right }, { ...options, ...extra }, previous);

test("colliding sections overflow the nearest eligible occurrence and reserve their button", () => {
    const result = solve([entry(100), entry(90, "auto"), entry(20, "auto")], [entry(80)], []);
    assert.deepEqual(plain(result.hidden), { left: [1, 2], center: [], right: [] });
    assert.equal(result.fits, true);
    assert.equal(result.layouts.left.totalSize, 134);
});

test("always-overflow items retain order and the holder can sit between visible widgets", () => {
    const result = solve([entry(40), entry(80, "always"), entry(50)], [], [], { positions: { left: 1 } });
    assert.deepEqual(plain(result.layouts.left.positions), [0, null, 78]);
    assert.equal(result.layouts.left.buttonPosition, 44);
    assert.deepEqual(plain(result.hidden.left), [1]);
});

test("the longer colliding side yields before the shorter one", () => {
    const result = solve([entry(100), entry(50, "auto")], [], [entry(100), entry(100, "auto")], { length: 340 });
    assert.deepEqual(plain(result.hidden), { left: [], center: [], right: [1] });
    assert.equal(result.fits, true);
});

test("center eligibility resolves a collision with pinned side widgets", () => {
    const result = solve([entry(130)], [entry(80, "auto"), entry(80)], [entry(80)]);
    assert.deepEqual(plain(result.hidden.center), [0]);
    assert.equal(result.fits, true);
});

test("the lowest overflow priority yields first, ahead of nearer widgets and across sections", () => {
    const left = solve([entry(100), entry(90, "auto", -1), entry(20, "auto")], [entry(80)], [], { length: 420 });
    assert.deepEqual(plain(left.hidden.left), [1]);
    const across = solve([entry(100), entry(50, "auto", -1)], [], [entry(100), entry(100, "auto")], { length: 360 });
    assert.deepEqual(plain(across.hidden), { left: [1], center: [], right: [] });
});

test("the highest priority returns from overflow first", () => {
    const result = solve([entry(100), entry(60, "auto"), entry(60, "auto", 5)], [entry(80)], [], { length: 500 }, { left: [1, 2] });
    assert.deepEqual(plain(result.hidden.left), [1]);
});

test("pinned-only impossible layouts stop without hiding widgets", () => {
    const result = solve([entry(250)], [entry(150)], [entry(250)]);
    assert.equal(result.fits, false);
    assert.deepEqual(plain(result.hidden), { left: [], center: [], right: [] });
});

test("restoration needs the margin on top of the preferred size and never reintroduces a collision", () => {
    const sections = [[entry(100), entry(60, "auto")], [entry(80)], []];
    const previous = { left: [1] };
    assert.deepEqual(plain(solve(...sections, { length: 416 }, previous).hidden.left), [1]);
    assert.deepEqual(plain(solve(...sections, { length: 432 }, previous).hidden.left), []);
    const narrow = solve([entry(55), entry(4, "auto")], [entry(60)], [], { length: 200 }, previous);
    assert.equal(narrow.fits, true);
    assert.deepEqual(plain(narrow.hidden.left), []);
});

test("fitted bars can shift the center within side bounds before hiding widgets", () => {
    const entries = [[entry(210)], [entry(60, "auto")], [entry(40)]];
    assert.deepEqual(plain(solve(...entries).hidden.center), [0]);
    assert.deepEqual(plain(solve(...entries, { confineCenter: true }).hidden.center), []);
});

test("edge insets count against the available length", () => {
    const sections = [[entry(200), entry(80, "auto")], [], [entry(110)]];
    assert.deepEqual(plain(solve(...sections).hidden.left), []);
    assert.deepEqual(plain(solve(...sections, { start: 6, end: 6 }).hidden.left), [1]);
});

test("a reserved range overflows both sides clear of it", () => {
    const sections = [[entry(100), entry(60, "auto")], [], [entry(60, "auto"), entry(100)]];
    assert.deepEqual(plain(solve(...sections).hidden), { left: [], center: [], right: [] });
    const result = solve(...sections, { reserve: { start: 150, end: 250 } });
    assert.deepEqual(plain(result.hidden), { left: [1], center: [], right: [0] });
    assert.equal(result.fits, true);
});

test("a center holder does not replace the configured middle-widget anchor", () => {
    for (const position of [0, 1, 2, 3]) {
        const result = solve([], [entry(40, "always"), entry(80), entry(70)], [], { length: 600, centeringMode: "index", positions: { center: position } });
        const clockStart = result.intervals.center.start + result.layouts.center.positions[1];
        assert.equal(clockStart + 40, 300);
    }
});

test("flexible widgets shrink to their minimum before anything overflows", () => {
    const result = solve([entry(100), { size: 200, min: 60, mode: "auto" }], [entry(80)], [], { length: 500 });
    assert.deepEqual(plain(result.hidden), { left: [], center: [], right: [] });
    assert.deepEqual(plain(result.sizes.left), [100, 102]);
    assert.equal(result.fits, true);
    const tight = solve([entry(100), { size: 200, min: 60, mode: "auto" }], [entry(80)], [], { length: 400 });
    assert.deepEqual(plain(tight.hidden.left), [1]);
});

test("a hidden flexible widget returns once its minimum fits the margin", () => {
    const sections = [[entry(100), { size: 200, min: 60, mode: "auto" }], [entry(80)], []];
    const result = solve(...sections, { length: 432 }, { left: [1] });
    assert.deepEqual(plain(result.hidden.left), []);
    assert.deepEqual(plain(result.sizes.left), [100, 68]);
    assert.deepEqual(plain(solve(...sections, { length: 420 }, { left: [1] }).hidden.left), [1]);
});
