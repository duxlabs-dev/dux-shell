import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const Session = loadScript(new URL("../Common/niri/sections/session.js", import.meta.url));
const { assemble } = loadScript(new URL("../Common/niri/assemble.js", import.meta.url));

const kdl = state => assemble([{ id: "workspaces", toKdl: Session.toKdl }], { ...Session.defaults, ...state });

test("writes nothing by default or when the session is off", () => {
    assert.equal(kdl({}), "");
    assert.equal(kdl({ "session.on": false, "session.apps": [{ appId: "mpv", command: ["mpv"], workspace: "web", output: "" }] }), "");
});

test("spawns each program with its own arguments and opens it on its workspace, else on its screen", () => {
    const apps = [
        { appId: "org.demo.Mail", command: ["demo-mail", "--hidden"], workspace: "web", output: "DP-1" },
        { appId: "alacritty", command: ["alacritty"], workspace: "", output: "eDP-1" }
    ];
    assert.equal(kdl({ "session.apps": apps }), [
        "spawn-at-startup \"demo-mail\" \"--hidden\"",
        "window-rule {",
        "    match app-id=\"^org\\\\.demo\\\\.Mail$\" at-startup=true",
        "    open-on-workspace \"web\"",
        "}",
        "spawn-at-startup \"alacritty\"",
        "window-rule {",
        "    match app-id=\"^alacritty$\" at-startup=true",
        "    open-on-output \"eDP-1\"",
        "}",
        ""
    ].join("\n"));
});

test("escapes quotes in names and regex characters in app ids, skips programs with no command", () => {
    const apps = [
        { appId: "a+b(c)", command: ["say \"hi\""], workspace: "my \"ws\"", output: "" },
        { appId: "ghost", command: [], workspace: "web", output: "" }
    ];
    const text = kdl({ "session.apps": apps });
    assert.match(text, /spawn-at-startup "say \\"hi\\""/);
    assert.match(text, /app-id="\^a\\\\\+b\\\\\(c\\\\\)\$"/);
    assert.match(text, /open-on-workspace "my \\"ws\\""/);
    assert.doesNotMatch(text, /ghost/);
});

test("groups programs by screen then named workspace, unnamed or gone ones under their saved screen", () => {
    const workspaces = [
        { name: "web", idx: 1, output: "DP-1" },
        { name: null, idx: 2, output: "DP-1" },
        { name: "chat", idx: 1, output: "eDP-1" }
    ];
    const apps = [
        { appId: "a", workspace: "chat", output: "DP-1" },
        { appId: "b", workspace: "", output: "eDP-1" },
        { appId: "c", workspace: "old", output: "HDMI-A-1" }
    ];
    const shape = JSON.parse(JSON.stringify(Session.layout(apps, workspaces))).map(o => [o.output, o.rows.map(r => [r.workspace, r.idx, r.apps.map(a => a.appId).join()])]);
    assert.deepEqual(shape, [
        ["DP-1", [["web", 1, ""], ["", -1, ""]]],
        ["eDP-1", [["chat", 1, "a"], ["", -1, "b"]]],
        ["HDMI-A-1", [["old", 0, "c"], ["", -1, ""]]]
    ]);
});

test("saving open windows keeps one place per app, the first one met", () => {
    const workspaces = { 1: { id: 1, name: "web", output: "DP-1" }, 2: { id: 2, name: null, output: "eDP-1" } };
    const windows = [
        { app_id: "librewolf", workspace_id: 1 },
        { app_id: "alacritty", workspace_id: 2 },
        { app_id: "librewolf", workspace_id: 2 },
        { app_id: "", workspace_id: 1 }
    ];
    const apps = Session.fromWindows(windows, workspaces, id => [id + "-bin"]);
    assert.deepEqual(JSON.parse(JSON.stringify(apps)), [
        { appId: "librewolf", command: ["librewolf-bin"], workspace: "web", output: "DP-1" },
        { appId: "alacritty", command: ["alacritty-bin"], workspace: "", output: "eDP-1" }
    ]);
});
