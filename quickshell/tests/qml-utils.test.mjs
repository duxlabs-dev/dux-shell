import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const qmlUtils = loadScript(new URL("../Common/QmlUtils.js", import.meta.url));

test("normalizePinList handles arrays, strings, and empty values", () => {
    assert.deepEqual(Array.from(qmlUtils.normalizePinList(["a", "", null, "b"])), ["a", "b"]);
    assert.deepEqual(Array.from(qmlUtils.normalizePinList("only")), ["only"]);
    assert.deepEqual(Array.from(qmlUtils.normalizePinList("")), []);
    assert.deepEqual(Array.from(qmlUtils.normalizePinList(null)), []);
    assert.deepEqual(Array.from(qmlUtils.normalizePinList(undefined)), []);
});

test("togglePinEntry adds, removes, caps at maxPins, and deletes empty keys without mutating input", () => {
    const initial = { preferredWifi: ["b", "c"], otherKey: ["x"] };
    const added = qmlUtils.togglePinEntry(initial, "preferredWifi", "a", 3);
    assert.deepEqual(Array.from(added.preferredWifi), ["a", "b", "c"]);
    assert.deepEqual(Array.from(added.otherKey), ["x"]);
    assert.deepEqual(initial.preferredWifi, ["b", "c"]);

    const capped = qmlUtils.togglePinEntry(added, "preferredWifi", "d", 3);
    assert.deepEqual(Array.from(capped.preferredWifi), ["d", "a", "b"]);

    const removed = qmlUtils.togglePinEntry(capped, "preferredWifi", "a", 3);
    assert.deepEqual(Array.from(removed.preferredWifi), ["d", "b"]);

    const cleared = qmlUtils.togglePinEntry({ preferredWifi: ["only"] }, "preferredWifi", "only", 3);
    assert.equal("preferredWifi" in cleared, false);
});

test("comparePinOrder ranks pinned items first in pin order and ties unpinned items", () => {
    const pins = ["first", "second"];
    assert.equal(qmlUtils.comparePinOrder(pins, "first", "other"), -1);
    assert.equal(qmlUtils.comparePinOrder(pins, "other", "first"), 1);
    assert.ok(qmlUtils.comparePinOrder(pins, "first", "second") < 0);
    assert.ok(qmlUtils.comparePinOrder(pins, "second", "first") > 0);
    assert.equal(qmlUtils.comparePinOrder(pins, "first", "first"), 0);
    assert.equal(qmlUtils.comparePinOrder(pins, "x", "y"), 0);
    assert.equal(qmlUtils.comparePinOrder([], "x", "y"), 0);
    assert.equal(qmlUtils.comparePinOrder(null, "x", "y"), 0);

    const items = ["c", "second", "a", "first", "b"];
    items.sort((a, b) => qmlUtils.comparePinOrder(pins, a, b) || a.localeCompare(b));
    assert.deepEqual(items, ["first", "second", "a", "b", "c"]);
});
