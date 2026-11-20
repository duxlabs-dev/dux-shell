import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const sc = loadScript(new URL("../Common/ScreenCorners.js", import.meta.url));

test("off is never visible", () => {
    assert.equal(sc.modeVisible("off", false), false);
    assert.equal(sc.modeVisible("off", true), false);
});

test("always is visible over fullscreen", () => {
    assert.equal(sc.modeVisible("always", false), true);
    assert.equal(sc.modeVisible("always", true), true);
});

test("unlessFullscreen hides only on fullscreen screens", () => {
    assert.equal(sc.modeVisible("unlessFullscreen", false), true);
    assert.equal(sc.modeVisible("unlessFullscreen", true), false);
});

test("anchors map to exactly two screen edges", () => {
    assert.equal(JSON.stringify(sc.anchorsFor("topLeft")), JSON.stringify({ top: true, right: false, bottom: false, left: true }));
    assert.equal(JSON.stringify(sc.anchorsFor("topRight")), JSON.stringify({ top: true, right: true, bottom: false, left: false }));
    assert.equal(JSON.stringify(sc.anchorsFor("bottomLeft")), JSON.stringify({ top: false, right: false, bottom: true, left: true }));
    assert.equal(JSON.stringify(sc.anchorsFor("bottomRight")), JSON.stringify({ top: false, right: true, bottom: true, left: false }));
});

const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));
const spec = store.SpecModule;

test("screen corner mode defaults to off and round-trips an explicit value", () => {
    assert.equal(spec.SPEC.screenCornerMode.def, "off");

    const fresh = { settingsConfigVersion: 46 };
    store.parse(fresh, { configVersion: 46 });
    assert.equal(fresh.screenCornerMode, "off");

    const root = { settingsConfigVersion: 46 };
    store.parse(root, { configVersion: 46, screenCornerMode: "unlessFullscreen" });
    assert.equal(root.screenCornerMode, "unlessFullscreen");
    assert.equal(store.toJson(root, new Set()).screenCornerMode, "unlessFullscreen");
});
