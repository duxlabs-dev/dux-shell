.pragma library
.import "sections/look.js" as Look
.import "sections/columns.js" as Columns
.import "sections/animations.js" as Animations

// Keys a style may set; names follow the section modules (look.js, columns.js, animations.js).
var styleKeys = ["look.gaps", "look.ringOn", "look.ringWidth", "look.borderOn", "look.radius", "look.shadowOn", "columns.centerFocused", "animations.slowdown"];

// Each section's own limits (slider from/to and min, choices); keys left out are switches.
var limits = Object.assign({}, Look.limits, Columns.limits, Animations.limits);

var NAME_MAX = 40;
// Import reads a file only up to this size.
var TEXT_MAX = 65536;

// The four presets of the validated mockup (a-final.html PRESETS).
var presets = [
    {
        id: "compact",
        values: { "look.gaps": 4, "look.ringOn": true, "look.ringWidth": 2, "look.borderOn": false, "look.radius": 4, "columns.centerFocused": "never", "look.shadowOn": false }
    },
    {
        id: "niri",
        values: { "look.gaps": 16, "look.ringOn": true, "look.ringWidth": 4, "look.borderOn": false, "look.radius": 0, "columns.centerFocused": "never", "look.shadowOn": false }
    },
    {
        id: "comfort",
        values: { "look.gaps": 16, "look.ringOn": true, "look.ringWidth": 4, "look.borderOn": false, "look.radius": 12, "columns.centerFocused": "never", "look.shadowOn": true }
    },
    {
        id: "focus",
        values: { "look.gaps": 24, "look.ringOn": true, "look.ringWidth": 3, "look.borderOn": false, "look.radius": 12, "columns.centerFocused": "always", "look.shadowOn": true }
    }
];

// get: key -> current value (NiriPageService.get); keys no section knows yet are left out.
function snapshot(get) {
    const out = {};
    for (const key of styleKeys) {
        const v = get(key);
        if (v !== undefined && v !== null)
            out[key] = v;
    }
    return out;
}

function matches(values, get) {
    return Object.keys(values).every(key => JSON.stringify(get(key)) === JSON.stringify(values[key]));
}

function exportStyle(name, values) {
    return JSON.stringify({ niriStyle: 1, name: name, values: values }, null, 2) + "\n";
}

function validValue(key, v) {
    const limit = limits[key];
    if (!limit)
        return typeof v === "boolean";
    if (Array.isArray(limit))
        return limit.includes(v);
    return typeof v === "number" && v >= (limit.min ?? limit.from) && v <= limit.to;
}

// Returns {error, name, values}; error is "" when the file is a usable style.
function parseStyle(text) {
    if (typeof text !== "string" || text.length > TEXT_MAX)
        return { error: "file too large", name: "", values: {} };
    let data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return { error: "not JSON", name: "", values: {} };
    }
    if (!data || typeof data !== "object" || Array.isArray(data) || data.niriStyle !== 1)
        return { error: "not a niri style file", name: "", values: {} };
    const values = data.values;
    if (!values || typeof values !== "object" || Array.isArray(values))
        return { error: "no values", name: "", values: {} };
    const keys = Object.keys(values);
    if (!keys.length)
        return { error: "no values", name: "", values: {} };
    for (const key of keys) {
        // The error goes to the log: it names the reason, never text from the file.
        if (!styleKeys.includes(key))
            return { error: "unknown key", name: "", values: {} };
        if (!validValue(key, values[key]))
            return { error: "value out of range", name: "", values: {} };
    }
    const name = typeof data.name === "string" ? data.name.trim().slice(0, NAME_MAX) : "";
    return { error: "", name: name, values: values };
}
