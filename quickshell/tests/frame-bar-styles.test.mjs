import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

function functions(source, indent, context) {
    const pattern = new RegExp(`^${indent}function (\\w+)\\(([^)]*)\\)(?:: \\w+)? \\{([\\s\\S]*?)^${indent}\\}`, "gm");
    for (const [, name, parameters, body] of source.matchAll(pattern)) {
        const args = parameters.replace(/:\s*\w+/g, "");
        vm.runInContext(`function ${name}(${args}) {${body}}`, context);
    }
    return context;
}

const settingsSource = readFileSync(new URL("../Common/SettingsData.qml", import.meta.url), "utf8");
const plain = value => JSON.parse(JSON.stringify(value));
const styled = { shadowIntensity: 40, squareCorners: true, attachToScreenEdge: true, gothCornersEnabled: true, borderEnabled: true };
const zeroed = { shadowIntensity: 0, squareCorners: false, attachToScreenEdge: false, gothCornersEnabled: false, borderEnabled: false };
const style = cfg => Object.fromEntries(Object.keys(styled).map(key => [key, cfg[key]]));

function frameSettings({ active = true, frameOn = ["A"], barConfigs, backups = {}, screens = [{ name: "A" }, { name: "B" }] } = {}) {
    const settings = functions(settingsSource, "    ", vm.createContext({
        Quickshell: { screens },
        connectedFrameModeActive: active,
        frameScreenPreferences: frameOn,
        connectedFrameBarStyleBackups: backups,
        barConfigs: barConfigs ?? [{ id: "bar1", screenPreferences: ["A"], ...styled }, { id: "bar2", screenPreferences: ["B"], ...styled }]
    }));
    settings.barConfigCoversScreen = (cfg, screen) => cfg.screenPreferences.includes(screen.name);
    settings.isScreenInPreferences = (screen, prefs) => prefs.includes(screen.name);
    settings.updateBarConfigs = () => settings.updates++;
    settings._restoreIslandWidget = () => {};
    settings.updates = 0;
    return settings;
}

const bar = (settings, id) => settings.barConfigs.find(cfg => cfg.id === id);

test("only bars on a frame display are sanitized", () => {
    const settings = frameSettings();
    settings._reconcileConnectedFrameBarStyles();
    assert.deepEqual(style(bar(settings, "bar1")), zeroed);
    assert.deepEqual(style(bar(settings, "bar2")), styled);
    assert.deepEqual(plain(settings.connectedFrameBarStyleBackups), { bar1: styled });
    assert.equal(settings.barUsesConnectedFrameStyle(bar(settings, "bar1")), true);
    assert.equal(settings.barUsesConnectedFrameStyle(bar(settings, "bar2")), false);
    assert.equal(settings.barUsesConnectedFrameStyle(null), false);
});

test("moving the frame display swaps which bar is sanitized", () => {
    const settings = frameSettings();
    settings._reconcileConnectedFrameBarStyles();
    settings.frameScreenPreferences = ["B"];
    settings._reconcileConnectedFrameBarStyles();
    assert.deepEqual(style(bar(settings, "bar1")), styled);
    assert.deepEqual(style(bar(settings, "bar2")), zeroed);
    assert.deepEqual(plain(settings.connectedFrameBarStyleBackups), { bar2: styled });
});

test("leaving connected mode restores all bars and clears backups", () => {
    const settings = frameSettings({ frameOn: ["A", "B"] });
    settings._reconcileConnectedFrameBarStyles();
    assert.deepEqual(style(bar(settings, "bar2")), zeroed);
    settings.connectedFrameModeActive = false;
    settings._reconcileConnectedFrameBarStyles();
    assert.deepEqual(style(bar(settings, "bar1")), styled);
    assert.deepEqual(style(bar(settings, "bar2")), styled);
    assert.deepEqual(plain(settings.connectedFrameBarStyleBackups), {});
    assert.equal(settings.barUsesConnectedFrameStyle(bar(settings, "bar1")), false);
});

test("legacy all-sanitized state self-heals on reconcile", () => {
    const settings = frameSettings({
        barConfigs: [{ id: "bar1", screenPreferences: ["A"], ...zeroed }, { id: "bar2", screenPreferences: ["B"], ...zeroed }],
        backups: { bar1: styled, bar2: styled, gone: styled }
    });
    settings._reconcileConnectedFrameBarStyles();
    assert.deepEqual(style(bar(settings, "bar1")), zeroed);
    assert.deepEqual(style(bar(settings, "bar2")), styled);
    assert.deepEqual(plain(settings.connectedFrameBarStyleBackups), { bar1: styled });
    assert.equal(settings.updates, 1);
    settings._reconcileConnectedFrameBarStyles();
    assert.equal(settings.updates, 1, "a settled state does not write again");
});

test("committing a bar onto a frame display captures its styling first", () => {
    const settings = frameSettings({ barConfigs: [{ id: "bar2", screenPreferences: ["B"], ...styled }] });
    const configs = plain(settings.barConfigs);
    configs[0].screenPreferences = ["A"];
    settings._commitBarConfigs(configs);
    assert.deepEqual(style(bar(settings, "bar2")), zeroed);
    assert.deepEqual(plain(settings.connectedFrameBarStyleBackups), { bar2: styled });
});

test("adding a bar off the frame display keeps its styling", () => {
    const settings = frameSettings();
    settings._reconcileConnectedFrameBarStyles();
    settings.addBarConfig({ id: "bar3", screenPreferences: ["B"], ...styled });
    assert.deepEqual(style(bar(settings, "bar3")), styled);
    assert.equal(plain(settings.connectedFrameBarStyleBackups).bar3, undefined);
});

test("an empty screen list leaves bar styles and backups alone", () => {
    const settings = frameSettings();
    settings._reconcileConnectedFrameBarStyles();
    settings.Quickshell.screens = [];
    settings._reconcileConnectedFrameBarStyles();
    assert.deepEqual(style(bar(settings, "bar1")), zeroed);
    assert.deepEqual(plain(settings.connectedFrameBarStyleBackups), { bar1: styled });
    assert.equal(settings.updates, 1);
});
