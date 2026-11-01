.pragma library
.import "sections/look.js" as Look

const WIDTH_PRESETS = [1 / 3, 1 / 2, 2 / 3, 1];
const GAPS = Look.limits["look.gaps"];
// niri's default when DMS leaves gaps to the user's config (override -2)
const NIRI_GAPS = 16;
// Drawn until niri reports the output and the window knows its screen
const FALLBACK_OUTPUT = { width: 1920, height: 1080 };
// A window title comes from any app; this keeps a rule name and its match readable
const TITLE_MAX = 100;

// niri's tile sizes are logical pixels. Its cached output info goes stale after a live output
// scale change, so the live screen size wins when the screen is the output being drawn.
function outputSize(output, screen) {
    const logical = output?.logical;
    const sameOutput = output?.name && screen?.name && output.name === screen.name;
    if (sameOutput && screen.width > 0 && screen.height > 0)
        return { width: screen.width, height: screen.height };
    if (logical?.width > 0 && logical?.height > 0)
        return { width: logical.width, height: logical.height };
    if (screen?.width > 0 && screen?.height > 0)
        return { width: screen.width, height: screen.height };
    return FALLBACK_OUTPUT;
}

function capTitle(title) {
    return String(title ?? "").slice(0, TITLE_MAX);
}

// s holds section keys ("look.gaps": -1, ...), live or previewed; ctx: {barSpacing, themeRadius}.
// Same fallbacks as NiriService.doGenerateNiriLayoutConfig; ring on and border off are niri's defaults.
function baseState(s, ctx) {
    const g = s["look.gaps"] ?? -1;
    const size = key => s[key] >= 0 ? s[key] : 2;
    return {
        gaps: g >= 0 ? g : g === -2 ? NIRI_GAPS : Math.max(4, ctx.barSpacing ?? 4),
        ringOn: s["look.ringOn"] !== false,
        ringWidth: size("look.ringWidth"),
        ringColor: s["look.ringColor"] || "primary",
        borderOn: s["look.borderOn"] === true,
        borderWidth: size("look.borderWidth"),
        borderColor: s["look.borderColor"] || "primary",
        radius: s["look.radius"] >= 0 ? s["look.radius"] : ctx.themeRadius,
        shadowOn: s["look.shadowOn"] === true,
        blurOn: s["look.blurOn"] === true,
        centerFocused: s["columns.centerFocused"] || "never",
        columnWidth: 0
    };
}

function tileOf(w) {
    return {
        id: w.id,
        appId: w.app_id || "",
        title: w.title || "",
        focused: !!w.is_focused
    };
}

function onWorkspace(w, workspaceId) {
    return String(w.workspace_id) === String(workspaceId) && !!w.layout?.tile_size;
}

// Fractions come from the live tile width so a previewed gap size reflows like niri would.
function columns(windows, workspaceId, outputWidth, liveGaps) {
    const byCol = {};
    for (const w of windows || []) {
        const pos = w.layout?.pos_in_scrolling_layout;
        if (!onWorkspace(w, workspaceId) || w.is_floating || !pos)
            continue;
        (byCol[pos[0]] = byCol[pos[0]] || []).push(w);
    }
    return Object.keys(byCol).map(Number).sort((a, b) => a - b).map(col => {
        const list = byCol[col].sort((a, b) => a.layout.pos_in_scrolling_layout[1] - b.layout.pos_in_scrolling_layout[1]);
        const width = Math.max(...list.map(w => w.layout.tile_size[0]));
        return {
            fraction: (width + liveGaps) / (outputWidth - liveGaps),
            span: list.reduce((a, w) => a + w.layout.tile_size[1], 0) + liveGaps * (list.length + 1),
            tiles: list.map(w => Object.assign(tileOf(w), {
                            height: w.layout.tile_size[1]
                        }))
        };
    });
}

// niri gives floating windows a position in the view; tiled ones get none, the desk scrolls them itself.
function floating(windows, workspaceId) {
    return (windows || []).filter(w => onWorkspace(w, workspaceId) && w.is_floating && w.layout.tile_pos_in_workspace_view).map(w => Object.assign(tileOf(w), {
                x: w.layout.tile_pos_in_workspace_view[0],
                y: w.layout.tile_pos_in_workspace_view[1],
                width: w.layout.tile_size[0],
                height: w.layout.tile_size[1]
            }));
}

// Height left to windows once the bar's exclusive zone is taken; the output height when nothing tells.
function workArea(cols, outputHeight) {
    return cols.reduce((a, c) => Math.max(a, c.span || 0), 0) || outputHeight;
}

function stack(c, x, width, o) {
    const g = o.gaps;
    const total = c.tiles.reduce((a, t) => a + t.height, 0) || 1;
    const free = o.height - g * (c.tiles.length + 1);
    let y = g;
    return c.tiles.map(t => {
        const h = free * t.height / total;
        const r = Object.assign({}, t, {
            x: x,
            y: y,
            width: width,
            height: h,
            floating: false
        });
        y += h + g;
        return r;
    });
}

// Output pixels; tiled x is in workspace space (column 0 at 0), floating x stays in view space.
// o: {outputWidth, height, top, gaps, columnWidth}; columnWidth > 0 overrides the focused column.
function layout(cols, floats, o) {
    const g = o.gaps;
    const focus = Math.max(0, cols.findIndex(c => c.tiles.some(t => t.focused)));
    const out = [];
    let tiles = [];
    let x = 0;
    cols.forEach((c, i) => {
        const fraction = i === focus && o.columnWidth > 0 ? o.columnWidth : c.fraction;
        const width = fraction * (o.outputWidth - g) - g;
        out.push({
            x: x,
            width: width,
            fraction: fraction
        });
        tiles = tiles.concat(stack(c, x, width, o));
        x += width + g;
    });
    for (const f of floats || [])
        tiles.push(Object.assign({}, f, {
            y: f.y - (o.top || 0),
            floating: true
        }));
    return {
        focus: focus,
        columns: out,
        tiles: tiles
    };
}

// center-focused-column: "never" keeps the view and scrolls just enough to show the focused column,
// "always" centers it, "on-overflow" centers it when the view has to scroll.
function follow(offset, col, viewWidth, gaps, mode) {
    const from = isNaN(offset) ? -gaps : offset;
    if (!col)
        return from;
    const centered = col.x + col.width / 2 - viewWidth / 2;
    if (mode === "always")
        return centered;
    const outLeft = col.x - gaps < from;
    const outRight = col.x + col.width + gaps > from + viewWidth;
    if (!outLeft && !outRight)
        return from;
    if (col.width + 2 * gaps > viewWidth)
        return col.x - gaps;
    // shortcut: niri centers on overflow only when the column cannot sit beside the previously focused one; track that column if the desk must match exactly.
    if (mode === "on-overflow")
        return centered;
    return outLeft ? col.x - gaps : col.x + col.width + gaps - viewWidth;
}

function gapsFromDrag(from, dx, scale) {
    const v = Math.round((from - dx / scale * 0.5) / 2) * 2;
    return Math.max(GAPS.from, Math.min(GAPS.to, v));
}

function stepGaps(from, dir) {
    return Math.max(GAPS.from, Math.min(GAPS.to, from + 2 * dir));
}

function stepWidth(from, dir) {
    const near = WIDTH_PRESETS.reduce((best, p, i) => Math.abs(p - from) < Math.abs(WIDTH_PRESETS[best] - from) ? i : best, 0);
    return WIDTH_PRESETS[Math.max(0, Math.min(WIDTH_PRESETS.length - 1, near + dir))];
}

function fractionFromDrag(from, dx, width, gap) {
    const f = (from * (width - gap) + dx) / (width - gap);
    return WIDTH_PRESETS.reduce((best, p) => Math.abs(p - f) < Math.abs(best - f) ? p : best);
}

// Rules a window can get from the desk menu; "Open on" only makes sense with several screens.
function windowMenu(outputNames) {
    const names = (outputNames || []).slice().sort();
    const onOutput = names.length > 1 ? names.map(n => ({ id: "output", icon: "monitor", output: n, actions: { openOnOutput: n }, kdl: "open-on-output \"" + n + "\"" })) : [];
    return [{ id: "floating", icon: "picture_in_picture", actions: { openFloating: true }, kdl: "open-floating true" }].concat(onOutput, [
        { id: "fullscreen", icon: "fullscreen", actions: { openFullscreen: true }, kdl: "open-fullscreen true" },
        { id: "blockOut", icon: "visibility_off", actions: { blockOutFrom: "screencast" }, kdl: "block-out-from \"screencast\"" }
    ]);
}

// win.title is already cut to its stem; crit comes from rules.js criteria(), and empty criteria would make niri apply the rule to every window.
function menuRule(win, item, crit) {
    if (!crit || (!crit.appId && !crit.title))
        return null;
    return { name: win.appId || win.title, matchCriteria: crit, actions: item.actions, enabled: true };
}
