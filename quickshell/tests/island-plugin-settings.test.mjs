import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

function functions(source, indent, context) {
    const pattern = new RegExp(`^${indent}function (\\w+)\\(([^)]*)\\)(?:: \\w+)? \\{([\\s\\S]*?)^${indent}\\}`, "gm");
    for (const [, name, parameters, body] of source.matchAll(pattern)) {
        const args = parameters.replace(/:\s*\w+/g, "");
        vm.runInContext(`function ${name}(${args}) {${body}}`, context);
    }
    return context;
}

const source = readFileSync(new URL("../Common/SettingsData.qml", import.meta.url), "utf8");
const plain = value => JSON.parse(JSON.stringify(value));

function settings() {
    const context = vm.createContext({ islandPluginsBlocked: [], islandSystemFaces: {}, saves: 0 });
    functions(source, "    ", context);
    context.saveSettings = () => context.saves++;
    return context;
}

test("a plugin is allowed in the island until the user turns it off", () => {
    const s = settings();
    assert.equal(s.islandPluginsBlocked.includes("smartTimer"), false);
    s.setIslandPluginAllowed("smartTimer", false);
    s.setIslandPluginAllowed("smartTimer", false);
    assert.deepEqual(plain(s.islandPluginsBlocked), ["smartTimer"], "turning off twice keeps one entry");
    assert.equal(s.islandPluginsBlocked.includes("smartTimer"), true);
    assert.equal(s.islandPluginsBlocked.includes("orbit"), false);
    s.setIslandPluginAllowed("smartTimer", true);
    assert.deepEqual(plain(s.islandPluginsBlocked), []);
    assert.equal(s.saves, 3);
});

test("each system activity keeps its own face provider", () => {
    const s = settings();
    assert.equal(s.islandSystemFaces.volume ?? "", "");
    s.setIslandSystemFace("volume", "orbit");
    s.setIslandSystemFace("mic", "orbit");
    s.setIslandSystemFace("mic", "");
    assert.deepEqual(plain(s.islandSystemFaces), { "volume": "orbit" }, "an empty provider goes back to the shell's face");
    assert.equal(s.islandSystemFaces.volume ?? "", "orbit");
});
