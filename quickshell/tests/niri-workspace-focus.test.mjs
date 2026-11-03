import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../Services/NiriService.qml", import.meta.url), "utf8");

function fixture() {
    const context = vm.createContext({ workspaces: {}, allWorkspaces: [] });
    context.root = context;
    for (const [, name, args, body] of source.matchAll(/^    function (\w+)\(([^)]*)\) \{([\s\S]*?)^    \}/gm)) {
        if (["setWorkspaces", "handleWorkspacesChanged", "handleWorkspaceActivated", "updateCurrentOutputWorkspaces"].includes(name))
            vm.runInContext(`function ${name}(${args}) {${body}}`, context);
    }
    context.handleWorkspacesChanged({ workspaces: [
        { id: 1, idx: 1, output: "eDP-1", is_active: true, is_focused: true },
        { id: 2, idx: 1, output: "DP-1", is_active: true, is_focused: false },
        { id: 3, idx: 2, output: "DP-1", is_active: false, is_focused: false }
    ] });
    return context;
}

test("scrolling the other output preserves focus; focusing it then transfers focus", () => {
    const state = fixture();
    state.handleWorkspaceActivated({ id: 3, focused: false });
    assert.equal(state.workspaces[2].is_active, false);
    assert.equal(state.workspaces[3].is_active, true);
    assert.equal(state.focusedWorkspaceId, 1);
    assert.equal(state.allWorkspaces[state.focusedWorkspaceIndex].id, 1);
    assert.equal(state.currentOutput, "eDP-1");
    assert.deepEqual(Array.from(state.currentOutputWorkspaces, w => w.id), [1]);

    state.handleWorkspaceActivated({ id: 3, focused: true });
    assert.equal(state.focusedWorkspaceId, 3);
    assert.equal(state.allWorkspaces[state.focusedWorkspaceIndex].id, 3);
    assert.equal(state.currentOutput, "DP-1");
    assert.deepEqual(Array.from(state.allWorkspaces.filter(w => w.is_focused), w => w.id), [3]);
    assert.deepEqual(Array.from(state.currentOutputWorkspaces, w => w.id), [2, 3]);
});
