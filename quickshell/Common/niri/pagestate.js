.pragma library

// Pure state logic of NiriPageService; `sections` is registry.js's list.

// ["page"], ["SettingsData", prop], ["SessionData", prop] or ["NiriService", prop, setter]
function storeOf(sections, key) {
    for (const section of sections) {
        const where = section.stored?.[key];
        if (where)
            return where.split(":");
    }
    return ["page"];
}

// Keys DMS already writes elsewhere stay out, so niri.kdl never sets them twice.
function pageState(sections, page) {
    const state = {};
    for (const section of sections)
        Object.assign(state, section.defaults);
    Object.assign(state, page);
    for (const key in state) {
        if (key.startsWith("custom.") || storeOf(sections, key)[0] !== "page")
            delete state[key];
    }
    return state;
}

function customOf(sections, page) {
    const custom = {};
    for (const section of sections)
        custom[section.id] = page["custom." + section.id] ?? "";
    return custom;
}

// niri only takes literal colours, so theme roles ({secondary: "#rrggbb"}) become hex before toKdl.
function withColors(state, colors) {
    for (const key in state) {
        const hex = colors[state[key]];
        if (key.endsWith("Color") && typeof hex === "string")
            state[key] = hex;
    }
    return state;
}

// niri validate prints a generic "× error loading config" chain, then one "× <reason>" per error with
// the user's config quoted under it: only the first reason is useful, and it quotes nothing.
function refusal(error) {
    const after = (line, mark) => line.slice(line.indexOf(mark) + mark.length).trim();
    const lines = error.replace(/^invalid: /, "").split("\n").map(l => l.trim()).filter(l => l !== "");
    const reason = lines.filter(l => l.includes("× ")).map(l => after(l, "× ")).find(r => r !== "error loading config");
    const chain = lines.filter(l => l.includes("─▶ "));
    return reason ?? (chain.length ? after(chain[chain.length - 1], "─▶ ") : (lines[0] ?? "").replace(/^Error:\s*/, ""));
}
