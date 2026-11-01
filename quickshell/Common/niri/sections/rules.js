.pragma library

// Rules are written by the DMS window rules provider (`dms config windowrules`), never by the page.
var defaults = {};
var stored = {};
var search = [
    { key: "rules.pick", title: "Rule from a window", words: ["window rule", "pick", "app-id", "title", "règle", "fenêtre", "choisir"] },
    { key: "rules.list", title: "Window rules", words: ["rules", "list", "edit", "reorder", "règles", "liste", "modifier"] },
    { key: "rules.blockOut", title: "Hide when sharing", words: ["screencast", "share", "block out", "partage", "masquer", "capture"] },
    { key: "rules.dmsFloating", title: "Open DMS windows floating", words: ["floating", "settings window", "flottante", "fenêtres DMS"] }
];

function toKdl() {
    return [];
}

function escapeRegex(text) {
    return String(text ?? "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Titles often end with a changing part ("Inbox · 12 unread"): keep the stable head.
function titleStem(title) {
    const text = String(title ?? "").trim();
    const cut = [" — ", " – ", " - ", " · ", " | "].map(sep => text.indexOf(sep)).filter(i => i > 0);
    return cut.length ? text.slice(0, Math.min(...cut)).trim() : text;
}

// `niri msg --json pick-window` prints the window object, or null when the pick is cancelled.
function parsePicked(output) {
    let win;
    try {
        win = JSON.parse(String(output ?? "").trim());
    } catch (e) {
        return null;
    }
    if (!win || typeof win !== "object")
        return null;
    return { appId: win.app_id || "", title: win.title || "" };
}

function criteria(win, useAppId, useTitle) {
    const out = {};
    if (useAppId && win.appId)
        out.appId = "^" + escapeRegex(win.appId) + "$";
    if (useTitle && titleStem(win.title))
        out.title = escapeRegex(titleStem(win.title));
    return out;
}

// -1 when nothing would be matched on (a rule for every window) or a regex is invalid.
function matchCount(windows, crit) {
    if (!crit.appId && !crit.title)
        return -1;
    let appRe, titleRe;
    try {
        appRe = crit.appId ? new RegExp(crit.appId) : null;
        titleRe = crit.title ? new RegExp(crit.title) : null;
    } catch (e) {
        return -1;
    }
    return (windows || []).filter(w => (!appRe || appRe.test(w.app_id || "")) && (!titleRe || titleRe.test(w.title || ""))).length;
}

function buildRule(win, opts) {
    const actions = {};
    if (opts.workspace)
        actions.openOnWorkspace = opts.workspace;
    if (opts.floating)
        actions.openFloating = true;
    if (opts.blockOut)
        actions.blockOutFrom = "screencast";
    return {
        name: win.appId || titleStem(win.title),
        matchCriteria: criteria(win, opts.useAppId, opts.useTitle),
        actions: actions,
        enabled: true
    };
}
