import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));

const removedKeys = ["animationSpeed", "customAnimationDuration", "popoutAnimationSpeed", "popoutCustomAnimationDuration", "modalAnimationSpeed", "modalCustomAnimationDuration", "notificationAnimationSpeed", "notificationCustomAnimationDuration"];

function load(settings) {
    const root = { settingsConfigVersion: 26 };
    store.parse(root, Object.assign({ configVersion: 25 }, settings));
    return root;
}

test("speed presets become their preset duration", () => {
    const root = load({ animationSpeed: 3, popoutAnimationSpeed: 2, modalAnimationSpeed: 0, notificationAnimationSpeed: 3 });
    assert.equal(root.animationDuration, 750);
    assert.equal(root.popoutAnimationDuration, 300);
    assert.equal(root.modalAnimationDuration, 0);
    assert.equal(root.notificationAnimationDuration, 600);
    for (const key of removedKeys)
        assert.equal(key in root, false, key);
});

test("custom speed keeps the custom duration", () => {
    const root = load({ animationSpeed: 4, customAnimationDuration: 320, notificationAnimationSpeed: 4, notificationCustomAnimationDuration: 550 });
    assert.equal(root.animationDuration, 320);
    assert.equal(root.notificationAnimationDuration, 550);
});

test("custom speed without a stored duration falls back to the old custom default", () => {
    const root = load({ animationSpeed: 4, popoutAnimationSpeed: 4, modalAnimationSpeed: 4, notificationAnimationSpeed: 4 });
    assert.equal(root.animationDuration, 500);
    assert.equal(root.popoutAnimationDuration, 150);
    assert.equal(root.modalAnimationDuration, 150);
    assert.equal(root.notificationAnimationDuration, 400);
});

test("a custom duration without custom speed is dropped", () => {
    const root = load({ customAnimationDuration: 900 });
    assert.equal(root.animationDuration, store.SpecModule.SPEC.animationDuration.def);
});

test("saved settings keep only changed durations and no speed keys", () => {
    const saved = store.toJson(load({ animationSpeed: 1, modalAnimationSpeed: 3 }), new Set());
    assert.equal(saved.modalAnimationDuration, 500);
    assert.equal(saved.animationDuration ?? store.SpecModule.SPEC.animationDuration.def, 250);
    for (const key of removedKeys)
        assert.equal(key in saved, false, key);
    assert.equal(saved.configVersion, 26);
});
