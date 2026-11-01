import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const keep = loadScript(new URL("../Common/niri/keep.js", import.meta.url));

const risky = ["advanced.modKey", "advanced.xwayland"];
const idle = () => keep.idle();
const edit = (state, key, before, after) => keep.edit(state, risky, key, before, after);

test("a risky change made in the section starts the countdown", () => {
    const next = edit(idle(), "advanced.modKey", "Super", "Alt");
    assert.equal(next.left, keep.seconds);
    assert.deepEqual({ ...next.pending }, { "advanced.modKey": "Super" });
});

test("a key outside the risky list or a write of the same value leaves it idle", () => {
    assert.equal(edit(idle(), "look.gaps", 8, 16).left, 0);
    assert.equal(edit(idle(), "advanced.modKey", "Super", "Super").left, 0);
});

test("only edits passed in count: a state that moved elsewhere starts nothing", () => {
    // A style, the KDL drawer or undo change the state without calling edit(), so the section stays idle.
    const state = idle();
    assert.equal(state.left, 0);
    assert.equal(keep.restores(state.pending, () => "Alt", () => "Super").length, 0);
});

test("a second risky change restarts the count and keeps the first value to go back to", () => {
    let state = edit(idle(), "advanced.modKey", "Super", "Alt");
    state = { pending: state.pending, left: 3 };
    state = edit(state, "advanced.modKey", "Alt", "Super2");
    assert.equal(state.left, keep.seconds);
    assert.equal(state.pending["advanced.modKey"], "Super");
});

test("putting the value back by hand ends the question", () => {
    let state = edit(idle(), "advanced.modKey", "Super", "Alt");
    state = edit(state, "advanced.modKey", "Alt", "Super");
    assert.equal(state.left, 0);
    assert.deepEqual(Object.keys(state.pending), []);
});

test("a non-risky edit during a question neither stops nor restarts it", () => {
    let state = edit(idle(), "advanced.modKey", "Super", "Alt");
    state = { pending: state.pending, left: 4 };
    assert.equal(edit(state, "look.gaps", 8, 16).left, 4);
});

test("revert writes back only what still differs, a default as a reset", () => {
    const pending = { "advanced.modKey": "Super", "advanced.xwayland": false, "input.layouts": "fr" };
    const now = { "advanced.modKey": "Alt", "advanced.xwayland": false, "input.layouts": "us" };
    const defaults = { "advanced.modKey": "Super", "advanced.xwayland": true, "input.layouts": "" };
    const out = keep.restores(pending, k => now[k], k => defaults[k]);
    assert.deepEqual(JSON.parse(JSON.stringify(out)), [
        { key: "advanced.modKey", value: "Super", reset: true },
        { key: "input.layouts", value: "fr", reset: false }
    ]);
});
