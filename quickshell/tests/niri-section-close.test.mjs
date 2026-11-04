import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const Close = loadScript(new URL("../Common/niri/sections/close.js", import.meta.url));

const state = (askFrom, neverAsk = false) => ({ "close.askFrom": askFrom, "close.neverAsk": neverAsk });

test("asks from the threshold on, not below", () => {
    assert.equal(Close.needsConfirm(state(3), 2), false);
    assert.equal(Close.needsConfirm(state(3), 3), true);
    assert.equal(Close.needsConfirm(state(3), 7), true);
});

test("0 always asks, even for one window", () => {
    assert.equal(Close.needsConfirm(state(0), 1), true);
});

test("never ask wins over any threshold", () => {
    assert.equal(Close.needsConfirm(state(0, true), 1), false);
    assert.equal(Close.needsConfirm(state(1, true), 9), false);
});

test("the settings never reach the niri config", () => {
    assert.equal(Close.toKdl(state(0, true)).length, 0);
    assert.deepEqual(Object.keys(Close.stored).sort(), Object.keys(Close.defaults).sort());
});
