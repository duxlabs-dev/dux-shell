.pragma library

// DMS reads these keys itself (Services/NiriWorkspaceActions.qml); niri never sees them.
var defaults = { "close.askFrom": 3, "close.neverAsk": false };
var stored = { "close.askFrom": "page", "close.neverAsk": "page" };
var search = [
    { key: "close.askFrom", title: "Close a whole workspace", words: ["close", "workspace", "windows", "all", "shortcut", "confirm"] },
    { key: "close.neverAsk", title: "Never ask before closing", words: ["never", "ask", "confirm"] }
];

function toKdl(state) {
    return [];
}

// 0 always asks; "never ask" wins over the threshold.
function needsConfirm(state, count) {
    if (state["close.neverAsk"])
        return false;
    const from = state["close.askFrom"];
    return from === 0 || count >= from;
}
