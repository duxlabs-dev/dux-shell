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

test("a notification belongs to the activity whose plugin declared its app, else to the plugin's name or id", () => {
    assert.equal(activities.normalizeOptions({ "notifyApp": "  Sands " }).notifyApp, "Sands");
    assert.equal(activities.normalizeOptions({ "notifyApp": 3 }).notifyApp, "");
    const names = { "sandsTimer": "Sands Timer", "noisy": "Noisy" };
    const nameOf = id => names[id];
    const declared = [{ "pluginId": "sandsTimer", "notifyApp": "sands" }];
    assert.equal(activities.holdsApp(declared, "Sands", nameOf), true);
    assert.equal(activities.holdsApp(declared, " sands ", nameOf), true);
    // Declared means explicit: the plugin's own name no longer guesses.
    assert.equal(activities.holdsApp(declared, "Sands Timer", nameOf), false);
    assert.equal(activities.holdsApp(declared, "sandsTimer", nameOf), false);
    const guessed = [{ "pluginId": "noisy", "notifyApp": "" }, { "pluginId": "script:backup" }];
    assert.equal(activities.holdsApp(guessed, "noisy", nameOf), true);
    assert.equal(activities.holdsApp(guessed, "NOISY", nameOf), true);
    assert.equal(activities.holdsApp(guessed, "Backup", nameOf), true);
    assert.equal(activities.holdsApp(guessed, "firefox", nameOf), false);
    assert.equal(activities.holdsApp(guessed, "", nameOf), false);
    assert.equal(activities.holdsApp(guessed, "noisy"), true);
    assert.equal(activities.holdsApp(null, "noisy", nameOf), false);
});

test("what the user brought in from a bubble holds the island until it closes", () => {
    const held = { "activity": "volume", "system": true, "held": true };
    assert.equal(activities.takesIsland({ "token": "a", "kind": "alert", "state": "interrupted" }, held, "", false), false);
    assert.equal(activities.takesIsland({ "token": "a", "kind": "alert", "state": "waiting" }, held, "", false), true);
    const live = { "activity": "plugin", "kind": "live", "expanded": true, "held": true };
    assert.equal(activities.takesIsland({ "token": "a", "kind": "alert", "state": "interrupted" }, live, "b", true), false);
    assert.equal(activities.takesIsland({ "token": "a", "kind": "alert", "state": "interrupted" }, { "activity": "plugin", "kind": "live" }, "b", true), true);
});

test("bubbles split the machine from the apps and rank the apps", () => {
    const sides = activities.bubbleSides([
        { "id": "v", "source": "system", "kind": "volume", "seq": 1 },
        { "id": "b", "source": "system", "kind": "brightness", "seq": 4 },
        { "id": "w", "source": "system", "kind": "network", "seq": 6 },
        { "id": "m", "source": "media", "seq": 9 },
        { "id": "n1", "source": "notification", "seq": 2 },
        { "id": "n2", "source": "notification", "seq": 5 },
        { "id": "l", "source": "plugin", "kind": "live", "seq": 7 },
        { "id": "a", "source": "plugin", "kind": "alert", "seq": 3 },
        { "id": "c", "source": "notification", "critical": true, "seq": 1 }
    ], false);
    assert.equal(sides.machine.id, "w");
    assert.deepEqual(sides.apps.map(b => b.id), ["c", "a", "n2", "n1", "l", "m"]);
    assert.deepEqual(plain(activities.bubbleSides([], false)), { "machine": null, "machines": [], "apps": [] });
    assert.deepEqual(plain(activities.bubbleSides(null, false).apps), []);
});

test("a bubble ranks as its plugin's kind or as a notification, a critical one above all, the rest last", () => {
    const rank = bubble => activities.bubbleRank(bubble);
    assert.equal(rank({ "source": "plugin", "kind": "alert" }), activities.kindRank("alert"));
    assert.equal(rank({ "source": "plugin", "kind": "unknown" }), activities.kindRank("live"));
    assert.ok(rank({ "source": "notification", "critical": true }) > rank({ "source": "plugin", "kind": "alert" }));
    assert.ok(rank({ "source": "plugin", "kind": "alert" }) > rank({ "source": "notification" }));
    assert.ok(rank({ "source": "notification" }) > rank({ "source": "plugin", "kind": "live" }));
    assert.ok(rank({ "source": "plugin", "kind": "glance" }) > rank({ "source": "media" }));
    assert.equal(rank({ "source": "media" }), 0);
});

test("machine changes wait on the machine side, the newest first", () => {
    const older = { "id": "older", "source": "system", "kind": "brightness", "seq": -1 };
    const sides = activities.bubbleSides([older, { "id": "system", "source": "system", "kind": "volume", "seq": 0 }, { "id": "n", "source": "notification", "seq": 2 }], true);
    assert.equal(sides.machine.id, "system");
    assert.deepEqual(sides.machines.map(b => b.id), ["system", "older"]);
    assert.deepEqual(sides.apps.map(b => b.id), []);
    assert.equal(activities.bubbleSide({ "id": "p", "source": "plugin", "side": "machine" }), "apps", "only the system source is the machine");
});

test("do not disturb keeps only critical popups and what the user lets through on the apps side", () => {
    const bubbles = [
        { "id": "v", "source": "system", "kind": "volume", "seq": 1 },
        { "id": "n", "source": "notification", "seq": 2 },
        { "id": "l", "source": "plugin", "kind": "live", "seq": 3 },
        { "id": "a", "source": "plugin", "kind": "alert", "seq": 4 },
        { "id": "crit", "source": "notification", "critical": true, "seq": 7 }
    ];
    const sides = activities.bubbleSides(bubbles, true);
    assert.equal(sides.machine.id, "v");
    assert.deepEqual(sides.apps.map(b => b.id), ["crit"], "an alert waits");
    assert.deepEqual(activities.bubbleSides(bubbles, true, b => b.kind === "alert").apps.map(b => b.id).sort(), ["a", "crit"]);
});

test("the machine bubble shows the system source's values, a long value off the pill", () => {
    const volume = { "kind": "volume", "icon": "volume_up", "title": "Volume", "value": "40%", "progress": 0.4 };
    const entry = activities.machineEntry("volume", volume);
    assert.deepEqual([entry.kind, entry.icon, entry.title, entry.detail, entry.text, entry.progress], ["volume", "volume_up", "Volume", "40%", "40%", 0.4]);
    assert.equal(activities.machineEntry("powerprofile", { ...volume, "value": "Performance" }).text, "");
});

test("only levels go to a bubble when the user asks for it", () => {
    assert.equal(activities.levelInBubble("volume", true), true);
    assert.equal(activities.levelInBubble("volume", false), false);
    assert.equal(activities.levelInBubble("capslock", true), false);
});

test("brief info goes to a bubble when the user asks for it, never plugging in or a level", () => {
    for (const kind of ["capslock", "powerprofile", "idleinhibitor"]) {
        assert.equal(activities.briefInBubble(kind, true), true, kind);
        assert.equal(activities.briefInBubble(kind, false), false, kind);
    }
    for (const kind of ["charging", "volume", "mic", "brightness", "plugin", ""])
        assert.equal(activities.briefInBubble(kind, true), false, kind);
});

test("plugging in is a normal info (big, 5 s)", () => {
    assert.equal(activities.faceTier("charging"), 1);
    assert.equal(activities.faceTimeoutMs("charging"), activities.lifetimeMs(1));
    assert.equal(activities.faceTimeoutMs("charging", 2200), activities.lifetimeMs(1), "a glance keeps its lifetime");
});

test("the lasting charge bubble yields to a passing machine bubble, then comes back", () => {
    const charge = { "id": "charge", "source": "system", "kind": "charging", "seq": -1 };
    const volume = { "id": "system", "source": "system", "kind": "volume", "seq": 0 };
    assert.equal(activities.bubbleSides([charge, volume]).machine, volume);
    assert.equal(activities.bubbleSides([charge, volume]).machines[1], charge);
    assert.equal(activities.bubbleSides([charge]).machine, charge);
});

test("an island face lasts a brief info's lifetime, or DMS's own OSD delay the island passes", () => {
    for (const kind of ["volume", "capslock", "powerprofile", "idleinhibitor", ""])
        assert.equal(activities.faceTimeoutMs(kind), 2000, kind);
    assert.equal(activities.faceTimeoutMs("volume", 2200), 2200);
    assert.equal(activities.faceTimeoutMs("powerprofile", 2200), 2200);
});

test("lifetimes per tier: big then compact in the island, a bubble lives the total", () => {
    assert.deepEqual([0, 1, 2].map(t => activities.bigMs(t)), [400, 1400, 2000]);
    assert.deepEqual([0, 1, 2].map(t => activities.compactMs(t)), [1600, 3600, 3600]);
    assert.deepEqual([0, 1, 2].map(t => activities.lifetimeMs(t)), [2000, 5000, 5600]);
    assert.equal(activities.lifetimeMs(1), activities.normalizeOptions({ "kind": "glance" }).timeoutMs);
});

test("a tier out of range is held to the nearest one, a missing one reads as normal", () => {
    const t = activities.tiers;
    assert.deepEqual([-1, t.brief, t.normal, t.important, 7, undefined, null].map(x => activities.tierIndex(x)), [t.brief, t.brief, t.normal, t.important, t.important, t.normal, t.normal]);
});

test("a face's arrival tier: brief for a brief info or a level, normal for the others", () => {
    for (const kind of ["capslock", "powerprofile", "idleinhibitor", "volume", "mic", "brightness"])
        assert.equal(activities.faceTier(kind), activities.tiers.brief, kind);
    for (const kind of ["charging", "plugin", "notification", "media"])
        assert.equal(activities.faceTier(kind), activities.tiers.normal, kind);
});

test("each wing rests at its own width: a wide face on one side never stretches the other", () => {
    assert.equal(activities.wingRest(120, 300), 300);
    assert.equal(activities.wingRest(300, 0), 300, "the last item leaving keeps the wing's own width");
    // One side open on a wide card, the other at rest: each reaches only as far as its own content.
    assert.equal(activities.wingReach(true, true, 400, 120, 8), 408);
    assert.equal(activities.wingReach(true, false, 400, 120, 8), 128);
    assert.equal(activities.wingReach(true, true, 100, 300, 8), 308);
    assert.equal(activities.wingReach(false, true, 400, 120, 8), 0);
});

test("a call or a critical notification shows even from an app the island holds; the rest stays in the list", () => {
    const requests = [{ "pluginId": "discord-rpc", "notifyApp": "Discord" }];
    const held = activities.holdsApp(requests, "Discord", () => "");
    assert.equal(held, true);
    assert.equal(activities.notificationShows(held, true), true);
    assert.equal(activities.notificationShows(held, false), false);
    assert.equal(activities.notificationShows(false, false), true);
});
