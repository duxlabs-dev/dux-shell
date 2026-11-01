import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const { assemble, fragments } = loadScript(new URL("../Common/niri/assemble.js", import.meta.url));
const { kdlString } = loadScript(new URL("../Common/niriKdl.js", import.meta.url));

const section = (id, blocks) => ({ id, toKdl: () => blocks });

test("nests dotted blocks, merges two sections into one block, keeps first-appearance order", () => {
    const look = section("look", [
        { block: "layout.focus-ring", lines: ["width 4"] },
        { block: "layout", lines: ["gaps 8"] }
    ]);
    const anim = section("anim", [
        { block: "animations", lines: ["slowdown 2.0"] },
        { block: "layout", lines: ["center-focused-column \"always\""] },
        { block: "layout.focus-ring", lines: ["active-color \"#ff0000\""] }
    ]);
    assert.equal(assemble([look, anim], {}), [
        "layout {",
        "    gaps 8",
        "    center-focused-column \"always\"",
        "    focus-ring {",
        "        width 4",
        "        active-color \"#ff0000\"",
        "    }",
        "}",
        "animations {",
        "    slowdown 2.0",
        "}",
        ""
    ].join("\n"));
});

test("drops blocks with no lines, even when only empty children are under them", () => {
    const s = section("look", [
        { block: "layout.border", lines: [] },
        { block: "layout.shadow", lines: [] },
        { block: "animations.window-open", lines: [] },
        { block: "cursor", lines: ["hide-when-typing"] }
    ]);
    assert.equal(assemble([s], {}), "cursor {\n    hide-when-typing\n}\n");
    assert.equal(assemble([section("x", [{ block: "layout", lines: [] }])], {}), "");
});

test("null block lines stay top level, indented multi-line entries keep their shape", () => {
    const s = section("rules", [
        { block: null, lines: ["workspace \"chat\"", "window-rule {\n    open-maximized true\n}"] },
        { block: "layout", lines: ["struts {\n    left 8\n}"] }
    ]);
    assert.equal(assemble([s], {}), [
        "workspace \"chat\"",
        "window-rule {",
        "    open-maximized true",
        "}",
        "layout {",
        "    struts {",
        "        left 8",
        "    }",
        "}",
        ""
    ].join("\n"));
});

test("custom text goes to its own fragment in section order, included after the generated blocks", () => {
    const a = section("a", [{ block: "layout", lines: ["gaps 8"] }]);
    const b = section("b", [{ block: null, lines: ["prefer-no-csd"] }]);
    const out = fragments([a, b], {}, { b: "layout { gaps 20; }", a: "  \n", c: "ignored" });
    assert.deepEqual({ ...out }, {
        main: "prefer-no-csd\nlayout {\n    gaps 8\n}\ninclude optional=true \"niri-custom.kdl\"\n",
        custom: "layout { gaps 20; }\n"
    });
});

test("modules sharing one section id write that section's custom text once", () => {
    const look = section("windows", [{ block: "layout", lines: ["gaps 8"] }]);
    const rules = section("windows", [{ block: null, lines: ["window-rule {\n}"] }]);
    const out = fragments([look, rules], {}, { windows: "layout { gaps 20; }" });
    assert.equal(out.custom, "layout { gaps 20; }\n");
});

test("passes state to every section and keeps kdlString escapes on one line", () => {
    const s = { id: "env", toKdl: state => [{ block: "environment", lines: ["NAME " + kdlString(state["env.name"])] }] };
    assert.equal(assemble([s], { "env.name": "a \"b\"\\c\nd" }),
        "environment {\n    NAME \"a \\\"b\\\"\\\\c\\nd\"\n}\n");
});
