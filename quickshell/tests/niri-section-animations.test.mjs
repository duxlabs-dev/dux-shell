import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const Section = loadScript(new URL("../Common/niri/sections/animations.js", import.meta.url));
const { assemble } = loadScript(new URL("../Common/niri/assemble.js", import.meta.url));

const module = { id: "animations", toKdl: Section.toKdl };
const kdl = changes => assemble([module], Object.assign({}, Section.defaults, changes));

test("defaults give no KDL at all", () => {
    assert.equal(kdl({}), "");
});

test("off and slowdown are single lines", () => {
    assert.equal(kdl({ "animations.on": false, "animations.slowdown": 2 }), "animations {\n    off\n    slowdown 2.0\n}\n");
    assert.equal(kdl({ "animations.slowdown": 1.5 }), "animations {\n    slowdown 1.5\n}\n");
});

test("only the changed animation is written, whole, as niri replaces it whole", () => {
    assert.equal(kdl({ "animations.window-open.ms": 300 }), [
        "animations {",
        "    window-open {",
        "        duration-ms 300",
        "        curve \"ease-out-expo\"",
        "    }",
        "}",
        ""
    ].join("\n"));
});

test("a field of the kind not in use writes nothing", () => {
    assert.equal(kdl({ "animations.window-open.stiffness": 1400 }), "");
});

test("switching kind writes the other kind's values", () => {
    assert.equal(kdl({ "animations.workspace-switch.kind": "curve" }), [
        "animations {",
        "    workspace-switch {",
        "        duration-ms 250",
        "        curve \"ease-out-cubic\"",
        "    }",
        "}",
        ""
    ].join("\n"));
});

test("read gives an animation's fields from the state", () => {
    const a = Section.read(Object.assign({}, Section.defaults, { "animations.window-resize.damping": 0.5 }), "window-resize");
    assert.equal(a.kind, "spring");
    assert.equal(a.damping, 0.5);
    assert.equal(a.stiffness, 800);
});

test("every key is stored in the page and has a default", () => {
    for (const key in Section.stored)
        assert.ok(key in Section.defaults, key);
    assert.equal(Object.keys(Section.defaults).length, 2 + 11 * 6);
    for (const entry of Section.search)
        assert.ok(entry.key in Section.defaults, entry.key);
});
