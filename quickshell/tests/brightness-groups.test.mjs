import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const SERVICE = "../Services/BrightnessService.qml";
const plain = value => JSON.parse(JSON.stringify(value));

function functionSource(file, name) {
    const source = readFileSync(new URL(file, import.meta.url), "utf8");
    const found = source.match(new RegExp(`^    function ${name}\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
    if (!found)
        throw new Error(`${name} not found in ${file}`);
    return found[0];
}

function service(globals) {
    const context = vm.createContext(Object.assign({
        QmlUtils: loadScript(new URL("../Common/QmlUtils.js", import.meta.url)),
        Quickshell: { screens: [] },
        SettingsData: { getScreenDisplayName: screen => screen?.name ?? "" },
        CacheData: { brightnessDevicePins: {} },
        devices: [],
        deviceBrightness: {},
        brightnessAvailable: true,
        suppressOsd: false,
        currentDevice: "",
        lastIpcGroup: [],
        lastIpcDevice: "",
        getDeviceBrightness(id) {
            return id && id in context.deviceBrightness ? context.deviceBrightness[id] : 50;
        },
        getCurrentDeviceInfoByName(id) {
            return context.devices.find(d => d.id === id) ?? null;
        },
        brightnessMinimum(info) {
            return info?.min ?? (info?.class === "backlight" || info?.class === "ddc" ? 1 : 0);
        },
        brightnessMaximum(info) {
            return info?.max ?? 100;
        },
        setCurrentDevice(id) {
            context.currentDevice = id;
            context.lastIpcDevice = id;
        },
        brightnessChanged() {}
    }, globals));
    context.root = context;
    for (const name of [
        "internalPanelActive",
        "isInternalPanelName",
        "internalPanelDevice",
        "getDefaultDevice",
        "setGroupBrightness",
        "lastIpcTargets",
        "pinnedDevices",
        "screenPinnedDevices",
        "screenBrightnessTargets",
        "adjustScreenBrightness",
        "screenTargets",
        "screenTargetsLastDevice",
        "screenLeadDevice"
    ])
        vm.runInContext(functionSource(SERVICE, name), context);
    return context;
}

function recordingService(ranges) {
    const calls = [];
    const context = service({
        getCurrentDeviceInfoByName: id => ranges[id],
        brightnessMinimum: info => info?.min ?? 1,
        brightnessMaximum: info => info?.max ?? 100,
        setBrightness(value, id, suppressOsd) {
            calls.push([value, id, suppressOsd]);
            context.lastIpcDevice = id;
            context.lastIpcGroup = [];
        }
    });
    return { context, calls };
}

test("a group maps the lead's position onto each member's range and sets the lead last", () => {
    const { context, calls } = recordingService({
        "backlight:a": { min: 1, max: 100 },
        "ddc:i2c-11": { min: 1, max: 100 },
        "ddc:i2c-12": { min: 0, max: 50 }
    });

    context.setGroupBrightness(51, ["ddc:i2c-11", "backlight:a", "ddc:i2c-12"], false);

    assert.deepEqual(calls, [[51, "backlight:a", true], [25, "ddc:i2c-12", true], [51, "ddc:i2c-11", false]]);
    assert.deepEqual(plain(context.lastIpcTargets()), ["ddc:i2c-11", "backlight:a", "ddc:i2c-12"]);
});

test("a single or default target is set once and never becomes a group", () => {
    const { context, calls } = recordingService({});

    context.setGroupBrightness(40, [""], false);

    assert.deepEqual(calls, [[40, "", false]]);
    assert.deepEqual(plain(context.lastIpcTargets()), [""]);
});

test("follow-up controls drop the group once another device became the last target", () => {
    const context = service({ lastIpcGroup: ["ddc:i2c-11", "ddc:i2c-12"], lastIpcDevice: "backlight:a" });

    assert.deepEqual(plain(context.lastIpcTargets()), ["backlight:a"]);
});

test("pins read legacy single-device strings and skip unplugged devices", () => {
    const devices = [{ id: "backlight:a" }, { id: "ddc:i2c-11" }];
    const context = service({
        devices,
        CacheData: { brightnessDevicePins: { "eDP-1": "backlight:a", "DP-1": ["ddc:i2c-12", "ddc:i2c-11", "backlight:a"] } }
    });

    assert.deepEqual(plain(context.pinnedDevices("eDP-1")), ["backlight:a"]);
    assert.deepEqual(plain(context.pinnedDevices("DP-1")), ["ddc:i2c-11", "backlight:a"]);
    assert.deepEqual(plain(context.pinnedDevices("")), []);
});

test("each screen targets its own pins and only unpinned screens follow the last target", () => {
    const context = service({
        devices: [{ id: "ddc:i2c-11" }, { id: "ddc:i2c-12" }, { id: "ddc:i2c-13" }, { id: "backlight:a" }],
        SettingsData: { getScreenDisplayName: screen => screen.name },
        CacheData: { brightnessDevicePins: { "DP-1": ["ddc:i2c-11"], "DP-2": ["ddc:i2c-12", "ddc:i2c-13"] } },
        lastIpcDevice: "backlight:a"
    });

    assert.deepEqual(plain(context.screenTargets({ name: "DP-1" })), ["ddc:i2c-11"]);
    assert.equal(context.screenLeadDevice({ name: "DP-1" }), "ddc:i2c-11");
    assert.deepEqual(plain(context.screenTargets({ name: "DP-2" })), ["ddc:i2c-12", "ddc:i2c-13"]);
    assert.equal(context.screenLeadDevice({ name: "DP-2" }), "ddc:i2c-12");
    assert.deepEqual(plain(context.screenTargets({ name: "HDMI-1" })), ["backlight:a"]);
    assert.equal(context.screenLeadDevice({ name: "HDMI-1" }), "backlight:a");
    assert.deepEqual(plain(context.screenTargets(null)), ["backlight:a"]);
});

test("only screens that target the changed device react to it", () => {
    const context = service({
        devices: [{ id: "ddc:i2c-11" }, { id: "ddc:i2c-12" }, { id: "ddc:i2c-13" }],
        SettingsData: { getScreenDisplayName: screen => screen.name },
        CacheData: { brightnessDevicePins: { "DP-1": ["ddc:i2c-11"], "DP-2": ["ddc:i2c-12", "ddc:i2c-13"] } },
        lastIpcDevice: "ddc:i2c-11"
    });

    assert.equal(context.screenTargetsLastDevice({ name: "DP-1" }), true);
    assert.equal(context.screenTargetsLastDevice({ name: "DP-2" }), false);
    assert.equal(context.screenTargetsLastDevice({ name: "HDMI-1" }), true);
    assert.equal(context.screenTargetsLastDevice(null), true);
});

test("screenBrightnessTargets resolves pins, internal panel, per-screen software, and unambiguous single external DDC", () => {
    const screens = [{ name: "eDP-1" }, { name: "DP-1" }];
    const context = service({
        Quickshell: { screens },
        devices: [
            { id: "backlight:intel_backlight", class: "backlight" },
            { id: "ddc:i2c-7", class: "ddc" },
            { id: "software:HDMI-A-1", class: "software" }
        ],
        CacheData: { brightnessDevicePins: {} }
    });

    assert.deepEqual(plain(context.screenBrightnessTargets({ name: "eDP-1" })), ["backlight:intel_backlight"]);
    assert.deepEqual(plain(context.screenBrightnessTargets("DP-1")), ["ddc:i2c-7"]);
    assert.deepEqual(plain(context.screenBrightnessTargets("HDMI-A-1")), ["software:HDMI-A-1"]);

    context.CacheData.brightnessDevicePins = { "DP-1": ["ddc:i2c-7", "backlight:intel_backlight"] };
    assert.deepEqual(plain(context.screenBrightnessTargets({ name: "DP-1" })), ["ddc:i2c-7", "backlight:intel_backlight"]);

    // With two external screens and unpinned DDC, avoid guessing the wrong external monitor
    context.CacheData.brightnessDevicePins = {};
    context.Quickshell.screens = [{ name: "eDP-1" }, { name: "DP-1" }, { name: "DP-2" }];
    assert.deepEqual(plain(context.screenBrightnessTargets({ name: "DP-1" })), ["backlight:intel_backlight"]);
});

test("adjustScreenBrightness steps groups, clamps bounds, and skips hardware writes when already at min or max", () => {
    const calls = [];
    const osdSignals = [];
    const context = service({
        Quickshell: { screens: [{ name: "DP-1" }] },
        devices: [
            { id: "ddc:i2c-11", class: "ddc", min: 1, max: 100 },
            { id: "ddc:i2c-12", class: "ddc", min: 0, max: 50 }
        ],
        deviceBrightness: { "ddc:i2c-11": 98, "ddc:i2c-12": 49 },
        CacheData: { brightnessDevicePins: { "DP-1": ["ddc:i2c-11", "ddc:i2c-12"] } },
        setBrightness(value, id, suppressOsd) {
            calls.push([value, id, suppressOsd]);
            context.deviceBrightness[id] = value;
            context.lastIpcDevice = id;
            context.lastIpcGroup = [];
        },
        brightnessChanged(showOsd) {
            osdSignals.push(showOsd);
        }
    });

    assert.equal(context.adjustScreenBrightness({ name: "DP-1" }, 5, 1), true);
    assert.deepEqual(calls, [[50, "ddc:i2c-12", true], [100, "ddc:i2c-11", false]]);
    assert.equal(context.currentDevice, "ddc:i2c-11");
    assert.deepEqual(plain(context.lastIpcTargets()), ["ddc:i2c-11", "ddc:i2c-12"]);

    // Already at max: no duplicate I2C write, group stays intact, OSD still pings
    calls.length = 0;
    assert.equal(context.adjustScreenBrightness({ name: "DP-1" }, 5, 1), true);
    assert.deepEqual(calls, []);
    assert.deepEqual(osdSignals, [true]);
    assert.deepEqual(plain(context.lastIpcTargets()), ["ddc:i2c-11", "ddc:i2c-12"]);
});
