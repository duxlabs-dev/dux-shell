import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const activities = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/IslandActivities.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), activities);
vm.runInContext(readFileSync(new URL("../Common/IslandActivityInput.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), activities);
const plain = value => JSON.parse(JSON.stringify(value));

test("an ended plugin activity keeps its entry while its face folds away with the island", () => {
    const live = { "token": "b" }, last = { "token": "a" };
    assert.equal(activities.shownEntry(null, last, true), last);
    assert.equal(activities.shownEntry(null, last, false), null);
    assert.equal(activities.shownEntry(live, last, true), live);
    assert.equal(activities.shownEntry(null, null, true), null);
});

test("a plugin activity takes the island only from a lower occupant", () => {
    const home = { "activity": "home" };
    const sheet = { "activity": "launcher", "expanded": true };
    const notification = { "activity": "notification" };
    const critical = { "activity": "notification", "critical": true };
    const osd = { "activity": "volume", "system": true };
    const glance = { "activity": "plugin", "kind": "glance" };
    const live = { "activity": "plugin", "kind": "live" };
    const alert = { "activity": "plugin", "kind": "alert" };
    const matrix = [
        ["alert", home, true],
        ["alert", sheet, true],
        ["alert", osd, true],
        ["alert", critical, false],
        ["alert", alert, false],
        ["live", sheet, false],
        ["live", osd, false],
        ["live", notification, false],
        ["live", glance, true],
        ["live", live, false],
        ["glance", notification, false],
        ["glance", home, true],
        ["glance", { "activity": "home", "expanded": true }, false]
    ];
    for (const [kind, occupant, expected] of matrix)
        assert.equal(activities.preempts(kind, occupant), expected, `${kind} over ${JSON.stringify(occupant)}`);
});

test("a notification shows over a live activity but not over an alert", () => {
    const notification = activities.occupantRank({ "activity": "notification" });
    assert.ok(notification > activities.kindRank("live"));
    assert.ok(notification < activities.kindRank("alert"));
});

test("the next request is the highest kind for that island, oldest first", () => {
    const requests = [
        { "token": "a", "kind": "live", "hosts": ["DP-1"], "seq": 1 },
        { "token": "b", "kind": "alert", "hosts": ["DP-2"], "seq": 2 },
        { "token": "c", "kind": "glance", "hosts": ["DP-1"], "seq": 3 },
        { "token": "d", "kind": "live", "hosts": ["DP-1"], "seq": 4 }
    ];
    assert.equal(activities.nextRequest(requests, "DP-1").token, "a");
    assert.equal(activities.nextRequest(requests, "DP-2").token, "b");
    assert.equal(activities.nextRequest(requests, "HDMI-A-1"), null);
    assert.equal(activities.nextRequest(requests, "DP-1", true), null, "do not disturb holds live and glance");
    assert.equal(activities.nextRequest(requests, "DP-2", true), null, "and alerts");
    assert.equal(activities.nextRequest(requests, "DP-2", true, request => request.kind === "alert").token, "b", "but those the user lets through");
    // A one-time code waits too, as a screen share turns do not disturb on: on a shared screen it would leak.
    const code = requests.concat([{ "token": "f", "kind": "glance", "pluginId": "dms:code2fa", "hosts": ["DP-1"], "seq": 6 }]);
    assert.equal(activities.nextRequest(code, "DP-1", true), null);
    assert.equal(activities.nextRequest(code, "DP-1", true, request => request.pluginId === "dms:code2fa").token, "f");
    assert.equal(activities.normalizeOptions({ "screen": "D".repeat(500) }).screen.length, 64, "a screen name over IPC is cut");
    assert.equal(activities.nextRequest(requests.concat([{ "token": "e", "kind": "alert", "hosts": ["DP-1"], "seq": 5 }]), "DP-1").token, "e");
    const everywhere = [{ "token": "f", "kind": "alert", "hosts": ["DP-1", "DP-2"], "seq": 6 }];
    assert.equal(activities.nextRequest(everywhere, "DP-1").token, "f");
    assert.equal(activities.nextRequest(everywhere, "DP-2").token, "f");
});

test("an activity on every screen is interrupted only when its last island lets go", () => {
    let entry = { "state": "waiting", "shownOn": [] };
    const step = (island, showing) => {
        const change = activities.shownChange(entry, island, showing);
        entry = { "state": change.state, "shownOn": change.shownOn };
        return change.signal;
    };
    assert.equal(step("DP-1", true), "shown");
    assert.equal(step("DP-2", true), "", "already shown on the other screen");
    assert.equal(step("DP-1", false), "", "still on DP-2");
    assert.equal(entry.state, "shown");
    assert.equal(step("DP-2", false), "interrupted");
    assert.equal(step("DP-2", false), "", "interrupted once");
    assert.equal(step("DP-1", true), "resumed");
    assert.deepEqual(plain(entry.shownOn), ["DP-1"]);
});

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
        "accent": "primary"
    });
    assert.equal(activities.readyFace({ "progress": null }).progress, -1);
    assert.equal(activities.readyFace({ "progress": "" }).progress, -1);
    assert.equal(activities.readyFace({ "progress": -2 }).progress, 0);
    assert.equal(activities.readyFace({ "accent": "error" }).accent, "error");
    assert.equal(activities.readyFace(null).title, "");
    assert.equal(activities.primaryAction(face), "stop");
    assert.equal(activities.primaryAction(activities.readyFace({})), "");
});

test("IPC data must be a JSON object", () => {
    assert.deepEqual(plain(activities.parseIpcData('{"title":"Tea"}')), { "title": "Tea" });
    assert.deepEqual(plain(activities.parseIpcData("")), {});
    assert.equal(activities.parseIpcData("[1]"), null);
    assert.equal(activities.parseIpcData("tea"), null);
    assert.equal(activities.parseIpcData("3"), null);
});

test("the held activity ends, shows, or waits behind the lock and other occupants", () => {
    assert.equal(activities.heldOutcome(false, true, false), "end");
    assert.equal(activities.heldOutcome(true, true, false), "shown");
    assert.equal(activities.heldOutcome(true, true, true), "interrupted", "the lock screen interrupts");
    assert.equal(activities.heldOutcome(true, false, false), "interrupted");
});

test("a plugin activity with no end of its own holds a hidden bar out only on arrival and never counts down", () => {
    assert.equal(activities.holdsHost(true, true, 5000, false), true, "a glance holds the bar out until it goes");
    assert.equal(activities.holdsHost(true, true, 0, true), true, "an alert or a live activity shows the bar on arrival");
    assert.equal(activities.holdsHost(true, true, 0, false), false, "then lets the bar hide again");
    assert.equal(activities.holdsHost(true, false, 0, false), true, "a notification over it still holds the bar out");
    assert.equal(activities.holdsHost(false, false, 5000, true), false);
    assert.equal(activities.countdownRuns(true, false, 5000), true);
    assert.equal(activities.countdownRuns(true, true, 5000), false, "a hover or an open sheet holds it (M21)");
    assert.equal(activities.countdownRuns(true, false, 0), false);
    assert.equal(activities.countdownRuns(false, false, 5000), false, "pushed aside, it waits to be handed back");
});

test("the next request takes the island only when it outranks the occupant", () => {
    const home = { "activity": "home", "expanded": false };
    const sheet = { "activity": "controlcenter", "expanded": true };
    const live = { "token": "a", "kind": "live", "state": "waiting" };
    const back = { "token": "a", "kind": "live", "state": "interrupted" };
    const alert = { "token": "b", "kind": "alert", "state": "interrupted" };
    assert.equal(activities.takesIsland(null, home, "", false), false);
    assert.equal(activities.takesIsland(live, home, "", false), true);
    assert.equal(activities.takesIsland(live, home, "a", true), false, "already on screen");
    assert.equal(activities.takesIsland(back, home, "a", false), true, "comes back once the island is free");
    assert.equal(activities.takesIsland(live, { "activity": "notification" }, "", false), false, "waits for the notification");
    assert.equal(activities.takesIsland({ "token": "b", "kind": "alert", "state": "waiting" }, sheet, "", false), true, "a new alert passes the user's sheet");
    assert.equal(activities.takesIsland({ "token": "c", "kind": "alert", "state": "interrupted" }, { "activity": "home", "expanded": true }, "", false), false, "waits for the user's sheet");
    assert.equal(activities.takesIsland(alert, { "activity": "plugin", "kind": "live", "expanded": true }, "a", true), true, "an alert pushes a live aside");
});

test("a request says shown once, resumed after each interruption, nothing while on screen", () => {
    assert.equal(activities.showSignal("waiting"), "shown");
    assert.equal(activities.showSignal("interrupted"), "resumed");
    assert.equal(activities.showSignal("shown"), "");
    assert.equal(activities.showSignal(undefined), "");
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

test("face sizes stay inside the island bounds", () => {
    assert.equal(activities.clampSize(undefined, 120, 360, 240), 240);
    assert.equal(activities.clampSize(NaN, 120, 360, 240), 240);
    assert.equal(activities.clampSize(5000, 120, 360, 240), 360);
    assert.equal(activities.clampSize(10, 120, 360, 240), 120);
    assert.equal(activities.clampSize(300.4, 120, 360, 240), 301);
    assert.equal(activities.faceSize(null, "compactLength"), 240);
    assert.equal(activities.faceSize({ "expandedWidth": 2000 }, "expandedWidth"), 736);
    assert.equal(activities.faceSize({ "expandedHeight": 10 }, "expandedHeight"), 120);
    assert.equal(activities.systemFaceSize(null, "compactLength"), 0);
    assert.equal(activities.systemFaceSize({ "compactLength": 0 }, "compactLength"), 0);
    assert.equal(activities.systemFaceSize({ "expandedWidth": 2000 }, "expandedWidth"), 736);
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
    for (const name of ["x".repeat(65), "a:b", ""])
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
