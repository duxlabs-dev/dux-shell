import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const scorerUrl = new URL("../Modals/DLauncherV2/Scorer.js", import.meta.url);
const item = (name, id = "same") => ({ id, type: "dmenu", name, subtitle: "", keywords: [] });
const results = (scorer, items, query) => Array.from(scorer.scoreItems(items, query, null), row => [row.item.name, row.score, row.order]);

test("prepared names follow edits, replacement lists and duplicate IDs without mutating items", () => {
    const scorer = loadScript(scorerUrl);
    const current = item("Git Browser");
    assert.deepEqual(results(scorer, [current], "git"), [["Git Browser", 5000, 0]]);
    current.name = "Network Manager";
    assert.deepEqual(results(scorer, [current], "git"), []);
    assert.deepEqual(results(scorer, [current], "network"), [["Network Manager", 5000, 0]]);
    const replacement = [Object.freeze(item("Git Browser")), Object.freeze(item("Git Tools"))];
    assert.deepEqual(results(scorer, replacement, "git"), [["Git Browser", 5000, 0], ["Git Tools", 5000, 1]]);
    assert.deepEqual(Object.keys(replacement[0]), Object.keys(item("")));
    for (const name of ["__proto__", "constructor", "toString"])
        assert.deepEqual(results(scorer, [item(name)], name), [[name, 10000, 0]]);
});

test("prepared name retention is bounded for both many short names and long names", () => {
    const scorer = loadScript(scorerUrl);
    const first = item("first");
    let prepared = scorer.preparedName(first);
    for (let i = 0; i < 10000; i++)
        scorer.preparedName(item("entry-" + i));
    assert.notEqual(scorer.preparedName(first), prepared);
    prepared = scorer.preparedName(first);
    for (let i = 0; i < 100; i++)
        scorer.preparedName(item("x".repeat(4096) + i));
    assert.notEqual(scorer.preparedName(first), prepared);
    const oversized = item("y".repeat(1024 * 1024));
    assert.notEqual(scorer.preparedName(oversized), scorer.preparedName(oversized));
    prepared = scorer.preparedName(first);
    scorer.clearPreparedNames();
    assert.notEqual(scorer.preparedName(first), prepared);
    assert.deepEqual(results(scorer, [first], "first"), [["first", 10000, 0]]);
});
