import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const { press, observe, atTop, focused, target } = loadScript(new URL("../Common/niri/colwidth.js", import.meta.url));

const same = (a, b, msg) => assert.equal(JSON.stringify(a), JSON.stringify(b), msg);
const presets = [0.33333, 0.5, 0.66667];
const win = (width, id = 7) => ({ id, width });
// One key press followed by the width niri settles on.
const step = (state, before, after, top = false) => {
    const r = press(state, win(before), top);
    return { action: r.action, state: observe(r.state, win(after)) };
};

test("first press fills, second restores the width before the fill", () => {
    let r = step(null, 300, 700);
    same(r.action, { ExpandColumnToAvailableWidth: {} });
    r = step(r.state, 700, 300);
    same(r.action, { SetColumnWidth: { change: { SetFixed: 300 } } });
});

test("from 1/3: fill, back, 1/2, 2/3, fill, back, 1/3, fill", () => {
    let r = step(null, 300, 700);
    r = step(r.state, 700, 300);
    r = step(r.state, 300, 500);
    same(r.action, { SwitchPresetColumnWidth: {} });
    r = step(r.state, 500, 700);
    same(r.action, { SwitchPresetColumnWidth: {} });
    r = step(r.state, 700, 1000, true);
    same(r.action, { ExpandColumnToAvailableWidth: {} }, "top preset reached: fill again");
    r = step(r.state, 1000, 700, true);
    same(r.action, { SetColumnWidth: { change: { SetFixed: 700 } } });
    r = step(r.state, 700, 300, true);
    same(r.action, { SwitchPresetColumnWidth: {} }, "restored 2/3 wraps to 1/3 through niri");
    r = step(r.state, 300, 700);
    same(r.action, { ExpandColumnToAvailableWidth: {} }, "cycle restarts with a fill");
});

test("a fill that changed nothing skips the restore so the key never feels dead", () => {
    let r = step(null, 1000, 1000);
    r = step(r.state, 1000, 300);
    same(r.action, { SwitchPresetColumnWidth: {} });
});

test("a width change not made by the key, or a focus change, forgets the width before", () => {
    let r = step(null, 300, 700);
    assert.equal(observe(r.state, win(650)), null, "mouse resize");
    assert.equal(observe(r.state, win(700, 8)), null, "other window focused");
    assert.equal(observe(r.state, null), null, "no window");
    same(observe(r.state, win(700)), r.state, "same width keeps the state");
});

test("a fill that changed nothing still hands the next change to the mouse", () => {
    const r = step(null, 1000, 1000);
    assert.equal(observe(r.state, win(650)), null, "mouse resize after a no-op fill");
});

test("a window opened or closed in the workspace forgets the width before", () => {
    const w = (width, count) => ({ id: 7, width, count });
    const s = observe(press(null, w(300, 2), false).state, w(700, 2));
    assert.equal(observe(s, w(700, 1)), null, "neighbour closed");
    assert.equal(observe(s, w(700, 3)), null, "window opened");
    same(observe(s, w(700, 2)), s, "same count keeps the state");
    const restored = press(s, w(700, 2), false);
    same(restored.action, { SetColumnWidth: { change: { SetFixed: 300 } } });
    assert.notEqual(observe(restored.state, w(300, 2)), null, "restore keeps the count");
    assert.equal(observe(restored.state, w(300, 1)), null, "neighbour closed after a restore");
});

test("a fill that gained a few pixels skips the restore (10 px tolerance)", () => {
    let r = step(null, 846, 847, true);
    r = step(r.state, 847, 421, true);
    same(r.action, { SwitchPresetColumnWidth: {} }, "not SetFixed 846");
    assert.equal(r.state, null);
    r = step(null, 300, 311);
    r = step(r.state, 311, 300);
    same(r.action, { SetColumnWidth: { change: { SetFixed: 300 } } }, "11 px is a real change");
});

test("a width that moved by a few pixels keeps the state", () => {
    const r = step(null, 300, 700);
    same(observe(r.state, win(709)), r.state, "9 px");
    assert.equal(observe(r.state, win(711)), null, "11 px");
});

test("no tiled window focused: niri's native preset switch, no state", () => {
    same(press(null, null, false), { state: null, action: { SwitchPresetColumnWidth: {} } });
});

const tiled = (id, width, extra = {}) => ({ id, workspace_id: 3, layout: { pos_in_scrolling_layout: [id, 0], window_size: [width, 600] }, ...extra });

test("focused picks the focused tiled window and counts the tiled ones of its workspace", () => {
    const windows = [tiled(1, 400), tiled(2, 500, { is_focused: true }), tiled(4, 300, { workspace_id: 9 }),
        { id: 5, workspace_id: 3, is_floating: true, layout: { pos_in_scrolling_layout: null, window_size: [200, 200] } }];
    same(focused(windows), { id: 2, width: 500, workspace_id: 3, count: 2 });
});

test("focused is null without a focused tiled window or a usable width", () => {
    assert.equal(focused([]), null);
    assert.equal(focused(undefined), null, "no list");
    assert.equal(focused([tiled(1, 400), { id: 5, is_focused: true, layout: { pos_in_scrolling_layout: null, window_size: [200, 200] } }]), null, "floating focused");
    assert.equal(focused([{ id: 1, is_focused: true }]), null, "layout absent");
    assert.equal(focused([{ id: 1, is_focused: true, layout: { pos_in_scrolling_layout: [1, 0] } }]), null, "window_size missing");
    assert.equal(focused([tiled(1, "500", { is_focused: true })]), null, "width is a string");
    assert.equal(focused([tiled(1, -5, { is_focused: true })]), null, "negative width");
    assert.equal(focused([tiled(1, 0, { is_focused: true })]), null, "zero width");
    assert.equal(focused({ length: 1 }), null, "not an array");
    assert.equal(focused("windows"), null, "a string");
});

test("focused skips null and non-object entries", () => {
    same(focused([null, 3, "w", tiled(2, 500, { is_focused: true }), undefined]), { id: 2, width: 500, workspace_id: 3, count: 1 });
});

test("option off: every press is niri's native switch and nothing is remembered", () => {
    const windows = [tiled(2, 500, { is_focused: true })];
    const off = { "columns.cycleWidth": false };
    let state = observe(press(null, focused(windows), false).state, focused(windows));
    assert.notEqual(state, null, "a cycle was under way before the option went off");
    for (let i = 0; i < 3; i++) {
        const r = press(state, target(off, { "columns.cycleWidth": true }, windows), false);
        same(r, { state: null, action: { SwitchPresetColumnWidth: {} } }, `press ${i + 1}`);
        state = r.state;
    }
});

test("option absent or on: the focused tiled window is the target", () => {
    const windows = [tiled(2, 500, { is_focused: true })];
    const want = { id: 2, width: 500, workspace_id: 3, count: 1 };
    same(target({}, { "columns.cycleWidth": true }, windows), want, "absent, default on");
    same(target({}, {}, windows), want, "absent everywhere");
    same(target(undefined, undefined, windows), want, "no page");
    same(target({ "columns.cycleWidth": true }, { "columns.cycleWidth": false }, windows), want, "page wins");
    assert.equal(target({}, { "columns.cycleWidth": false }, windows), null, "default off");
});

test("atTop compares the width with the midpoint of the two largest presets", () => {
    assert.equal(atTop(1000, 1600, presets), true);
    assert.equal(atTop(934, 1600, presets), true, "midpoint 933");
    assert.equal(atTop(800, 1600, presets), false);
    assert.equal(atTop(800, 0, presets), false, "unknown output: let niri wrap");
    assert.equal(atTop(800, 1600, [0.5]), true, "one preset is always the top");
});
