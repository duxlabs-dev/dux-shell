import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const SERVICE = "../Services/BrightnessService.qml";
const plain = value => JSON.parse(JSON.stringify(value));

function functionSource(name) {
    const source = readFileSync(new URL(SERVICE, import.meta.url), "utf8");
    const found = source.match(new RegExp(`^    function ${name}\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
    if (!found)
        throw new Error(`${name} not found in ${SERVICE}`);
    return found[0];
}

const touchBar = { id: "backlight:appletb_backlight", class: "backlight", name: "appletb_backlight", current: 1, max: 2, currentPercent: 50 };
const panel = { id: "backlight:gmux_backlight", class: "backlight", name: "gmux_backlight", current: 500, max: 1000, currentPercent: 50 };

function service(controlled) {
    const context = vm.createContext({
        Quickshell: { screens: [{ name: "eDP-1" }] },
        SessionData: {
            brightnessControlledDevices: controlled,
            lastBrightnessDevice: "",
            getBrightnessExponential: () => false
        },
        allDevices: [],
        devices: [],
        deviceBrightness: {},
        deviceBrightnessUserSet: {},
        deviceMaxCache: {},
        pendingOsdDevices: {},
        brightnessVersion: 0,
        brightnessAvailable: false,
        brightnessInitialized: false,
        suppressOsd: false,
        currentDevice: "",
        lastIpcDevice: "",
        lastIpcGroup: [],
        osdShown: 0,
        brightnessChanged() {
            context.osdShown++;
        },
        isDeviceUserControlled: () => false,
        setCurrentDevice(id) {
            context.currentDevice = id;
            context.lastIpcDevice = id;
        }
    });
    for (const name of ["controlsAllDevices", "isDeviceControlled", "updateSingleDevice", "updateFromBrightnessState", "internalPanelActive", "isInternalPanelName", "internalPanelDevice"])
        vm.runInContext(functionSource(name), context);
    return context;
}

test("only checked devices are controlled, picked as default, or raise the OSD", () => {
    const context = service([panel.id]);

    context.updateFromBrightnessState({ devices: [touchBar, panel] });
    context.updateSingleDevice(Object.assign({}, touchBar, { currentPercent: 0 }));
    context.updateFromBrightnessState({ devices: [Object.assign({}, touchBar, { currentPercent: 100 }), panel] });

    assert.deepEqual(plain(context.devices.map(d => d.id)), [panel.id]);
    assert.deepEqual(plain(context.allDevices.map(d => d.id)), [touchBar.id, panel.id]);
    assert.equal(context.currentDevice, panel.id);
    assert.equal(context.osdShown, 0);
});

test("unchecking the current device moves control to a checked one", () => {
    const context = service(["all"]);
    context.updateFromBrightnessState({ devices: [touchBar, panel] });
    assert.equal(context.currentDevice, touchBar.id);

    context.SessionData.brightnessControlledDevices = [panel.id];
    context.updateFromBrightnessState({ devices: [touchBar, panel] });

    assert.deepEqual([context.currentDevice, context.lastIpcDevice], [panel.id, panel.id]);
});

test("with every checked device unplugged, the present devices stay controlled", () => {
    const context = service(["ddc:i2c-5"]);

    context.updateFromBrightnessState({ devices: [touchBar, panel] });

    assert.deepEqual(plain(context.devices.map(d => d.id)), [touchBar.id, panel.id]);
});
