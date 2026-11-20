import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));

const removedKeys = ["animationSpeed", "customAnimationDuration", "animationDuration", "syncComponentAnimationSpeeds", "popoutAnimationDuration", "modalAnimationDuration", "notificationAnimationDuration"];

function step(settings) {
    const root = { settingsConfigVersion: 45 };
    store.parse(root, settings);
    return root.motionDuration;
}

test("each millisecond duration lands on the step with the nearest duration", () => {
    const expected = [[0, -1], [100, 0], [250, 0], [320, 1], [375, 1], [500, 2], [600, 2], [750, 3], [900, 4], [1000, 4]];
    for (const [ms, motionDuration] of expected)
        assert.equal(step({ configVersion: 42, animationDuration: ms }), motionDuration, `${ms} ms`);
});

test("a config that never stored a duration keeps the old 250 ms default", () => {
    assert.equal(step({ configVersion: 42 }), 0);
});

test("legacy speed presets map through their preset duration", () => {
    assert.equal(step({ configVersion: 25, animationSpeed: 0 }), -1);
    assert.equal(step({ configVersion: 25, animationSpeed: 2 }), 2);
    assert.equal(step({ configVersion: 25, animationSpeed: 4, customAnimationDuration: 320 }), 1);
});

test("the old duration keys are gone after a save", () => {
    const root = { settingsConfigVersion: 45 };
    store.parse(root, { configVersion: 42, animationDuration: 750, popoutAnimationDuration: 300, syncComponentAnimationSpeeds: false, notificationAnimationDuration: 400 });
    const saved = store.toJson(root, new Set());
    assert.equal(saved.motionDuration, 3);
    for (const key of removedKeys)
        assert.equal(key in saved, false, key);
});
