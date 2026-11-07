import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../DMSShellIPC.qml", import.meta.url), "utf8");
const widgetBlock = source.slice(source.indexOf("    IpcHandler {\n        function toggleOverlay("), source.indexOf('        target: "desktopWidget"'));
const functions = [...widgetBlock.matchAll(/^ {4,8}function (\w+)\(([^)]*)\)(?:: \w+)? \{\n[\s\S]*?^\s{4,8}\}$/gm)];
const untyped = functions.map(match => match[0].replace(/\((.*?)\)(?:: \w+)? \{/, (_, params) => "(" + params.replace(/: \w+/g, "") + ") {"));

function createIpcContext(initialInstances = []) {
    const instances = JSON.parse(JSON.stringify(initialInstances));
    const configUpdates = [];
    const instanceUpdates = [];

    const SettingsData = {
        desktopWidgetInstances: instances,
        getDesktopWidgetInstance(id) {
            return instances.find(inst => inst.id === id) ?? null;
        },
        updateDesktopWidgetInstanceConfig(id, patch) {
            configUpdates.push([id, patch]);
            const inst = instances.find(i => i.id === id);
            if (inst) {
                inst.config = Object.assign({}, inst.config || {}, patch);
            }
        },
        updateDesktopWidgetInstance(id, patch) {
            instanceUpdates.push([id, patch]);
            const inst = instances.find(i => i.id === id);
            if (inst) {
                Object.assign(inst, patch);
            }
        }
    };

    const DesktopWidgetRegistry = { editing: false };
    const context = vm.createContext({ SettingsData, DesktopWidgetRegistry });

    for (const body of untyped) {
        vm.runInContext(body.replace(/^ {4}/gm, ""), context);
    }

    return { context, instances, configUpdates, instanceUpdates };
}

test("setLayer validates arguments and errors early", () => {
    const { context } = createIpcContext([{ id: "w1", widgetType: "desktopClock", enabled: true, config: {} }]);

    assert.equal(context.setLayer("", "overlay"), "ERROR: No instance ID specified");
    assert.equal(context.setLayer("nonexistent", "overlay"), "DESKTOP_WIDGET_NOT_FOUND: nonexistent");
    assert.equal(context.setLayer("w1", "top"), "ERROR: Invalid layer 'top'. Must be one of: background, bottom, overlay");
    assert.equal(context.setLayer("w1", "invalid"), "ERROR: Invalid layer 'invalid'. Must be one of: background, bottom, overlay");
});

test("setLayer updates layer and keeps showOnOverlay synchronized", () => {
    const { context, configUpdates } = createIpcContext([{ id: "w1", widgetType: "desktopClock", enabled: true, config: {} }]);

    assert.equal(context.setLayer("w1", "background"), "DESKTOP_WIDGET_LAYER_SET: w1 -> background");
    assert.deepEqual(JSON.parse(JSON.stringify(configUpdates[0])), ["w1", { layer: "background", showOnOverlay: false }]);

    assert.equal(context.setLayer("w1", "overlay"), "DESKTOP_WIDGET_LAYER_SET: w1 -> overlay");
    assert.deepEqual(JSON.parse(JSON.stringify(configUpdates[1])), ["w1", { layer: "overlay", showOnOverlay: true }]);

    assert.equal(context.setLayer("w1", "bottom"), "DESKTOP_WIDGET_LAYER_SET: w1 -> bottom");
    assert.deepEqual(JSON.parse(JSON.stringify(configUpdates[2])), ["w1", { layer: "bottom", showOnOverlay: false }]);

    assert.equal(context.setLayer("w1", "wallpaper"), "DESKTOP_WIDGET_LAYER_SET: w1 -> background");
    assert.deepEqual(JSON.parse(JSON.stringify(configUpdates[3])), ["w1", { layer: "background", showOnOverlay: false }]);
});

test("toggleOverlay and setOverlay maintain backward compatibility with layer", () => {
    const { context, configUpdates } = createIpcContext([
        { id: "w1", widgetType: "desktopClock", enabled: true, config: { layer: "bottom" } },
        { id: "w2", widgetType: "desktopClock", enabled: true, config: { showOnOverlay: true } }
    ]);

    // toggleOverlay flips bottom -> overlay
    assert.equal(context.toggleOverlay("w1"), "DESKTOP_WIDGET_OVERLAY_ENABLED: w1");
    assert.deepEqual(JSON.parse(JSON.stringify(configUpdates[0])), ["w1", { layer: "overlay", showOnOverlay: true }]);

    // toggleOverlay flips overlay -> bottom
    assert.equal(context.toggleOverlay("w2"), "DESKTOP_WIDGET_OVERLAY_DISABLED: w2");
    assert.deepEqual(JSON.parse(JSON.stringify(configUpdates[1])), ["w2", { layer: "bottom", showOnOverlay: false }]);

    // setOverlay explicit true/false
    assert.equal(context.setOverlay("w1", "false"), "DESKTOP_WIDGET_OVERLAY_DISABLED: w1");
    assert.deepEqual(JSON.parse(JSON.stringify(configUpdates[2])), ["w1", { layer: "bottom", showOnOverlay: false }]);
});

test("status includes layer and overlay state", () => {
    const { context } = createIpcContext([
        { id: "w1", widgetType: "desktopClock", enabled: true, config: { layer: "background" } }
    ]);

    const status = context.status("w1");
    assert.match(status, /layer: background/);
    assert.match(status, /overlay: false/);
});
