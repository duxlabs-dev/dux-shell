import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const interceptors = loadScript(new URL("../Common/NotificationInterceptors.js", import.meta.url));
const matcher = info => info.desktopEntry === "dank-calendar";
const handled = info => ({ consume: true, activity: { title: info.summary, icon: "event" } });

test("interceptors validate owners, replace IDs and bound their registry", () => {
    let entries = interceptors.register([], "dankCalendar", "events", 10, matcher, handled, "Calendar events", "Summarize event alerts");
    assert.equal(entries.length, 1);
    assert.equal(entries[0].label, "Calendar events");
    entries = interceptors.register(entries, "dankCalendar", "events", 20, matcher, handled, "Updated events", "");
    assert.equal(entries.length, 1);
    assert.equal(entries[0].priority, 20);
    assert.equal(interceptors.register(entries, "invalid source", "events", 0, matcher, handled), null);
    assert.equal(interceptors.register(entries, "owner", "bad", 0, "not a callback", handled), null);
    const full = Array.from({ length: 128 }, (_, i) => ({ source: "owner", id: String(i) }));
    assert.equal(interceptors.register(full, "other", "more", 0, matcher, handled), null);
});

test("highest-priority matching enabled interceptor consumes and transforms once", () => {
    const lower = { source: "generic", id: "calendar", priority: 5, matcher: () => true, interceptor: () => ({ presentation: { icon: "notifications" } }) };
    const higher = { source: "dankCalendar", id: "event", priority: 20, matcher, interceptor: handled };
    const info = { desktopEntry: "dank-calendar", summary: "Design review" };
    const priorityFor = entry => entry.priority;
    const enabled = entry => entry.source !== "dankCalendar";
    assert.equal(interceptors.evaluate([higher, lower], info, priorityFor, enabled).source, "generic");
    const result = interceptors.evaluate([lower, higher], info, priorityFor, () => true);
    assert.equal(result.source, "dankCalendar");
    assert.equal(result.result.consume, true);
    assert.deepEqual(result.result.activity, { title: "Design review", icon: "event" });
});

test("nonmatches and failing plugin callbacks do not block later interceptors", () => {
    const broken = { source: "broken", id: "rule", priority: 100, matcher: () => { throw new Error("broken plugin"); }, interceptor: handled };
    const calendar = { source: "calendar", id: "events", priority: 10, matcher, interceptor: handled };
    assert.equal(interceptors.evaluate([broken, calendar], { desktopEntry: "dank-calendar", summary: "Event" }, entry => entry.priority, () => true).source, "calendar");
    assert.equal(interceptors.evaluate([calendar], { desktopEntry: "mail", summary: "Message" }, entry => entry.priority, () => true), null);
});
