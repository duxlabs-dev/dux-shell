import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../Common/SessionData.qml", import.meta.url), "utf8");

function session(recentColors) {
    const context = vm.createContext({ recentColors, saves: 0 });
    vm.runInContext("function saveSettings() { saves++; }", context);
    const methods = ["addRecentColor", "removeRecentColor"];
    const found = [];
    for (const match of source.matchAll(/^    function (\w+)\([^\n]*\)(?:: \w+)? \{\n[\s\S]*?^    \}/gm)) {
        if (!methods.includes(match[1]))
            continue;
        found.push(match[1]);
        vm.runInContext(match[0], context);
    }
    assert.deepEqual(found.sort(), [...methods].sort());
    return context;
}

test("removing a recent color drops only that color and saves", () => {
    const context = session(["#ff0000", "#00ff00", "#0000ff"]);
    context.removeRecentColor("#00ff00");
    assert.deepEqual(Array.from(context.recentColors), ["#ff0000", "#0000ff"]);
    assert.equal(context.saves, 1);
});

test("removing a color that is not in the list changes nothing", () => {
    const context = session(["#ff0000"]);
    context.removeRecentColor("#123456");
    assert.deepEqual(Array.from(context.recentColors), ["#ff0000"]);
    assert.equal(context.saves, 0);
});

test("a removed color can be picked again and comes back first", () => {
    const context = session(["#ff0000", "#00ff00"]);
    context.removeRecentColor("#ff0000");
    context.addRecentColor("#ff0000");
    assert.deepEqual(Array.from(context.recentColors), ["#ff0000", "#00ff00"]);
});
