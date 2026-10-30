.pragma library

// What a script (over IPC) or a plugin hands the island, checked and shaped; its own rules are in IslandActivities.js.

const accents = ["primary", "secondary", "tertiary", "error", "warning", "info", "success"];
const maxActions = 3;

function faceText(value) {
    if (typeof value === "string")
        return value;
    return typeof value === "number" && isFinite(value) ? String(value) : "";
}

// The shell-drawn face, for scripts and for plugins that leave compactContent unset.
function readyFace(data) {
    const d = data && typeof data === "object" ? data : {};
    const progress = Number(d.progress);
    const hasProgress = d.progress !== undefined && d.progress !== null && d.progress !== "" && isFinite(progress);
    const actions = (Array.isArray(d.actions) ? d.actions : []).filter(a => a && typeof a === "object" && faceText(a.id) && faceText(a.label)).slice(0, maxActions).map(a => ({
                "id": faceText(a.id),
                "label": faceText(a.label)
            }));
    return {
        "icon": faceText(d.icon),
        "title": faceText(d.title),
        "text": faceText(d.text),
        "progress": hasProgress ? Math.max(0, Math.min(1, progress)) : -1,
        "actions": actions,
        "accent": accents.indexOf(d.accent) === -1 ? "primary" : d.accent
    };
}

// Enter on a focused sheet runs the first action.
function primaryAction(face) {
    return face?.actions?.[0]?.id ?? "";
}

// IPC limits, so a script cannot flood the island nor pass for another source.
const maxIpcData = 16384;
const maxScripts = 8;
const maxScriptName = 64;
const maxNotifyApp = 128;
// A script's source and tokens start with it (requestScript, ipcOwns); var, as the service reads it.
var scriptPrefix = "script:";

// IPC hands strings; anything but a JSON object refuses the call instead of showing an empty face.
function parseIpcData(json) {
    if (json === undefined || json === null || String(json).trim() === "")
        return {};
    if (String(json).length > maxIpcData)
        return null;
    try {
        const value = JSON.parse(json);
        return value && typeof value === "object" && !Array.isArray(value) ? value : null;
    } catch (e) {
        return null;
    }
}

// Only a script's own activity ("script:<name>:<n>") answers over IPC, never a plugin's or the shell's.
function ipcOwns(token) {
    return typeof token === "string" && token.startsWith(scriptPrefix) && /^[^:]+:\d+$/.test(token.slice(scriptPrefix.length));
}

// A token is "<source>:<n>": a plugin id with a colon could pass for a script's or the shell's.
function pluginIdAllowed(id) {
    return typeof id === "string" && id !== "" && id.indexOf(":") === -1;
}

// The IPC answer refusing a script's activity, or "". liveNames: scripts showing one now; asking again replaces it.
function scriptRefusal(name, liveNames, notifyApp) {
    if (!name || name.length > maxScriptName || name.indexOf(":") !== -1)
        return "ISLAND_ACTIVITY_BAD_NAME";
    if (typeof notifyApp === "string" && notifyApp.trim().length > maxNotifyApp)
        return "ISLAND_ACTIVITY_BAD_NOTIFY_APP";
    return liveNames.indexOf(name) !== -1 || liveNames.length < maxScripts ? "" : "ISLAND_ACTIVITY_TOO_MANY";
}

function clampSize(value, min, max, fallback) {
    const n = Number(value);
    if (value === undefined || value === null || !isFinite(n))
        return fallback;
    return Math.max(min, Math.min(max, Math.ceil(n)));
}

// [min, max, default] for each size a plugin face may ask for.
const faceBounds = {
    "compactLength": [120, 360, 240],
    "expandedWidth": [280, 736, 460],
    "expandedHeight": [120, 480, 200]
};

function faceSize(face, key) {
    const b = faceBounds[key];
    return clampSize(face ? face[key] : undefined, b[0], b[1], b[2]);
}

// 0 keeps the shell's size for a system face that does not ask for one.
function systemFaceSize(face, key) {
    return face && face[key] > 0 ? faceSize(face, key) : 0;
}
