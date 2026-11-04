import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const ws = loadScript(new URL("../Common/niri/sections/workspaces.js", import.meta.url));
const assemble = loadScript(new URL("../Common/niri/assemble.js", import.meta.url));

const plain = v => JSON.parse(JSON.stringify(v));
const kdl = named => assemble.assemble([{ id: "workspaces", toKdl: ws.toKdl }], { "workspaces.named": named });

test("toKdl writes nothing by default", () => {
    assert.equal(kdl(ws.defaults["workspaces.named"]), "");
});

test("toKdl writes top-level workspace lines in order, with the screen when set", () => {
    assert.equal(kdl([{ name: "web", output: "DP-1" }, { name: "chat", output: "" }]),
        "workspace \"web\" {\n    open-on-output \"DP-1\"\n}\nworkspace \"chat\"\n");
});

test("toKdl escapes names", () => {
    assert.equal(kdl([{ name: "a \"b\"", output: "" }]), "workspace \"a \\\"b\\\"\"\n");
});

test("rename changes a named workspace and keeps its screen", () => {
    assert.deepEqual(plain(ws.rename([{ name: "web", output: "DP-1" }], "web", " www ")), [{ name: "www", output: "DP-1" }]);
});

test("rename of an unnamed workspace adds it", () => {
    assert.deepEqual(plain(ws.rename([{ name: "web", output: "" }], "", "code")), [{ name: "web", output: "" }, { name: "code", output: "" }]);
});

test("rename refuses empty and taken names, case-insensitive like niri", () => {
    const list = [{ name: "web", output: "" }, { name: "code", output: "" }];
    assert.equal(ws.rename(list, "web", "  "), null);
    assert.equal(ws.rename(list, "web", "Code"), null);
    assert.equal(ws.add(list, "WEB"), null);
    assert.deepEqual(plain(ws.rename(list, "web", "Web")), [{ name: "Web", output: "" }, { name: "code", output: "" }]);
});

test("moveUp, remove and setOutput", () => {
    const list = [{ name: "a", output: "" }, { name: "b", output: "" }];
    assert.deepEqual(plain(ws.moveUp(list, 1).map(w => w.name)), ["b", "a"]);
    assert.equal(ws.moveUp(list, 0), list);
    assert.deepEqual(plain(ws.remove(list, "a")), [{ name: "b", output: "" }]);
    assert.deepEqual(plain(ws.setOutput(list, "b", "eDP-1")[1]), { name: "b", output: "eDP-1" });
});

const workspaces = [{ id: 3, idx: 2, output: "DP-1", name: null }, { id: 1, idx: 1, output: "eDP-1", name: "web" }, { id: 2, idx: 1, output: "DP-1", name: "code" }];
const windows = [{ id: 10, app_id: "librewolf", workspace_id: 1 }, { id: 11, app_id: "librewolf", workspace_id: 2 }, { id: 12, app_id: "mpv", workspace_id: 1 }, { id: 13, app_id: null, workspace_id: 3 }];

test("lanes sort by screen then index and hold their windows", () => {
    const out = ws.lanes(workspaces, windows);
    assert.deepEqual(plain(out).map(l => l.id), [2, 3, 1]);
    assert.deepEqual(plain(out)[2].windows.map(w => w.id), [10, 12]);
    assert.equal(out[1].name, "");
});

test("lanes mark the focused workspace as active, ids compared as strings", () => {
    const out = ws.lanes(workspaces, windows, 2);
    assert.equal(out[0].active, true);
    assert.equal(out[2].active, false);
    assert.ok(!ws.lanes(workspaces, windows, "").some(l => l.active));
    assert.ok(!ws.lanes(workspaces, windows).some(l => l.active));
});

test("screens group contiguous lanes per output, in lane order", () => {
    const out = plain(ws.screens(ws.lanes(workspaces, windows)));
    assert.deepEqual(out.map(s => s.output), ["DP-1", "eDP-1"]);
    assert.deepEqual(out[0].lanes.map(l => l.id), [2, 3]);
    assert.deepEqual(out[1].lanes.map(l => l.id), [1]);
    assert.deepEqual(plain(ws.screens([])), []);
    assert.deepEqual(plain(ws.screens(undefined)), []);
});

test("apps counts windows per app and skips windows without app id", () => {
    assert.deepEqual(plain(ws.apps(windows)), [{ app: "librewolf", count: 2 }, { app: "mpv", count: 1 }]);
});

test("bulk helpers pick the right window ids", () => {
    assert.deepEqual(plain(ws.groupIds(windows, "librewolf", 2)), [10]);
    assert.deepEqual(plain(ws.onWorkspace(windows, 1)), [10, 12]);
    assert.deepEqual(plain(ws.ofApp(windows, "librewolf")), [10, 11]);
});
