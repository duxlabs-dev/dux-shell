import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const presets = loadScript(new URL("../Common/niri/presets.js", import.meta.url));

test("every preset uses only style keys", () => {
    for (const p of presets.presets)
        for (const key of Object.keys(p.values))
            assert.ok(presets.styleKeys.includes(key), p.id + " " + key);
});

test("snapshot keeps known values only", () => {
    const state = { "look.gaps": 8, "columns.centerFocused": "always" };
    assert.deepEqual(JSON.parse(JSON.stringify(presets.snapshot(key => state[key]))), state);
});

test("matches compares every value of the style", () => {
    const values = { "look.gaps": 8, "look.ringOn": true };
    assert.equal(presets.matches(values, key => ({ "look.gaps": 8, "look.ringOn": true })[key]), true);
    assert.equal(presets.matches(values, key => ({ "look.gaps": 8, "look.ringOn": false })[key]), false);
});

test("exported text parses back", () => {
    const values = { "look.gaps": 8, "columns.centerFocused": "always" };
    const r = presets.parseStyle(presets.exportStyle("Laptop", values));
    assert.equal(r.error, "");
    assert.equal(r.name, "Laptop");
    assert.deepEqual(JSON.parse(JSON.stringify(r.values)), values);
});

test("parseStyle refuses broken or hostile files", () => {
    const wrap = values => JSON.stringify({ niriStyle: 1, name: "x", values: values });
    for (const text of [
        "",
        "not json",
        "[]",
        JSON.stringify({ niriStyle: 2, name: "x", values: { "look.gaps": 8 } }),
        JSON.stringify({ name: "x", values: { "look.gaps": 8 } }),
        wrap({}),
        wrap([1]),
        wrap({ "custom.windows": "x" }),
        wrap({ "styles.profiles": 1 }),
        wrap({ "gaps": 8 }),
        wrap({ "look.gaps": { a: 1 } }),
        wrap({ "look.gaps": Infinity }),
        wrap({ "look.ringColor": "red\" }\nspawn-at-startup \"x" }),
        wrap({ "look.ringColor": "x".repeat(300) }),
        wrap({ "look.ringColor": "#ffffff" }),
        wrap({ "look.gaps": 8, "advanced.debugRender": true }),
        wrap({ "input.xkbLayout": "us" }),
        wrap({ "look.gaps": 8, "look.pad": "x".repeat(60) }) + " ".repeat(70000)
    ])
        assert.notEqual(presets.parseStyle(text).error, "", text.slice(0, 80));
});

test("parseStyle bounds each number to its slider and each choice to its list", () => {
    const wrap = values => JSON.stringify({ niriStyle: 1, name: "x", values: values });
    for (const values of [
        { "look.gaps": 65 },
        { "look.gaps": -3 },
        { "look.ringWidth": 17 },
        { "look.radius": 1e9 },
        { "animations.slowdown": 0 },
        { "animations.slowdown": 40 },
        { "look.ringOn": 1 },
        { "look.gaps": true },
        { "columns.centerFocused": "sometimes" }
    ])
        assert.notEqual(presets.parseStyle(wrap(values)).error, "", JSON.stringify(values));
    for (const values of [
        { "look.gaps": -2 },
        { "look.gaps": 64 },
        { "look.ringWidth": -1 },
        { "look.radius": 32 },
        { "animations.slowdown": 0.2 },
        { "columns.centerFocused": "on-overflow" }
    ])
        assert.equal(presets.parseStyle(wrap(values)).error, "", JSON.stringify(values));
    for (const p of presets.presets)
        assert.equal(presets.parseStyle(wrap(p.values)).error, "", p.id);
});

test("import bounds are the section modules' own limits, not a copy", () => {
    const sections = ["look", "columns", "animations"].map(name => loadScript(new URL("../Common/niri/sections/" + name + ".js", import.meta.url)));
    const own = Object.assign({}, ...sections.map(s => JSON.parse(JSON.stringify(s.limits))));
    for (const key of presets.styleKeys) {
        if (key in own)
            assert.deepEqual(JSON.parse(JSON.stringify(presets.limits[key])), own[key], key);
        else
            assert.equal(presets.limits[key], undefined, key + " is a switch");
    }
    assert.ok(Object.keys(own).length >= 5);
});

test("a refused import never echoes text read from the file", () => {
    const key = "look.secret-" + "z".repeat(20);
    const r = presets.parseStyle(JSON.stringify({ niriStyle: 1, name: "x", values: { [key]: 1 } }));
    assert.notEqual(r.error, "");
    assert.ok(!r.error.includes("secret"), r.error);
});

test("parseStyle trims and bounds the name", () => {
    const r = presets.parseStyle(JSON.stringify({ niriStyle: 1, name: "  " + "n".repeat(60), values: { "look.gaps": 8 } }));
    assert.equal(r.error, "");
    assert.equal(r.name.length, presets.NAME_MAX);
});
