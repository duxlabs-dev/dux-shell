.pragma library
.import "../../niriKdl.js" as Kdl
.import "rules.js" as Rules

// apps: [{appId, command: [argv], workspace: name or "", output: name or ""}]
var defaults = {
    "session.on": true,
    "session.apps": []
};

var stored = {
    "session.on": "page",
    "session.apps": "page"
};

var search = [
    {
        key: "session.on",
        title: "Reopen programs at login",
        words: ["session", "restore", "login", "startup", "programs", "workspace", "screen", "output", "restaurer", "démarrage", "connexion", "programmes", "espace", "écran"]
    }
];

function toKdl(state) {
    if (!state["session.on"])
        return [];
    const lines = [];
    for (const app of state["session.apps"] || []) {
        if (!app.appId || !app.command?.length)
            continue;
        lines.push("spawn-at-startup " + app.command.map(Kdl.kdlString).join(" "));
        const place = app.workspace ? "open-on-workspace " + Kdl.kdlString(app.workspace) : app.output ? "open-on-output " + Kdl.kdlString(app.output) : "";
        if (!place)
            continue;
        lines.push("window-rule {\n    match app-id=" + Kdl.kdlString("^" + Rules.escapeRegex(app.appId) + "$") + " at-startup=true\n    " + place + "\n}");
    }
    return [{ block: null, lines: lines }];
}

// [{output, rows: [{workspace, idx, apps}]}]; the "" row of a screen holds what opens on it without a named workspace.
function layout(apps, workspaces) {
    const outputs = [];
    const outputOf = name => {
        let o = outputs.find(x => x.output === name);
        if (!o) {
            o = { output: name, rows: [] };
            outputs.push(o);
        }
        return o;
    };
    const named = [];
    for (const w of workspaces) {
        if (!w.output)
            continue;
        const o = outputOf(w.output);
        if (!w.name)
            continue;
        const row = { workspace: w.name, idx: w.idx, apps: [] };
        o.rows.push(row);
        named.push(row);
    }
    for (const app of apps) {
        let row = app.workspace ? named.find(r => r.workspace === app.workspace) : null;
        if (!row) {
            const o = outputOf(app.output);
            row = o.rows.find(r => r.workspace === app.workspace);
            if (!row) {
                row = { workspace: app.workspace, idx: 0, apps: [] };
                o.rows.push(row);
                if (app.workspace)
                    named.push(row);
            }
        }
        row.apps.push(app);
    }
    for (const o of outputs) {
        const loose = o.rows.findIndex(r => r.workspace === "");
        const row = loose < 0 ? { workspace: "", idx: -1, apps: [] } : o.rows.splice(loose, 1)[0];
        row.idx = -1;
        o.rows.push(row);
    }
    return outputs;
}

// niri matches startup rules by app-id only, so one app can have one place.
function fromWindows(windows, workspaces, commandOf) {
    const apps = [];
    for (const w of windows) {
        if (!w.app_id || apps.some(a => a.appId === w.app_id))
            continue;
        const ws = workspaces[w.workspace_id];
        apps.push({ appId: w.app_id, command: commandOf(w.app_id), workspace: ws?.name ?? "", output: ws?.output ?? "" });
    }
    return apps;
}
