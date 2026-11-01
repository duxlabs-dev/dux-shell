import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const here = new URL("./", import.meta.url);
const source = path => readFileSync(new URL(path, here), "utf8");
const fixture = name => JSON.parse(readFileSync(new URL(`fixtures/windows/${name}.json`, here), "utf8"));
const Position = { Top: 0, Bottom: 1, Left: 2, Right: 3 };
const positions = ["Top", "Bottom", "Left", "Right"];

function lift(text, name, context) {
    const match = text.match(new RegExp(`^    function ${name}\\([^\\n]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
    assert.ok(match, `function ${name} not found`);
    vm.runInContext(match[0], context);
}

const compositorService = source("../Services/CompositorService.qml");
const aqueousService = source("../Services/AqueousService.qml");
const model = vm.createContext({});
vm.runInContext(source("../Common/WindowModel.js").replace(/^\.pragma.*$/m, ""), model);

test("mango monitor changes invalidate cached toplevels", () => {
    const context = vm.createContext({});
    lift(compositorService, "_toplevelListEquivalent", context);
    const window = { mangoWindowId: 1, appId: "app1", mangoMonitor: "DP-1", mangoTags: [1] };
    assert.equal(context._toplevelListEquivalent([window], [{ ...window }]), true);
    assert.equal(context._toplevelListEquivalent([window], [{ ...window, mangoMonitor: "HDMI-A-1" }]), false);
});

function niriState(scenario) {
    const s = fixture("niri")[scenario];
    const toplevels = s.toplevels.map(t => ({ ...t }));
    const window = id => s.windows.find(w => w.id === id);
    const sorted = s.sortedToplevels.map(st => ({ niriWindowId: st.niriWindowId, niriWorkspaceId: st.niriWorkspaceId, appId: window(st.niriWindowId).app_id, title: window(st.niriWindowId).title, sourceToplevel: st.toplevel === undefined ? undefined : toplevels[st.toplevel] }));
    return { ...s, toplevels, sorted, screens: fixture("niri").screens };
}

function filterCurrentDisplay(list, name) {
    return list.filter(t => !t.screens || t.screens.includes(name));
}

function facade(compositor, globals) {
    const context = vm.createContext({
        compositor,
        WindowModel: model,
        _edgePositions: { top: Position.Top, bottom: Position.Bottom, left: Position.Left, right: Position.Right },
        sortedToplevels: [],
        ToplevelManager: { activeToplevel: null, toplevels: { values: [] } },
        NiriService: {},
        Hyprland: {},
        MangoService: {},
        AqueousService: {},
        filterCurrentDisplay,
        ...globals
    });
    for (const name of ["_windowAlive", "_fallbackActiveWindow", "_retainedWindow", "activeWindowForScreen", "windowPid", "windowOnActiveWorkspace", "windowsHideBar", "windowsOverlapDock", "maximizedWindowOnScreen", "specialWorkspaceName"])
        lift(compositorService, name, context);
    return context;
}

function presentable(toplevel) {
    return !!toplevel && !!(toplevel.title || toplevel.appId);
}

function focusedAppNiri(state, screenName, includeLastFocused, activeToplevel, previous) {
    const context = facade("niri", {
        sortedToplevels: state.sorted,
        NiriService: { windows: state.windows, allWorkspaces: state.allWorkspaces, currentOutput: state.currentOutput, lastFocusedWindowId: state.lastFocusedWindowId },
        ToplevelManager: { activeToplevel, toplevels: { values: state.toplevels } }
    });
    const activeWindow = context.activeWindowForScreen(screenName, previous, includeLastFocused);
    const index = state.toplevels.indexOf(activeWindow);
    return { activeWindow: activeWindow === null ? null : index >= 0 ? index : "foreign", onActiveWorkspace: presentable(activeWindow) && context.windowOnActiveWorkspace(screenName ?? "", activeWindow, includeLastFocused), pid: context.windowPid(activeWindow) };
}

function barHideNiri(state, screenName, position) {
    const context = facade("niri", { NiriService: { windows: state.windows, allWorkspaces: state.allWorkspaces } });
    const screen = state.screens[screenName];
    return context.windowsHideBar(screenName, Position[position], 48 + 4, screen?.width ?? 0, screen?.height ?? 0);
}

function dockOverlapNiri(state, screenName, position) {
    const context = facade("niri", { NiriService: { windows: state.windows, allWorkspaces: state.allWorkspaces } });
    const screen = state.screens[screenName];
    return context.windowsOverlapDock(screenName, Position[position], 60, screen?.width ?? 0, screen?.height ?? 0);
}

function hyprlandState() {
    const s = fixture("hyprland");
    const waylands = {};
    const wayland = id => id === null ? null : (waylands[id] ??= { id, appId: id, title: id });
    return { focusedWorkspace: s.focusedWorkspace, toplevels: s.toplevels.map(t => ({ ...t, wayland: wayland(t.wayland) })), wayland: id => wayland(id) };
}

function focusedAppHyprland(state, activeWindow, focusedWorkspace) {
    const context = facade("hyprland", { Hyprland: { toplevels: { values: state.toplevels }, focusedWorkspace } });
    return { onActiveWorkspace: presentable(activeWindow) && context.windowOnActiveWorkspace("DP-1", activeWindow, false), pid: context.windowPid(activeWindow) };
}

function specialWorkspaceName(state, waylandToplevel) {
    return facade("hyprland", { Hyprland: { toplevels: { values: state.toplevels } } }).specialWorkspaceName(waylandToplevel);
}

function mangoPid(windows, sortedWindow) {
    const activeWindow = { appId: "app", title: "t" };
    const context = facade("mango", { sortedToplevels: sortedWindow ? [{ ...sortedWindow, sourceToplevel: activeWindow }] : [], MangoService: { windows } });
    return context.windowPid(activeWindow);
}

function mangoOverlap(s, screenName, position) {
    return facade("mango", { MangoService: { windows: s.windows, outputs: s.outputs } }).windowsOverlapDock(screenName, Position[position], 60, 1920, 1080);
}

function mangoMaximized(s, screenName) {
    return facade("mango", { MangoService: { windows: s.windows, outputs: s.outputs } }).maximizedWindowOnScreen(screenName);
}

function aqueousActiveWindow(focusedWindow, screenName) {
    const activeWindow = facade("aqueous", { AqueousService: { available: true, focusedWindow } }).activeWindowForScreen(screenName, null, false);
    return activeWindow === null ? null : activeWindow.id;
}

function aqueousOverlap(s, screenName, position) {
    const context = vm.createContext({ outputs: s.outputs, windows: s.windows, SettingsData: { Position } });
    lift(aqueousService, "overlapsDock", context);
    return context.overlapsDock(screenName, Position[position], 60, 1920, 1080);
}

test("niri active window: focused window on the bar's screen wins, foreign active toplevels keep an alive previous window", () => {
    const s = niriState("twoScreens");
    assert.deepEqual(focusedAppNiri(s, "DP-1", false, null, null), { activeWindow: 0, onActiveWorkspace: true, pid: 100 });
    assert.deepEqual(focusedAppNiri(s, "HDMI-A-1", false, null, null), { activeWindow: null, onActiveWorkspace: false, pid: 0 });
    assert.deepEqual(focusedAppNiri(s, null, false, null, null), { activeWindow: null, onActiveWorkspace: false, pid: 0 });
    assert.deepEqual(focusedAppNiri(s, "HDMI-A-1", false, s.toplevels[1], null), { activeWindow: 1, onActiveWorkspace: true, pid: 102 });
    assert.deepEqual(focusedAppNiri(s, "DP-1", false, s.toplevels[2], null), { activeWindow: null, onActiveWorkspace: false, pid: 0 });
    assert.deepEqual(focusedAppNiri(s, "DP-1", false, s.toplevels[2], s.toplevels[0]), { activeWindow: 0, onActiveWorkspace: true, pid: 100 });
    assert.deepEqual(focusedAppNiri(s, "HDMI-A-1", false, null, s.toplevels[1]), { activeWindow: 1, onActiveWorkspace: true, pid: 102 });
    assert.deepEqual(focusedAppNiri(s, "HDMI-A-1", false, null, { appId: "dead", title: "dead" }), { activeWindow: null, onActiveWorkspace: false, pid: 0 });
    assert.deepEqual(focusedAppNiri(s, "DP-3", false, s.toplevels[3], null), { activeWindow: 3, onActiveWorkspace: true, pid: 0 });
});

test("niri last-focused fallback applies only while the popout is open, ghosts on empty workspaces are dropped", () => {
    const unfocused = niriState("unfocused");
    assert.deepEqual(focusedAppNiri(unfocused, "DP-1", false, null, null), { activeWindow: null, onActiveWorkspace: false, pid: 0 });
    assert.deepEqual(focusedAppNiri(unfocused, "DP-1", true, null, null), { activeWindow: 1, onActiveWorkspace: true, pid: 0 });
    const sorted = niriState("unfocusedSorted");
    assert.deepEqual(focusedAppNiri(sorted, "DP-1", true, null, null), { activeWindow: 2, onActiveWorkspace: true, pid: 101 });
    assert.deepEqual(focusedAppNiri(sorted, "HDMI-A-1", true, null, null), { activeWindow: null, onActiveWorkspace: false, pid: 0 });
    const empty = niriState("emptyWorkspace");
    assert.deepEqual(focusedAppNiri(empty, "DP-1", true, null, null), { activeWindow: null, onActiveWorkspace: false, pid: 0 });
    assert.deepEqual(focusedAppNiri(empty, "DP-1", false, null, empty.toplevels[0]), { activeWindow: null, onActiveWorkspace: false, pid: 0 });
    const noActive = niriState("noActiveWorkspace");
    assert.deepEqual(focusedAppNiri(noActive, "DP-3", false, null, null), { activeWindow: 0, onActiveWorkspace: true, pid: 104 });
});

test("niri edges: the bar hides for any tiled window, the dock only when geometry crosses its edge", () => {
    const two = niriState("twoScreens");
    assert.deepEqual(positions.map(p => barHideNiri(two, "DP-1", p)), [true, true, true, true]);
    assert.deepEqual(positions.map(p => dockOverlapNiri(two, "DP-1", p)), [true, true, true, true]);
    assert.deepEqual(positions.map(p => barHideNiri(two, "HDMI-A-1", p)), [true, true, true, true]);
    assert.deepEqual(positions.map(p => dockOverlapNiri(two, "HDMI-A-1", p)), [false, false, false, false]);
    assert.deepEqual(positions.map(p => barHideNiri(two, "DP-3", p)), [false, false, false, false]);
    const floating = niriState("floatingAtEdge");
    assert.deepEqual(positions.map(p => barHideNiri(floating, "DP-1", p)), [false, true, false, false]);
    assert.deepEqual(positions.map(p => dockOverlapNiri(floating, "DP-1", p)), [false, true, false, false]);
    const tiledNoGeometry = niriState("tiledNoGeometry");
    assert.deepEqual([barHideNiri(tiledNoGeometry, "DP-1", "Top"), dockOverlapNiri(tiledNoGeometry, "DP-1", "Top")], [true, true]);
    const floatingNoGeometry = niriState("floatingNoGeometry");
    assert.deepEqual([barHideNiri(floatingNoGeometry, "DP-1", "Top"), dockOverlapNiri(floatingNoGeometry, "DP-1", "Top")], [false, false]);
    assert.equal(barHideNiri(niriState("emptyWorkspace"), "DP-1", "Top"), false);
});

test("hyprland: workspace membership against the focused workspace, pid from the ipc object, special workspace names", () => {
    const hypr = hyprlandState();
    assert.deepEqual(focusedAppHyprland(hypr, hypr.wayland("w1"), hypr.focusedWorkspace), { onActiveWorkspace: true, pid: 501 });
    assert.deepEqual(focusedAppHyprland(hypr, hypr.wayland("w3"), hypr.focusedWorkspace), { onActiveWorkspace: false, pid: 503 });
    assert.deepEqual(focusedAppHyprland(hypr, hypr.wayland("w4"), hypr.focusedWorkspace), { onActiveWorkspace: false, pid: 0 });
    assert.deepEqual(focusedAppHyprland(hypr, hypr.wayland("w5"), hypr.focusedWorkspace), { onActiveWorkspace: false, pid: 0 });
    assert.deepEqual(focusedAppHyprland(hypr, hypr.wayland("w1"), null), { onActiveWorkspace: false, pid: 501 });
    assert.deepEqual(["w1", "w2", "w4", "w5"].map(id => specialWorkspaceName(hypr, hypr.wayland(id))), ["", "scratch", "notes", ""]);
    assert.equal(specialWorkspaceName(hypr, null), "");
});

test("hyprland main: named workspaces all report id -1, so active-workspace membership compares addresses", () => {
    const music = { id: -1, address: "music", name: "music" };
    const chat = { id: -1, address: "chat", name: "chat" };
    const win = { id: "w", appId: "w", title: "w" };
    const state = { toplevels: [{ wayland: win, workspace: music, lastIpcObject: { pid: 7 } }] };
    assert.deepEqual([chat, music].map(focused => focusedAppHyprland(state, win, focused).onActiveWorkspace), [false, true]);
});

test("mango: compositor visibility covers global windows and overview without counting hidden clients", () => {
    const windows = [
        { id: 1, monitor: "DP-1", tags: [2], is_visible: true },
        { id: 2, monitor: "DP-1", tags: [1], is_visible: false },
        { id: 3, monitor: "DP-2", tags: [1], is_visible: true },
        { id: 4, monitor: "DP-1", tags: [1], is_visible: true, is_minimized: true },
        { id: 5, monitor: "DP-1", tags: [1] }
    ];
    const visible = activeTags => Array.from(model.mangoVisibleWindows(windows, { activeTags }, "DP-1"), win => win.id);
    assert.deepEqual(visible([1]), [1, 5]);
    assert.deepEqual(visible([0]), [1]);
});

test("mango: pid by window id, overlap and maximized only count visible windows on the output's active tags", () => {
    const m = fixture("mango");
    assert.equal(mangoPid(m.twoOutputs.windows, { mangoWindowId: 1 }), 201);
    assert.equal(mangoPid(m.twoOutputs.windows, { mangoWindowId: 99 }), 0);
    assert.equal(mangoPid(m.twoOutputs.windows, null), 0);
    assert.deepEqual(positions.map(p => mangoOverlap(m.twoOutputs, "DP-1", p)), [true, false, true, true]);
    assert.deepEqual(positions.map(p => mangoOverlap(m.twoOutputs, "DP-2", p)), [false, false, false, false]);
    assert.equal(mangoOverlap(m.twoOutputs, "DP-9", "Top"), false);
    assert.equal(mangoMaximized(m.twoOutputs, "DP-1"), false);
    assert.equal(mangoMaximized(m.twoOutputs, "DP-2"), true);
    assert.equal(mangoMaximized(m.maximizedActive, "DP-1"), true);
    assert.deepEqual(positions.map(p => mangoOverlap(m.maximizedActive, "DP-1", p)), [true, true, true, true]);
});

test("aqueous: focused window must sit on the bar's screen, overlap ignores hidden and minimized windows", () => {
    const a = fixture("aqueous");
    assert.equal(aqueousActiveWindow(a.focusedWindow, "DP-1"), "a1");
    assert.equal(aqueousActiveWindow(a.focusedWindow, "HDMI-A-1"), null);
    assert.equal(aqueousActiveWindow(a.focusedWindow, null), "a1");
    assert.equal(aqueousActiveWindow(a.focusedWindow, ""), null);
    assert.equal(aqueousActiveWindow(null, "DP-1"), null);
    assert.deepEqual(positions.map(p => aqueousOverlap(a, "DP-1", p)), [false, true, false, false]);
    assert.deepEqual(positions.map(p => aqueousOverlap(a, "HDMI-A-1", p)), [true, false, true, false]);
    assert.equal(aqueousOverlap(a, "DP-9", "Top"), false);
});
