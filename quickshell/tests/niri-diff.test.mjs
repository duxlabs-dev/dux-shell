import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const { lineDiff } = loadScript(new URL("../Common/niri/diff.js", import.meta.url));

const show = ops => Array.from(ops, op => ({ same: "  ", add: "+ ", del: "- " })[op.kind] + op.text);

test("marks added, removed and changed lines in order", () => {
    const cases = [
        ["", "a\nb", ["+ a", "+ b"]],
        ["a\nb\n", "", ["- a", "- b"]],
        ["a\nb\nc", "a\nx\nc", ["  a", "- b", "+ x", "  c"]],
        ["a\nc", "a\nb\nc", ["  a", "+ b", "  c"]],
        ["a\nb", "a\nb\n", []],
        ["same", "same", []]
    ];
    for (const [before, after, expected] of cases)
        assert.deepEqual(show(lineDiff(before, after, 3)), expected, JSON.stringify([before, after]));
});

test("keeps only the context lines around a change", () => {
    const before = "1\n2\n3\n4\n5\n6\n7\n8\n9";
    const after = "1\n2\n3\n4\nfive\n6\n7\n8\n9";
    assert.deepEqual(show(lineDiff(before, after, 1)), ["  4", "- 5", "+ five", "  6"]);
});
