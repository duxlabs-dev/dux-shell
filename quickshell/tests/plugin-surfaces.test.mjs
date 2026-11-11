import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../Services/PluginService.qml", import.meta.url), "utf8");
const context = vm.createContext({ pluginSurfaceKeys: ["widget", "desktop", "daemon", "launcher"], log: { warn() {} } });
for (const name of ["_pluginFilePath", "_resolveComponentPaths"])
    vm.runInContext(source.match(new RegExp(`^    function ${name}\\([^\\n]*\\{\\n[\\s\\S]*?^    \\}`, "m"))[0], context);

test("a widget surface that reuses the desktop card is not offered to bars and docks", () => {
    const cases = [
        { components: { widget: "./Card.qml", desktop: "./Card.qml" }, surfaces: ["desktop"] },
        { components: { widget: "Card.qml", desktop: "./Card.qml" }, surfaces: ["desktop"] },
        { components: { widget: "./Pill.qml", desktop: "./Card.qml" }, surfaces: ["widget", "desktop"] },
        { components: { widget: "./Pill.qml" }, surfaces: ["widget"] }
    ];
    for (const { components, surfaces } of cases)
        assert.deepEqual(Object.keys(context._resolveComponentPaths({ components }, "/p")), surfaces);
});
