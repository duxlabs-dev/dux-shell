.pragma library

// Only sent when set: a shell newer than the dms binary is supported, and an older binary
// exits on an unknown flag (see Theme.setDesiredTheme).
function args(overrides) {
    const keys = Object.keys(overrides || {}).filter(k => overrides[k] > 0).sort();
    if (keys.length === 0)
        return [];
    const set = {};
    keys.forEach(k => set[k] = overrides[k]);
    return ["--contrast-overrides", JSON.stringify(set)];
}

// A copy, so assigning it to the setting registers as a change; ratio 0 removes the override.
function withOverride(overrides, key, ratio) {
    const next = Object.assign({}, overrides || {});
    if (ratio > 0)
        next[key] = ratio;
    else
        delete next[key];
    return next;
}

// "dank16term.color5" -> {group: "terminal", ansi: "5"}; roles keep their Material name.
function describe(key) {
    const dot = key.indexOf(".");
    const ns = key.slice(0, dot);
    const name = key.slice(dot + 1);
    if (ns === "colors")
        return {
            "group": "apps",
            "name": name
        };
    return {
        "group": ns === "dank16term" ? "terminal" : "editors",
        "ansi": name.replace("color", "")
    };
}

// "default" is stored only when it is not the mode's variant. Empty for a dms-colors.json
// written before the audit was recorded.
function rows(colors, terminalsDark) {
    const audit = colors && colors.contrast;
    let list = audit && (audit.default || audit[colors.mode]);
    if (!list)
        return [];
    if (terminalsDark && audit.dark) {
        const dark = {};
        audit.dark.filter(r => r.key.startsWith("dank16term.")).forEach(r => dark[r.key] = r);
        list = list.map(r => dark[r.key] || r);
    }
    return sortByOriginal(list);
}

// Lowest theme ratio first. Keyed on the theme's own ratio, so changing a color never moves it.
function sortByOriginal(results) {
    return results.map((r, i) => ({
                "r": r,
                "i": i
            })).sort((a, b) => (a.r.original - b.r.original) || (a.i - b.i)).map(x => x.r);
}

// Two decimals: the bar is 4.5, and 4.47 must not read as 4.5.
function formatRatio(r) {
    return r.toFixed(2) + ":1";
}

// "own" when the user's setting for this color moved it, "cause" when a changed color it is drawn
// on did (result.cause names it), "" when it is the theme's.
function change(result) {
    if (result.cause)
        return "cause";
    return Math.abs(result.ratio - result.original) >= 0.005 ? "own" : "";
}
