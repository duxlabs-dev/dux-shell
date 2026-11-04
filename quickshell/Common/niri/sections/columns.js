.pragma library
.import "../../niriKdl.js" as Kdl

// prefer-no-csd defaults to on: DMS ships it in config.kdl, so "off" is the change worth writing.
var defaults = {
    "columns.centerFocused": "never",
    "columns.centerSingle": false,
    "columns.defaultWidth": 0.5,
    "columns.presetWidths": [0.33333, 0.5, 0.66667],
    "columns.cycleWidth": false,
    "columns.display": "normal",
    "columns.overviewZoom": 0.5,
    "columns.noCsd": true,
    "columns.altTab": true,
    "columns.altTabDelay": 150,
    "columns.altTabPreviewScale": 0.5
};

// Choices of the segmented control; style import reads the same list.
var limits = {
    "columns.centerFocused": ["never", "on-overflow", "always"]
};

var stored = {};
for (const key in defaults)
    stored[key] = "page";

// DMS behaviour written by the existing pipeline, no niri key of its own.
stored["columns.overviewCloseFocus"] = "SettingsData:closeNiriOverviewOnWindowFocus";

var search = [
    { key: "columns.centerFocused", title: "Center the focused column", words: ["center", "focused", "column", "middle"] },
    { key: "columns.centerSingle", title: "Center a lone column", words: ["center", "single", "lone", "alone", "column"] },
    { key: "columns.defaultWidth", title: "New column width", words: ["default", "column", "width", "new", "window", "size"] },
    { key: "columns.presetWidths", title: "Preset widths", words: ["preset", "column", "widths", "cycle"] },
    { key: "columns.cycleWidth", title: "Super+R fills the remaining space", words: ["super", "mod", "r", "fill", "remaining", "space", "width", "restore", "cycle"] },
    { key: "columns.display", title: "New columns", words: ["tabbed", "tabs", "column", "display"] },
    { key: "columns.overviewZoom", title: "Overview zoom", words: ["overview", "zoom", "size"] },
    { key: "columns.overviewCloseFocus", title: "Close on window focus", words: ["overview", "close", "leave", "focus", "window", "launch"] },
    { key: "columns.noCsd", title: "No app title bars", words: ["csd", "client", "decorations", "title", "bars"] },
    { key: "columns.altTab", title: "Alt-Tab switcher", words: ["alt", "tab", "switcher", "recent", "windows"] },
    { key: "columns.altTabDelay", title: "Show Alt-Tab after", words: ["alt", "tab", "delay", "show"] },
    { key: "columns.altTabPreviewScale", title: "Alt-Tab preview size", words: ["alt", "tab", "previews", "thumbnails", "size"] }
];

function num(v) {
    return Number.isInteger(v) ? v.toFixed(1) : String(v);
}

function changed(state, key) {
    return JSON.stringify(state[key]) !== JSON.stringify(defaults[key]);
}

function toKdl(state) {
    const layout = [];
    if (changed(state, "columns.centerFocused"))
        layout.push("center-focused-column " + Kdl.kdlString(state["columns.centerFocused"]));
    if (changed(state, "columns.centerSingle"))
        layout.push(state["columns.centerSingle"] ? "always-center-single-column" : "always-center-single-column false");
    // Always written: config.kdl from dms setup still says 0.5, so the 1/3 default must win at boot.
    layout.push("default-column-width { proportion " + num(state["columns.defaultWidth"]) + "; }");
    const presets = state["columns.presetWidths"] || [];
    if (changed(state, "columns.presetWidths") && presets.length > 0)
        layout.push("preset-column-widths {\n" + presets.map(p => "    proportion " + num(p)).join("\n") + "\n}");
    if (changed(state, "columns.display"))
        layout.push("default-column-display " + Kdl.kdlString(state["columns.display"]));

    const top = [];
    if (changed(state, "columns.noCsd"))
        top.push(state["columns.noCsd"] ? "prefer-no-csd" : "prefer-no-csd false");

    const overview = [];
    if (changed(state, "columns.overviewZoom"))
        overview.push("zoom " + num(state["columns.overviewZoom"]));

    // niri has no switch for the previews, only their size; alttab.kdl from DMS keeps the highlight.
    const recent = [];
    if (state["columns.altTab"] === false)
        recent.push("off");
    if (changed(state, "columns.altTabDelay"))
        recent.push("open-delay-ms " + Math.round(state["columns.altTabDelay"]));
    const previews = [];
    if (changed(state, "columns.altTabPreviewScale"))
        previews.push("max-scale " + num(state["columns.altTabPreviewScale"]));

    return [
        { block: null, lines: top },
        { block: "layout", lines: layout },
        { block: "overview", lines: overview },
        { block: "recent-windows", lines: recent },
        { block: "recent-windows.previews", lines: previews }
    ];
}
