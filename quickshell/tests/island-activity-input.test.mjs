import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const activities = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/IslandActivities.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), activities);
vm.runInContext(readFileSync(new URL("../Common/IslandActivityInput.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), activities);
const plain = value => JSON.parse(JSON.stringify(value));

test("the ready face keeps what it can draw and drops the rest", () => {
    const face = activities.readyFace({
        "icon": "timer",
        "title": "Pasta",
        "text": 42,
        "progress": 1.7,
        "accent": "#ff0000",
        "actions": [{ "id": "stop", "label": "Stop" }, { "id": "", "label": "No id" }, "x", { "id": "snooze", "label": "Snooze" }, { "id": "a", "label": "A" }, { "id": "b", "label": "B" }]
    });
    assert.deepEqual(plain(face), {
        "icon": "timer",
        "title": "Pasta",
        "text": "42",
        "progress": 1,
        "actions": [{ "id": "stop", "label": "Stop" }, { "id": "snooze", "label": "Snooze" }, { "id": "a", "label": "A" }],
        "accent": "primary",
        "detail": "42",
        "name": "Pasta, 42"
    });
    assert.equal(activities.readyFace({ "progress": null }).progress, -1);
    assert.equal(activities.readyFace({ "progress": "" }).progress, -1);
    assert.equal(activities.readyFace({ "progress": -2 }).progress, 0);
    assert.equal(activities.readyFace({ "accent": "error" }).accent, "error");
    assert.equal(activities.readyFace(null).title, "");
    assert.equal(activities.primaryAction(face), "stop");
    assert.equal(activities.primaryAction(activities.readyFace({})), "");
});

test("a state accent is said in words beside the detail and in the name a screen reader reads", () => {
    const words = { "error": "Error", "warning": "Warning", "success": "Success" };
    const face = activities.readyFace({ "title": "Backup", "text": "3 left", "accent": "error" }, words);
    assert.equal(face.detail, "Error · 3 left");
    assert.equal(face.name, "Error, Backup, 3 left");
    assert.equal(activities.readyFace({ "title": "Backup", "accent": "success" }, words).detail, "Success");
    const info = activities.readyFace({ "title": "Backup", "text": "3 left", "accent": "info" }, words);
    assert.equal(info.detail, "3 left", "an accent that is not a state says nothing");
    assert.equal(info.name, "Backup, 3 left");
});

test("IPC data must be a JSON object", () => {
    assert.deepEqual(plain(activities.parseIpcData('{"title":"Tea"}')), { "title": "Tea" });
    assert.deepEqual(plain(activities.parseIpcData("")), {});
    assert.equal(activities.parseIpcData("[1]"), null);
    assert.equal(activities.parseIpcData("tea"), null);
    assert.equal(activities.parseIpcData("3"), null);
});

test("a script's activity is refused without a title nor an icon, and for data that is not an object", () => {
    assert.equal(activities.ipcRefusal(activities.parseIpcData("[1]")), "ISLAND_ACTIVITY_BAD_DATA");
    assert.equal(activities.ipcRefusal(activities.parseIpcData("")), "ISLAND_ACTIVITY_NO_CONTENT");
    assert.equal(activities.ipcRefusal({ "text": "42 %", "progress": 0.4 }), "ISLAND_ACTIVITY_NO_CONTENT");
    assert.equal(activities.ipcRefusal({ "title": "Tea" }), "");
    assert.equal(activities.ipcRefusal({ "icon": "timer" }), "");
});

test("face sizes stay inside the island bounds", () => {
    assert.equal(activities.clampSize(undefined, 120, 360, 240), 240);
    assert.equal(activities.clampSize(NaN, 120, 360, 240), 240);
    assert.equal(activities.clampSize(5000, 120, 360, 240), 360);
    assert.equal(activities.clampSize(10, 120, 360, 240), 120);
    assert.equal(activities.clampSize(300.4, 120, 360, 240), 301);
    assert.equal(activities.faceSize(null, "compactLength"), 240);
    assert.equal(activities.faceSize({ "expandedWidth": 2000 }, "expandedWidth"), 736);
    assert.equal(activities.faceSize({ "expandedHeight": 10 }, "expandedHeight"), 120);
    // A shell-drawn ready face is never smaller than its title and actions need.
    assert.equal(activities.faceSize({ "expandedHeight": 120 }, "expandedHeight", true), 200);
    assert.equal(activities.faceSize({ "compactLength": 120 }, "compactLength", true), 240);
    assert.equal(activities.faceSize({ "expandedWidth": 280 }, "expandedWidth", true), 400);
    assert.equal(activities.faceSize({ "expandedWidth": 280 }, "expandedWidth"), 280, "a plugin drawing its own sheet keeps it");
    assert.equal(activities.faceSize({ "expandedHeight": 300 }, "expandedHeight", true), 300);
    assert.equal(activities.systemFaceSize(null, "compactLength"), 0);
    assert.equal(activities.systemFaceSize({ "compactLength": 0 }, "compactLength"), 0);
    assert.equal(activities.systemFaceSize({ "expandedWidth": 2000 }, "expandedWidth"), 736);
});

test("a bubble face keeps the ready face fields and a very short text", () => {
    assert.deepEqual(plain(activities.bubbleFace({ "icon": "timer", "progress": 0.5, "shortText": "4:59", "accent": "error" })), { "icon": "timer", "progress": 0.5, "text": "4:59", "accent": "error" });
    assert.equal(activities.bubbleFace({ "shortText": "far too long" }).text, "far to");
    assert.equal(activities.bubbleFace(null).text, "");
    assert.equal(activities.bubbleFace({ "shortText": 62 }).text, "62");
});

test("IPC reaches only the activities scripts started", () => {
    for (const token of ["script:x:1", "script:sands-timer:42"])
        assert.equal(activities.ipcOwns(token), true, token);
    for (const token of ["dms:auth:3", "monPlugin:2", "script:", "", "script:a:b:1", "script:x:", "script:x:1a", null, undefined, 3])
        assert.equal(activities.ipcOwns(token), false, String(token));
});

test("a script activity's timeout stays within one second and ten minutes", () => {
    const t = v => activities.normalizeOptions({ "timeoutMs": v }).timeoutMs;
    assert.equal(t(0.3), 1000);
    assert.equal(t(4000), 4000);
    assert.equal(t(3e9), 600000);
    for (const v of [true, NaN, "4000", 0, -5, Infinity])
        assert.equal(t(v), 0, String(v));
    assert.equal(activities.normalizeOptions({ "kind": "glance", "timeoutMs": true }).timeoutMs, 5000);
});

test("scripts get eight live activities at most, a short name without a colon and a short app", () => {
    const live = ["a", "b", "c", "d", "e", "f", "g", "h"];
    assert.equal(activities.scriptRefusal("i", live, ""), "ISLAND_ACTIVITY_TOO_MANY", "a 9th script");
    assert.equal(activities.scriptRefusal("h", live, ""), "", "asking again under a live name replaces it");
    assert.equal(activities.scriptRefusal("i", live.slice(1), ""), "");
    assert.equal(activities.scriptRefusal("x".repeat(64), [], ""), "");
    for (const name of ["x".repeat(65), "a:b", "", "a\nb", "a\rb", "tab\there", "bell\u0007", "del\u007f"])
        assert.equal(activities.scriptRefusal(name, [], ""), "ISLAND_ACTIVITY_BAD_NAME", name);
    assert.equal(activities.scriptRefusal("a", [], "d".repeat(128)), "");
    assert.equal(activities.scriptRefusal("a", [], "d".repeat(129)), "ISLAND_ACTIVITY_BAD_NOTIFY_APP");
    assert.equal(activities.scriptRefusal("a", [], 3), "", "a notifyApp that is no string is dropped later");
});

test("IPC data over 16 KiB is refused before it is parsed", () => {
    const json = n => '{"t":"' + "x".repeat(n - 8) + '"}';
    assert.equal(json(16384).length, 16384);
    assert.equal(activities.parseIpcData(json(16384)).t.length, 16376);
    assert.equal(activities.parseIpcData(json(16385)), null);
});

test("a plugin id never holds a colon, so its tokens never pass for a script's", () => {
    assert.equal(activities.pluginIdAllowed("sands"), true);
    for (const id of ["script:x", "a:b", "", null, 3])
        assert.equal(activities.pluginIdAllowed(id), false, String(id));
});

test("request options fall back per kind and reject what plugins cannot ask", () => {
    assert.deepEqual(plain(activities.normalizeOptions({})), { "kind": "live", "expanded": false, "timeoutMs": 0, "screen": "", "showInFullscreen": false, "notifyApp": "", "data": {} });
    assert.deepEqual(plain(activities.normalizeOptions({ "kind": "alert" })), { "kind": "alert", "expanded": true, "timeoutMs": 0, "screen": "", "showInFullscreen": false, "notifyApp": "", "data": {} });
    assert.equal(activities.normalizeOptions({ "kind": "glance" }).timeoutMs, 5000);
    assert.equal(activities.normalizeOptions({ "kind": "glance", "timeoutMs": -5 }).timeoutMs, 5000);
    assert.equal(activities.normalizeOptions({ "kind": "alert", "expanded": false }).expanded, false);
    assert.equal(activities.normalizeOptions({ "kind": "critical" }).kind, "live");
    assert.equal(activities.normalizeOptions({ "screen": 3, "data": "x" }).screen, "");
    assert.deepEqual(plain(activities.normalizeOptions({ "data": "x" }).data), {});
    assert.equal(activities.normalizeOptions(null).kind, "live");
});

// A double of IslandActivityService: what the island IPC target hands it, and what it answers.
function serviceDouble(known = true) {
    const calls = [];
    return {
        calls,
        requestScript: (id, options) => (calls.push(["request", id, options]), "script:" + id + ":1"),
        update: (token, data) => (calls.push(["update", token, data]), known),
        release: token => (calls.push(["release", token]), known),
        entry: token => known ? { "state": "shown", "lastAction": "pause" } : null
    };
}

test("the IPC activity calls check the data, then hand it to the service: activity, update, end, status", () => {
    const s = serviceDouble();
    assert.equal(activities.ipcActivity(s, "backup", "live", "", "[1]"), "ISLAND_ACTIVITY_BAD_DATA");
    assert.equal(activities.ipcActivity(s, "backup", "live", "", "{\"text\":\"x\"}"), "ISLAND_ACTIVITY_NO_CONTENT");
    assert.equal(s.calls.length, 0, "a refused call never reaches the service");
    assert.equal(activities.ipcActivity(s, "backup", "alert", "*", "{\"title\":\"Backup\",\"expanded\":true,\"timeoutMs\":5000,\"notifyApp\":\"rsync\"}"), "script:backup:1");
    const [, id, options] = s.calls[0];
    assert.equal(id, "backup");
    assert.deepEqual(plain(options), { "kind": "alert", "screen": "*", "expanded": true, "timeoutMs": 5000, "notifyApp": "rsync", "data": { "title": "Backup", "expanded": true, "timeoutMs": 5000, "notifyApp": "rsync" } });
    // Only a script's token answers; an update must still say what to show.
    assert.equal(activities.ipcActivityUpdate(s, "weather:3", "{\"title\":\"x\"}"), "ISLAND_ACTIVITY_UNKNOWN");
    assert.equal(activities.ipcActivityUpdate(s, "script:backup:1", "{}"), "ISLAND_ACTIVITY_NO_CONTENT");
    assert.equal(activities.ipcActivityUpdate(s, "script:backup:1", "{\"title\":\"Backup 50%\"}"), "ISLAND_ACTIVITY_UPDATED");
    assert.equal(activities.ipcActivityEnd(s, "weather:3"), "ISLAND_ACTIVITY_UNKNOWN");
    assert.equal(activities.ipcActivityEnd(s, "script:backup:1"), "ISLAND_ACTIVITY_ENDED");
    assert.deepEqual(s.calls.slice(1).map(c => c[0] + " " + c[1]), ["update script:backup:1", "release script:backup:1"]);
    assert.deepEqual(JSON.parse(activities.ipcActivityStatus(s, "script:backup:1")), { "state": "shown", "action": "pause" });
    assert.equal(activities.ipcActivityStatus(s, "weather:3"), "ISLAND_ACTIVITY_UNKNOWN");
    // A token the service no longer knows.
    const gone = serviceDouble(false);
    assert.equal(activities.ipcActivityUpdate(gone, "script:backup:1", "{\"title\":\"x\"}"), "ISLAND_ACTIVITY_UNKNOWN");
    assert.equal(activities.ipcActivityEnd(gone, "script:backup:1"), "ISLAND_ACTIVITY_UNKNOWN");
    assert.equal(activities.ipcActivityStatus(gone, "script:backup:1"), "ISLAND_ACTIVITY_UNKNOWN");
});

test("toggle activity opens the shown activity's sheet with the keyboard in it, and says when there is none", () => {
    const opened = [];
    const host = (active, opens = true) => ({ "screen": { "name": "DP-1" }, "islandController": { "pluginActive": active, "requestExpand": keyboard => opened.push(keyboard) && opens } });
    assert.equal(activities.ipcOpenActivity(host(false), "ISLAND"), "ISLAND_ACTIVITY_UNAVAILABLE: activity");
    assert.equal(opened.length, 0);
    assert.equal(activities.ipcOpenActivity(host(true), "DOT"), "DOT_OPEN: activity\tDP-1");
    assert.deepEqual(opened, [true]);
    // A face that cannot open (title only) or suspended input: requestExpand refuses, nothing opened.
    assert.equal(activities.ipcOpenActivity(host(true, false), "ISLAND"), "ISLAND_ACTIVITY_UNAVAILABLE: activity");
});
