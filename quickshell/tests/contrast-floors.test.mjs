import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const floors = loadScript(new URL("../Common/ContrastFloors.js", import.meta.url));

const plain = v => JSON.parse(JSON.stringify(v));

for (const { name, overrides, want } of [
    { name: "nothing set sends nothing, so older binaries keep working", overrides: {}, want: [] },
    { name: "zero overrides are dropped", overrides: { "colors.outline": 0 }, want: [] },
    {
        name: "overrides are sorted for a stable command line",
        overrides: { "dank16term.color8": 3, "colors.outline": 2 },
        want: ["--contrast-overrides", '{"colors.outline":2,"dank16term.color8":3}'],
    },
]) {
    test(`args: ${name}`, () => {
        assert.deepEqual(plain(floors.args(overrides)), want);
    });
}

test("withOverride returns a new object so the setting registers a change", () => {
    const before = { "dank16term.color5": 5 };
    const after = floors.withOverride(before, "dank16term.color8", 3);
    assert.notEqual(after, before);
    assert.deepEqual(plain(after), { "dank16term.color5": 5, "dank16term.color8": 3 });
    assert.deepEqual(plain(before), { "dank16term.color5": 5 });
});

test("withOverride with 0 removes the override", () => {
    assert.deepEqual(plain(floors.withOverride({ "dank16term.color5": 5 }, "dank16term.color5", 0)), {});
});

for (const [key, want] of [
    ["dank16term.color5", { group: "terminal", ansi: "5" }],
    ["dank16.color13", { group: "editors", ansi: "13" }],
    ["colors.on_surface_variant", { group: "apps", name: "on_surface_variant" }],
]) {
    test(`describe ${key}`, () => assert.deepEqual(plain(floors.describe(key)), want));
}

test("sortByOriginal orders by the theme's ratio, so changing a color does not move it", () => {
    const before = [
        { key: "a", original: 9, ratio: 9 },
        { key: "magenta", original: 1.7, ratio: 1.7 },
        { key: "b", original: 5, ratio: 5 },
        { key: "tie", original: 5, ratio: 5 },
    ];
    const order = r => floors.sortByOriginal(r).map(x => x.key);
    assert.deepEqual(order(before), ["magenta", "b", "tie", "a"]);
    const raised = before.map(r => r.key === "magenta" ? { ...r, ratio: 12 } : r);
    assert.deepEqual(order(raised), order(before));
});

for (const [r, want] of [[4.47, "4.47:1"], [4.5, "4.50:1"], [13.1, "13.10:1"]]) {
    test(`formatRatio ${r} keeps two decimals`, () => assert.equal(floors.formatRatio(r), want));
}

for (const [name, result, want] of [
    ["the theme's own color", { ratio: 4.5, original: 4.5000001 }, ""],
    ["the user's setting for this color", { ratio: 4.54, original: 1.73 }, "own"],
    ["a changed background, even with the color itself untouched", { ratio: 6.1, original: 8.82, cause: "colors.primary" }, "cause"],
]) {
    test(`change: ${name}`, () => assert.equal(floors.change(result), want));
}

const row = (key, ratio, original = ratio) => ({ key, ratio, original });

test("rows is empty for a dms-colors.json written before the audit was recorded", () => {
    assert.deepEqual(plain(floors.rows({ colors: {} }, false)), []);
    assert.deepEqual(plain(floors.rows(null, false)), []);
});

test("rows takes terminal colors from the dark variant when terminals are forced dark", () => {
    const colors = {
        contrast: {
            default: [row("colors.on_surface", 12), row("dank16term.color5", 6.1)],
            dark: [row("colors.on_surface", 13), row("dank16term.color5", 1.7)],
        },
    };
    const ratios = dark => Object.fromEntries(floors.rows(colors, dark).map(r => [r.key, r.ratio]));
    assert.deepEqual(ratios(false), { "colors.on_surface": 12, "dank16term.color5": 6.1 });
    assert.deepEqual(ratios(true), { "colors.on_surface": 12, "dank16term.color5": 1.7 });
});

test("rows use the mode's variant when default is not stored apart", () => {
    const colors = { mode: "light", contrast: { dark: [row("a", 13)], light: [row("a", 3)] } };
    assert.deepEqual(plain(floors.rows(colors, false)).map(r => r.ratio), [3]);
});

test("rows are ordered by the theme's own ratio", () => {
    const colors = { contrast: { default: [row("a", 9), row("b", 12, 1.7), row("c", 4)] } };
    assert.deepEqual(floors.rows(colors, false).map(r => r.key), ["b", "c", "a"]);
});
