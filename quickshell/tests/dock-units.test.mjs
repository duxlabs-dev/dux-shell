import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const config = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/settings/DockConfig.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), config);
const plain = value => JSON.parse(JSON.stringify(value));

const widgets = [{ id: "clock", widgetId: "clock" }, { id: "apps", widgetId: "appsDock" }, { id: "hidden", widgetId: "cpuUsage", enabled: false }, { id: "launcher", widgetId: "dockLauncher" }, { id: "trash", widgetId: "dockTrash" }];
const apps = [
    { uniqueKey: "launcher_button", type: "launcher", appId: "__LAUNCHER__", isPinned: true },
    { uniqueKey: "pinned_a", type: "pinned", appId: "a", isPinned: true },
    { uniqueKey: "pinned_b", type: "window", appId: "b", isPinned: true },
    { uniqueKey: "separator_ungrouped", type: "separator" },
    { uniqueKey: "niri:4", type: "window", appId: "c" },
    { uniqueKey: "niri:9", type: "window", appId: "d", isInOverflow: true },
    { uniqueKey: "trash_button", type: "trash" }
];
const ids = items => plain(items.map(item => item.id));

test("without a saved order widgets keep their list order and pins sit before the running windows", () => {
    const items = config.surfaceItems(widgets, apps, []);
    assert.deepEqual(ids(items), ["clock", "apps:pinned_a", "apps:pinned_b", "apps:separator_ungrouped", "apps:niri:4", "launcher:launcher_button", "trash:trash_button"]);
    assert.deepEqual(plain(config.units(items)), ["clock", "pin:a", "pin:b", "apps", "launcher", "trash"]);
    assert.deepEqual(plain(items.map(item => item.appIndex ?? null)), [null, 1, 2, 3, 4, 0, 6]);
});

test("a saved order interleaves widgets with pins and keeps the running windows together", () => {
    const order = ["launcher", "pin:a", "clock", "trash", "pin:b", "apps"];
    const items = config.surfaceItems(widgets, apps, order);
    assert.deepEqual(plain(config.units(items)), ["launcher", "pin:a", "clock", "trash", "pin:b", "apps"]);
    assert.deepEqual(ids(items).slice(-2), ["apps:separator_ungrouped", "apps:niri:4"]);
});

test("the separator only follows a pinned app", () => {
    const items = config.surfaceItems(widgets, apps, ["launcher", "pin:a", "pin:b", "clock", "apps", "trash"]);
    assert.equal(items.some(item => item.appData?.type === "separator"), false);
});

test("hidden launcher, trash and apps leave no unit behind", () => {
    const items = config.surfaceItems(widgets, apps.filter(app => app.type !== "launcher"), []);
    assert.deepEqual(plain(config.units(items)), ["clock", "pin:a", "pin:b", "apps", "trash"]);
    const disabled = widgets.map(widget => widget.widgetId === "appsDock" ? { ...widget, enabled: false } : widget);
    assert.deepEqual(plain(config.units(config.surfaceItems(disabled, apps, []))), ["clock", "launcher", "trash"]);
});

test("unit list keeps pin slots in pin order, drops stale ids and appends new pins after the last pin", () => {
    const pins = ["pin:a", "pin:b", "pin:c"];
    assert.deepEqual(plain(config.unitList(widgets, pins, ["pin:b", "clock", "pin:a", "gone", "pin:z"])), ["pin:a", "clock", "pin:b", "pin:c", "apps", "hidden", "launcher", "trash"]);
    assert.deepEqual(plain(config.unitList(widgets, pins, ["trash", "apps", "launcher", "clock", "hidden"])), ["trash", "pin:a", "pin:b", "pin:c", "apps", "launcher", "clock", "hidden"]);
    assert.deepEqual(plain(config.unitList(widgets, [], ["trash"])), ["trash", "clock", "apps", "hidden", "launcher"]);
});

test("a new widget lands at the end of the order", () => {
    const added = widgets.concat([{ id: "weather", widgetId: "weather" }]);
    assert.deepEqual(plain(config.unitList(added, ["pin:a"], ["trash", "apps", "launcher", "clock", "hidden"])), ["trash", "pin:a", "apps", "launcher", "clock", "hidden", "weather"]);
});

test("unit preview carries every item of the dragged unit", () => {
    const items = config.surfaceItems(widgets, apps, []);
    assert.deepEqual(plain(config.unitOrder(items, "apps", "clock")), [3, 4, 0, 1, 2, 5, 6]);
    assert.deepEqual(plain(config.unitOrder(items, "pin:b", "launcher")), [0, 1, 3, 4, 5, 2, 6]);
});

test("reordering pin units rewrites the raw pin list and leaves it alone otherwise", () => {
    const pins = ["A-raw", "B-raw"];
    assert.deepEqual(plain(config.reorderPins(pins, apps, ["launcher", "pin:b", "clock", "pin:a", "apps"])), ["B-raw", "A-raw"]);
    assert.equal(config.reorderPins(pins, apps, ["clock", "pin:a", "launcher", "pin:b", "apps"]), null);
    assert.equal(config.reorderPins(["A-raw"], apps, ["pin:b", "pin:a"]), null);
});

test("normalize gives every dock exactly one launcher and trash slot around the apps and a clean order", () => {
    const [bare] = plain(config.normalize([{ id: "d", widgets: [{ id: "c", widgetId: "clock" }, { id: "d_apps", widgetId: "appsDock" }], order: ["c", 3, "c", null] }]));
    assert.deepEqual(bare.widgets.map(widget => widget.widgetId), ["clock", "dockLauncher", "appsDock", "dockTrash"]);
    assert.deepEqual(bare.order, ["c"]);
    const [moved] = plain(config.normalize([{ id: "d", widgets: [{ id: "t", widgetId: "dockTrash" }, { id: "a", widgetId: "appsDock" }, { id: "l", widgetId: "dockLauncher" }, { id: "l2", widgetId: "dockLauncher" }] }]));
    assert.deepEqual(moved.widgets.map(widget => widget.id), ["t", "a", "l"]);
    assert.deepEqual(moved.order, []);
});

test("drop target follows the leading edge so a wide unit can pass a narrow one at the end", () => {
    const spans = [{ id: "launcher", start: 0, end: 42 }, { id: "apps", start: 50, end: 500 }, { id: "trash", start: 508, end: 550 }];
    assert.equal(config.unitTarget(spans, "apps", -20), "apps");
    assert.equal(config.unitTarget(spans, "apps", -30), "launcher");
    assert.equal(config.unitTarget(spans, "apps", 30), "trash");
    assert.equal(config.unitTarget(spans, "launcher", 240), "apps");
    assert.equal(config.unitTarget(spans, "launcher", 490), "trash");
});

test("a dock shown only in the overview resolves onto an edge no enabled dock holds", () => {
    const screen = { name: "eDP-1" };
    const overviewOnly = { ...config.create("dock", "Dock"), openOnOverview: true };
    assert.equal(config.resolveEdge([overviewOnly], screen, [screen], "bottom"), overviewOnly);
    assert.equal(config.resolveEdge([config.create("dock", "Dock")], screen, [screen], "bottom"), null);
    const enabled = { ...config.create("second", "Second"), enabled: true };
    assert.equal(config.resolveEdge([overviewOnly, enabled], screen, [screen], "bottom"), enabled);
});

test("settings reorder follows the saved dock order and pins travel with the widget after them", () => {
    const list = [{ id: "launcher", widgetId: "dockLauncher" }, { id: "apps", widgetId: "appsDock" }, { id: "trash", widgetId: "dockTrash" }, { id: "spacer", widgetId: "spacer" }, { id: "desk", widgetId: "showDesktop" }];
    const saved = ["launcher", "pin:a", "pin:b", "apps", "trash", "desk", "spacer"];
    assert.deepEqual(plain(config.widgetOrder(list, saved)), ["launcher", "apps", "trash", "desk", "spacer"]);
    assert.deepEqual(plain(config.widgetOrder(list, [])), ["launcher", "apps", "trash", "spacer", "desk"]);
    const cases = [
        { order: saved, ids: ["launcher", "trash", "desk", "spacer", "apps"], expected: ["launcher", "trash", "desk", "spacer", "pin:a", "pin:b", "apps"] },
        { order: ["pin:a", "launcher", "apps", "pin:b"], ids: ["apps", "launcher", "trash", "spacer", "desk"], expected: ["apps", "pin:a", "launcher", "pin:b", "trash", "spacer", "desk"] },
        { order: [], ids: ["desk", "launcher", "apps", "trash", "spacer"], expected: ["desk", "launcher", "apps", "trash", "spacer"] },
        { order: saved, ids: ["trash", "launcher"], expected: ["trash", "launcher", "pin:a", "pin:b", "apps", "spacer", "desk"] }
    ];
    for (const { order, ids: next, expected } of cases) {
        const result = plain(config.reorderWidgets(list, order, next));
        assert.deepEqual(result.order, expected);
        assert.deepEqual(result.widgets.map(widget => widget.id), expected.filter(id => !id.startsWith("pin:")));
        assert.deepEqual(plain(config.widgetOrder(result.widgets, result.order)), result.widgets.map(widget => widget.id));
    }
});
