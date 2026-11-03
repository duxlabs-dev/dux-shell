import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const model = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Modules/SurfaceWidgets/ApplicationModel.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), model);
const plain = value => JSON.parse(JSON.stringify(value));

test("overflow boundary and empty lists preserve entries and metadata", () => {
    const items = [0, 1, 2].map(index => ({ uniqueKey: String(index), type: "pinned", isPinned: true, payload: index }));
    assert.equal(model.overflow([], 1, 1).count, 0);
    assert.equal(model.overflow(items, 3, 1).count, 0);
    assert.equal(model.overflow(items, 2, 1).count, 1);
    assert.equal(model.overflow(items, 2, 1).items.find(item => item.uniqueKey === "2").payload, 2);
    assert.equal(items.some(item => item.isInOverflow), false);
});

test("pin reorder uses actual items around launcher and overflow boundaries", () => {
    const pins = ["a", "b", "c"];
    const items = [{ type: "pinned", isPinned: true }, { type: "launcher", isPinned: true },
        { type: "pinned", isPinned: true }, { type: "pinned", isPinned: true }, { type: "overflow-toggle" }, { type: "separator" }];
    assert.deepEqual(plain(model.movePin(pins, items, 0, 3)), ["b", "c", "a"]);
    assert.deepEqual(plain(model.movePin(pins, items, 3, 0)), ["c", "a", "b"]);
    assert.deepEqual(plain(model.movePin(pins, items, 3, 1)), ["a", "c", "b"]);
    for (const [from, to] of [[0, 4], [0, 5], [1, 2], [-1, 0], [0, 0]])
        assert.equal(model.movePin(pins, items, from, to), pins);
});

test("compositor window identity survives reorder and rejects null", () => {
    const service = readFileSync(new URL("../Services/CompositorService.qml", import.meta.url), "utf8");
    const code = service.slice(service.indexOf("    function windowKey("), service.indexOf("    function getFocusedScreenName("));
    const live = [];
    const context = vm.createContext({ _windowKeys: [], _windowSerial: 0, ToplevelManager: { toplevels: { values: live } } });
    vm.runInContext(code, context);
    const first = {}, second = {};
    live.push(first, second);
    const key = context.windowKey(first);
    assert.notEqual(context.windowKey(second), key);
    assert.equal(context.windowKey(first), key);
    assert.equal(context.windowKey({ niriWindowId: 4 }), "niri:4");
    assert.equal(context.windowKey({ mangoWindowId: 5 }), "mango:5");
    assert.equal(context.windowKey({ aqueousKey: "aq:6" }), "aq:6");
    assert.equal(context.windowKey(null), "");
    live.splice(live.indexOf(first), 1);
    context.windowKey({});
    assert.equal(context._windowKeys.some(entry => entry.toplevel === first), false);
    assert.equal(context._windowKeys.some(entry => entry.toplevel === second), true);
});
