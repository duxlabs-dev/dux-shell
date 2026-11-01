.pragma library
.import "../../niriKdl.js" as Kdl

// Named workspaces in niri's order: [{name, output}], output "" means any screen.
var defaults = {
    "workspaces.named": []
};

var stored = {
    "workspaces.named": "page"
};

var search = [
    {
        key: "workspaces.named",
        title: "Live workspaces",
        words: ["workspace", "named", "rename", "drag", "windows", "move", "order", "screen", "espace", "espaces", "renommer", "glisser", "fenêtres", "déplacer", "ordre", "écran"]
    },
    {
        key: "workspaces.named",
        title: "Bulk actions",
        words: ["group", "app", "move all", "close app", "kill", "quit", "regrouper", "tout déplacer", "fermer", "appli"]
    }
];

function toKdl(state) {
    const lines = [];
    for (const ws of state["workspaces.named"] || []) {
        if (!ws.name)
            continue;
        const head = "workspace " + Kdl.kdlString(ws.name);
        lines.push(ws.output ? head + " {\n    open-on-output " + Kdl.kdlString(ws.output) + "\n}" : head);
    }
    return [{ block: null, lines: lines }];
}

// niri compares workspace names without case.
function hasName(list, name, except) {
    const low = name.toLowerCase();
    return list.some(ws => ws.name.toLowerCase() === low && ws.name !== except);
}

// Returns the new list, or null when the name is empty or taken.
function rename(list, oldName, newName) {
    const name = (newName || "").trim();
    if (!name || hasName(list, name, oldName))
        return null;
    if (!list.some(ws => ws.name === oldName))
        return list.concat([{ name: name, output: "" }]);
    return list.map(ws => ws.name === oldName ? { name: name, output: ws.output } : ws);
}

function add(list, name) {
    return rename(list, null, name);
}

function remove(list, name) {
    return list.filter(ws => ws.name !== name);
}

function moveUp(list, index) {
    if (index <= 0 || index >= list.length)
        return list;
    const next = list.slice();
    next[index - 1] = list[index];
    next[index] = list[index - 1];
    return next;
}

function setOutput(list, name, output) {
    return list.map(ws => ws.name === name ? { name: ws.name, output: output || "" } : ws);
}

// One lane per live workspace, screen by screen, each with its windows.
// focusedId marks the active lane (niri's focused workspace; string or number, compared as a string).
function lanes(workspaces, windows, focusedId) {
    const focus = focusedId === null || focusedId === undefined ? "" : String(focusedId);
    const sorted = (workspaces || []).slice().sort((a, b) => (a.output || "").localeCompare(b.output || "") || a.idx - b.idx);
    return sorted.map(ws => ({
        id: ws.id,
        idx: ws.idx,
        name: ws.name || "",
        output: ws.output || "",
        active: !!focus && String(ws.id) === focus,
        windows: (windows || []).filter(w => w.workspace_id === ws.id)
    }));
}

// Lanes already sorted by output: group the contiguous runs, one band per screen.
function screens(lanes) {
    const groups = [];
    for (const lane of lanes || []) {
        const last = groups[groups.length - 1];
        if (last && last.output === lane.output)
            last.lanes.push(lane);
        else
            groups.push({ output: lane.output, lanes: [lane] });
    }
    return groups;
}

function apps(windows) {
    const counts = {};
    for (const w of windows || []) {
        if (w.app_id)
            counts[w.app_id] = (counts[w.app_id] || 0) + 1;
    }
    return Object.keys(counts).sort().map(app => ({ app: app, count: counts[app] }));
}

// Window ids to send to workspaceId so every window of app sits there.
function groupIds(windows, app, workspaceId) {
    return (windows || []).filter(w => w.app_id === app && w.workspace_id !== workspaceId).map(w => w.id);
}

function onWorkspace(windows, workspaceId) {
    return (windows || []).filter(w => w.workspace_id === workspaceId).map(w => w.id);
}

function ofApp(windows, app) {
    return (windows || []).filter(w => w.app_id === app).map(w => w.id);
}
