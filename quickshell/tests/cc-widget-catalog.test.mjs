import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const catalog = loadScript(new URL("../Modules/ControlCenter/utils/catalog.js", import.meta.url));

const widgets = [
    { id: "wifi", text: "Network", description: "Wi-Fi and ethernet", category: "connectivity" },
    { id: "bluetooth", text: "Bluetooth", description: "Wireless devices", category: "connectivity" },
    { id: "darkMode", text: "Dark mode", description: "Network of colors", category: "display" },
    { id: "plugin_x", text: "Clock", description: "" }
];
const ids = list => Array.from(list, widget => widget.id);

test("category and query narrow the list together, case-insensitively", () => {
    assert.deepEqual(ids(catalog.filterWidgets(widgets, "NETWORK", "connectivity")), ["wifi"]);
    assert.deepEqual(ids(catalog.filterWidgets(widgets, "network", "all")), ["wifi", "darkMode"]);
    assert.deepEqual(ids(catalog.filterWidgets(widgets, "  ", "display")), ["darkMode"]);
    assert.deepEqual(ids(catalog.filterWidgets(widgets, "", "")), ids(widgets));
    assert.deepEqual(ids(catalog.filterWidgets(widgets, "plugin_x")), ["plugin_x"]);
});

test("a widget without a category belongs to plugins", () => {
    assert.equal(catalog.categoryOf(widgets[3]), "plugins");
    assert.deepEqual(ids(catalog.filterWidgets(widgets, "", "plugins")), ["plugin_x"]);
});

test("categories without widgets are hidden", () => {
    const defs = [{ id: "connectivity" }, { id: "display" }, { id: "audio" }, { id: "plugins" }];
    assert.deepEqual(Array.from(catalog.shownCategories(defs, widgets), def => def.id), ["connectivity", "display", "plugins"]);
    assert.deepEqual(Array.from(catalog.shownCategories(defs, widgets.slice(0, 2)), def => def.id), ["connectivity"]);
});
