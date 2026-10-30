import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const fixtures = new URL("fixtures/outputs/", import.meta.url);
const text = name => readFileSync(new URL(name, fixtures), "utf8");
const json = name => JSON.parse(text(name));
const plain = value => value === undefined ? null : JSON.parse(JSON.stringify(value));
const clone = value => JSON.parse(JSON.stringify(value));
const rounded = values => values.map(v => Math.round(v * 1000) / 1000);

const context = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/OutputModel.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), context);
const model = new Proxy(context, { get: (target, name) => (...args) => plain(target[name](...args)) });

const wlr = json("wlr-outputs.json");
const monitors = json("monitors.json");
const modeSamples = json("modes.json");
const live = plain(model.outputsFromWlr(wlr.outputs, {}));
const dell = { make: "Dell Inc.", model: "DELL U2720Q", serial: "ABC123" };
const boe = { make: "BOE", model: "0x0A1B", serial: "" };
const transformNames = ["Normal", "90", "180", "270", "Flipped", "Flipped90", "Flipped180", "Flipped270"];

test("transform lookups fall back to Normal and only our spelling counts as rotated", () => {
    assert.deepEqual([-1, "1"].map(i => model.transformName(i)), ["Normal", "Normal"]);
    assert.equal(model.transformIndex("bogus"), 0);
    assert.equal(model.niriTransform("bogus"), "normal");
    assert.deepEqual(transformNames.filter(n => model.isRotated(n)), ["90", "270", "Flipped90", "Flipped270"]);
    assert.equal(model.isRotated("flipped-90"), false);
});

test("identifier rules: niri appends the serial or Unknown, hyprland uses desc: without commas, the profile rule drops the serial off niri", () => {
    assert.equal(model.niriIdentifier(dell, "DP-1", "system"), "DP-1");
    assert.equal(model.niriIdentifier(dell, "DP-1", "model"), "Dell Inc. DELL U2720Q ABC123");
    assert.equal(model.niriIdentifier(boe, "DP-1", "model"), "BOE 0x0A1B Unknown");
    assert.equal(model.hyprlandIdentifier(dell, "DP-1", "model"), "desc:Dell Inc. DELL U2720Q ABC123");
    assert.equal(model.hyprlandIdentifier({ make: "Foo, Inc.", model: "Bar, 27", serial: "S,1" }, "DP-1", "model"), "desc:Foo Inc. Bar 27 S1");
    assert.equal(model.hyprlandIdentifier(boe, "DP-1", "model"), "desc:BOE 0x0A1B");
    assert.equal(model.hyprlandIdentifier(dell, "DP-1", "system"), "DP-1");
    assert.equal(model.profileIdentifier(dell, "DP-1", "model", "niri"), "Dell Inc. DELL U2720Q ABC123");
    assert.equal(model.profileIdentifier(dell, "DP-1", "model", "hyprland"), "Dell Inc. DELL U2720Q");
    assert.equal(model.profileIdentifier(boe, "DP-1", "model", "mango"), "BOE 0x0A1B");
    assert.equal(model.profileIdentifier({ make: "", model: "X", serial: "1" }, "DP-1", "model", "niri"), "DP-1");
    assert.equal(model.profileIdentifier(dell, "DP-1", "system", "niri"), "DP-1");
});

test("niri kdl parser: top-level off disables, nested off does not, on-demand vrr, raw transform spelling", () => {
    const parsed = plain(model.parseNiriOutputs(text("niri-outputs.kdl")));
    assert.deepEqual(Object.keys(parsed), ["DP-1", "HDMI-A-1", "eDP-1", "Dell Inc. DELL U2720Q ABC123"]);
    assert.deepEqual(parsed["DP-1"], { name: "DP-1", disabled: false, logical: { x: 0, y: 0, scale: 1.25, transform: "90" }, modes: [{ width: 2560, height: 1440, refresh_rate: 143998 }], current_mode: 0, vrr_enabled: true, vrr_on_demand: true, vrr_supported: true });
    assert.equal(parsed["HDMI-A-1"].disabled, true);
    assert.equal(parsed["eDP-1"].disabled, false);
    assert.deepEqual([parsed["eDP-1"].vrr_enabled, parsed["eDP-1"].vrr_on_demand], [true, false]);
    assert.deepEqual(parsed["Dell Inc. DELL U2720Q ABC123"].logical, { x: -2560, y: 0, scale: 1.5, transform: "flipped-90" });
});

test("hyprland conf lines only parse for 1.x profile migration: extras, disable line, desc name, trailing space, mirror, bare line skipped", () => {
    assert.deepEqual(Object.keys(plain(model.parseHyprlandOutputs(text("hyprland-monitors.conf")))), []);
    const parsed = plain(model.parseHyprlandConfProfile(text("hyprland-monitors.conf")));
    assert.deepEqual(Object.keys(parsed), ["DP-1", "HDMI-A-1", "desc:Dell Inc. DELL U2720Q ABC123", "eDP-1", "DP-2"]);
    assert.deepEqual(parsed["DP-1"].logical, { x: 0, y: 0, scale: 1.25, transform: "90" });
    assert.equal(parsed["DP-1"].vrr_enabled, true);
    assert.deepEqual(parsed["HDMI-A-1"], { name: "HDMI-A-1", logical: { x: 0, y: 0, scale: 1, transform: "Normal" }, modes: [], current_mode: -1, vrr_enabled: false, vrr_supported: false });
    assert.equal(parsed["desc:Dell Inc. DELL U2720Q ABC123"].logical.transform, "Flipped90");
    assert.equal(parsed["eDP-1"].mirror, "DP-1");
    assert.deepEqual(parsed["DP-2"].modes, [{ width: 1920, height: 1080, refresh_rate: 60000 }]);
});

test("hyprland lua parser: quoted and long-bracket strings, hdr fields, mode-less lines, apostrophe names", () => {
    const parsed = plain(model.parseHyprlandOutputs(text("hyprland-monitors.lua")));
    assert.deepEqual(Object.keys(parsed), ["DP-1", "HDMI-A-1", "desc:Dell Inc. DELL U2720Q ABC123", "eDP-1", "DP-2", "DP-3", "it's"]);
    assert.deepEqual(parsed["DP-1"].hyprlandSettings, { bitdepth: 10, colorManagement: "hdr", sdrBrightness: 1.2, sdrSaturation: 0.9, supportsWideColor: true, supportsHdr: false, sdrEotf: "gamma22", icc: "/home/u/profile with spaces.icc", sdrMinLuminance: 0.005, sdrMaxLuminance: 200, minLuminance: 0.001, maxLuminance: 1000, maxAvgLuminance: 400, vrr: 2 });
    assert.deepEqual([parsed["HDMI-A-1"].hyprlandSettings, parsed["HDMI-A-1"].current_mode], [{ disabled: true }, -1]);
    assert.deepEqual([parsed["eDP-1"].current_mode, parsed["eDP-1"].mirror], [-1, "DP-1"]);
    assert.deepEqual([parsed["DP-3"].vrr_enabled, parsed["DP-3"].vrr_supported, parsed["DP-3"].hyprlandSettings], [true, true, { vrr: 2 }]);
    assert.equal(parsed["it's"].modes[0].width, 1920);
    assert.equal(model.parseHyprlandLuaMonitorLine("monitor=DP-1,disable"), null);
    assert.equal(model.parseHyprlandLuaMonitorLine("hl.monitor({ scale = 1 })"), null);
});

test("mango parser: anchors stripped, defaults filled, nameless rule skipped, out-of-range rotation is Normal", () => {
    const parsed = plain(model.parseMangoOutputs(text("mango-monitors.conf")));
    assert.deepEqual(Object.keys(parsed), ["DP-1", "eDP-1", "HDMI-A-1", "DP-2", "DP-3"]);
    assert.deepEqual(parsed["DP-1"], { name: "DP-1", logical: { x: 0, y: 0, scale: 1.25, transform: "90" }, modes: [{ width: 2560, height: 1440, refresh_rate: 143998 }], current_mode: 0, vrr_enabled: true, vrr_supported: true });
    assert.deepEqual(parsed["eDP-1"].modes, [{ width: 1920, height: 1080, refresh_rate: 60000 }]);
    assert.deepEqual([parsed["DP-2"].logical.transform, parsed["DP-2"].modes[0].refresh_rate], ["Flipped270", 59950]);
    assert.equal(parsed["DP-3"].logical.transform, "Normal");
});

test("wlr snapshot normalizes modes and vrr, disabled heads keep a 1920x1080 viewport, hyprland live geometry overrides", () => {
    assert.deepEqual(Object.keys(live), ["DP-1", "eDP-1", "HDMI-A-1"]);
    assert.deepEqual(live["DP-1"], { name: "DP-1", enabled: true, make: "Dell Inc.", model: "DELL U2720Q", serial: "ABC123", modes: [{ id: 0, width: 3840, height: 2160, refresh_rate: 60000, preferred: true }, { id: 1, width: 3840, height: 2160, refresh_rate: 59997, preferred: false }, { id: 2, width: 1920, height: 1080, refresh_rate: 60000, preferred: false }], current_mode: 1, vrr_supported: true, vrr_enabled: true, logical: { x: 0, y: 0, width: 3840, height: 2160, scale: 1.5, transform: "Normal" } });
    assert.deepEqual([live["HDMI-A-1"].current_mode, live["HDMI-A-1"].logical], [-1, { x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: "Normal" }]);
    const withLive = plain(model.outputsFromWlr(wlr.outputs, wlr.liveMonitors));
    assert.deepEqual(withLive["eDP-1"].logical, { x: 2600, y: 10, width: 1920, height: 1200, scale: 1.6, transform: "90" });
    assert.deepEqual(withLive["DP-1"], live["DP-1"]);
});

test("current output set and fingerprints follow the naming mode", () => {
    assert.deepEqual(model.currentOutputSet(live, "system", "niri"), ["DP-1", "HDMI-A-1", "eDP-1"]);
    assert.deepEqual(model.currentOutputSet(live, "model", "niri"), ["BOE 0x0A1B Unknown", "Dell Inc. DELL U2720Q ABC123", "LG Electronics LG ULTRAGEAR 0x0001"]);
    assert.deepEqual(model.currentOutputSet(live, "model", "hyprland"), ["BOE 0x0A1B", "Dell Inc. DELL U2720Q", "LG Electronics LG ULTRAGEAR"]);
    assert.deepEqual(monitors.configurations.map(c => model.configFingerprint(c)), ["DP-1+eDP-1", "BOE 0x0A1B Unknown+Dell Inc. DELL U2720Q ABC123", "desc:Dell Inc. DELL U2720Q", "DP-1+DP-9", "DP-1+eDP-1"]);
    assert.equal(model.outputSetFingerprint(["b", "a", "c"]), "a+b+c");
});

test("profile lookup: named profiles win over auto ones, autoOnly skips named, order-insensitive sets", () => {
    assert.equal(model.findConfigEntryById(monitors, "profile_all_off").index, 3);
    assert.equal(model.findConfigEntryById(monitors, "nope"), null);
    assert.equal(model.findConfigEntryById({}, "x"), null);
    assert.equal(model.findConfigEntryByFingerprint(monitors, ["DP-1", "eDP-1"], false).entry.id, "profile_named_same_set");
    assert.equal(model.findConfigEntryByFingerprint(monitors, ["eDP-1", "DP-1"], false).entry.id, "profile_named_same_set");
    assert.equal(model.findConfigEntryByFingerprint(monitors, ["DP-1", "eDP-1"], true).entry.id, "auto_1a2b3c");
    assert.equal(model.findConfigEntryByFingerprint(monitors, ["Dell Inc. DELL U2720Q ABC123", "BOE 0x0A1B Unknown"], false).entry.id, "profile_1700000000000_abc1234");
    assert.equal(model.findConfigEntryByFingerprint(monitors, ["Dell Inc. DELL U2720Q ABC123", "BOE 0x0A1B Unknown"], true), null);
    assert.equal(model.findConfigEntryByFingerprint(monitors, ["nope"], false), null);
});

test("profile keys match live outputs by name, desc prefix and model without serial", () => {
    const matches = key => Object.keys(live).filter(name => model.profileKeyMatchesOutput(key, live[name], name, "model", "hyprland"));
    assert.deepEqual(matches("DP-1"), ["DP-1"]);
    assert.deepEqual(matches("desc:Dell Inc. DELL U2720Q ABC123"), ["DP-1"]);
    assert.deepEqual(matches("desc:Dell Inc. DELL U2720Q"), ["DP-1"]);
    assert.deepEqual(matches("desc:Dell"), ["DP-1"]);
    assert.deepEqual(matches("Dell Inc. DELL U2720Q"), ["DP-1"]);
    assert.deepEqual(matches("Dell Inc. DELL U2720Q ABC123"), []);
    assert.deepEqual(matches("desc:BOE 0x0A1B"), ["eDP-1"]);
    assert.deepEqual(matches("desc:DELL U2720Q"), []);
});

test("ensureEnabledOutput re-enables the first real live output of an all-disabled profile and leaves virtual-only profiles alone", () => {
    const allOff = clone(monitors.configurations[3]);
    assert.equal(model.ensureEnabledOutput(allOff, live, "system", "niri"), true);
    assert.equal(allOff.outputs["DP-1"].disabled, undefined);
    assert.equal(allOff.outputs["DP-9"].disabled, true);
    assert.equal(model.ensureEnabledOutput(clone(monitors.configurations[1]), live, "model", "niri"), false);
    assert.equal(model.ensureEnabledOutput({ outputs: {} }, live, "system", "niri"), false);
    const virtualOutputs = { "Virtual-1": { name: "Virtual-1", make: "", model: "" } };
    const virtualEntry = { outputs: { "Virtual-1": { disabled: true } } };
    assert.equal(model.ensureEnabledOutput(virtualEntry, virtualOutputs, "system", "niri"), false);
    assert.equal(virtualEntry.outputs["Virtual-1"].disabled, true);
    assert.deepEqual([model.profileOutputIsReal("DP-1", live, "system", "niri"), model.profileOutputIsReal("Virtual-1", virtualOutputs, "system", "niri"), model.profileOutputIsReal("DP-9", live, "system", "niri"), model.profileOutputIsReal("Dell Inc. DELL U2720Q ABC123", live, "model", "niri")], [true, false, true, true]);
});

test("profile entries expand against live modes and match the live layout only when geometry agrees", () => {
    const desk = plain(model.outputsDataFromConfigEntry(monitors.configurations[1], live, "model", "niri"));
    assert.deepEqual(Object.keys(desk), ["Dell Inc. DELL U2720Q ABC123", "BOE 0x0A1B Unknown"]);
    const dellEntry = desk["Dell Inc. DELL U2720Q ABC123"];
    assert.deepEqual([dellEntry.explicitIdentifier, dellEntry.configured_mode, dellEntry.current_mode, dellEntry.modes.length], [true, "3840x2160@60.000", 0, 3]);
    assert.deepEqual(dellEntry.logical, { x: 0, y: 0, scale: 2, transform: "Normal" });
    const mirror = plain(model.outputsDataFromConfigEntry(monitors.configurations[2], live, "model", "hyprland"))["desc:Dell Inc. DELL U2720Q"];
    assert.deepEqual([mirror.current_mode, mirror.mirror], [2, "eDP-1"]);
    assert.equal(model.configEntryMatchesLiveLayout(monitors.configurations[0], live, "system", "niri"), true);
    assert.equal(model.configEntryMatchesLiveLayout(monitors.configurations[1], live, "model", "niri"), false);
    assert.equal(model.configEntryMatchesLiveLayout(monitors.configurations[4], live, "system", "niri"), false);
    const wlrScale = clone(live);
    wlrScale["eDP-1"].logical.scale = Math.floor(1.3 * 256) / 256;
    assert.equal(model.configEntryMatchesLiveLayout(monitors.configurations[0], wlrScale, "system", "niri"), true);
    const otherScale = clone(live);
    otherScale["eDP-1"].logical.scale = 1.3 + 2 / 256;
    assert.equal(model.configEntryMatchesLiveLayout(monitors.configurations[0], otherScale, "system", "niri"), false);
    assert.equal(model.configEntryMatchesLiveLayout({ outputs: { "HDMI-A-1": { disabled: true } } }, live, "system", "niri"), true);
});

test("neutral config carries the backend settings for the compositor and hoists disabled out of them", () => {
    const niriSettings = { "DP-1": { vrrOnDemand: true, disabled: true }, "Dell Inc. DELL U2720Q ABC123": { focusAtStartup: true } };
    const hyprSettings = { "DP-1": { bitdepth: 10, disabled: true }, "desc:Dell Inc. DELL U2720Q ABC123": { colorManagement: "hdr" } };
    assert.deepEqual(plain(model.outputNeutralConfig("DP-1", live["DP-1"], niriSettings, hyprSettings, "system", "niri")), { mode: "3840x2160@59.997", position: { x: 0, y: 0 }, scale: 1.5, transform: "Normal", vrr: true, disabled: true, niri: { vrrOnDemand: true } });
    assert.deepEqual(plain(model.outputNeutralConfig("DP-1", live["DP-1"], niriSettings, hyprSettings, "model", "hyprland")), { mode: "3840x2160@59.997", position: { x: 0, y: 0 }, scale: 1.5, transform: "Normal", vrr: true, disabled: false, hyprland: { colorManagement: "hdr" } });
    assert.deepEqual(plain(model.outputNeutralConfig("DP-1", { ...live["DP-1"], mirror: "eDP-1" }, niriSettings, hyprSettings, "system", "hyprland")).hyprland, { bitdepth: 10, mirror: "eDP-1" });
});

test("filterDisconnectedOnly keeps saved outputs no live head matches, desc: keys resolve only on hyprland, names are trimmed", () => {
    const hyprParsed = plain(model.parseHyprlandOutputs(text("hyprland-monitors.lua")));
    assert.deepEqual(Object.keys(model.filterDisconnectedOnly(hyprParsed, live, "model", "hyprland")), ["DP-2", "DP-3", "it's"]);
    assert.deepEqual(Object.keys(model.filterDisconnectedOnly(hyprParsed, live, "system", "niri")), ["desc:Dell Inc. DELL U2720Q ABC123", "DP-2", "DP-3", "it's"]);
    assert.deepEqual(model.filterDisconnectedOnly(plain(model.parseNiriOutputs(text("niri-outputs.kdl"))), live, "model", "niri"), {});
    assert.deepEqual(Object.keys(model.filterDisconnectedOnly({ " DP-1 ": { name: "DP-1" }, "DP-7 ": { name: "DP-7" } }, live, "system", "niri")), ["DP-7 "]);
});

test("aqueous heads: fingerprint, head list and comparison tolerate scale noise and equivalent custom modes", () => {
    assert.deepEqual(JSON.parse(model.outputFingerprint(wlr.outputs))[0], { name: "DP-1", id: 1, enabled: true, x: 0, y: 0, scale: 1.5, transform: 0, mode: [3840, 2160, 59997], adaptiveSync: 1 });
    const heads = plain(model.outputHeads(wlr.outputs));
    assert.deepEqual(heads[0], { name: "DP-1", enabled: true, modeId: 1, position: { x: 0, y: 0 }, scale: 1.5, transform: 0, adaptiveSync: 1 });
    assert.deepEqual(heads[2], { name: "HDMI-A-1", enabled: false, position: { x: 0, y: 0 }, scale: 0, transform: 0, adaptiveSync: 0 });
    assert.equal(model.outputHeadsMatch(heads, wlr.outputs, wlr.outputs), true);
    const moved = clone(wlr.outputs);
    moved[0].x = 10;
    assert.equal(model.outputHeadsMatch(heads, moved, wlr.outputs), false);
    assert.equal(model.outputHeadsMatch(heads.slice(1), wlr.outputs, wlr.outputs), false);
    const renumbered = clone(wlr.outputs);
    renumbered[0].id = 99;
    assert.equal(model.outputHeadsMatch(heads, wlr.outputs, renumbered), false);
    const scaled = clone(heads);
    scaled[1].scale = 1.30001;
    assert.equal(model.outputHeadsMatch(scaled, wlr.outputs, wlr.outputs), true);
    const customMode = clone(heads);
    customMode[0].modeId = 77;
    customMode[0].customMode = { width: 3840, height: 2160, refresh: 59997 };
    assert.equal(model.outputHeadsMatch(customMode, wlr.outputs, wlr.outputs), true);
});

test("sizes: rotation swaps, niri ceils and hyprland rounds logical sizes, bounds default to 1920x1080", () => {
    assert.deepEqual(model.physicalSize(live["DP-1"]), { w: 3840, h: 2160 });
    assert.deepEqual(model.physicalSize(live["eDP-1"]), { w: 1200, h: 1920 });
    assert.deepEqual(model.physicalSize(null), { w: 1920, h: 1080 });
    assert.deepEqual(model.logicalSize(live["DP-1"], "niri"), { w: 2560, h: 1440 });
    assert.deepEqual(model.logicalSize(live["eDP-1"], "niri"), { w: 924, h: 1477 });
    assert.deepEqual(model.logicalSize({ modes: [{ width: 2560, height: 1600 }], current_mode: 0, logical: { scale: 1.75 } }, "niri"), { w: 1463, h: 915 });
    assert.deepEqual(model.logicalSize(live["eDP-1"], "hyprland"), { w: 923, h: 1477 });
    assert.deepEqual(model.logicalSize({ logical: { width: 2560, height: 1440, scale: 2, transform: "90" } }, "niri"), { w: 1440, h: 2560 });
    assert.deepEqual(model.outputBounds(live, "niri"), { minX: 0, minY: 0, maxX: 3484, maxY: 1477, width: 3484, height: 1477 });
    assert.deepEqual(model.outputBounds(live, "hyprland").maxY, 1477);
    assert.deepEqual(model.outputBounds({}, "niri"), { minX: 0, minY: 0, maxX: 1920, maxY: 1080, width: 1920, height: 1080 });
});

test("canvas: overlap ignores disabled outputs, snapping to neighbour edges, adjacent shifts on rescale, normalization to origin", () => {
    const layout = { outputs: live, disabled: { "HDMI-A-1": true }, compositor: "niri" };
    assert.equal(model.checkOverlap(layout, "eDP-1", 2560, 0, 923, 1476), false);
    assert.equal(model.checkOverlap(layout, "eDP-1", 2559, 0, 923, 1476), true);
    assert.equal(model.checkOverlap(layout, "HDMI-A-1", 0, 0, 100, 100), true);
    assert.equal(model.checkOverlap(layout, "DP-1", 0, 0, 10, 10), false);
    assert.equal(model.checkOverlap({ outputs: live, disabled: {}, compositor: "hyprland" }, "DP-1", 0, 0, 10, 10), true);
    assert.deepEqual([[2570, 30], [3000, 3000], [2400, 100], [1000, 1500], [-900, 1300]].map(([x, y]) => model.snapToEdges(layout, "eDP-1", x, y, 923, 1476)), [{ x: 2560, y: 0 }, { x: 3000, y: 3000 }, { x: 2560, y: 0 }, { x: 1000, y: 1440 }, { x: -923, y: 1440 }]);
    const issue3875 = { compositor: "niri", disabled: {}, outputs: {
        "DP-1": { modes: [{ width: 3440, height: 1440 }], current_mode: 0, logical: { x: 0, y: 0, scale: 1 } },
        "eDP-1": { modes: [{ width: 2560, height: 1600 }], current_mode: 0, logical: { x: 3440, y: 526, scale: 1.75 } },
        "DP-2": { modes: [{ width: 5120, height: 1440 }], current_mode: 0, logical: { x: 10022, y: 0, scale: 1 } }
    } };
    assert.deepEqual(model.snapToEdges(issue3875, "DP-2", 4890, -5, 5120, 1440), { x: 4903, y: 0 });
    assert.deepEqual(model.recalculateAdjacentPositions(live, {}, "DP-1", 2, "niri"), [{ name: "eDP-1", x: 1920, y: 0 }]);
    assert.deepEqual(model.recalculateAdjacentPositions(live, { "eDP-1": { position: { x: 2563, y: 5 } } }, "eDP-1", 1, "niri"), [{ name: "eDP-1", x: 2560, y: 5 }]);
    assert.deepEqual(model.recalculateAdjacentPositions(live, {}, "HDMI-A-1", 1, "niri"), []);
    assert.deepEqual(model.normalizeOutputPositions({ a: { logical: { x: -100, y: 50 } }, b: { logical: { x: 200, y: -20 } }, c: { name: "c" } }), { a: { logical: { x: 0, y: 70 } }, b: { logical: { x: 300, y: 0 } }, c: { name: "c" } });
    assert.deepEqual(model.normalizeOutputPositions({ a: { logical: { x: 40, y: 40 } } }), { a: { logical: { x: 0, y: 0 } } });
});

test("labels and scale presets: every offered scale divides the mode into whole logical pixels", () => {
    assert.deepEqual([null, { width: 1920, height: 1080, refresh_rate: 59997 }].map(m => model.formatMode(m)), ["", "1920x1080@59.997"]);
    const hd = { name: "X", modes: [{ width: 1366, height: 768, refresh_rate: 60000 }, { width: 1920, height: 1080, refresh_rate: 60000 }], current_mode: 0 };
    assert.deepEqual(rounded(model.scalePresetValues(hd, undefined, "hyprland")), [0.5, 0.667, 1, 2]);
    assert.deepEqual(model.scalePresetValues(hd, undefined, "sway"), [0.5, 1, 1.125, 1.25, 1.375, 1.5, 1.625, 1.75, 1.875, 2]);
    const qhd = { name: "Q", modes: [{ width: 2560, height: 1440, refresh_rate: 60000 }], current_mode: 0 };
    assert.deepEqual(rounded(model.scalePresetValues(qhd, undefined, "niri")).filter(s => s >= 1 && s <= 1.34), [1, 1.067, 1.1, 1.15, 1.2, 1.25, 1.3, 1.333]);
    assert.deepEqual([1.1, 1.07, 1.26].map(s => model.snapScaleToMode(qhd, undefined, "niri", s)).concat(model.snapScaleToMode(qhd, undefined, "hyprland", 1.1)), [1.1, 1.066667, 1.25, 1.066667]);
    const fullHd = model.scalePresetValues(hd, "1920x1080@60.000", "hyprland");
    assert.equal(fullHd.includes(1.75), false);
    assert.deepEqual(fullHd.filter(s => Math.abs(1920 / s - Math.round(1920 / s)) > 0.01 || Math.abs(1080 / s - Math.round(1080 / s)) > 0.01), []);
    assert.deepEqual(model.scalePresetValues({ name: "Z", modes: [] }, undefined, "niri"), [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]);
    assert.deepEqual([1.75, 1.3, 0.3, 9, "abc"].map(s => model.snapScaleToMode(hd, "1920x1080@60.000", "hyprland", s)), [1.666667, 1.333333, 0.3, null, null]);
    assert.equal(model.snapScaleToMode({ name: "Z", modes: [] }, undefined, "niri", 1.7), 1.7);
    assert.equal(model.modeForScalePresets(live["DP-1"], "1920x1080@60.000").id, 2);
    assert.equal(model.modeForScalePresets(live["DP-1"], "9x9@1.000").id, 1);
    assert.equal(model.modeForScalePresets({ name: "Z", modes: [] }, undefined), null);
});

const gaming = modeSamples.niri.gaming;
const tolerance = 1000;

test("mode strings parse and format with three decimals, refresh_rate wins over refresh", () => {
    assert.deepEqual(model.parseModeString("2560x1440@59.940"), { width: 2560, height: 1440, refresh: 59940 });
    assert.deepEqual(model.parseModeString("2560x1440@60"), { width: 2560, height: 1440, refresh: 60000 });
    assert.deepEqual(["1920x1080", null].map(s => model.parseModeString(s)), [null, null]);
    assert.equal(model.formatModeString({ width: 2560, height: 1440, refresh_rate: 143998 }), "2560x1440@143.998");
    assert.equal(model.formatModeString({ id: 1, width: 3840, height: 2160, refresh: 59997 }), "3840x2160@59.997");
    assert.equal(model.formatModeString({ width: 1920, height: 1080, refresh_rate: 60000, refresh: 48000 }), "1920x1080@60.000");
    assert.equal(model.formatModeString(null), "");
    assert.equal(model.modeRefresh({ width: 1920, height: 1080, refresh_rate: 0, refresh: 48000 }), 0);
});

test("findModeByString: exact string first, then same resolution within the refresh tolerance", () => {
    assert.deepEqual(model.findModeByString(gaming.modes, "2560x1440@144.000", tolerance), gaming.modes[0]);
    assert.deepEqual(model.findModeByString(gaming.modes, "2560x1440@59.940", tolerance), gaming.modes[2]);
    assert.deepEqual(model.findModeByString(gaming.modes, "2560x1440@60", tolerance), gaming.modes[2]);
    assert.equal(model.findModeByString(gaming.modes, "2560x1440@61.500", tolerance), null);
    assert.equal(model.findModeByString(gaming.modes, "1920x1080@120", tolerance), null);
    assert.equal(model.findModeByString([], "1920x1080@60.000", tolerance), null);
    assert.equal(model.findModeByString(modeSamples.wlr.gaming.modes, "2560x1440@59.940", tolerance).id, 2);
});

test("battery refresh mode: same resolution closest to 60 Hz, none for single-rate, vrr, far or disabled wlr outputs", () => {
    const niri = (output, target = 60000, tol = tolerance) => model.batteryRefreshMode(output, model.niriCurrentMode(output), "niri", target, tol);
    const wlrPick = output => model.batteryRefreshMode(output, output.currentMode, "wlr", 60000, tolerance);
    assert.deepEqual(niri(modeSamples.niri.gaming), { width: 2560, height: 1440, refresh_rate: 60000 });
    assert.deepEqual(niri(modeSamples.niri.nearSixty), { width: 1920, height: 1080, refresh_rate: 60000 });
    assert.deepEqual(niri(modeSamples.niri.atSixty), { width: 2560, height: 1440, refresh_rate: 60000 });
    assert.equal(niri(modeSamples.niri.single), null);
    assert.equal(niri(modeSamples.niri.vrr), null);
    assert.equal(niri(modeSamples.niri.far), null);
    assert.equal(niri(modeSamples.niri.noCurrent), null);
    assert.equal(wlrPick(modeSamples.wlr.gaming).id, 2);
    assert.equal(wlrPick(modeSamples.wlr.nearSixty).id, 11);
    assert.equal(wlrPick(modeSamples.wlr.disabled), null);
    assert.equal(model.batteryRefreshMode(modeSamples.wlr.disabled, modeSamples.wlr.disabled.currentMode, "niri", 60000, tolerance).id, 41);
    assert.equal(model.batteryRefreshMode(null, gaming.modes[0], "niri", 60000, tolerance), null);
    assert.deepEqual(niri(modeSamples.niri.gaming, 120000), gaming.modes[1]);
    assert.deepEqual(niri(modeSamples.niri.far, 60000, 30000), modeSamples.niri.far.modes[1]);
});

test("modeAlreadyCurrent tolerates the refresh tolerance, restoreModeValue keeps wlr id 0 and formats niri strings", () => {
    assert.equal(model.modeAlreadyCurrent(modeSamples.niri.nearSixty.modes[1], modeSamples.niri.nearSixty.modes[2], tolerance), true);
    assert.equal(model.modeAlreadyCurrent(gaming.modes[1], gaming.modes[2], tolerance), false);
    assert.equal(model.modeAlreadyCurrent(gaming.modes[2], gaming.modes[3], tolerance), false);
    assert.equal(model.modeAlreadyCurrent(null, gaming.modes[0], tolerance), true);
    assert.equal(model.modeAlreadyCurrent(modeSamples.wlr.nearSixty.modes[1], { width: 1920, height: 1080, refresh_rate: 61000 }, tolerance), true);
    assert.equal(model.modeAlreadyCurrent(modeSamples.wlr.nearSixty.modes[1], { width: 1920, height: 1080, refresh_rate: 61001 }, tolerance), false);
    assert.equal(model.restoreModeValue(modeSamples.wlr.gaming.modes[0], "wlr"), 0);
    assert.equal(model.restoreModeValue({ width: 1920, height: 1080, refresh: 60000 }, "wlr"), null);
    assert.equal(model.restoreModeValue(gaming.modes[0], "niri"), "2560x1440@144.000");
    assert.equal(model.restoreModeValue(null, "wlr"), null);
    assert.deepEqual([{}, { vrr_enabled: "true" }, { adaptiveSync: true }, { adaptiveSync: 1 }, { vrr_enabled: true, adaptiveSync: 0 }].map(o => model.outputVrrEnabled(o)), [false, false, false, true, true]);
    assert.equal(model.niriCurrentMode({ current_mode: 0 }), null);
});

test("mango rule writer carries hdr/icc/disable from existing rules, keeps fractional refresh, writes snake_case", () => {
    const outputs = {
        "DP-1": { configured_mode: "2560x1440@59.951", logical: { x: 0, y: 0, scale: 1, transform: "Normal" }, vrr_enabled: true, enabled: true },
        "HDMI-A-1": { modes: [{ width: 1920, height: 1080, refresh_rate: 60000 }], current_mode: 0, logical: { x: 2560, y: 0, scale: 1, transform: "90" }, enabled: false }
    };
    const existing = [
        "monitor_rule=name:^DP-1$,width:2560,height:1440,refresh:60,x:0,y:0,scale:1,rr:0,vrr:0,icc:/p.icc,disable:1",
        "monitor_rule=name:DP-1,hdr:1,icc:/ignored.icc",
        "monitor_rule=name:^HDMI-A-1$,primary:1"
    ].join("\n");
    assert.deepEqual(model.mangoMonitorRuleLines(outputs, existing), [
        "monitor_rule=name:^DP-1$,width:2560,height:1440,refresh:59.951,x:0,y:0,scale:1,rr:0,vrr:1,icc:/p.icc,hdr:1",
        "monitor_rule=name:^HDMI-A-1$,width:1920,height:1080,refresh:60,x:2560,y:0,scale:1,rr:1,vrr:0,primary:1,disable:1"
    ]);
});

test("hyprland hardwareDetails gate vrr and color modes like Hyprland does, and gate nothing when absent", () => {
    const edp = model.hyprlandHardware({ hardwareDetails: { backend: "drm", hdr: false, chroma: true, bt2020: false, vrrCapable: true } });
    const hdrPanel = model.hyprlandHardware({ hardwareDetails: { hdr: true, chroma: false, bt2020: true, vrrCapable: false } });
    assert.equal(model.hyprlandHardware({ name: "eDP-1" }), null);
    const allowed = caps => ["auto", "wide", "edid", "hdr", "hdredid", "dcip3"].filter(cm => model.hyprlandCmAllowed(cm, caps));
    const matrix = [
        [model.hyprlandCaps(null, {}), ["auto", "wide", "edid", "hdr", "hdredid", "dcip3"], undefined],
        [model.hyprlandCaps(edp, {}), ["auto", "edid", "dcip3"], true],
        [model.hyprlandCaps(edp, { supportsWideColor: 1, supportsHdr: true }), ["auto", "wide", "edid", "hdr", "hdredid", "dcip3"], true],
        [model.hyprlandCaps(hdrPanel, {}), ["auto", "wide", "hdr", "hdredid", "dcip3"], false],
        [model.hyprlandCaps(hdrPanel, { supportsWideColor: false }), ["auto", "dcip3"], false]
    ];
    assert.deepEqual(matrix.map(([caps]) => [allowed(caps), caps?.vrr]), matrix.map(([, cms, vrr]) => [cms, vrr]));
    const wlr = model.outputsFromWlr([{ name: "eDP-1", modes: [] }], { "eDP-1": { x: 0, y: 0, scale: 1.25, hardware: edp } });
    assert.deepEqual(plain(wlr["eDP-1"].hardware), plain(edp));
});
