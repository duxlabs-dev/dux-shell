import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const Corners = loadScript(new URL("../Common/niri/sections/corners.js", import.meta.url));
const plain = value => JSON.parse(JSON.stringify(value));

function state(actions) {
    return Object.assign({}, Corners.defaults, ...Object.entries(actions).map(([c, a]) => ({ ["corners." + c]: a })));
}

test("toKdl writes only the overview corners, and off when niri would light top-left", () => {
    const cases = [
        [{}, []],
        [{ "top-right": "notifications" }, []],
        [{ "top-left": "launcher" }, ["off"]],
        [{ "top-left": "none", "top-right": "overview" }, ["top-right"]],
        [{ "bottom-right": "overview" }, ["top-left", "bottom-right"]]
    ];
    for (const [actions, lines] of cases) {
        const out = plain(Corners.toKdl(state(actions)));
        assert.deepEqual(out, lines.length ? [{ block: "gestures.hot-corners", lines }] : [], JSON.stringify(actions));
    }
});

test("a screen with its own niri corners drops every global corner", () => {
    const global = state({ "top-right": "notifications" });
    assert.deepEqual(plain(Corners.screenCorners(global, null, {})), { "top-left": "overview", "top-right": "notifications", "bottom-left": "none", "bottom-right": "none" });
    assert.equal(Corners.screenCorners(global, { corners: [] }, {})["top-right"], "notifications");
    assert.deepEqual(plain(Corners.screenCorners(global, { off: true }, { "bottom-left": "launcher" })), { "top-left": "none", "top-right": "none", "bottom-left": "launcher", "bottom-right": "none" });
    assert.deepEqual(plain(Corners.screenCorners(global, { corners: ["bottom-right"] }, {})), { "top-left": "none", "top-right": "none", "bottom-left": "none", "bottom-right": "overview" });
});

test("a screen's actions split into niri corners and DMS zones", () => {
    const actions = { "top-left": "overview", "top-right": "screenshot", "bottom-left": "none", "bottom-right": "controlCenter" };
    assert.deepEqual(plain(Corners.niriOverrideOf(actions)), { corners: ["top-left"] });
    assert.deepEqual(plain(Corners.niriOverrideOf({ "top-left": "launcher" })), { off: true });
    assert.deepEqual(plain(Corners.ownOf(actions)), { "top-right": "screenshot", "bottom-right": "controlCenter" });
    // Corner names only, so a new action on the same corner keeps its surface.
    assert.deepEqual(plain(Corners.zones(actions)), ["top-right", "bottom-right"]);
});

test("one screen's corners change alone, in the settings and in its Displays profile", () => {
    const settings = { "LG A": { vrrOnDemand: true, hotCorners: { off: true } }, "BenQ B": { hotCorners: { corners: ["top-left"] } } };
    const before = JSON.stringify(settings);
    assert.deepEqual(plain(Corners.settingsWithCorners(settings, "LG A", { corners: ["bottom-right"] })), { "LG A": { vrrOnDemand: true, hotCorners: { corners: ["bottom-right"] } }, "BenQ B": { hotCorners: { corners: ["top-left"] } } });
    assert.deepEqual(plain(Corners.settingsWithCorners(settings, "LG A", null))["LG A"], { vrrOnDemand: true });
    assert.deepEqual(plain(Corners.settingsWithCorners({}, "New C", { off: true })), { "New C": { hotCorners: { off: true } } });
    assert.equal(JSON.stringify(settings), before);

    const entry = { id: "auto-1", name: "", outputs: { "LG A": { scale: 1.5, niri: { vrrOnDemand: true } }, "BenQ B": { scale: 1, niri: { hotCorners: { off: true } } } } };
    const entryBefore = JSON.stringify(entry);
    const patched = plain(Corners.profileWithCorners(entry, "LG A", { corners: ["top-right"] }));
    assert.deepEqual(patched.outputs["LG A"], { scale: 1.5, niri: { vrrOnDemand: true, hotCorners: { corners: ["top-right"] } } });
    assert.deepEqual(patched.outputs["BenQ B"], entry.outputs["BenQ B"]);
    assert.equal(patched.id, "auto-1");
    assert.deepEqual(plain(Corners.profileWithCorners(entry, "BenQ B", null)).outputs["BenQ B"], { scale: 1, niri: {} });
    assert.deepEqual(plain(Corners.profileWithCorners(entry, "Gone D", { off: true })), plain(entry));
    assert.equal(JSON.stringify(entry), entryBefore);
});
