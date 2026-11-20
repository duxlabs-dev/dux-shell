import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));

const plain = (value) => JSON.parse(JSON.stringify(value));
const migrate = (settings) => plain(store.migrateToVersion(Object.assign({ configVersion: 46 }, settings), 47));
const bar = (position, widgets, extra = {}) => Object.assign({ id: "default", position, leftWidgets: [], centerWidgets: [], rightWidgets: widgets }, extra);

test("a saved theme color becomes low and charging, level and a missing key stay", () => {
    const result = migrate({ barConfigs: [bar(0, [], { batteryColorMode: "theme" }), bar(0, [], { batteryColorMode: "level" }), bar(0, [])] });
    assert.equal(result.barConfigs[0].batteryColorMode, "lowcharging");
    assert.equal(result.barConfigs[1].batteryColorMode, "level");
    assert.equal("batteryColorMode" in result.barConfigs[2], false);
    assert.equal(result.configVersion, 47);
});

test("old styles fold into solid and circle and keep the meter orientation of the bar", () => {
    const styles = ["solid", "outline", "ring", "duo", "icon", "circle", "future"].map(batteryStyle => ({ id: "battery", batteryStyle }));
    const horizontal = migrate({ barConfigs: [bar(1, styles)] }).barConfigs[0].rightWidgets;
    assert.deepEqual(horizontal.map(w => w.batteryStyle), ["solid", "solid", "circle", "circle", "icon", "circle", "future"]);
    assert.deepEqual(horizontal.map(w => w.batteryDirection), ["horizontal", "horizontal", "horizontal", "horizontal", undefined, undefined, undefined]);
    for (const position of [2, 3]) {
        const vertical = migrate({ barConfigs: [bar(position, styles)] }).barConfigs[0].rightWidgets;
        assert.deepEqual(vertical.map(w => w.batteryDirection).slice(0, 4), ["vertical", "vertical", "vertical", "vertical"]);
    }
});

test("an explicit direction is kept and other widgets are not touched", () => {
    const widgets = [{ id: "battery", batteryStyle: "ring", batteryDirection: "vertical" }, { id: "clock", batteryStyle: "ring" }, "battery"];
    const result = migrate({ barConfigs: [bar(1, widgets)] }).barConfigs[0].rightWidgets;
    assert.deepEqual(result[0], { id: "battery", batteryStyle: "circle", batteryDirection: "vertical" });
    assert.deepEqual(result[1], { id: "clock", batteryStyle: "ring" });
    assert.equal(result[2], "battery");
});

test("dock widgets follow the dock position", () => {
    const dock = (position) => ({ position, widgets: [{ id: "x1", widgetId: "battery", batteryStyle: "outline" }, { id: "x2", widgetId: "clock", batteryStyle: "outline" }] });
    const result = migrate({ dockConfigs: [dock(1), dock(2)] }).dockConfigs;
    assert.equal(result[0].widgets[0].batteryStyle, "solid");
    assert.equal(result[0].widgets[0].batteryDirection, "horizontal");
    assert.equal(result[1].widgets[0].batteryDirection, "vertical");
    assert.deepEqual(result[0].widgets[1], { id: "x2", widgetId: "clock", batteryStyle: "outline" });
});

test("running twice changes nothing and partial or foreign shapes do not throw", () => {
    const once = migrate({ barConfigs: [bar(2, [{ id: "battery", batteryStyle: "duo" }], { batteryColorMode: "theme" })] });
    assert.deepEqual(plain(store.migrateToVersion(Object.assign({}, once, { configVersion: 46 }), 47)), once);
    for (const settings of [{}, { barConfigs: {} }, { barConfigs: [null, 3, { rightWidgets: "x" }, { rightWidgets: [null, 1] }] }, { dockConfigs: [null, { widgets: 5 }] }])
        assert.doesNotThrow(() => migrate(settings));
});
