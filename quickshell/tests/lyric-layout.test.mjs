import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const layout = loadScript(new URL("../Common/LyricLayout.js", import.meta.url));

test("hasWords rejects instrumental filler and keeps sung text", () => {
    for (const text of ["", "   ", "♪", " ♫ ♫ ", "🎵🎶", "(...)", "♪ ~ ♪", "[—]", "\u{1D160}", " \u{1D158}\u{1D165}\u{1D16E} "])
        assert.equal(layout.hasWords(text), false, JSON.stringify(text));
    for (const text of ["I", "la la ♪", "(oh)", "夜に駆ける", "привет", "🎤"])
        assert.equal(layout.hasWords(text), true, JSON.stringify(text));
});

test("pageWidth sizes from the median line", () => {
    const cases = [
        [[100, 150, 400], 200, 48, 10, 150],
        [[100, 140, 160, 900], 200, 48, 10, 150],
        [[300, 320, 340], 200, 48, 10, 170],
        [[300, 380, 1000], 210, 48, 10, 200],
        [[300, 500, 600], 200, 48, 10, 200],
        [[20, 30], 200, 48, 10, 48],
        [[0, 0], 200, 48, 10, 0],
        [[], 200, 48, 10, 0]
    ];
    for (const [widths, cap, minimum, slack, expected] of cases)
        assert.equal(layout.pageWidth(widths, cap, minimum, slack), expected, JSON.stringify(widths));
});
