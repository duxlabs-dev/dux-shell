.pragma library
.import "sections/workspaces.js" as Ws

// Bulk actions of the Workspaces board, by name; the card shows them in this order.
var actions = ["group", "move", "close"];

// The move target starts on the next workspace so the default pair is never the same one.
function choices(action, apps, lanes) {
    if (action === "move")
        return { left: lanes, right: lanes.slice(1).concat(lanes.slice(0, 1)) };
    return { left: apps, right: action === "group" ? lanes : [] };
}

function pick(value, list) {
    return list.includes(value) ? value : (list[0] ?? "");
}

function ready(action, left, right, apps, lanes) {
    if (action === "close")
        return apps.includes(left);
    if (action === "group")
        return apps.includes(left) && lanes.includes(right);
    if (action === "move")
        return lanes.includes(left) && lanes.includes(right) && left !== right;
    return false;
}

// from, to: board lanes ({id}) or null. to is -1 when nothing moves.
function plan(action, windows, app, from, to) {
    if (action === "close")
        return { ids: Ws.ofApp(windows, app), to: -1 };
    if (!to)
        return { ids: [], to: -1 };
    if (action === "group")
        return { ids: Ws.groupIds(windows, app, to.id), to: to.id };
    if (!from || from.id === to.id)
        return { ids: [], to: -1 };
    return { ids: Ws.onWorkspace(windows, from.id), to: to.id };
}
