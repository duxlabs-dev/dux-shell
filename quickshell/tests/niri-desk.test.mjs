import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const desk = loadScript(new URL("../Common/niri/desk.js", import.meta.url));
const plain = value => JSON.parse(JSON.stringify(value));

const win = (id, ws, col, row, w, h, extra) => ({ id, app_id: "app" + id, workspace_id: ws, is_floating: false, is_focused: false, layout: { pos_in_scrolling_layout: [col, row], tile_size: [w, h] }, ...extra });

test("base state follows what DMS writes to layout.kdl", () => {
    const cases = [
        [{ "look.gaps": -1, "look.ringWidth": -1, "look.borderWidth": -1, "look.radius": -1 }, 2, { gaps: 4, ringWidth: 2, borderWidth: 2, radius: 12 }],
        [{ "look.gaps": -1, "look.ringWidth": -1, "look.borderWidth": -1, "look.radius": 0 }, 10, { gaps: 10, ringWidth: 2, borderWidth: 2, radius: 0 }],
        [{ "look.gaps": 0, "look.ringWidth": 6, "look.borderWidth": 6, "look.radius": 20 }, 10, { gaps: 0, ringWidth: 6, borderWidth: 6, radius: 20 }],
        [{ "look.gaps": -2 }, 10, { gaps: 16, ringWidth: 2, borderWidth: 2, radius: 12 }]
    ];
    for (const [keys, barSpacing, want] of cases) {
        const s = desk.baseState(keys, { barSpacing, themeRadius: 12 });
        assert.deepEqual({ gaps: s.gaps, ringWidth: s.ringWidth, borderWidth: s.borderWidth, radius: s.radius }, want, JSON.stringify(keys));
    }
});

test("base state draws the section's switches and colors, with niri's defaults when a key is missing", () => {
    const ctx = { barSpacing: 4, themeRadius: 12 };
    assert.deepEqual(plain(desk.baseState({}, ctx)), { gaps: 4, ringOn: true, ringWidth: 2, ringColor: "primary", borderOn: false, borderWidth: 2, borderColor: "primary", radius: 12, shadowOn: false, blurOn: false, centerFocused: "never", columnWidth: 0 });
    const s = desk.baseState({ "look.ringOn": false, "look.borderOn": true, "look.borderColor": "#aabbcc", "look.shadowOn": true, "look.blurOn": true, "columns.centerFocused": "always" }, ctx);
    assert.deepEqual([s.ringOn, s.borderOn, s.borderColor, s.shadowOn, s.blurOn, s.centerFocused], [false, true, "#aabbcc", true, true, "always"]);
});

test("columns keep only tiled windows of the workspace, in niri's column and row order", () => {
    const windows = [
        win(3, 1, 2, 2, 600, 300, { is_focused: true }),
        win(1, 1, 1, 1, 400, 700),
        win(2, 1, 2, 1, 600, 400),
        win(4, 2, 1, 1, 600, 700),
        win(5, 1, 3, 1, 300, 700, { is_floating: true }),
        { id: 6, workspace_id: 1, layout: {} }
    ];
    const cols = plain(desk.columns(windows, "1", 1280, 16));
    assert.deepEqual(cols.map(c => c.tiles.map(t => t.id)), [[1], [2, 3]]);
    assert.equal(cols[1].tiles[1].focused, true);
    assert.equal(cols[0].fraction, (400 + 16) / (1280 - 16));
    assert.deepEqual(plain(desk.columns([], 1, 1280, 16)), []);
});

// What niri 26.04 reports on a 1280x800 output with a 44 px bar and gaps 4: tiled windows get no view position.
const bench = focused => [
    win(2, 1, 1, 1, 634, 372, { is_focused: focused === 2 }),
    win(3, 1, 1, 2, 634, 372),
    win(4, 1, 2, 1, 889, 748, { is_focused: focused === 4 }),
    win(5, 1, 3, 1, 378, 748, { is_focused: focused === 5 }),
    { id: 6, app_id: "pip", workspace_id: 1, is_floating: true, layout: { pos_in_scrolling_layout: null, tile_size: [300, 200], tile_pos_in_workspace_view: [902, 52] } }
];
const rect = t => [t.id, Math.round(t.x), Math.round(t.y), Math.round(t.width), Math.round(t.height)];

test("layout gives real column widths, stacked rows and floating windows over them, in output pixels", () => {
    const cols = desk.columns(bench(5), 1, 1280, 4);
    const height = desk.workArea(cols, 800);
    assert.equal(height, 756);
    const l = desk.layout(cols, desk.floating(bench(5), 1), { outputWidth: 1280, height, top: 800 - height, gaps: 4, columnWidth: 0 });
    assert.equal(l.focus, 2);
    assert.deepEqual(plain(l.tiles.map(rect)), [[2, 0, 4, 634, 372], [3, 0, 380, 634, 372], [4, 638, 4, 889, 748], [5, 1531, 4, 378, 748], [6, 902, 8, 300, 200]]);
    assert.deepEqual(plain(l.tiles.map(t => t.floating)), [false, false, false, false, true]);

    const wide = desk.layout(cols, [], { outputWidth: 1280, height, gaps: 16, columnWidth: 1 });
    assert.equal(wide.columns[2].width, 1280 - 32);
    assert.equal(wide.columns[1].x - wide.columns[0].x, wide.columns[0].width + 16);
});

test("the view scrolls like niri: just enough to show the focused column, and stays put otherwise", () => {
    const at = focused => {
        const cols = desk.columns(bench(focused), 1, 1280, 4);
        const l = desk.layout(cols, [], { outputWidth: 1280, height: 756, gaps: 4, columnWidth: 0 });
        return l.columns[l.focus];
    };
    let offset = desk.follow(NaN, at(2), 1280, 4);
    assert.equal(offset, -4);
    offset = desk.follow(offset, at(5), 1280, 4);
    assert.equal(Math.round(offset), 633);
    assert.equal(Math.round(desk.follow(offset, at(4), 1280, 4)), 633);
    assert.equal(desk.follow(offset, at(2), 1280, 4), -4);
    assert.equal(Math.round(desk.follow(-4, at(4), 1280, 4)), 251);
    assert.equal(desk.follow(10, undefined, 1280, 4), 10);
});

test("center-focused-column always and on-overflow center the focused column", () => {
    const at = focused => {
        const cols = desk.columns(bench(focused), 1, 1280, 4);
        return desk.layout(cols, [], { outputWidth: 1280, height: 756, gaps: 4, columnWidth: 0 }).columns[cols.findIndex(c => c.tiles.some(t => t.focused))];
    };
    const center = c => c.x + c.width / 2 - 640;
    assert.equal(desk.follow(NaN, at(2), 1280, 4, "always"), center(at(2)));
    assert.equal(desk.follow(-4, at(4), 1280, 4, "always"), center(at(4)));
    assert.equal(desk.follow(-4, at(2), 1280, 4, "on-overflow"), -4);
    assert.equal(desk.follow(-4, at(5), 1280, 4, "on-overflow"), center(at(5)));
    assert.equal(Math.round(desk.follow(-4, at(5), 1280, 4, "never")), 633);
});

test("dragging the edges gives even gaps in range and snaps width to a preset", () => {
    assert.equal(desk.gapsFromDrag(16, 0, 0.5), 16);
    assert.equal(desk.gapsFromDrag(16, -16, 0.5), 32);
    assert.equal(desk.gapsFromDrag(16, 500, 0.5), 0);
    assert.equal(desk.gapsFromDrag(16, -500, 0.5), 64);
    assert.equal(desk.gapsFromDrag(16, -3, 0.5) % 2, 0);
    assert.equal(desk.fractionFromDrag(0.5, 0, 640, 8), 0.5);
    assert.equal(desk.fractionFromDrag(0.5, 110, 640, 8), 2 / 3);
    assert.equal(desk.fractionFromDrag(0.5, 900, 640, 8), 1);
    assert.equal(desk.fractionFromDrag(0.5, -900, 640, 8), 1 / 3);
});

test("arrow keys on the edges step gaps by 2 and width to the next preset, within range", () => {
    assert.equal(desk.stepGaps(16, 1), 18);
    assert.equal(desk.stepGaps(16, -1), 14);
    assert.equal(desk.stepGaps(0, -1), 0);
    assert.equal(desk.stepGaps(64, 1), 64);
    assert.equal(desk.stepWidth(0.5, 1), 2 / 3);
    assert.equal(desk.stepWidth(0.47, -1), 1 / 3);
    assert.equal(desk.stepWidth(1 / 3, -1), 1 / 3);
    assert.equal(desk.stepWidth(1, 1), 1);
});

test("window menu offers floating, one entry per screen only when there are several, fullscreen and hide when sharing", () => {
    assert.deepEqual(plain(desk.windowMenu(["eDP-1"])).map(i => i.id), ["floating", "fullscreen", "blockOut"]);
    const items = plain(desk.windowMenu(["eDP-1", "DP-1"]));
    assert.deepEqual(items.map(i => i.id), ["floating", "output", "output", "fullscreen", "blockOut"]);
    assert.deepEqual(items.filter(i => i.id === "output").map(i => [i.output, i.actions.openOnOutput, i.kdl]), [["DP-1", "DP-1", 'open-on-output "DP-1"'], ["eDP-1", "eDP-1", 'open-on-output "eDP-1"']]);
    assert.deepEqual(items.find(i => i.id === "blockOut").actions, { blockOutFrom: "screencast" });
    assert.deepEqual(plain(desk.windowMenu(undefined)).map(i => i.id), ["floating", "fullscreen", "blockOut"]);
});

test("a rule from the window menu needs something to match on, never every window", () => {
    const item = desk.windowMenu([])[0];
    assert.equal(desk.menuRule({ appId: "", title: "" }, item, {}), null);
    assert.deepEqual(plain(desk.menuRule({ appId: "mpv", title: "x" }, item, { appId: "^mpv$" })), { name: "mpv", matchCriteria: { appId: "^mpv$" }, actions: { openFloating: true }, enabled: true });
    assert.equal(desk.menuRule({ appId: "", title: "Inbox" }, item, { title: "Inbox" }).name, "Inbox");
});

test("a window title from outside is capped before it names or matches a rule", () => {
    const long = "x".repeat(5000);
    assert.equal(desk.capTitle(long).length, 100);
    assert.equal(desk.capTitle("Inbox"), "Inbox");
    assert.equal(desk.capTitle(undefined), "");
    assert.equal(desk.capTitle(42), "42");
});

test("the desk is drawn in logical pixels: the live screen wins over stale output info", () => {
    // after a live output scale change the cached output info still says 1280x800 scale 1
    assert.deepEqual(plain(desk.outputSize({ name: "winit", logical: { width: 1280, height: 800, scale: 1 } }, { name: "winit", width: 1707, height: 1067 })), { width: 1707, height: 1067 });
    // another screen's size never describes this output
    assert.deepEqual(plain(desk.outputSize({ name: "winit", logical: { width: 1706, height: 1066 } }, { name: "HDMI-A-1", width: 2560, height: 1440 })), { width: 1706, height: 1066 });
    // niri has not reported the output yet: the screen's size, else a named fallback
    assert.deepEqual(plain(desk.outputSize(undefined, { name: "winit", width: 800, height: 600 })), { width: 800, height: 600 });
    assert.deepEqual(plain(desk.outputSize({ name: "winit", logical: { width: 0, height: 0 } }, { name: "winit", width: 0, height: 0 })), { width: 1920, height: 1080 });
    assert.deepEqual(plain(desk.outputSize(null, null)), { width: 1920, height: 1080 });
});
