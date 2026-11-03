import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));
const SPEC = loadScript(new URL("../Common/settings/SettingsSpec.js", import.meta.url)).SPEC;

const CONFIG_VERSION = 26;
const RUNTIME_ONLY = Object.keys(SPEC).filter(key => SPEC[key].persist === false);

function freshRoot() {
    return { settingsConfigVersion: CONFIG_VERSION };
}

function loaded(json) {
    const root = freshRoot();
    store.parse(root, Object.assign({ configVersion: CONFIG_VERSION }, json));
    return root;
}

function defaultRoot() {
    const root = loaded({});
    for (const key of RUNTIME_ONLY)
        root[key] = store.Util.cloneDef(SPEC[key].def);
    return root;
}

test("runtime-only keys are never written by a load", () => {
    const root = loaded({});
    const touched = RUNTIME_ONLY.filter(key => key in root);
    assert.deepEqual(touched, []);
});

test("a root at every default persists nothing but its version", () => {
    const json = store.toJson(defaultRoot(), new Set());
    assert.deepEqual(Object.keys(json), ["configVersion"]);
    assert.equal(json.configVersion, CONFIG_VERSION);
});

test("a key is persisted while it differs and dropped once it matches again", () => {
    const root = defaultRoot();
    root.animationDuration = 700;
    assert.equal(store.toJson(root, new Set()).animationDuration, 700);
    root.animationDuration = SPEC.animationDuration.def;
    assert.equal("animationDuration" in store.toJson(root, new Set()), false);
});

test("a coerced key normalises a percentage and leaves a unit value alone", () => {
    assert.equal(loaded({ popupTransparency: 50 }).popupTransparency, 0.5);
    assert.equal(loaded({ popupTransparency: 0.5 }).popupTransparency, 0.5);
});

test("a focus override persists both off and on, and resetting removes it", () => {
    const root = defaultRoot();
    for (const mode of [0, 1]) {
        root.focusFollowsMouse = mode;
        const json = store.toJson(root, new Set());
        assert.equal(json.focusFollowsMouse, mode);
        assert.equal(loaded(json).focusFollowsMouse, mode);
    }
    root.focusFollowsMouse = -1;
    assert.equal("focusFollowsMouse" in store.toJson(root, new Set()), false);
});
