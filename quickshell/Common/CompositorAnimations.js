.pragma library

var PRESETS = ["stock", "dms", "material"];
var GROUPS = ["open", "movement", "workspace", "popups"];
var COMPOSITORS = ["niri", "hyprland", "mango"];

var DURATION_MIN = 100;
var DURATION_MAX = 1000;
var DURATION_STEP = 10;
var BOUNCE_MAX = 50;
var BOUNCE_STEP = 5;
var SLOWDOWN_MIN = 0.2;
var SLOWDOWN_MAX = 3.0;
// Calibrated on M3 Expressive pairing a 0.8/380 spring with a 500 ms bezier
var SPRING_K = 9750;
// Theme.expressiveCurves expressiveEffects
var FADE_CURVE = [0.34, 0.8, 0.34, 1];

// Slider values for a group nobody overrode
var REPRESENTATIVE = {
    niri: {
        stock: {
            open: { duration: 150, bounce: 0 },
            movement: { duration: 340, bounce: 0 },
            workspace: { duration: 310, bounce: 0 },
            popups: { duration: 310, bounce: 40 }
        }
    },
    hyprland: {
        stock: {
            open: { duration: 630, bounce: 20 },
            movement: { duration: 630, bounce: 20 },
            workspace: { duration: 190, bounce: 0 },
            popups: { duration: 400, bounce: 0 }
        }
    },
    mango: {
        stock: {
            open: { duration: 400, bounce: 0 },
            movement: { duration: 500, bounce: 0 },
            workspace: { duration: 350, bounce: 0 }
        }
    }
};

var SHARED_REPRESENTATIVE = {
    dms: {
        open: { duration: 150, bounce: 0 },
        movement: { duration: 470, bounce: 15 },
        workspace: { duration: 430, bounce: 20 },
        popups: { duration: 320, bounce: 35 }
    },
    material: {
        open: { duration: 500, bounce: 20 },
        movement: { duration: 500, bounce: 20 },
        workspace: { duration: 500, bounce: 20 },
        popups: { duration: 350, bounce: 40 }
    }
};

function supports(compositor) {
    return COMPOSITORS.indexOf(compositor) >= 0;
}

// Mango has no duration of its own for fades and layers
function groups(compositor) {
    if (!supports(compositor))
        return [];
    if (compositor === "mango")
        return GROUPS.filter(g => g !== "popups");
    return GROUPS;
}

function normalizePreset(preset) {
    return PRESETS.indexOf(preset) >= 0 ? preset : "dms";
}

function representative(compositor, preset) {
    if (!supports(compositor))
        return {};
    const p = normalizePreset(preset);
    return p === "stock" ? REPRESENTATIVE[compositor].stock : SHARED_REPRESENTATIVE[p];
}

function clamp(v, min, max) {
    return Math.min(max, Math.max(min, v));
}

function isNumber(v) {
    return typeof v === "number" && isFinite(v);
}

function overrideEntry(overrides, group) {
    const o = overrides ? overrides[group] : null;
    if (!o || typeof o !== "object" || Array.isArray(o))
        return null;
    return o;
}

function effective(compositor, preset, overrides) {
    const rep = representative(compositor, preset);
    const out = {};
    for (const group of groups(compositor)) {
        const o = overrideEntry(overrides, group);
        if (!o) {
            out[group] = { duration: rep[group].duration, bounce: rep[group].bounce, overridden: false };
            continue;
        }
        out[group] = {
            duration: isNumber(o.duration) ? clamp(Math.round(o.duration), DURATION_MIN, DURATION_MAX) : rep[group].duration,
            bounce: isNumber(o.bounce) ? clamp(o.bounce, 0, BOUNCE_MAX) : rep[group].bounce,
            overridden: true
        };
    }
    return out;
}

function isCustom(compositor, overrides) {
    return groups(compositor).some(g => overrideEntry(overrides, g) !== null);
}

function setOverride(compositor, preset, overrides, group, field, value) {
    const out = Object.assign({}, overrides || {});
    if (groups(compositor).indexOf(group) < 0 || (field !== "duration" && field !== "bounce"))
        return out;
    const seed = effective(compositor, preset, overrides)[group];
    out[group] = { duration: seed.duration, bounce: seed.bounce };
    out[group][field] = value;
    return out;
}

function clearOverride(overrides, group) {
    const out = Object.assign({}, overrides || {});
    delete out[group];
    return out;
}

function stiffnessFor(durationMs) {
    return Math.round(Math.pow(SPRING_K / durationMs, 2));
}

// Lifts y1 of M3's default spatial family until its overshoot matches a spring with damping 1 - bounce
function bounceCurve(bounce) {
    if (!(bounce > 0))
        return [0.38, 1, 0.22, 1];
    const zeta = 1 - bounce / 100;
    const target = Math.exp(-Math.PI * zeta / Math.sqrt(1 - zeta * zeta));
    let lo = 0;
    let hi = 2;
    for (let i = 0; i < 40; i++) {
        const s = (lo + hi) / 2;
        if (4 * s * s * s / ((3 * s + 1) * (3 * s + 1)) < target)
            lo = s;
        else
            hi = s;
    }
    return [0.38, Math.round((1 + (lo + hi) / 2) * 100) / 100, 0.22, 1];
}

function slowdownOf(settings) {
    const v = settings.compositorAnimationSlowdown;
    if (!isNumber(v))
        return 1.0;
    return Math.round(clamp(v, SLOWDOWN_MIN, SLOWDOWN_MAX) * 100) / 100;
}

function num(v, decimals) {
    const f = Math.pow(10, decimals);
    return String(Math.round(v * f) / f);
}

function overriddenGroups(compositor, preset, overrides) {
    const eff = effective(compositor, preset, overrides);
    const out = {};
    for (const group in eff) {
        if (eff[group].overridden)
            out[group] = eff[group];
    }
    return out;
}

var NIRI_NODES = ["workspace-switch", "window-open", "window-close", "horizontal-view-movement", "window-movement", "window-resize", "config-notification-open-close", "exit-confirmation-open-close", "screenshot-ui-open", "overview-open-close", "recent-windows-close"];

var NIRI_GROUP_NODES = {
    open: ["window-open", "window-close"],
    movement: ["horizontal-view-movement", "window-movement", "window-resize"],
    workspace: ["workspace-switch", "overview-open-close"],
    popups: ["config-notification-open-close", "exit-confirmation-open-close", "screenshot-ui-open", "recent-windows-close"]
};

// Opacity is clamped by niri, so a bouncy spring only makes these fades look late
var NIRI_FADE_NODES = ["window-close", "screenshot-ui-open", "recent-windows-close"];

var NIRI_EPSILON = {
    "workspace-switch": "0.0001",
    "window-open": "0.0001",
    "window-close": "0.0001",
    "horizontal-view-movement": "0.0001",
    "window-movement": "0.0001",
    "window-resize": "0.0001",
    "config-notification-open-close": "0.001",
    "exit-confirmation-open-close": "0.01",
    "screenshot-ui-open": "0.001",
    "overview-open-close": "0.0001",
    "recent-windows-close": "0.001"
};

function spring(damping, stiffness, epsilon) {
    return {
        damping: damping,
        stiffness: stiffness,
        epsilon: epsilon
    };
}

function eased(durationMs, curve) {
    return {
        durationMs: durationMs,
        curve: curve
    };
}

// Damping and epsilon stay strings: the dms output must match core's embedded file byte for byte
var NIRI_PRESETS = {
    stock: {
        "workspace-switch": spring("1.0", 1000, "0.0001"),
        "window-open": eased(150, "ease-out-expo"),
        "window-close": eased(150, "ease-out-quad"),
        "horizontal-view-movement": spring("1.0", 800, "0.0001"),
        "window-movement": spring("1.0", 800, "0.0001"),
        "window-resize": spring("1.0", 800, "0.0001"),
        "config-notification-open-close": spring("0.6", 1000, "0.001"),
        "exit-confirmation-open-close": spring("0.6", 500, "0.01"),
        "screenshot-ui-open": eased(200, "ease-out-quad"),
        "overview-open-close": spring("1.0", 800, "0.0001"),
        "recent-windows-close": spring("1.0", 800, "0.001")
    },
    dms: {
        "workspace-switch": spring("0.80", 523, "0.0001"),
        "window-open": eased(150, "ease-out-expo"),
        "window-close": eased(150, "ease-out-quad"),
        "horizontal-view-movement": spring("0.85", 423, "0.0001"),
        "window-movement": spring("0.75", 323, "0.0001"),
        "window-resize": spring("0.85", 423, "0.0001"),
        "config-notification-open-close": spring("0.65", 923, "0.001"),
        "exit-confirmation-open-close": spring("0.6", 500, "0.01"),
        "screenshot-ui-open": eased(200, "ease-out-quad"),
        "overview-open-close": spring("0.85", 800, "0.0001"),
        "recent-windows-close": spring("1.0", 800, "0.001")
    },
    // M3 Expressive: default spatial windows, slow spatial overview, fast spatial popups, effects fades
    material: {
        "workspace-switch": spring("0.8", 380, "0.0001"),
        "window-open": spring("0.8", 380, "0.0001"),
        "window-close": spring("0.8", 380, "0.0001"),
        "horizontal-view-movement": spring("0.8", 380, "0.0001"),
        "window-movement": spring("0.8", 380, "0.0001"),
        "window-resize": spring("0.8", 380, "0.0001"),
        "config-notification-open-close": spring("0.6", 800, "0.001"),
        "exit-confirmation-open-close": spring("0.6", 800, "0.001"),
        "screenshot-ui-open": spring("1.0", 1600, "0.001"),
        "overview-open-close": spring("0.8", 200, "0.0001"),
        "recent-windows-close": spring("1.0", 1600, "0.001")
    }
};

function formatFloat(v) {
    const s = num(v, 2);
    return s.indexOf(".") >= 0 ? s : s + ".0";
}

function generateNiri(preset, overrides, slowdown) {
    const nodes = Object.assign({}, NIRI_PRESETS[preset]);
    const custom = overriddenGroups("niri", preset, overrides);
    for (const group in custom) {
        for (const node of NIRI_GROUP_NODES[group]) {
            const damping = NIRI_FADE_NODES.indexOf(node) >= 0 ? "1.0" : formatFloat(1 - custom[group].bounce / 100);
            nodes[node] = spring(damping, stiffnessFor(custom[group].duration), NIRI_EPSILON[node]);
        }
    }

    // niri keeps an earlier `off` until a later `on`, and an earlier slowdown unless one is set here
    let out = "// ! DO NOT EDIT !\n// ! AUTO-GENERATED BY DMS !\n// ! CHANGES WILL BE OVERWRITTEN !\n// ! PLACE YOUR CUSTOM CONFIGURATION ELSEWHERE !\n\nanimations {\n    on\n    slowdown " + formatFloat(slowdown) + "\n";
    for (const name of NIRI_NODES) {
        const n = nodes[name];
        out += "    " + name + " {\n";
        if (n.curve)
            out += "        duration-ms " + n.durationMs + "\n        curve \"" + n.curve + "\"\n";
        else
            out += "        spring damping-ratio=" + n.damping + " stiffness=" + n.stiffness + " epsilon=" + n.epsilon + "\n";
        out += "    }\n";
    }
    return out + "}\n";
}

// Every leaf is written resolved, so the fragment beats any leaf set earlier in hyprland.lua

var HYPR_NODES = ["global", "windows", "windowsIn", "windowsOut", "windowsMove", "layers", "layersIn", "layersOut", "fade", "fadeIn", "fadeOut", "fadeSwitch", "fadeShadow", "fadeGlow", "fadeDim", "fadeDpms", "fadeLayers", "fadeLayersIn", "fadeLayersOut", "fadePopups", "fadePopupsIn", "fadePopupsOut", "border", "workspaces", "workspacesIn", "workspacesOut", "specialWorkspace", "specialWorkspaceIn", "specialWorkspaceOut", "zoomFactor", "monitorAdded"];

var HYPR_PARENT = {
    windows: "global",
    windowsIn: "windows",
    windowsOut: "windows",
    windowsMove: "windows",
    layers: "global",
    layersIn: "layers",
    layersOut: "layers",
    fade: "global",
    fadeIn: "fade",
    fadeOut: "fade",
    fadeSwitch: "fade",
    fadeShadow: "fade",
    fadeGlow: "fade",
    fadeDim: "fade",
    fadeDpms: "fade",
    fadeLayers: "fade",
    fadeLayersIn: "fadeLayers",
    fadeLayersOut: "fadeLayers",
    fadePopups: "fade",
    fadePopupsIn: "fadePopups",
    fadePopupsOut: "fadePopups",
    border: "global",
    workspaces: "global",
    workspacesIn: "workspaces",
    workspacesOut: "workspaces",
    specialWorkspace: "workspaces",
    specialWorkspaceIn: "specialWorkspace",
    specialWorkspaceOut: "specialWorkspace",
    zoomFactor: "global",
    monitorAdded: "global"
};

var HYPR_GROUP_NODES = {
    open: ["windows", "windowsIn", "windowsOut", "fadeIn", "fadeOut"],
    movement: ["windowsMove"],
    workspace: ["workspaces", "workspacesIn", "workspacesOut", "specialWorkspace", "specialWorkspaceIn", "specialWorkspaceOut"],
    popups: ["layers", "layersIn", "layersOut", "fade", "fadeSwitch", "fadeShadow", "fadeGlow", "fadeDim", "fadeDpms", "fadeLayers", "fadeLayersIn", "fadeLayersOut", "fadePopups", "fadePopupsIn", "fadePopupsOut", "border"]
};

// Only leaves Hyprland animates with; parents like windows or layers just pass values down
var HYPR_BOUNCY = ["windowsIn", "windowsMove", "layersIn", "workspacesIn", "workspacesOut", "specialWorkspaceIn", "specialWorkspaceOut"];

function leaf(ms, curve, style) {
    return {
        ms: ms,
        curve: curve,
        style: style || ""
    };
}

// Sparse tables, resolved through HYPR_PARENT like Hyprland's own inheritance
var HYPR_PRESETS = {
    // Upstream's example config, which Hyprland writes for a user without one; spring constants from 0.57
    stock: {
        curves: {
            default: [0, 0.75, 0.15, 1],
            easeOutQuint: [0.23, 1, 0.32, 1],
            linear: [0, 0, 1, 1],
            almostLinear: [0.5, 0.5, 0.75, 1],
            quick: [0.15, 0, 0.1, 1],
            easy: { stiffness: 238.1191, damping: 24.21279333 }
        },
        nodes: {
            global: leaf(1000, "default"),
            border: leaf(539, "easeOutQuint"),
            windows: leaf(479, "easy"),
            windowsIn: leaf(410, "easy", "popin 87%"),
            windowsOut: leaf(149, "linear", "popin 87%"),
            fadeIn: leaf(173, "almostLinear"),
            fadeOut: leaf(146, "almostLinear"),
            fade: leaf(303, "quick"),
            layers: leaf(381, "easeOutQuint"),
            layersIn: leaf(400, "easeOutQuint", "fade"),
            layersOut: leaf(150, "linear", "fade"),
            fadeLayersIn: leaf(179, "almostLinear"),
            fadeLayersOut: leaf(139, "almostLinear"),
            workspaces: leaf(194, "almostLinear", "fade"),
            workspacesIn: leaf(121, "almostLinear", "fade"),
            workspacesOut: leaf(194, "almostLinear", "fade"),
            zoomFactor: leaf(700, "quick")
        }
    },
    dms: {
        curves: {
            fade: FADE_CURVE,
            open: bounceCurve(0),
            movement: bounceCurve(15),
            workspace: bounceCurve(20),
            popups: bounceCurve(35)
        },
        nodes: {
            global: leaf(300, "fade"),
            windows: leaf(150, "open"),
            windowsIn: leaf(150, "open", "popin 80%"),
            windowsOut: leaf(150, "fade", "popin 80%"),
            windowsMove: leaf(470, "movement"),
            layers: leaf(320, "popups"),
            layersIn: leaf(320, "popups", "popin 90%"),
            layersOut: leaf(150, "fade", "popin 90%"),
            fade: leaf(150, "fade"),
            border: leaf(200, "fade"),
            workspaces: leaf(430, "workspace")
        }
    },
    // Theme.expressiveCurves by surface size; the special workspace is the full-screen overlay, so slow spatial
    material: {
        curves: {
            fade: FADE_CURVE,
            fastFade: [0.31, 0.94, 0.34, 1],
            open: [0.38, 1.21, 0.22, 1],
            movement: [0.38, 1.21, 0.22, 1],
            workspace: [0.38, 1.21, 0.22, 1],
            slow: [0.39, 1.29, 0.35, 0.98],
            popups: [0.42, 1.67, 0.21, 0.9]
        },
        nodes: {
            global: leaf(300, "fade"),
            windows: leaf(500, "open"),
            windowsIn: leaf(500, "open", "popin 80%"),
            windowsOut: leaf(200, "fade", "popin 80%"),
            windowsMove: leaf(500, "movement"),
            layers: leaf(350, "popups"),
            layersIn: leaf(350, "popups", "popin 90%"),
            layersOut: leaf(150, "fastFade", "popin 90%"),
            fade: leaf(200, "fade"),
            fadeOut: leaf(150, "fastFade"),
            fadeLayersOut: leaf(150, "fastFade"),
            fadePopupsOut: leaf(150, "fastFade"),
            border: leaf(200, "fade"),
            workspaces: leaf(500, "workspace"),
            specialWorkspace: leaf(650, "slow")
        }
    }
};

function generateHyprland(preset, overrides, slowdown) {
    const table = HYPR_PRESETS[preset];
    const curves = Object.assign({}, table.curves);
    const nodes = {};
    for (const name of HYPR_NODES) {
        let p = name;
        while (!table.nodes[p])
            p = HYPR_PARENT[p];
        nodes[name] = Object.assign({}, table.nodes[p]);
    }

    // Beziers scale to keep the preset's in/out ratios; a spring ignores ms, so it takes the duration
    const rep = representative("hyprland", preset);
    const custom = overriddenGroups("hyprland", preset, overrides);
    for (const group in custom) {
        const d = custom[group].duration;
        curves[group] = bounceCurve(custom[group].bounce);
        curves.fade = curves.fade || FADE_CURVE;
        for (const name of HYPR_GROUP_NODES[group]) {
            const n = nodes[name];
            n.ms = Array.isArray(curves[n.curve]) ? clamp(Math.round(n.ms * d / rep[group].duration), DURATION_MIN, DURATION_MAX) : d;
            n.curve = HYPR_BOUNCY.indexOf(name) >= 0 && n.style.indexOf("fade") !== 0 ? group : "fade";
        }
    }

    // Leaves ignore an earlier animations.enabled = false, so the fragment turns it back on
    let out = "-- Auto-generated by DMS — do not edit manually\n\nhl.config({ animations = { enabled = true } })\n\n";
    // Prefixed so the fragment never redefines a curve the user's own lines use
    const used = [];
    for (const name of HYPR_NODES) {
        if (used.indexOf(nodes[name].curve) < 0)
            used.push(nodes[name].curve);
    }
    for (const c of used) {
        const v = curves[c];
        if (Array.isArray(v))
            out += "hl.curve(\"dms_" + c + "\", { type = \"bezier\", points = { { " + num(v[0], 2) + ", " + num(v[1], 2) + " }, { " + num(v[2], 2) + ", " + num(v[3], 2) + " } } })\n";
        else
            out += "hl.curve(\"dms_" + c + "\", { type = \"spring\", mass = 1, stiffness = " + num(v.stiffness / (slowdown * slowdown), 4) + ", dampening = " + num(v.damping / slowdown, 4) + " })\n";
    }
    out += "\n";

    // Springs ignore speed but Hyprland still requires it; 0.55 and 0.56 accept only `dampening`, 0.57 keeps it as an alias of `damping`
    for (const name of HYPR_NODES) {
        const n = nodes[name];
        const ms = clamp(Math.round(n.ms * slowdown), 10, 10000);
        const kind = Array.isArray(curves[n.curve]) ? "bezier" : "spring";
        out += "hl.animation({ leaf = \"" + name + "\", enabled = true, speed = " + num(ms / 100, 2) + ", " + kind + " = \"dms_" + n.curve + "\"" + (n.style ? ", style = \"" + n.style + "\"" : "") + " })\n";
    }
    // Gradient-rotation loops are off upstream and redraw every frame while on; 0.55 rejects the 0.56 leaves
    out += "hl.animation({ leaf = \"borderangle\", enabled = false })\n";
    out += "local minor = tonumber(hl.version():match(\"^0%.(%d+)\"))\nif not minor or minor >= 56 then\n";
    out += "    hl.animation({ leaf = \"shadowangle\", enabled = false })\n    hl.animation({ leaf = \"glowangle\", enabled = false })\nend\n";
    return out;
}

// Mango lines must start at column 0; fade curves stay flat because fade-in opacity is not clamped

var MANGO_KEYS = ["animations", "layer_animations", "animation_type_open", "animation_type_close", "animation_fade_in", "animation_fade_out", "tag_animation_direction", "zoom_initial_ratio", "zoom_end_ratio", "fade_in_begin_opacity", "fade_out_begin_opacity", "animation_duration_move", "animation_duration_open", "animation_duration_tag", "animation_duration_close", "animation_duration_focus", "animation_curve_open", "animation_curve_move", "animation_curve_tag", "animation_curve_close", "animation_curve_focus", "animation_curve_opacity_fade_out", "animation_curve_opacity_fade_in"];

var MANGO_DURATIONS = ["animation_duration_move", "animation_duration_open", "animation_duration_tag", "animation_duration_close", "animation_duration_focus"];

var MANGO_PRESETS = {
    // Upstream's example config, installed to /etc/mango and used by a fresh user
    stock: {
        animations: 1,
        layer_animations: 1,
        animation_type_open: "slide",
        animation_type_close: "slide",
        animation_fade_in: 1,
        animation_fade_out: 1,
        tag_animation_direction: 1,
        zoom_initial_ratio: 0.4,
        zoom_end_ratio: 0.8,
        fade_in_begin_opacity: 0.5,
        fade_out_begin_opacity: 0.8,
        animation_duration_move: 500,
        animation_duration_open: 400,
        animation_duration_tag: 350,
        animation_duration_close: 800,
        animation_duration_focus: 0,
        animation_curve_open: [0.46, 1, 0.29, 1],
        animation_curve_move: [0.46, 1, 0.29, 1],
        animation_curve_tag: [0.46, 1, 0.29, 1],
        animation_curve_close: [0.08, 0.92, 0, 1],
        animation_curve_focus: [0.46, 1, 0.29, 1],
        animation_curve_opacity_fade_out: [0.5, 0.5, 0.5, 0.5],
        animation_curve_opacity_fade_in: [0.46, 1, 0.29, 1]
    },
    dms: {
        animations: 1,
        layer_animations: 0,
        animation_type_open: "zoom",
        animation_type_close: "zoom",
        animation_fade_in: 1,
        animation_fade_out: 1,
        tag_animation_direction: 1,
        zoom_initial_ratio: 0.8,
        zoom_end_ratio: 0.8,
        fade_in_begin_opacity: 0,
        fade_out_begin_opacity: 1,
        animation_duration_move: 470,
        animation_duration_open: 150,
        animation_duration_tag: 430,
        animation_duration_close: 150,
        animation_duration_focus: 0,
        animation_curve_open: bounceCurve(0),
        animation_curve_move: bounceCurve(15),
        animation_curve_tag: bounceCurve(20),
        animation_curve_close: FADE_CURVE,
        animation_curve_focus: FADE_CURVE,
        animation_curve_opacity_fade_out: FADE_CURVE,
        animation_curve_opacity_fade_in: FADE_CURVE
    },
    material: {
        animations: 1,
        layer_animations: 0,
        animation_type_open: "zoom",
        animation_type_close: "zoom",
        animation_fade_in: 1,
        animation_fade_out: 1,
        tag_animation_direction: 1,
        zoom_initial_ratio: 0.8,
        zoom_end_ratio: 0.8,
        fade_in_begin_opacity: 0,
        fade_out_begin_opacity: 1,
        animation_duration_move: 500,
        animation_duration_open: 500,
        animation_duration_tag: 500,
        animation_duration_close: 200,
        animation_duration_focus: 0,
        animation_curve_open: [0.38, 1.21, 0.22, 1],
        animation_curve_move: [0.38, 1.21, 0.22, 1],
        animation_curve_tag: [0.38, 1.21, 0.22, 1],
        animation_curve_close: FADE_CURVE,
        animation_curve_focus: FADE_CURVE,
        animation_curve_opacity_fade_out: [0.31, 0.94, 0.34, 1],
        animation_curve_opacity_fade_in: FADE_CURVE
    }
};

var MANGO_GROUP_KEYS = {
    open: { durations: ["animation_duration_open", "animation_duration_close"], curve: "animation_curve_open" },
    movement: { durations: ["animation_duration_move"], curve: "animation_curve_move" },
    workspace: { durations: ["animation_duration_tag"], curve: "animation_curve_tag" }
};

function generateMango(preset, overrides, slowdown) {
    const values = Object.assign({}, MANGO_PRESETS[preset]);
    const rep = representative("mango", preset);
    const custom = overriddenGroups("mango", preset, overrides);
    for (const group in custom) {
        const keys = MANGO_GROUP_KEYS[group];
        for (const key of keys.durations)
            values[key] = clamp(Math.round(values[key] * custom[group].duration / rep[group].duration), DURATION_MIN, DURATION_MAX);
        values[keys.curve] = bounceCurve(custom[group].bounce);
    }
    for (const key of MANGO_DURATIONS)
        values[key] = clamp(Math.round(values[key] * slowdown), 0, 50000);

    let out = "# Auto-generated by DMS - do not edit manually\n";
    for (const key of MANGO_KEYS) {
        const v = values[key];
        let text = v;
        if (Array.isArray(v))
            text = v.map(x => num(x, 2)).join(",");
        else if (typeof v === "number")
            text = num(v, 2);
        out += key + "=" + text + "\n";
    }
    return out;
}

// A control is live only if moving it changes the written config
function controls(compositor, preset) {
    const p = normalizePreset(preset);
    const rep = representative(compositor, p);
    const out = {};
    for (const group of groups(compositor)) {
        const probe = (duration, bounce) => {
            const o = {};
            o[group] = { duration: duration, bounce: bounce };
            return generate(compositor, { compositorAnimationPreset: p, compositorAnimationOverrides: o });
        };
        out[group] = {
            duration: probe(DURATION_MIN, rep[group].bounce) !== probe(DURATION_MAX, rep[group].bounce),
            bounce: probe(rep[group].duration, 0) !== probe(rep[group].duration, BOUNCE_MAX)
        };
    }
    return out;
}

function generate(compositor, settings) {
    if (!supports(compositor))
        return "";
    const s = settings || {};
    const preset = normalizePreset(s.compositorAnimationPreset);
    const overrides = s.compositorAnimationOverrides;
    const slowdown = slowdownOf(s);
    if (compositor === "niri")
        return generateNiri(preset, overrides, slowdown);
    if (compositor === "hyprland")
        return generateHyprland(preset, overrides, slowdown);
    return generateMango(preset, overrides, slowdown);
}
