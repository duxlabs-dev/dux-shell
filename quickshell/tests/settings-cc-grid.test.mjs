import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));

test("control center width percentages become square grid cells", () => {
    const migrated = store.migrateToVersion({
        configVersion: 26,
        controlCenterWidth: 800,
        controlCenterWidgets: [{ id: "wifi", width: 75 }, { id: "diskUsage", width: 25, mountPath: "/", instanceId: "disk" }, { id: "battery" }, { id: "plugin_x", width: 100, w: 3, h: 2, enabled: false }]
    }, 27);
    assert.equal(migrated.configVersion, 27);
    assert.equal(migrated.controlCenterColumns, 12);
    assert.equal(migrated.controlCenterWidth, undefined);
    assert.deepEqual(JSON.parse(JSON.stringify(migrated.controlCenterWidgets)), [{ id: "wifi", w: 6, h: 1 }, { id: "diskUsage", mountPath: "/", instanceId: "disk", w: 2, h: 1 }, { id: "battery", w: 4, h: 1 }, { id: "plugin_x", w: 6, h: 2, enabled: false }]);
    assert.equal(store.migrateToVersion(migrated, 27), null);
});

test("sparse settings migrate without inventing grid keys", () => {
    const sparse = store.migrateToVersion({ configVersion: 26 }, 27);
    assert.equal(sparse.controlCenterColumns, undefined);
    assert.equal(sparse.controlCenterWidgets, undefined);
});

test("header entries become a user row and lock, power and settings tiles", () => {
    const released = store.migrateToVersion({ configVersion: 18, controlCenterWidgets: [{ id: "wifi", width: 50 }] }, 35);
    assert.deepEqual(JSON.parse(JSON.stringify(released.controlCenterWidgets.map(w => [w.id, w.w, w.h, !!w.footer]))), [["user", 5, 1, false], ["settings", 1, 1, false], ["lock", 1, 1, false], ["power", 1, 1, false], ["wifi", 4, 1, false], ["runningApps", 4, 1, true]]);
});

test("the edit button is added once and keeps a placed one", () => {
    const migrated = store.migrateToVersion({ configVersion: 36, controlCenterWidgets: [{ id: "wifi", w: 4, h: 1 }] }, 37);
    assert.equal(migrated.configVersion, 37);
    assert.deepEqual(JSON.parse(JSON.stringify(migrated.controlCenterWidgets)), [{ id: "wifi", w: 4, h: 1 }, { id: "edit", enabled: true, w: 1, h: 1, small: true }]);
    const placed = store.migrateToVersion({ configVersion: 36, controlCenterWidgets: [{ id: "edit", w: 1, h: 1, col: 2, row: 0 }] }, 37);
    assert.deepEqual(JSON.parse(JSON.stringify(placed.controlCenterWidgets)), [{ id: "edit", w: 1, h: 1, col: 2, row: 0 }]);
    assert.equal(store.migrateToVersion({ configVersion: 36 }, 37).controlCenterWidgets, undefined);
});

test("footer entries form a row under the grid in footer order, fills sharing the spare width and end entries right-aligned", () => {
    const migrated = store.migrateToVersion({
        configVersion: 40,
        controlCenterFooterPosition: "top",
        controlCenterWidgets: [{ id: "edit", w: 1, h: 1, small: true, footer: true, footerEnd: true }, { id: "wifi", w: 4, h: 1, col: 0, row: 0 }, { id: "runningApps", w: 4, h: 1, col: 2, row: 1, footer: true, footerW: 3.5, footerFill: true }, { id: "bluetooth", w: 4, h: 1 }, { id: "volumeSlider", w: 4, h: 1, footer: true }]
    }, 41);
    assert.equal(migrated.configVersion, 41);
    assert.equal(migrated.controlCenterFooterPosition, undefined);
    assert.deepEqual(JSON.parse(JSON.stringify(migrated.controlCenterWidgets)), [{ id: "wifi", w: 4, h: 1, col: 0, row: 0 }, { id: "bluetooth", w: 4, h: 1 }, { id: "runningApps", w: 3, h: 1, col: 0, row: 1, small: true }, { id: "volumeSlider", w: 4, h: 1, col: 3, row: 1 }, { id: "edit", w: 1, h: 1, small: true, col: 7, row: 1 }]);
    assert.equal(store.migrateToVersion({ configVersion: 40 }, 41).controlCenterWidgets, undefined);
});

test("footer widths keep half steps, follow the saved column count and wrap when they overflow it", () => {
    const migrated = store.migrateToVersion({
        configVersion: 40,
        controlCenterColumns: 6,
        controlCenterWidgets: [{ id: "wifi", w: 6, h: 1 }, { id: "runningApps", w: 4, h: 1, footer: true, footerW: 3.5 }, { id: "battery", w: 4, h: 1, footer: true, footerW: 2 }, { id: "edit", w: 1, h: 1, footer: true, footerEnd: true }]
    }, 41);
    assert.deepEqual(JSON.parse(JSON.stringify(migrated.controlCenterWidgets)), [{ id: "wifi", w: 6, h: 1 }, { id: "runningApps", w: 3.5, h: 1, col: 0, row: 1, small: true }, { id: "battery", w: 2, h: 1, col: 3.5, row: 1, small: true }, { id: "edit", w: 1, h: 1, col: 0, row: 2, small: true }]);
});

test("tall footer entries shrink to one row, full-height ones keep theirs, and stale footer keys are dropped", () => {
    const migrated = store.migrateToVersion({
        configVersion: 40,
        controlCenterWidgets: [{ id: "diskUsage", w: 4, h: 2, footer: true }, { id: "bluetooth", w: 4, h: 1.5, footer: true }, { id: "user", w: 5, h: 2, footer: true }, { id: "wifi", w: 4, h: 2, col: 0, row: 1, footerW: 3, footerFill: true, footer: false }]
    }, 41);
    assert.deepEqual(JSON.parse(JSON.stringify(migrated.controlCenterWidgets)), [{ id: "wifi", w: 4, h: 2, col: 0, row: 1 }, { id: "diskUsage", w: 1, h: 1, col: 0, row: 2, small: true }, { id: "bluetooth", w: 1, h: 1, col: 1, row: 2, small: true }, { id: "user", w: 3, h: 2, col: 2, row: 2 }]);
});
