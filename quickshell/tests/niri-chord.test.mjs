import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const { parseChord } = loadScript(new URL("../Common/niri/chord.js", import.meta.url));

test("a plain chord keeps its modifier and key names", () => {
    assert.equal(parseChord("Super+R", "Super"), "Super+R");
});

test("loose spacing and case normalize, modifiers sort in a fixed order", () => {
    assert.equal(parseChord(" shift + ctrl + t ", "Super"), "Ctrl+Shift+T");
    assert.equal(parseChord("mod+Return", "Alt"), "Alt+Return");
    assert.equal(parseChord("super+f5", "Super"), "Super+F5");
});

test("text that is not a chord of known modifiers parses to nothing", () => {
    assert.equal(parseChord("", "Super"), "");
    assert.equal(parseChord(undefined, "Super"), "");
    assert.equal(parseChord("r", "Super"), "");
    assert.equal(parseChord("ctrl shift t", "Super"), "");
    assert.equal(parseChord("foo+r", "Super"), "");
    assert.equal(parseChord("ctrl+ctrl+r", "Super"), "");
    assert.equal(parseChord("ctrl+", "Super"), "");
});
