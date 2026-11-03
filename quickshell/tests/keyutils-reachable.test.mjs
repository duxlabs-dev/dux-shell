import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const keys = loadScript(new URL("../Common/KeyUtils.js", import.meta.url));

// Shaped like `dms keybinds keymap` on de:neo, where bracketleft sits on layer 4
// and so appears on no key's first level. `named` is the vocabulary the keysyms
// are drawn from.
const neoKeymap = {
    keysyms: { 26: ["l"], 27: ["c"], 10: ["1"] },
    named: ["1", "a", "bracketleft", "bracketright", "c", "l", "A", "C", "L"],
};

const usKeymap = {
    keysyms: { 26: ["e"], 34: ["bracketleft"], 38: ["a"] },
    named: ["a", "bracketleft", "e", "A", "E"],
};

test("a bracket that only exists on layer 4 is unreachable", () => {
    assert.equal(keys.keysymUnreachable("bracketleft", neoKeymap), true);
    assert.equal(keys.keysymUnreachable("bracketright", neoKeymap), true);
});

test("a key on the first level is fine", () => {
    assert.equal(keys.keysymUnreachable("l", neoKeymap), false);
    assert.equal(keys.keysymUnreachable("bracketleft", usKeymap), false);
});

test("letter case does not matter", () => {
    assert.equal(keys.keysymUnreachable("A", usKeymap), false);
    assert.equal(keys.keysymUnreachable("L", neoKeymap), false);
});

// Anything the keymap could not name is absent from the vocabulary, and absent
// has to mean "no idea" rather than "unreachable", otherwise every function key
// and every umlaut would be flagged.
test("a key outside the vocabulary is never flagged", () => {
    assert.equal(keys.keysymUnreachable("F5", neoKeymap), false);
    assert.equal(keys.keysymUnreachable("udiaeresis", neoKeymap), false);
    assert.equal(keys.keysymUnreachable("XF86AudioPlay", neoKeymap), false);
});

test("a missing or empty keymap never flags", () => {
    assert.equal(keys.keysymUnreachable("bracketleft", undefined), false);
    assert.equal(keys.keysymUnreachable("bracketleft", {}), false);
    assert.equal(keys.keysymUnreachable("bracketleft", { keysyms: {}, named: [] }), false);
    assert.equal(keys.keysymUnreachable("", neoKeymap), false);
});

// A second layout keeps the bind alive, so de,us must not be warned about.
test("a second layout group counts", () => {
    assert.equal(keys.keysymUnreachable("bracketleft", { keysyms: { 34: ["0xfc", "bracketleft"] }, named: ["bracketleft"] }), false);
});
