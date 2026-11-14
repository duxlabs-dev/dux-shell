import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));

function migratedDock(settings) {
    return store.migrateToVersion(Object.assign({ configVersion: 18 }, settings), 25).dockConfigs[0];
}

test("a default 1.6 dock keeps its size and gaps", () => {
    const dock = migratedDock({});
    assert.equal(dock.enabled, false);
    assert.equal(dock.smartAutoHide, false);
    assert.equal(dock.iconSize, 40);
    assert.equal(dock.itemSpacing, 4);
    assert.equal(dock.spacing, 4);
    assert.equal(dock.margin, 0);
    assert.equal(dock.launcherEnabled, false);
});

test("legacy icon gap follows the legacy icon size", () => {
    assert.equal(migratedDock({ showDock: true, dockIconSize: 100 }).itemSpacing, 8);
    assert.equal(migratedDock({ dockIconSize: 64 }).itemSpacing, 64 * 0.08);
    assert.equal(migratedDock({ dockIconSize: 24 }).itemSpacing, 4);
});

test("legacy dock keys land on the dock config and are dropped", () => {
    const migrated = store.migrateToVersion({ configVersion: 18, showDock: true, dockIconSize: 56, dockSpacing: 10, dockTransparency: 80, dockPosition: 2 }, 25);
    const dock = migrated.dockConfigs[0];
    assert.equal(dock.enabled, true);
    assert.equal(dock.iconSize, 56);
    assert.equal(dock.spacing, 10);
    assert.equal(dock.transparency, 0.8);
    assert.equal(dock.position, 2);
    assert.deepEqual(Object.keys(migrated).filter(key => key === "showDock" || /^dock[A-Z]/.test(key)), ["dockConfigs"]);
});

test("a default 1.6 bar apps widget keeps indicators and icon size", () => {
    const migrated = store.migrateToVersion({ configVersion: 18, barConfigs: [{ id: "default", leftWidgets: ["appsDock"], rightWidgets: [{ id: "appsDock", enabled: true, appsDockIconSizePercentage: 150 }] }] }, 25);
    const [left] = migrated.barConfigs[0].leftWidgets;
    const [right] = migrated.barConfigs[0].rightWidgets;
    assert.equal(left.appsDockHideIndicators, false);
    assert.equal(left.appsDockIconSizePercentage, 100);
    assert.equal(right.appsDockIconSizePercentage, 150);
});

test("stored 1.6 globals still win over legacy defaults", () => {
    const migrated = store.migrateToVersion({ configVersion: 18, appsDockHideIndicators: true, barConfigs: [{ id: "default", centerWidgets: ["appsDock"] }] }, 25);
    assert.equal(migrated.barConfigs[0].centerWidgets[0].appsDockHideIndicators, true);
    assert.equal("appsDockHideIndicators" in migrated, false);
});
