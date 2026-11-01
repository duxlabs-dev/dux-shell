.pragma library

var corners = ["top-left", "top-right", "bottom-left", "bottom-right"];

// The same commands as the default binds, so a corner behaves like the key. Overview is niri's own corner.
var commands = {
    "notifications": ["dms", "ipc", "call", "notifications", "toggle"],
    "launcher": ["dms", "ipc", "call", "spotlight", "toggle"],
    "controlCenter": ["dms", "ipc", "call", "control-center", "toggle"],
    "screenshot": ["dms", "screenshot"]
};

var defaults = {
    "corners.top-left": "overview",
    "corners.top-right": "none",
    "corners.bottom-left": "none",
    "corners.bottom-right": "none",
    // DMS actions of the screens that override the global corners, by niri output identifier
    "corners.screens": {}
};

var stored = {
    "corners.top-left": "page",
    "corners.top-right": "page",
    "corners.bottom-left": "page",
    "corners.bottom-right": "page",
    "corners.screens": "page"
};

var search = [{
        key: "corners.top-left",
        title: "Hot corners",
        words: ["hot corners", "corner", "overview", "notifications", "launcher", "control center", "screenshot", "capture"]
    }];

function globalCorners(state) {
    const out = {};
    for (const c of corners)
        out[c] = state["corners." + c] ?? "none";
    return out;
}

// niri lights top-left when no corner is listed, so a list without any corner must say off.
function toKdl(state) {
    const overview = corners.filter(c => state["corners." + c] === "overview");
    if (overview.length === 1 && overview[0] === "top-left")
        return [];
    return [{
            block: "gestures.hot-corners",
            lines: overview.length ? overview : ["off"]
        }];
}

// DMS writes `{corners: []}` for « inherit », niri reads it the same way.
function overrides(niriOverride) {
    return !!niriOverride && (niriOverride.off === true || (niriOverride.corners || []).length > 0);
}

// niri replaces the global corners of a screen that has its own, so DMS does the same.
function screenCorners(state, niriOverride, own) {
    if (!overrides(niriOverride))
        return globalCorners(state);
    const out = {};
    for (const c of corners)
        out[c] = !niriOverride.off && niriOverride.corners.includes(c) ? "overview" : (own?.[c] ?? "none");
    return out;
}

function niriOverrideOf(actions) {
    const overview = corners.filter(c => actions[c] === "overview");
    return overview.length ? {
        "corners": overview
    } : {
        "off": true
    };
}

function ownOf(actions) {
    const out = {};
    for (const c of corners) {
        if (commands[actions[c]])
            out[c] = actions[c];
    }
    return out;
}

// Corner names only: a surface is kept while its corner runs any DMS action, and reads the action when hovered.
function zones(actions) {
    return corners.filter(c => commands[actions[c]]);
}

function withCorners(niri, hotCorners) {
    const out = Object.assign({}, niri);
    if (hotCorners)
        out.hotCorners = hotCorners;
    else
        delete out.hotCorners;
    return out;
}

function settingsWithCorners(settings, id, hotCorners) {
    const out = Object.assign({}, settings);
    out[id] = withCorners(out[id], hotCorners);
    return out;
}

// A Displays profile keeps each output's niri settings under `niri`; an output it does not list stays out.
function profileWithCorners(entry, id, hotCorners) {
    if (!entry.outputs?.[id])
        return entry;
    const outputs = Object.assign({}, entry.outputs);
    outputs[id] = Object.assign({}, outputs[id], {
        "niri": withCorners(outputs[id].niri, hotCorners)
    });
    return Object.assign({}, entry, {
        "outputs": outputs
    });
}
