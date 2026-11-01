import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const Shell = loadScript(new URL("../Common/niri/shell.js", import.meta.url));

test("paneOf reads the pane a section declares and nothing else", () => {
    assert.equal(Shell.paneOf(null), null);
    assert.equal(Shell.paneOf({}), null);
    assert.equal(Shell.paneOf({ sidePane: null }), null);
    assert.equal(Shell.paneOf({ sidePane: "pane" }), "pane");
});

test("place: right when wide, below for keybinds, inline otherwise, never for workspaces when narrow", () => {
    assert.equal(Shell.place("windows", false, true), "");
    assert.equal(Shell.place("windows", true, true), "right");
    assert.equal(Shell.place("workspaces", true, true), "right");
    assert.equal(Shell.place("workspaces", true, false), "");
    assert.equal(Shell.place("keybinds", true, false), "below");
    assert.equal(Shell.place("gestures", true, false), "inline");
});

test("modifiedCounts counts per section, skips custom and styles, one per animation", () => {
    const keys = ["look.gaps", "look.ringWidth", "custom.extra", "styles.x", "animations.window-open.curve", "animations.window-open.duration", "animations.workspace-switch.curve", "input.tap"];
    const counts = Shell.modifiedCounts(keys, key => key !== "input.tap");
    // the vm context has its own Object prototype: compare the shape
    assert.equal(JSON.stringify(counts), JSON.stringify({ look: 2, animations: 2 }));
});

test("breakpoints are the validated mockup's", () => {
    assert.equal(Shell.wideMinWidth, 1181);
    assert.equal(Shell.narrowMaxWidth, 860);
    assert.equal(Shell.compactMaxWidth, 480);
    assert.ok(Shell.menuWideWidth > Shell.menuMediumWidth);
});
