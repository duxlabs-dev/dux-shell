import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../Common/SessionData.qml", import.meta.url), "utf8");
const setters = ["setMonitorCyclingEnabled", "setMonitorCyclingRandom", "setMonitorCyclingRecursive", "setMonitorCyclingMode", "setMonitorCyclingInterval", "setMonitorCyclingTime", "setMonitorCyclingFolderPath"];
const helpers = ["getMonitorCyclingSettings", "_findMonitorValue", "_screenByName", "updateMonitorCyclingSetting"];

function session(initial) {
    const warnings = [];
    let saves = 0;
    const context = vm.createContext({
        monitorCyclingSettings: initial,
        Quickshell: { screens: [{ name: "DP-1", model: "LG 27" }, { name: "HDMI-A-1", model: "" }] },
        SettingsData: { getScreenDisplayName: screen => screen.model ? screen.model : screen.name },
        log: { warn: message => warnings.push(message) },
        saveSettings: () => saves++
    });
    const found = [];
    for (const match of source.matchAll(/^    function (\w+)\([^\n]*\)(?:: \w+)? \{\n[\s\S]*?^    \}/gm)) {
        if (!setters.includes(match[1]) && !helpers.includes(match[1]))
            continue;
        found.push(match[1]);
        vm.runInContext(match[0], context);
    }
    assert.deepEqual(found.sort(), [...setters, ...helpers].sort());
    return { context, warnings, saved: () => saves };
}

function plain(value) {
    return JSON.parse(JSON.stringify(value));
}

test("a setter writes its field under the display identifier and keeps other screens", () => {
    const { context, saved } = session({ "HDMI-A-1": { enabled: true, interval: 10 } });
    context.setMonitorCyclingInterval("DP-1", 60);
    const result = plain(context.monitorCyclingSettings);
    assert.deepEqual(Object.keys(result).sort(), ["HDMI-A-1", "LG 27"]);
    assert.deepEqual(result["HDMI-A-1"], { enabled: true, interval: 10 });
    assert.deepEqual(result["LG 27"], { enabled: false, random: false, recursive: false, mode: "interval", interval: 60, time: "06:00", folderPath: "" });
    assert.equal(saved(), 1);
});

test("keys stored under the connector name or model are replaced by the identifier", () => {
    const { context } = session({ "DP-1": { enabled: true, mode: "time" }, "LG 27": { interval: 45 }, other: { enabled: true } });
    context.setMonitorCyclingRandom("DP-1", true);
    const result = plain(context.monitorCyclingSettings);
    assert.deepEqual(Object.keys(result).sort(), ["LG 27", "other"]);
    assert.equal(result["LG 27"].random, true);
    assert.deepEqual(result.other, { enabled: true });
});

test("unknown screens warn and change nothing", () => {
    const initial = { "DP-1": { enabled: true } };
    const { context, warnings, saved } = session(initial);
    context.setMonitorCyclingEnabled("DP-9", false);
    assert.equal(context.monitorCyclingSettings, initial);
    assert.equal(warnings.length, 1);
    assert.equal(saved(), 0);
});

test("a screen without a model keeps its connector name as key", () => {
    const { context } = session({});
    context.setMonitorCyclingInterval("HDMI-A-1", 120);
    assert.deepEqual(Object.keys(context.monitorCyclingSettings), ["HDMI-A-1"]);
    assert.equal(context.monitorCyclingSettings["HDMI-A-1"].interval, 120);
});
