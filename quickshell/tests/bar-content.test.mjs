import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const read = path => readFileSync(new URL("../" + path, import.meta.url), "utf8");
const model = vm.createContext({});
vm.runInContext(read("Modules/DBar/WidgetModel.js").replace(/^\.pragma.*$/m, ""), model);
const plain = value => JSON.parse(JSON.stringify(value));

function method(source, name) {
    const start = source.indexOf("    function " + name + "(");
    const end = source.indexOf("\n    }", start) + 6;
    return source.slice(start, end);
}

test("widget normalization preserves metadata, defaults and positional occurrences", () => {
    const entries = ["clock", { id: "clock", enabled: false, clockDateOrder: "dateFirst", extra: { value: 4 } },
        { widgetId: "plugin:variant", size: 0, enabled: null }, { id: "spacer", widgetId: "ignored", enabled: 0 }, "clock"];
    const original = structuredClone(entries);
    assert.deepEqual(plain(model.normalize(entries)), [
        { widgetId: "clock", id: "clock_0", enabled: true },
        { widgetId: "clock", id: "clock_1", enabled: false, clockDateOrder: "dateFirst", extra: { value: 4 } },
        { widgetId: "plugin:variant", id: "plugin:variant_2", size: 0, enabled: true },
        { widgetId: "spacer", id: "spacer_3", enabled: true },
        { widgetId: "clock", id: "clock_4", enabled: true }
    ]);
    assert.deepEqual(entries, original);
    assert.deepEqual(plain(model.normalize()), []);
    assert.deepEqual(plain(model.normalize([])), []);
    assert.deepEqual(plain(model.normalize([entries[4], entries[2]])).map(entry => entry.id), ["clock_0", "plugin:variant_1"]);
});

test("focus discovery keeps compositor names separate from first-screen fallback", () => {
    const source = read("Services/CompositorService.qml");
    const context = vm.createContext({
        isAqueous: false, isHyprland: false, isNiri: false, isSway: false, isScroll: false, isMiracle: false, isMango: false, isUmbriel: false,
        AqueousService: { available: true, focusedOutput: "second" }, Hyprland: { focusedMonitor: { name: "second" } },
        NiriService: { currentOutput: "second" }, I3: { workspaces: { values: [{ focused: true, monitor: { name: "second" } }] } },
        MangoService: { activeOutput: "second" }, Quickshell: { screens: [{ name: "first" }, { name: "second" }] }
    });
    vm.runInContext(method(source, "getFocusedScreenName") + method(source, "getFocusedScreen"), context);
    assert.equal(context.getFocusedScreenName(), "");
    assert.equal(context.getFocusedScreen().name, "first");
    for (const compositor of ["isAqueous", "isHyprland", "isNiri", "isSway", "isScroll", "isMiracle", "isMango"]) {
        context[compositor] = true;
        assert.equal(context.getFocusedScreenName(), "second", compositor);
        assert.equal(context.getFocusedScreen().name, "second", compositor);
        context[compositor] = false;
    }
    context.isNiri = true;
    context.NiriService.currentOutput = "unmapped";
    assert.equal(context.getFocusedScreenName(), "unmapped");
    assert.equal(context.getFocusedScreen().name, "first");
    context.isNiri = false;
    context.Quickshell.screens = [];
    assert.equal(context.getFocusedScreen(), null);
});

test("center placement preserves configured anchors, visible fallbacks and geometric extents", () => {
    const layout = vm.createContext({});
    vm.runInContext(read("Modules/DBar/CenterLayout.js").replace(/^\.pragma.*$/m, ""), layout);
    const cases = [
        [[], 600, 4, "index", [], 0],
        [[30, 80, 60], 600, 4, "geometric", [211, 245, 329], 178],
        [[30, 80, 60], 600, 4, "index", [226, 260, 344], 178],
        [[30, null, 60], 600, 4, "index", [268, null, 302], 94],
        [[30, 80, 60, 20], 600, 4, "index", [184, 218, 302, 366], 202],
        [[30, 80], 31, 0, "geometric", [-39.5, -9.5], 110]
    ];
    for (const [sizes, length, spacing, mode, positions, totalSize] of cases) {
        const original = [...sizes];
        assert.deepEqual(plain(layout.resolve(sizes, length, spacing, mode)), { positions, totalSize });
        assert.deepEqual(sizes, original);
    }
});

test("center placement yields to side sections without overlapping them", () => {
    const layout = vm.createContext({});
    vm.runInContext(read("Modules/DBar/CenterLayout.js").replace(/^\.pragma.*$/m, ""), layout);
    const cases = [
        [{ min: 250 }, [250, 284, 368]],
        [{ max: 300 }, [122, 156, 240]],
        [{ min: 100, max: 200 }, [61, 95, 179]]
    ];
    for (const [bounds, positions] of cases)
        assert.deepEqual(plain(layout.resolve([30, 80, 60], 600, 4, "geometric", bounds)), { positions, totalSize: 178 });
});
