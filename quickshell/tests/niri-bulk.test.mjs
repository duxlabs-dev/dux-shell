import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const Bulk = loadScript(new URL("../Common/niri/bulk.js", import.meta.url));
const plain = v => JSON.parse(JSON.stringify(v));

const apps = ["librewolf", "mpv"];
const lanes = ["web", "code", "chat"];
const windows = [{ id: 10, app_id: "librewolf", workspace_id: 1 }, { id: 11, app_id: "librewolf", workspace_id: 2 }, { id: 12, app_id: "mpv", workspace_id: 1 }];

test("the move target list is a rotation: every workspace once, the next one first", () => {
    assert.deepEqual(plain(Bulk.choices("move", apps, lanes)), { left: lanes, right: ["code", "chat", "web"] });
    assert.deepEqual(plain(Bulk.choices("move", apps, [])), { left: [], right: [] });
});

test("group picks an app and a workspace, close only an app", () => {
    assert.deepEqual(plain(Bulk.choices("group", apps, lanes)), { left: apps, right: lanes });
    assert.deepEqual(plain(Bulk.choices("close", apps, lanes)), { left: apps, right: [] });
});

test("pick keeps a listed value, else the first one", () => {
    assert.equal(Bulk.pick("code", lanes), "code");
    assert.equal(Bulk.pick("gone", lanes), "web");
    assert.equal(Bulk.pick("gone", []), "");
});

test("ready needs a valid target for each of the three actions", () => {
    assert.equal(Bulk.ready("group", "mpv", "web", apps, lanes), true);
    assert.equal(Bulk.ready("group", "mpv", "", apps, []), false);
    assert.equal(Bulk.ready("group", "", "web", [], lanes), false);
    assert.equal(Bulk.ready("move", "web", "code", apps, lanes), true);
    assert.equal(Bulk.ready("move", "web", "web", apps, lanes), false);
    assert.equal(Bulk.ready("move", "web", "", apps, ["web"]), false);
    assert.equal(Bulk.ready("close", "mpv", "", apps, lanes), true);
    assert.equal(Bulk.ready("close", "", "", [], lanes), false);
    assert.equal(Bulk.ready("unknown", "mpv", "web", apps, lanes), false);
});

test("plan of group sends only the windows not already there", () => {
    assert.deepEqual(plain(Bulk.plan("group", windows, "librewolf", null, { id: 1 })), { ids: [11], to: 1 });
    assert.deepEqual(plain(Bulk.plan("group", windows, "mpv", null, { id: 1 })), { ids: [], to: 1 });
});

test("plan of move takes every window of the source, never onto itself", () => {
    assert.deepEqual(plain(Bulk.plan("move", windows, "", { id: 1 }, { id: 2 })), { ids: [10, 12], to: 2 });
    assert.deepEqual(plain(Bulk.plan("move", windows, "", { id: 1 }, { id: 1 })), { ids: [], to: -1 });
    assert.deepEqual(plain(Bulk.plan("move", windows, "", null, { id: 1 })), { ids: [], to: -1 });
});

test("plan of close takes every window of the app, a missing target plans nothing", () => {
    assert.deepEqual(plain(Bulk.plan("close", windows, "librewolf", null, null)), { ids: [10, 11], to: -1 });
    assert.deepEqual(plain(Bulk.plan("group", windows, "mpv", null, null)), { ids: [], to: -1 });
});
