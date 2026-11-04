import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const adv = loadScript(new URL("../Common/niri/sections/advanced.js", import.meta.url));
const { assemble } = loadScript(new URL("../Common/niri/assemble.js", import.meta.url));

const state = patch => Object.assign({}, adv.defaults, patch);
const kdl = patch => assemble([{ id: "advanced", toKdl: adv.toKdl }], state(patch));

test("defaults write nothing", () => {
    assert.equal(kdl({}), "");
});

test("mod key, power button and xwayland off", () => {
    assert.equal(kdl({ "advanced.modKey": "Alt", "advanced.powerKey": true, "advanced.xwayland": false }), [
        "input {",
        "    mod-key \"Alt\"",
        "    disable-power-key-handling",
        "}",
        "xwayland-satellite {",
        "    off",
        "}",
        ""
    ].join("\n"));
});

test("debug flags only count while debug options are on", () => {
    assert.equal(kdl({ "advanced.dbg.disable-direct-scanout": true }), "");
    assert.equal(kdl({ "advanced.debug": true }), "");
    assert.equal(kdl({ "advanced.debug": true, "advanced.dbg.disable-direct-scanout": true }), "debug {\n    disable-direct-scanout\n}\n");
});

test("every key is stored in the page, is risky and is searchable", () => {
    const keys = Object.keys(adv.defaults);
    assert.deepEqual(keys.filter(key => adv.stored[key] !== "page"), []);
    assert.deepEqual(Array.from(adv.risky), keys);
    for (const key of ["advanced.modKey", "advanced.powerKey", "advanced.xwayland", "advanced.debug"])
        assert.ok(adv.search.some(entry => entry.key === key), key);
});

test("the config toast binds to the SessionData property and writes no KDL", () => {
    assert.equal(adv.stored["advanced.configToast"], "SessionData:showConfigReloadToast");
    assert.ok(adv.search.some(entry => entry.key === "advanced.configToast"));
    assert.equal(kdl({ "advanced.configToast": false }), "");
    assert.ok(!adv.risky.includes("advanced.configToast"));
});
