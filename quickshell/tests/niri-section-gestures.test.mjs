import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const gestures = loadScript(new URL("../Common/niri/sections/gestures.js", import.meta.url));
// The module runs in its own realm: copy its values before deepEqual.
const plain = v => JSON.parse(JSON.stringify(v));

test("defaults match niri and emit nothing", () => {
    assert.equal(gestures.defaults["gestures.dndViewWidth"], 30);
    assert.equal(gestures.defaults["gestures.dndWorkspaceHeight"], 50);
    const lines = gestures.toKdl(gestures.defaults).flatMap(b => b.lines);
    assert.deepEqual(plain(lines), []);
});

test("changed edges go to their own gestures blocks, 0 turns one off", () => {
    const state = Object.assign({}, gestures.defaults, { "gestures.dndViewWidth": 0, "gestures.dndWorkspaceHeight": 80 });
    assert.deepEqual(plain(gestures.toKdl(state)), [
        { block: "gestures.dnd-edge-view-scroll", lines: ["trigger-width 0"] },
        { block: "gestures.dnd-edge-workspace-switch", lines: ["trigger-height 80"] }
    ]);
});

test("every key is stored in the page and searchable", () => {
    for (const key of Object.keys(gestures.defaults)) {
        assert.equal(gestures.stored[key], "page", key);
        assert.ok(gestures.search.some(s => s.key === key), key);
    }
});
