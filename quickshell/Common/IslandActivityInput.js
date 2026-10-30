.pragma library

// What a script (over IPC) or a plugin hands the island, checked and shaped; its own rules are in IslandActivities.js.

// A bubble reads the same fields as the ready face, plus a very short text ("62 %", "4:59"), cut at maxShortText.
const maxShortText = 6;
function bubbleFace(data) {
    const face = readyFace(data);
    const short = faceText(data && typeof data === "object" ? data.shortText : "");
    return {
        "icon": face.icon,
        "progress": face.progress,
        "text": short.slice(0, maxShortText),
        "accent": face.accent
    };
}

const accents = ["primary", "secondary", "tertiary", "error", "warning", "info", "success"];
const maxActions = 3;

function faceText(value) {
    if (typeof value === "string")
        return value;
    return typeof value === "number" && isFinite(value) ? String(value) : "";
}

// The shell-drawn face (scripts, plugins without compactContent). words: the host's translated names of the state
// accents, as a light theme folds several onto the surface's text tone.
function readyFace(data, words) {
    const d = data && typeof data === "object" ? data : {};
    const progress = Number(d.progress);
    const hasProgress = d.progress !== undefined && d.progress !== null && d.progress !== "" && isFinite(progress);
    const actions = (Array.isArray(d.actions) ? d.actions : []).filter(a => a && typeof a === "object" && faceText(a.id) && faceText(a.label)).slice(0, maxActions).map(a => ({
                "id": faceText(a.id),
                "label": faceText(a.label)
            }));
    const accent = accents.indexOf(d.accent) === -1 ? "primary" : d.accent;
    const state = words?.[accent] ?? "";
    const title = faceText(d.title);
    const text = faceText(d.text);
    return {
        "icon": faceText(d.icon),
        "title": title,
        "text": text,
        "progress": hasProgress ? Math.max(0, Math.min(1, progress)) : -1,
        "actions": actions,
        "accent": accent,
        "detail": [state, text].filter(part => part !== "").join(" · "),
        "name": [state, title, text].filter(part => part !== "").join(", ")
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

// `dms ipc call island activity*` answers, besides a token: ISLAND_ACTIVITY_BAD_DATA (not a JSON object within
// maxIpcData), _NO_CONTENT (no title nor icon, first call or update), scriptRefusal's _BAD_NAME, _BAD_NOTIFY_APP and
// _TOO_MANY, _NO_ISLAND (none on that screen), _UNKNOWN (no script activity under that token), _UPDATED, _ENDED.
function ipcRefusal(parsed) {
    if (!parsed)
        return "ISLAND_ACTIVITY_BAD_DATA";
    const face = readyFace(parsed);
    return face.title === "" && face.icon === "" ? "ISLAND_ACTIVITY_NO_CONTENT" : "";
}

// The bare token, so a script keeps it: tok=$(dms ipc call island activity ...).
function ipcActivity(service, id, kind, screen, data) {
    const parsed = parseIpcData(data);
    const refused = ipcRefusal(parsed);
    if (refused)
        return refused;
    return service.requestScript(id, {
        "kind": kind,
        "screen": screen,
        "expanded": parsed.expanded,
        "timeoutMs": parsed.timeoutMs,
        "notifyApp": parsed.notifyApp,
        "data": parsed
    });
}

function ipcActivityUpdate(service, token, data) {
    if (!ipcOwns(token))
        return "ISLAND_ACTIVITY_UNKNOWN";
    const parsed = parseIpcData(data);
    const refused = ipcRefusal(parsed);
    if (refused)
        return refused;
    return service.update(token, parsed) ? "ISLAND_ACTIVITY_UPDATED" : "ISLAND_ACTIVITY_UNKNOWN";
}

function ipcActivityEnd(service, token) {
    return ipcOwns(token) && service.release(token) ? "ISLAND_ACTIVITY_ENDED" : "ISLAND_ACTIVITY_UNKNOWN";
}

function ipcActivityStatus(service, token) {
    const entry = ipcOwns(token) ? service.entry(token) : null;
    return entry ? JSON.stringify({
        "state": entry.state,
        "action": entry.lastAction
    }) : "ISLAND_ACTIVITY_UNKNOWN";
}

function ipcOpenActivity(host, tag) {
    // A face that cannot open (title, icon or progress only) or suspended input: nothing opens, so say so.
    if (!host.islandController.pluginActive || !host.islandController.requestExpand(true))
        return `${tag}_ACTIVITY_UNAVAILABLE: activity`;
    return `${tag}_OPEN: activity\t${host.screen?.name ?? ""}`;
}

// Only a script's activity ("script:<name>:<n>") answers over IPC, never a plugin's or the shell's. Any local caller of
// dms ipc may address any script's token (island status lists them): scripts run as the same user, no boundary between.
function ipcOwns(token) {
    return typeof token === "string" && token.startsWith(scriptPrefix) && /^[^:]+:\d+$/.test(token.slice(scriptPrefix.length));
}

// A token is "<source>:<n>": a plugin id with a colon could pass for a script's or the shell's.
function pluginIdAllowed(id) {
    return typeof id === "string" && id !== "" && id.indexOf(":") === -1;
}

// Permanent bubbles (IslandActivityService.permanent): one entry per owner, { pluginId: { side, image, label, dropText,
// receiving, seq } }. Keep awake ("dms:keepawake") is the shell's own and draws its own bubble.
function permanentAllowed(id, loaded, allowed) {
    return id === "dms:keepawake" || (pluginIdAllowed(id) && loaded === true && allowed === true);
}

// A permanent bubble's own fields come from a plugin: typed and bounded as a face's are (B10). The bubble's width follows
// its label; an image URL too long to be one is dropped, never cut.
const maxPermanentLabel = 24;
const maxPermanentDropText = 64;
const maxPermanentImage = 2048;

// A new table with id's entry set (options) or gone (null); an owner setting its entry again keeps its place in line.
function withPermanent(table, id, options, seq) {
    const previous = (table || {})[id];
    if (!options && !previous)
        return table;
    const next = Object.assign({}, table);
    if (options)
        next[id] = Object.assign({}, options, {
            "pluginId": id,
            "side": options.side === "left" ? "left" : "right",
            "receiving": options.receiving === true,
            "label": faceText(options.label).slice(0, maxPermanentLabel),
            "dropText": faceText(options.dropText).slice(0, maxPermanentDropText),
            "image": typeof options.image === "string" && options.image.length <= maxPermanentImage ? options.image : "",
            "seq": previous ? previous.seq : seq
        });
    else
        delete next[id];
    return next;
}

// The plugin bubble a side shows: the newest owner there.
function permanentOn(table, side) {
    let shown = null;
    for (const entry of Object.values(table || {})) {
        if (entry.side === side && pluginIdAllowed(entry.pluginId) && (!shown || entry.seq > shown.seq))
            shown = entry;
    }
    return shown;
}

// The IPC answer refusing a script's activity, or "". liveNames: scripts showing one now; asking again replaces it.
function scriptRefusal(name, liveNames, notifyApp) {
    if (!name || name.length > maxScriptName || name.indexOf(":") !== -1 || /[\u0000-\u001f\u007f]/.test(name))
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

// [min, max, default, ready-face min] per size a plugin face may ask for; that min fits three whole labels at 125 % text.
const faceBounds = {
    "compactLength": [120, 360, 240, 240],
    "expandedWidth": [280, 736, 460, 400],
    "expandedHeight": [120, 480, 200, 200]
};

function faceSize(face, key, ready) {
    const b = faceBounds[key];
    return clampSize(face ? face[key] : undefined, b[ready ? 3 : 0], b[1], b[2]);
}

// 0 keeps the shell's size for a system face that does not ask for one.
function systemFaceSize(face, key) {
    return face && face[key] > 0 ? faceSize(face, key) : 0;
}
