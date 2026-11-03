.pragma library

const ACTIONS = ["dnd", "history", "hints", "settings"];
const ICONS = {
    "dnd": "do_not_disturb_on",
    "history": "history",
    "hints": "info",
    "settings": "settings",
    "remove": "close"
};

function icon(action) {
    return ICONS[action] ?? "add";
}

function isAvailable(action, historyEnabled) {
    return ACTIONS.includes(action) && (action !== "history" || historyEnabled);
}

function choices(current, other, historyEnabled) {
    return ACTIONS.filter(action => action !== current && action !== other && isAvailable(action, historyEnabled));
}
