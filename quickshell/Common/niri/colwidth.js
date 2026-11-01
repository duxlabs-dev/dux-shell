.pragma library

// Mod+R emulated by DMS: fill the remaining space, press again to go
// back to the width before, then the presets upward; past the largest preset, fill again.
// state: null (next press fills) or {id, width, count, phase, before, pending}
//   phase "filled": before = width to go back to; "restored": niri picks the preset above
//   (it wraps to the first past the top); "cycling": presets go up until the top one.
// pending: the next observed state is the one the key asked for; observe() consumes it once.
// shortcut: with no niri event after a press, pending stays true until the next event, add a timeout only if a stale pending is ever seen.
// count: windows of the workspace; one opened or closed changes the layout, so forget before.

// A fill next to a neighbour can gain a pixel (846 -> 847): PaperWM's tolerance says "unchanged".
const TOLERANCE = 10;

function near(a, b) {
    return Math.abs(a - b) <= TOLERANCE;
}

function tiled(w) {
    return Boolean(w.layout?.pos_in_scrolling_layout);
}

// windows: niri's window list. Null unless a tiled window has the focus and a usable width.
function focused(windows) {
    if (!Array.isArray(windows))
        return null;
    const list = windows.filter(o => o && typeof o === "object" && tiled(o));
    const w = list.find(o => o.is_focused);
    const width = w?.layout.window_size?.[0];
    if (!Number.isFinite(width) || width <= 0)
        return null;
    return {
        id: w.id,
        width: width,
        workspace_id: w.workspace_id,
        count: list.filter(o => o.workspace_id === w.workspace_id).length
    };
}

// page: SettingsData.niriPage. Option off or absent: null, so press() sends niri's stock switch
// and forgets any cycle.
function target(page, defaults, windows) {
    const on = (page?.["columns.cycleWidth"] ?? defaults?.["columns.cycleWidth"]) === true;
    return on ? focused(windows) : null;
}

// The bind of each key with the option on and off.
const BINDS = {
    "Mod+R": { on: "spawn dms ipc call niri cycleColumnWidth", off: "switch-preset-column-width", desc: "Column width" },
    "Mod+Shift+R": { on: "switch-preset-column-width-back", off: "switch-preset-window-height", desc: "" }
};

// current: {key: {action, dms}} of each key, absent when unbound. A key on another action,
// or from config.kdl, is the user's own and lands in kept instead of writes.
function rebinds(on, current) {
    const writes = [];
    const kept = [];
    for (const key in BINDS) {
        const bind = BINDS[key];
        const cur = current?.[key];
        const want = on ? bind.on : bind.off;
        if (cur && cur.action === want)
            continue;
        if (cur && (!cur.dms || (cur.action !== bind.on && cur.action !== bind.off))) {
            kept.push(key);
            continue;
        }
        writes.push({ key: key, action: want, desc: on ? bind.desc : "" });
    }
    return { writes: writes, kept: kept };
}

function fill(win) {
    return {
        state: { id: win.id, width: win.width, count: win.count, phase: "filled", before: win.width, pending: true },
        action: { ExpandColumnToAvailableWidth: {} }
    };
}

function preset(win, phase) {
    return {
        state: phase ? { id: win.id, width: win.width, count: win.count, phase: phase, pending: true } : null,
        action: { SwitchPresetColumnWidth: {} }
    };
}

// win: focused() of the window list; top: its width is at or above the largest preset.
// No tiled window focused (floating): niri's stock preset switch, so the key always does something.
function press(state, win, top) {
    if (!win)
        return preset(win, null);
    if (!state || state.id !== win.id)
        return fill(win);
    switch (state.phase) {
    case "filled":
        if (near(win.width, state.before))
            return preset(win, top ? null : "cycling");
        return {
            state: { id: win.id, width: win.width, count: win.count, phase: "restored", pending: true },
            action: { SetColumnWidth: { change: { SetFixed: state.before } } }
        };
    case "restored":
        return preset(win, top ? null : "cycling");
    default:
        return top ? fill(win) : preset(win, "cycling");
    }
}

// Call on every window change: a focus change, a window opened or closed, or a width change
// the key did not ask for forgets the width before.
function observe(state, win) {
    if (!state || !win || win.id !== state.id || win.count !== state.count)
        return null;
    if (!state.pending)
        return near(win.width, state.width) ? state : null;
    return Object.assign({}, state, { width: win.width, pending: false });
}

// shortcut: the preset widths are compared against the output width, not niri's working area
// (gaps, struts, a side bar); the midpoint between the two largest presets absorbs that slack.
function atTop(width, outputWidth, presets) {
    const sorted = (presets || []).slice().sort((a, b) => b - a);
    if (sorted.length < 2)
        return true;
    if (!outputWidth)
        return false;
    return width >= outputWidth * (sorted[0] + sorted[1]) / 2;
}
