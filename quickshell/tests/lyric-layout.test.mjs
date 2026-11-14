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
        [[300, 500, 600], 200, 48, 10, 200],
        [[20, 30], 200, 48, 10, 48],
        [[0, 0], 200, 48, 10, 0],
        [[], 200, 48, 10, 0]
    ];
    for (const [widths, cap, minimum, slack, expected] of cases)
        assert.equal(layout.pageWidth(widths, cap, minimum, slack), expected, JSON.stringify(widths));
});

test("lyric scrolling sleeps through the hold and stops at the end", () => {
    const motion = { start: 10, end: 20, from: 0, to: 200, hold: 1.2, speed: 50 };
    assert.ok(Math.abs(layout.scrollState(motion, 10, 200).wait - 1.2) < 1e-9);
    assert.equal(layout.scrollState(motion, 10, 200).offset, 0);
    assert.ok(Math.abs(layout.scrollState(motion, 15.6, 200).offset - 100) < 1e-9);
    assert.equal(layout.scrollState(motion, 20, 200).wait, Infinity);
    assert.equal(layout.scrollState(motion, 20, 200).offset, 200);
    assert.equal(layout.scrollState(motion, 12, 200).offset < 100, true);
    assert.equal(layout.scrollState(motion, 15, 0).wait, Infinity);
});

test("a lyric without a finite end traverses once at the fallback speed", () => {
    for (const end of [Infinity, NaN, 10]) {
        const motion = { start: 10, end, from: 0, to: 200, hold: 1, speed: 50 };
        assert.equal(layout.scrollState(motion, 13, 200).offset, 100);
        assert.equal(layout.scrollState(motion, 15, 200).offset, 200);
        assert.equal(layout.scrollState(motion, 15, 200).wait, Infinity);
    }
});

test("a wide timed cue reveals its start, middle and tail independently of highlight fill", () => {
    const motion = { start: 0, end: 4, from: -75, to: 325, hold: 0, speed: 50 };
    assert.equal(layout.scrollState(motion, 0, 300).offset, 0);
    assert.equal(layout.scrollState(motion, 0, 300).wait, 0.75);
    assert.equal(layout.scrollState(motion, 2, 300).offset, 125);
    assert.equal(layout.scrollState(motion, 4, 300).offset, 300);
    assert.equal(layout.scrollState(motion, 4, 300).wait, Infinity);
});

test("a whitespace cue preserves the scroll position without scheduling movement", () => {
    const motion = { start: 1, end: 2, from: 80, to: 80, hold: 0, speed: 50 };
    assert.equal(layout.scrollState(motion, 1.5, 200).offset, 80);
    assert.equal(layout.scrollState(motion, 1.5, 200).wait, Infinity);
});
