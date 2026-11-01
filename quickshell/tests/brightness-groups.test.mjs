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
        lastIpcGroup: [],
        lastIpcDevice: ""
    }, globals));
    for (const name of ["setGroupBrightness", "lastIpcTargets", "pinnedDevices"])
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
