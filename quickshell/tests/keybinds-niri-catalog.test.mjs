import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const Actions = loadScript(new URL("../Common/KeybindActions.js", import.meta.url));
const offered = configNext => Actions.getCompositorCategories("niri").flatMap(category => [...Actions.getCompositorActions("niri", category, configNext)].map(action => action.id));

test("actions niri 26.04 rejects are only offered with config-next", () => {
    const next = ["toggle-touchpad", "change-vt", "set-window-fullscreen", "move-column-to-new-workspace-below", "focus-window-previous filter=\"app-id\""];
    const stable = offered(false);
    const all = offered(true);
    for (const id of next) {
        assert.ok(!stable.includes(id), `${id} hidden on 26.04`);
        assert.ok(all.includes(id), `${id} offered with config-next`);
        assert.equal(Actions.isKnownCompositorAction("niri", id, false), false, `${id} edits as raw text on 26.04`);
    }
    assert.ok(stable.includes("focus-window-previous"));
});

test("properties no preset or arg field carries edit as raw text", () => {
    for (const action of ["focus-window-previous scope=\"output\" filter=\"app-id\"", "focus-window-previous scope=\"all\""]) {
        assert.equal(Actions.isKnownCompositorAction("niri", action, false), false, action);
        assert.equal(Actions.getActionLabel(action, "niri"), action);
    }
    for (const action of ["move-column-to-index 3 focus=false", "quit skip-confirmation=true", "screenshot show-pointer=false"])
        assert.equal(Actions.isKnownCompositorAction("niri", action, false), true, action);
});

test("workspace reference and focus survive a niri action round trip", () => {
    const cases = [
        ["move-window-to-new-workspace-below chat focus=false", { index: "chat", focus: false }],
        ["move-column-to-index 3 focus=false", { index: "3", focus: false }],
        ['move-column-to-workspace "3" focus=false', { index: '"3"', focus: false }],
        ['focus-workspace "3"', { index: '"3"' }],
        ["focus-workspace 3", { index: "3" }],
        ["move-window-to-workspace-up focus=false", { focus: false }]
    ];
    for (const [action, args] of cases) {
        const parsed = Actions.parseCompositorActionArgs("niri", action);
        assert.deepEqual({ ...parsed.args }, args, action);
        assert.equal(Actions.buildCompositorAction("niri", parsed.base, parsed.args), action);
    }
});
