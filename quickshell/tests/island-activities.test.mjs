import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const activities = loadScript(new URL("../Common/IslandActivities.js", import.meta.url));
const entry = (source, id, payload = {}, now = 1000) => activities.normalize(source, id, { title: "Recording", ...payload }, now);

test("activity updates replace only the matching source and ID", () => {
    const first = entry("recorder", "status", { duration: 0 });
    const other = entry("timer", "status", { duration: 0 });
    const update = entry("recorder", "status", { title: "Saving", duration: 0 }, 2000);
    const entries = activities.upsert([first, other], update, 2000);
    assert.equal(entries.length, 2);
    assert.equal(entries.find(item => item.source === "recorder").title, "Saving");
    assert.equal(entries.find(item => item.source === "timer"), other);
});

test("priority, expiry and routing restore an ongoing recording after a flash", () => {
    const recording = entry("recorder", "status", { duration: 0, screen: "DP-1" });
    const flash = entry("recorder", "message", { duration: 500, priority: 10 }, 1100);
    const entries = activities.upsert([recording], flash, 1100);
    assert.equal(activities.select(entries, "DP-1", "bar", []).id, "message");
    assert.equal(activities.nextExpiry(entries), 1600);
    const expired = entries.filter(item => !item.expiresAt || item.expiresAt > 1600);
    assert.equal(activities.select(expired, "DP-1", "bar", []).id, "status");
    assert.equal(activities.select(expired, "DP-2", "bar", []), null);
    assert.equal(activities.select(expired, "DP-1", "bar", ["recorder"]), null);
    assert.equal(activities.nextExpiry(expired), 0);
    assert.equal(activities.select([entry("timer", "status", { barId: "other" })], "DP-1", "bar", []), null);
});

test("equal-priority publications in the same millisecond prefer the newest", () => {
    const first = entry("recorder", "first");
    const second = entry("timer", "second");
    assert.equal(activities.select([first, second], "screen", "bar", []).id, "second");
});

test("priority classes map consistently while explicit priorities remain supported", () => {
    assert.equal(entry("recording", "start", { priorityClass: "urgent" }).priority, 90);
    assert.equal(entry("system", "volume", { priorityClass: "high" }).priority, 60);
    assert.equal(entry("calendar", "reminder", { priorityClass: "normal" }).priority, 0);
    assert.equal(entry("recorder", "start", { priorityClass: "urgent", priority: 75 }).priority, 75);
});

test("invalid payloads cannot become persistent or unbounded entries", () => {
    for (const duration of [-1, NaN, Infinity, "0", null, 3600001])
        assert.equal(entry("recorder", "status", { duration }), null);
    assert.equal(entry("bad source", "status"), null);
    assert.equal(entry("recorder", "status", { title: "" }), null);
    const bounded = entry("recorder", "status", { title: "x".repeat(1000), body: "x".repeat(10000), progress: 9, background: "invalid", actions: [{ id: "stop", label: "Stop" }, null] });
    assert.equal(bounded.title.length, 256);
    assert.equal(bounded.body.length, 4096);
    assert.equal(bounded.progress, 1);
    assert.equal(bounded.background, "");
    assert.equal(bounded.actions.length, 1);
});

test("the activity limit permits updates and reclaims expired entries", () => {
    const entries = Array.from({ length: 64 }, (_, index) => entry("recorder", String(index), { duration: 0 }));
    assert.equal(activities.upsert(entries, entry("new", "one"), 1000), null);
    assert.equal(activities.upsert(entries, entry("recorder", "0"), 1000).length, 64);
    entries[0] = entry("recorder", "0", { duration: 1 });
    assert.equal(activities.upsert(entries, entry("new", "one"), 1001).length, 64);
});

test("notification templates substitute literal text without interpreting it", () => {
    const info = { summary: "Team meeting", body: "{appName} $&", appName: "Calendar" };
    assert.equal(activities.notificationTitle("{summary} · {body}", info), "Team meeting · {appName} $&");
    assert.equal(activities.notificationTitle("{unknown}", info), "{unknown}");
});

test("island colours accept Theme roles only, and every role resolves to Theme properties", () => {
    const theme = readFileSync(new URL("../Common/Theme.qml", import.meta.url), "utf8");
    for (const colors of Object.values(activities.ROLE_COLORS)) {
        for (const name of [colors.fill, colors.on, colors.tint].filter(Boolean))
            assert.match(theme, new RegExp(`property color ${name}\\b`), name);
    }
    for (const role of activities.SURFACE_ROLES.filter(Boolean))
        assert.ok(activities.roleColors(role), role);
    assert.equal(activities.surfaceRole("error"), "");
    assert.equal(activities.surfaceRole("#ff0000"), "");
    const colored = entry("plugin", "preview", { background: "#ff0000", expandedBackground: "tertiaryContainer", foreground: "warning" });
    assert.equal(colored.background, "");
    assert.equal(colored.expandedBackground, "tertiaryContainer");
    assert.equal(colored.foreground, "warning");
});

function serviceFunctions(file, context, names) {
    const source = readFileSync(new URL(file, import.meta.url), "utf8");
    const scope = vm.createContext(context);
    scope.root = scope;
    for (const match of source.matchAll(/^    function (\w+)\([^\n]*\) \{\n[\s\S]*?^    \}/gm)) {
        if (!names || names.includes(match[1]))
            vm.runInContext(match[0], scope);
    }
    return scope;
}

test("source cleanup, action dispatch and expiry scheduling share the activity registry", () => {
    const invoked = [];
    const expiry = { interval: 0, running: false, stop() { this.running = false; }, start() { this.running = true; } };
    const service = serviceFunctions("../Services/IslandActivityService.qml", {
        Activities: activities, entries: [], renderers: {}, publicationRevision: 0, sessions: [], pendingHosts: {}, announcedHosts: {}, actionQueue: [],
        Date: { now: () => 1000 }, expiry,
        actionInvoked: (...args) => invoked.push(args)
    });
    assert.equal(service.publish("recorder", "status", { title: "Recording", duration: 0, actions: [{ id: "stop", label: "Stop" }] }), true);
    const firstRevision = service.entries[0].revision;
    service.registerRenderer("recorder", {}, {});
    service.scheduleExpiry();
    assert.equal(expiry.running, false);
    assert.equal(service.invoke("recorder", "status", "unknown"), false);
    assert.equal(service.invoke("recorder", "status", "stop"), true);
    assert.deepEqual(invoked, [["recorder", "status", "stop"]]);
    service.publish("recorder", "status", { title: "Updated", duration: 0 });
    assert.ok(service.entries[0].revision > firstRevision);
    service.publish("timer", "flash", { title: "Timer", duration: 400 });
    service.scheduleExpiry();
    assert.equal(expiry.interval, 400);
    assert.equal(expiry.running, true);
    service.clearSource("recorder");
    assert.equal(service.entries.length, 1);
    assert.equal(service.entries[0].source, "timer");
    assert.equal(service.renderers.recorder, undefined);
    assert.equal(service.invoke("recorder", "status", "stop"), false);
    assert.equal(service.remove("timer", "flash"), true);
    service.scheduleExpiry();
    assert.equal(expiry.running, false);
});

test("persistent activities retain their slot after their preview and accept placement overrides", () => {
    const recording = entry("recorder", "status", { persistent: true, category: "status", duration: 1000 });
    assert.equal(recording.persistent, true);
    assert.equal(recording.expiresAt, 0);
    assert.equal(recording.position, "right");
    assert.equal(recording.announce, true);
    const clipboard = entry("clipboard", "status", { duration: 0, position: "center" });
    const slots = activities.stableEntries([recording, clipboard], "DP-1", "bar", [], { recorder: { position: "left", compact: "label", clickActivity: "clipboard" } }, 6);
    assert.equal(slots[0].position, "left");
    assert.equal(slots[0].stableCompact, "label");
    assert.equal(slots[0].clickActivity, "clipboard");
    assert.equal(slots[1].position, "center");
    assert.equal(recording.position, "right");
    assert.equal(activities.stableEntries([recording, clipboard], "DP-1", "bar", ["recorder"], {}, 1)[0].source, "clipboard");
    assert.equal(activities.stableEntries([recording], "DP-1", "bar", [], {}, 0).length, 0);
});

function registry() {
    const expiry = { interval: 0, running: false, stop() { this.running = false; }, start() { this.running = true; } };
    return serviceFunctions("../Services/IslandActivityService.qml", {
        Activities: activities, entries: [], renderers: {}, publicationRevision: 0, sessions: [], pendingHosts: {}, announcedHosts: {}, actionQueue: [],
        Date: { now: () => 1000 }, expiry, actionInvoked() {}, Quickshell: { execDetached() {} }
    });
}

test("custom icon registration preserves full renderers and shares source cleanup", () => {
    const service = registry();
    const compact = {}, expanded = {}, icon = {};
    assert.equal(service.registerIconRenderer("recorder", icon), true);
    assert.equal(service.registerRenderer("recorder", compact, expanded), true);
    assert.equal(service.renderers.recorder.icon, icon);
    assert.equal(service.registerIconRenderer("recorder", null), true);
    assert.equal(service.renderers.recorder.compact, compact);
    assert.equal(service.renderers.recorder.expanded, expanded);
    assert.equal(service.renderers.recorder.icon, null);
    assert.equal(service.registerRenderer("recorder", compact, expanded, icon), true);
    service.clearSource("recorder");
    assert.equal(service.renderers.recorder, undefined);
    assert.equal(service.registerIconRenderer("invalid source", icon), false);
    for (let index = 0; index < 64; index++)
        service.registerIconRenderer(`source${index}`, icon);
    assert.equal(service.registerIconRenderer("overflow", icon), false);
    assert.equal(service.registerIconRenderer("source0", null), true);
});

function session(service) {
    const clock = { now: 1000 };
    const deferred = [];
    const timeout = { interval: 0, running: false, start() { this.running = true; }, stop() { this.running = false; } };
    const instance = serviceFunctions("../Services/IslandActivitySession.qml", {
        Activities: activities, IslandActivityService: service,
        enabled: true, blocked: false, held: false, registered: true,
        screenName: "DP-1", barId: "bar", hostKey: "host", excludedSources: [], defaultDuration: 5000,
        queue: [], current: null, remaining: 0, deadline: 0, timeout,
        Date: { now: () => clock.now }, Qt: { callLater: fn => deferred.push(fn) }
    });
    return { instance, clock, timeout, flush() { while (deferred.length) deferred.shift()(); } };
}

test("a held recording preview resumes its remaining time before the queued preview", () => {
    const service = registry();
    const host = session(service);
    const state = host.instance;
    service.registerSession(state);
    service.publish("recorder", "status", { title: "Recording", persistent: true, category: "status", duration: 1000 });
    service.publish("calendar", "reminder", { title: "Meeting", duration: 3000 });
    host.flush();
    assert.equal(state.current.source, "recorder");
    assert.equal(state.queue.length, 1);
    assert.equal(service.entries.find(entry => entry.source === "calendar").expiresAt, 0);

    host.clock.now = 1400;
    state.held = true;
    state.syncTimer();
    assert.equal(state.remaining, 600);
    assert.equal(host.timeout.running, false);
    host.clock.now = 9000;
    state.held = false;
    state.syncTimer();
    assert.equal(host.timeout.interval, 600);
    state.finishCurrent(state.current);
    host.flush();
    assert.equal(service.entries.find(entry => entry.source === "recorder").persistent, true);
    assert.equal(service.entries.find(entry => entry.source === "recorder").announce, false);
    assert.equal(state.current.source, "calendar");
    assert.equal(host.timeout.interval, 3000);
    state.finishCurrent(state.current);
    host.flush();
    assert.equal(state.current, null);
    assert.equal(host.timeout.running, false);
    assert.deepEqual(Array.from(service.entries, entry => entry.source), ["recorder"]);
});

test("ongoing updates avoid replaying previews and explicit announcements reuse the same slot", () => {
    const service = registry();
    const host = session(service);
    service.registerSession(host.instance);
    service.publish("recorder", "status", { title: "Recording", persistent: true, duration: 1000 });
    host.instance.finishCurrent(host.instance.current);
    host.flush();
    service.publish("recorder", "status", { title: "00:10", persistent: true, duration: 1000 });
    assert.equal(host.instance.current, null);
    assert.equal(host.instance.queue.length, 0);
    service.publish("recorder", "status", { title: "Paused", persistent: true, duration: 1000, announce: true });
    assert.equal(host.instance.current.title, "Paused");
    assert.equal(service.entries.length, 1);
    service.remove("recorder", "status");
    host.flush();
    assert.equal(host.instance.current, null);
    assert.equal(host.timeout.running, false);
});

test("a running initial preview settles even when a sheet blocks the next event", () => {
    const service = registry();
    const host = session(service);
    const state = host.instance;
    service.registerSession(state);
    service.publish("recorder", "status", { title: "Recording", persistent: true, duration: 1000 });
    service.publish("calendar", "event", { title: "Meeting", duration: 3000 });
    host.clock.now = 1400;
    state.blocked = true;
    state.syncTimer();
    assert.equal(host.timeout.running, true);
    assert.equal(host.timeout.interval, 600);
    state.finishCurrent(state.current);
    host.flush();
    assert.equal(state.current, null);
    assert.equal(state.queue.length, 1);
    assert.equal(service.entries.find(entry => entry.source === "recorder").persistent, true);
    state.blocked = false;
    state.advance();
    assert.equal(state.current.source, "calendar");
    assert.equal(host.timeout.interval, 3000);
});

test("silent status updates preserve both the active and queued preview durations", () => {
    const service = registry();
    const host = session(service);
    const state = host.instance;
    service.registerSession(state);
    service.publish("recorder", "status", { title: "Recording", persistent: true, duration: 1000 });
    service.publish("timer", "status", { title: "Timer", persistent: true, duration: 2000 });
    host.clock.now = 1500;
    service.publish("recorder", "status", { title: "00:01", duration: 0 });
    service.publish("timer", "status", { title: "00:02", duration: 0 });
    assert.equal(state.current.duration, 1000);
    assert.equal(state.queue[0].duration, 2000);
    state.held = true;
    state.syncTimer();
    state.held = false;
    state.syncTimer();
    assert.equal(host.timeout.interval, 500);
    state.finishCurrent(state.current);
    host.flush();
    assert.equal(state.current.source, "timer");
    assert.equal(host.timeout.interval, 2000);
});

test("queue saturation cannot retain an unqueued transient forever", () => {
    const service = registry();
    const host = session(service);
    const state = host.instance;
    state.blocked = true;
    service.registerSession(state);
    state.queue = Array.from({length: 64}, (_, index) => entry("queue", String(index)));
    assert.equal(service.publish("calendar", "event", {title: "Meeting", duration: 1000}), false);
    assert.equal(service.entries.length, 0);
    assert.equal(service.publish("recorder", "status", {title: "Recording", persistent: true, duration: 1000}), true);
    assert.equal(service.pendingHosts[activities.identity(service.entries[0])].length, 0);
    assert.equal(state.queue.length, 64);
    assert.equal(service.entries[0].persistent, true);
});

test("one host completing a queued activity does not drop it from another host", () => {
    const service = registry();
    const first = session(service);
    const second = session(service);
    second.instance.hostKey = "other";
    second.instance.blocked = true;
    service.registerSession(first.instance);
    service.registerSession(second.instance);
    service.publish("calendar", "event", { title: "Meeting", duration: 1000 });
    first.instance.finishCurrent(first.instance.current);
    assert.equal(service.entries.length, 1);
    assert.equal(second.instance.queue.length, 1);
    second.instance.blocked = false;
    second.instance.advance();
    second.instance.finishCurrent(second.instance.current);
    assert.equal(service.entries.length, 0);
});

test("republishing to another screen clears the preview from islands it left", () => {
    const service = registry();
    const first = session(service);
    const second = session(service);
    second.instance.screenName = "DP-2";
    second.instance.hostKey = "other";
    service.registerSession(first.instance);
    service.registerSession(second.instance);
    service.publish("download", "file", { title: "Download", screen: "DP-1", duration: 5000 });
    assert.equal(first.instance.current.id, "file");
    service.publish("download", "file", { title: "Download", screen: "DP-2", duration: 5000 });
    assert.equal(first.instance.current, null);
    assert.equal(second.instance.current.id, "file");
    assert.equal(service.entries.length, 1, "the stale host's acknowledgement must not remove the new revision");
});

test("re-seeding a host never replays a preview it already finished", () => {
    const service = registry();
    const first = session(service);
    const second = session(service);
    second.instance.hostKey = "other";
    second.instance.blocked = true;
    service.registerSession(first.instance);
    service.registerSession(second.instance);
    service.publish("calendar", "event", { title: "Meeting", duration: 1000 });
    first.instance.finishCurrent(first.instance.current);
    first.flush();
    first.instance.reconfigure();
    assert.equal(first.instance.current, null);
    assert.equal(first.instance.queue.length, 0);
    assert.equal(second.instance.queue.length, 1);
});

test("higher-priority preemptible events interrupt, then resume the active preview", () => {
    const queue = [entry("a", "one"), entry("b", "two")];
    const updated = activities.enqueue(queue, entry("a", "one", { title: "Updated" }, 2000));
    assert.equal(activities.nextEvent(updated).source, "a");
    assert.equal(activities.nextEvent(activities.enqueue(updated, entry("urgent", "one", { priority: 100 }))).source, "urgent");
    const service = registry();
    const host = session(service);
    service.registerSession(host.instance);
    service.publish("a", "one", { title: "First", duration: 1000 });
    host.clock.now = 1200;
    host.instance.syncTimer();
    service.publish("urgent", "one", { title: "Urgent", priorityClass: "urgent", preemption: "higher", duration: 500 });
    assert.equal(host.instance.current.source, "urgent");
    assert.equal(host.instance.queue[0].source, "a");
    assert.equal(host.instance.queue[0].duration, 800);
    host.clock.now = 1700;
    host.instance.finishCurrent(host.instance.current);
    host.flush();
    assert.equal(host.instance.current.source, "a");
    assert.equal(host.timeout.interval, 800);
});

test("IPC action polling drains only the requested source and stays bounded", () => {
    const service = registry();
    service.publish("recorder", "status", { title: "Recording", duration: 0, clickAction: "open" });
    service.publish("calendar", "status", { title: "Meeting", duration: 0, actions: [{ id: "open", label: "Open" }] });
    assert.equal(service.invoke("recorder", "status", "unknown"), false);
    for (let i = 0; i < 70; i++)
        service.invoke("recorder", "status", "open");
    service.invoke("calendar", "status", "open");
    assert.equal(service.actionQueue.length, 64);
    assert.equal(JSON.parse(service.pollActions("recorder")).length, 63);
    assert.equal(JSON.parse(service.pollActions("recorder")).length, 0);
    assert.equal(JSON.parse(service.pollActions("calendar"))[0].source, "calendar");
});

test("availability and source checks reflect live Island hosts and their settings", () => {
    const sessions = [
        { screenName: "DP-1", barId: "primary", enabled: true, notificationsEnabled: true, excludedSources: [] },
        { screenName: "DP-2", barId: "secondary", enabled: false, notificationsEnabled: false, excludedSources: ["workspace"] }
    ];
    const service = serviceFunctions("../Services/IslandActivityService.qml", { sessions }, ["canPresentSource", "availabilityOn", "availability"]);

    assert.equal(service.availability().islandPresent, true);
    assert.equal(service.availability().activitiesAvailable, true);
    assert.deepEqual(JSON.parse(JSON.stringify(service.availability().screens)), [
        { screen: "DP-1", islandPresent: true, activitiesAvailable: true, notificationsAvailable: true, hosts: [{ barId: "primary", activitiesEnabled: true, notificationsEnabled: true }] },
        { screen: "DP-2", islandPresent: true, activitiesAvailable: false, notificationsAvailable: false, hosts: [{ barId: "secondary", activitiesEnabled: false, notificationsEnabled: false }] }
    ]);
    assert.equal(service.canPresentSource("workspace", "DP-1"), true);
    assert.equal(service.canPresentSource("workspace", { name: "DP-1" }), true);
    assert.equal(service.canPresentSource("workspace", "DP-2"), false);
    assert.equal(service.canPresentSource("recording", "DP-2"), false);
    sessions.splice(0, 2);
    assert.deepEqual(JSON.parse(JSON.stringify(service.availability())), { islandPresent: false, activitiesAvailable: false, notificationsAvailable: false, screens: [] });
});

test("notification summaries respect existing matching and popup policy", () => {
    const presentation = { icon: "event", title: "{body}" };
    const rule = { field: "desktopEntry", matchType: "exact", pattern: "calendar", islandPresentation: presentation, action: "mute" };
    const service = serviceFunctions("../Services/NotificationService.qml", {
        SettingsData: { notificationRules: [rule], isNotificationRuleExpired: () => false },
        NotificationInterceptorService: { evaluate: () => null },
        IslandActivityService: { canPresentSource: () => false, publish: () => false },
        NotificationUrgency: { Low: 0, Normal: 1, Critical: 2 },
        log: { warn() {} }
    }, ["_ruleFieldValue", "_coerceRuleUrgency", "_matchesNotificationRule", "_applyPluginInterceptor", "_evaluateNotificationPolicy"]);
    service._resolveAppNameForRule = notification => notification.appName;
    const matched = service._evaluateNotificationPolicy({ appName: "Calendar", desktopEntry: "calendar" });
    assert.equal(matched.islandPresentation, presentation);
    assert.equal(matched.disablePopup, true);
    assert.equal(matched.drop, false);
    assert.equal(matched.hideFromCenter, false);
    assert.equal(matched.bypassDnd, false);
    assert.equal(service._evaluateNotificationPolicy({ appName: "Other", desktopEntry: "other" }).islandPresentation, null);
    rule.enabled = false;
    assert.equal(service._evaluateNotificationPolicy({ appName: "Calendar", desktopEntry: "calendar" }).islandPresentation, null);
});

test("plugin notification interceptors can consume into a live activity", () => {
    let published = null;
    const service = serviceFunctions("../Services/NotificationService.qml", {
        SettingsData: { notificationRules: [], isNotificationRuleExpired: () => false },
        NotificationUrgency: { Low: 0, Normal: 1, Critical: 2 },
        NotificationInterceptorService: { entries: [{}], activitySequence: 0, evaluate: () => ({ source: "dankCalendar", result: { consume: true, activity: { title: "Design review", icon: "event" } } }) },
        IslandActivityService: { canPresentSource: source => source === "dankCalendar", publish: (source, id, activity) => (published = { source, id, activity }, true) },
        Activities: activities,
        log: { warn() {} }
    }, ["_ruleFieldValue", "_coerceRuleUrgency", "_matchesNotificationRule", "_applyPluginInterceptor", "_publishInterceptedActivity", "_evaluateNotificationPolicy"]);
    service._resolveAppNameForRule = notification => notification.appName;
    const policy = service._evaluateNotificationPolicy({ appName: "Dank Calendar", summary: "Design review" });
    assert.equal(policy.drop, false);
    assert.deepEqual(JSON.parse(JSON.stringify(policy.activity)), { source: "dankCalendar", payload: { title: "Design review", icon: "event" } });
    assert.equal(published, null);
    assert.equal(service._publishInterceptedActivity(policy.activity), true);
    assert.equal(published.source, "dankCalendar");
    assert.equal(published.activity.title, "Design review");
    assert.equal(published.id, "notification-1");
    service._publishInterceptedActivity({ source: "dankCalendar", payload: { id: "review-42", title: "Design review" } });
    assert.equal(published.id, "review-42", "a plugin id lets the plugin update or remove it later");
});

test("consuming a notification needs an island on the activity's own screen and bar", () => {
    const islands = serviceFunctions("../Services/IslandActivityService.qml", {
        sessions: [{ screenName: "DP-1", barId: "bar", enabled: true, excludedSources: [] }]
    }, ["canPresentSource"]);
    let published = 0;
    const service = serviceFunctions("../Services/NotificationService.qml", {
        NotificationInterceptorService: { activitySequence: 0 },
        IslandActivityService: { canPresentSource: islands.canPresentSource, publish: () => (++published, true) },
        Activities: activities
    }, ["_publishInterceptedActivity"]);
    for (const [payload, expected] of [[{}, true], [{ screen: "DP-1", barId: "bar" }, true], [{ screen: "DP-2" }, false], [{ screen: "DP-1", barId: "other" }, false]])
        assert.equal(service._publishInterceptedActivity({ source: "calendar", payload: Object.assign({ title: "Review" }, payload) }), expected, JSON.stringify(payload));
    assert.equal(published, 2);
});

test("blocked sheets defer preemption without losing the running preview", () => {
    const service = registry();
    const host = session(service);
    service.registerSession(host.instance);
    service.publish("download", "one", { title: "Download", duration: 3000 });
    host.instance.blocked = true;
    host.instance.enqueue(entry("urgent", "one", { priorityClass: "urgent", preemption: "higher", duration: 500 }));
    assert.equal(host.instance.current.source, "download");
    assert.equal(host.instance.queue[0].source, "urgent");
});

test("a full queue never drops the interrupted preview", () => {
    const service = registry();
    const host = session(service);
    service.registerSession(host.instance);
    service.publish("download", "one", { title: "Download", duration: 3000 });
    host.instance.queue = Array.from({ length: 63 }, (_, i) => entry("queued", String(i), { title: "Queued" }));
    host.instance.enqueue(entry("urgent", "one", { priorityClass: "urgent", preemption: "higher", duration: 500 }));
    assert.equal(host.instance.current.source, "download");
    assert.equal(host.instance.queue.length, 64);
});

test("external persistent activities expire and renew through the existing registry timer", () => {
    const service = registry();
    let now = 1000;
    service.Date.now = () => now;
    const host = session(service);
    service.registerSession(host.instance);
    service.publish("external", "job", { title: "Job", persistent: true, ttl: 2000 }, true);
    service.scheduleExpiry();
    assert.equal(service.expiry.interval, 2000);
    now = 2000;
    service.publish("external", "job", { title: "Updated", persistent: true, ttl: 2000 }, true);
    assert.equal(service.entries[0].expiresAt, 4000);
    now = 3100;
    service.expireEntries();
    assert.equal(service.entries.length, 1);
    now = 4000;
    service.expireEntries();
    assert.equal(service.entries.length, 0);
    assert.equal(host.instance.current, null);
    assert.equal(Object.keys(service.pendingHosts).length, 0);
    service.scheduleExpiry();
    assert.equal(service.expiry.running, false);
});

test("external publishers get a bounded lifetime while plugin lifetime follows unload", () => {
    const service = registry();
    service.publish("external", "job", { title: "Job", duration: 0 }, true);
    service.publish("plugin", "job", { title: "Job", duration: 0 });
    assert.ok(service.entries[0].expiresAt > 1000);
    assert.equal(service.entries[1].expiresAt, 0);
    for (const ttl of [-1, Infinity, "2000", 86400001])
        assert.equal(service.publish("external", "bad", { title: "Bad", persistent: true, ttl }, true), false);
});

test("silent updates do not prevent an interrupted preview from resuming", () => {
    const service = registry();
    const host = session(service);
    service.registerSession(host.instance);
    service.publish("download", "job", { title: "Download", persistent: true });
    service.publish("download", "job", { title: "Halfway", persistent: true });
    host.instance.enqueue(entry("urgent", "one", { priorityClass: "urgent", preemption: "higher", duration: 500 }));
    assert.equal(host.instance.current.source, "urgent");
    host.instance.finishCurrent(host.instance.current);
    host.flush();
    assert.equal(host.instance.current.source, "download");
    assert.equal(host.instance.current.title, "Halfway");
});

test("silent updates retain slot order and visibility even for simultaneous publications", () => {
    for (const secondTime of [1000, 1100]) {
        let entries = activities.upsert([], entry("timer", "one", {duration: 0}), 1000);
        entries = activities.upsert(entries, entry("transfer", "two", {duration: 0}, secondTime), secondTime);
        entries = activities.upsert(entries, entry("timer", "one", {duration: 0, value: "0:02"}, 2000), 2000);
        assert.equal(activities.stableEntries(entries, "screen", "bar", [], {}, 1)[0].source, "timer");
        assert.equal(entries.find(item => item.source === "timer").value, "0:02");
        entries = activities.upsert(entries, entry("transfer", "two", {duration: 0, priority: 10}, 2100), 2100);
        assert.equal(activities.stableEntries(entries, "screen", "bar", [], {}, 1)[0].source, "transfer");
    }
});

test("action availability is enforced for both button and click dispatch", () => {
    const service = registry();
    for (const state of [{enabled: false}, {pending: true}, {enabled: true, pending: false}]) {
        service.publish("timer", "one", {title: "Timer", duration: 0, clickAction: "pause", actions: [{id: "pause", label: "Pause", role: "primary", ...state}]});
        assert.equal(service.invoke("timer", "one", "pause"), state.enabled !== false && !state.pending);
    }
    const payload = entry("timer", "one", {value: "x".repeat(200), status: "x".repeat(500), actions: [{id: "cancel", label: "Cancel", role: "destructive"}]});
    assert.equal(payload.value.length, 128);
    assert.equal(payload.status.length, 256);
    assert.equal(payload.actions[0].role, "destructive");
});

test("IPC payloads share the CLI's 64 KiB UTF-8 boundary", () => {
    for (const [text, count] of [["x", 65536], ["é", 32768], ["界", 21845], ["😀", 16384]]) {
        assert.equal(activities.validPayloadSize(text.repeat(count)), true);
        assert.equal(activities.validPayloadSize(text.repeat(count + 1)), false);
    }
});
