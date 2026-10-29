import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../DMSShellIPC.qml", import.meta.url), "utf8");
const barBlock = source.slice(source.indexOf("    function getBarConfig("), source.indexOf('        target: "bar"'));
const functions = [...barBlock.matchAll(/^ {4,8}function (\w+)\(([^)]*)\)(?:: \w+)? \{\n[\s\S]*?^\s{4,8}\}$/gm)];
const untyped = functions.map(match => match[0].replace(/\((.*?)\)(?:: \w+)? \{/, (_, params) => "(" + params.replace(/: \w+/g, "") + ") {"));

function shell(barConfigs, toggleResults = [], barItems = {}) {
    const updates = [];
    const reveals = [];
    const SettingsData = {
        barConfigs,
        Position: { Top: 0, Bottom: 1, Left: 2, Right: 3 },
        isIslandBarConfig: bar => bar.island === true,
        updateBarConfig: (id, patch) => updates.push([id, patch]),
        setBarIpcReveal: (id, on) => reveals.push(["set", id, on]),
        toggleBarIpcReveal: id => {
            reveals.push(["toggle", id]);
            return toggleResults.shift();
        }
    };
    const BarWidgetService = { dankBarItems: barItems };
    const context = vm.createContext({ SettingsData, BarWidgetService });
    for (const body of untyped)
        vm.runInContext(body.replace(/^ {4}/gm, ""), context);
    return { context, updates, reveals };
}

const bars = [{ id: "main", name: "Main", visible: true, autoHide: false, position: 0 }, { id: "isle", name: "Isle", island: true, visible: true, autoHide: true, position: 1 }, { id: "hidden", name: "Hidden", visible: false, autoHide: true, position: 2 }];

test("selector errors come back before any update", () => {
    const { context, updates } = shell(bars);
    assert.equal(context.reveal("bogus", "main"), "BAR_INVALID_SELECTOR");
    assert.equal(context.hide("id", "nope"), "BAR_NOT_FOUND");
    assert.equal(context.status("index", "7"), "BAR_NOT_FOUND");
    assert.deepEqual(updates, []);
});

test("island bars refuse mutations but answer queries", () => {
    const { context, updates } = shell(bars);
    for (const fn of ["reveal", "hide", "toggle", "autoHide", "manualHide", "toggleAutoHide", "toggleReveal"])
        assert.equal(context[fn]("id", "isle"), "BAR_IS_ISLAND", fn);
    assert.equal(context.status("id", "isle"), "visible");
    assert.equal(context.getPosition("id", "isle"), "bottom");
    assert.equal(context.setPosition("id", "isle", "left"), "BAR_POSITION_SET_SUCCESS");
    assert.deepEqual(JSON.parse(JSON.stringify(updates)), [["isle", { position: 2 }]]);
});

test("visibility and auto hide handlers write the expected patches", () => {
    const { context, updates } = shell(bars);
    assert.equal(context.reveal("name", "Main"), "BAR_SHOW_SUCCESS");
    assert.equal(context.hide("index", "0"), "BAR_HIDE_SUCCESS");
    assert.equal(context.toggle("id", "main"), "BAR_HIDE_SUCCESS");
    assert.equal(context.toggle("id", "hidden"), "BAR_SHOW_SUCCESS");
    assert.equal(context.autoHide("id", "main"), "BAR_AUTO_HIDE_SUCCESS");
    assert.equal(context.manualHide("id", "hidden"), "BAR_MANUAL_HIDE_SUCCESS");
    assert.equal(context.toggleAutoHide("id", "main"), "BAR_AUTO_HIDE_SUCCESS");
    assert.equal(context.toggleAutoHide("id", "hidden"), "BAR_MANUAL_HIDE_SUCCESS");
    assert.equal(context.status("id", "hidden"), "hidden");
    assert.equal(context.getPosition("id", "hidden"), "left");
    assert.equal(context.setPosition("id", "main", "Nowhere"), "BAR_INVALID_POSITION");
    assert.deepEqual(JSON.parse(JSON.stringify(updates)), [["main", { visible: true }], ["main", { visible: false }], ["main", { visible: false }], ["hidden", { visible: true }], ["main", { autoHide: true }], ["hidden", { autoHide: false }], ["main", { autoHide: true }], ["hidden", { autoHide: false }]]);
});

test("toggleReveal only works on auto hide bars and unhides first", () => {
    const { context, updates, reveals } = shell(bars, [true, false]);
    assert.equal(context.toggleReveal("id", "main"), "BAR_AUTO_HIDE_DISABLED");
    assert.equal(context.toggleReveal("id", "hidden"), "BAR_REVEAL_SUCCESS");
    assert.deepEqual(JSON.parse(JSON.stringify(updates)), [["hidden", { visible: true }]]);
    assert.deepEqual(reveals, [["set", "hidden", true]]);
    bars[2].visible = true;
    assert.equal(context.toggleReveal("id", "hidden"), "BAR_REVEAL_SUCCESS");
    assert.equal(context.toggleReveal("id", "hidden"), "BAR_TUCK_SUCCESS");
    assert.deepEqual(reveals.slice(1), [["toggle", "hidden"], ["toggle", "hidden"]]);
    bars[2].visible = false;

    const fullscreen = shell(bars, [true], { main: { fullscreenAutoHide: true } });
    assert.equal(fullscreen.context.toggleReveal("id", "main"), "BAR_REVEAL_SUCCESS");
    assert.deepEqual(fullscreen.reveals, [["toggle", "main"]]);
});

const ipcBarBody = source.slice(source.indexOf("    function getPreferredBar("), source.indexOf("    readonly property var defaultAppMimeTypes"));
const serviceSource = readFileSync(new URL("../Services/BarWidgetService.qml", import.meta.url), "utf8");
const serviceFunctions = ["registrationActive", "registrationShown", "registrationLive", "resolveWidget", "resolveIpcWidget"].map(name => serviceSource.match(new RegExp(`^ {4}function ${name}\\([\\s\\S]*?^ {4}\\}$`, "m"))[0]);
const registrySource = readFileSync(new URL("../Common/InstanceRegistry.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, "");

// Both IPC paths, getPreferredBar for control center and updates, resolveIpcWidget for `widget`, over one registry.
function ipcBarChoice(bars, { focused = "", lastUsed = {}, screens = ["A", "B"] } = {}) {
    const registry = vm.createContext({});
    vm.runInContext(registrySource, registry);
    const widgetRegistry = {};
    const windows = bars.map(spec => {
        const instanceId = `bar:${spec.id}:right:cc`;
        const config = { id: spec.id, enabled: true, visible: !spec.hidden, position: spec.position ?? 0 };
        const entry = {
            key: registry.key(spec.screen, instanceId),
            widgetId: "controlCenterButton",
            screenName: spec.screen,
            instanceId,
            item: { effectiveVisible: true },
            context: { barId: spec.id, kind: "bar", section: "right", occurrenceOrder: 0, owner: { active: true, widgetEnabled: !spec.disabled }, surface: { screen: { name: spec.screen }, config, host: { barRevealed: false } } }
        };
        widgetRegistry[entry.key] = entry;
        return { id: spec.id, modelData: { name: spec.screen }, barConfig: config, isIsland: false, controlCenterButtonRef: entry.item };
    });
    const context = vm.createContext({
        Registry: registry,
        widgetRegistry,
        Quickshell: { screens: screens.map(name => ({ name })) },
        SettingsData: { barConfigs: windows.map(bar => bar.barConfig), dockConfigs: [], lastUsedBarByScreen: lastUsed, Position: { Top: 0, Bottom: 1, Left: 2, Right: 3 } },
        ShellLayout: { forScreen: name => ({ instances: windows.filter(bar => bar.modelData.name === name).map(bar => ({ barId: bar.id })) }) },
        root: { dankBarRepeater: { count: windows.length, itemAt: i => ({ item: { barVariants: { instances: [windows[i]] } } }) } },
        getFocusedScreenName: () => focused
    });
    for (const fn of serviceFunctions)
        vm.runInContext(fn.replace(/^ {4}/gm, ""), context);
    context.BarWidgetService = {
        getFocusedScreenName: () => focused,
        frameHostedBars: {},
        frameBarsForScreen: () => [],
        registrationForItem: item => Object.values(widgetRegistry).find(entry => entry.item === item) ?? null,
        registrationShown: context.registrationShown,
        registrationLive: context.registrationLive
    };
    vm.runInContext(ipcBarBody.replace(/^ {4}/gm, ""), context);
    return [context.getPreferredBar("controlCenterButtonRef")?.id ?? null, context.resolveIpcWidget("controlCenterButton")?.context.barId ?? null];
}

test("every IPC path picks the same bar, visible first", () => {
    const cases = [
        ["visible bar beats a hidden one on the same screen", [{ id: "main", screen: "A", hidden: true }, { id: "second", screen: "A" }], { focused: "A" }, "second"],
        ["last used bar wins among visible bars", [{ id: "main", screen: "A" }, { id: "second", screen: "A" }], { focused: "A", lastUsed: { A: "second" } }, "second"],
        ["a visible bar beats a hidden last used one", [{ id: "main", screen: "A", hidden: true }, { id: "second", screen: "A" }], { focused: "A", lastUsed: { A: "main" } }, "second"],
        ["a shown bar beats a disabled last used one", [{ id: "main", screen: "A", disabled: true }, { id: "second", screen: "A" }], { focused: "A", lastUsed: { A: "main" } }, "second"],
        ["a hidden bar still answers when it is the only one", [{ id: "main", screen: "A", hidden: true }], { focused: "A" }, "main"],
        ["focused screen beats visibility elsewhere", [{ id: "main", screen: "A" }, { id: "other", screen: "B", hidden: true }], { focused: "B" }, "other"],
        ["unknown focus falls back to screen order", [{ id: "main", screen: "A" }, { id: "other", screen: "B" }], { screens: ["B", "A"] }, "other"],
        ["horizontal bar beats vertical in a tie", [{ id: "side", screen: "A", position: 2 }, { id: "top", screen: "A" }], { focused: "A" }, "top"]
    ];
    for (const [name, bars, opts, expected] of cases)
        assert.deepEqual(ipcBarChoice(bars, opts), [expected, expected], name);
});
