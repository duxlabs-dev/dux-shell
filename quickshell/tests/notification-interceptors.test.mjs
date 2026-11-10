import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const interceptors = loadScript(new URL("../Common/NotificationInterceptors.js", import.meta.url));
const serviceSource = readFileSync(new URL("../Services/NotificationService.qml", import.meta.url), "utf8");
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

function policyService(rules, decision) {
    const calls = { evaluate: 0 };
    const service = serviceFunctions({
        SettingsData: { notificationRules: rules, isNotificationRuleExpired: () => false },
        NotificationInterceptorService: { entries: decision ? [{}] : [], evaluate: () => (calls.evaluate++, decision) },
        IslandActivityService: { canPresentSource: () => true, publish: () => true },
        NotificationUrgency: { Low: 0, Normal: 1, Critical: 2 }
    });
    service._resolveAppNameForRule = notification => notification.appName;
    return { calls, evaluate: notification => JSON.parse(JSON.stringify(service._evaluateNotificationPolicy(notification))) };
}

function serviceFunctions(context) {
    const scope = vm.createContext(context);
    const names = ["_ruleFieldValue", "_coerceRuleUrgency", "_matchesNotificationRule", "_applyPluginInterceptor", "_evaluateNotificationPolicy"];
    for (const match of serviceSource.matchAll(/^    function (\w+)\([^\n]*\) \{\n[\s\S]*?^    \}/gm))
        if (names.includes(match[1]))
            vm.runInContext(match[0], scope);
    return scope;
}

test("a matching user rule wins over every interceptor outcome", () => {
    const overriding = { source: "plugin", result: {
        consume: true, activity: { title: "Swallowed" },
        policy: { drop: true, disablePopup: false, hideFromCenter: true, disableHistory: true, bypassDnd: false, urgency: "low" }
    } };
    const calendar = { appName: "Calendar", desktopEntry: "calendar" };
    const rule = overrides => ({ field: "appName", matchType: "exact", pattern: "Calendar", action: "default", ...overrides });
    const cases = [
        [rule({ action: "mute" }), { drop: false, disablePopup: true, hideFromCenter: false, disableHistory: false }],
        [rule({ bypassDnd: true, urgency: "critical" }), { drop: false, bypassDnd: true, urgency: 2, hideFromCenter: false }],
        [rule({ action: "popup_only" }), { drop: false, disablePopup: false, hideFromCenter: true, disableHistory: true }],
        [rule({ action: "ignore" }), { drop: true }]
    ];
    for (const [userRule, expected] of cases) {
        const result = policyService([userRule], overriding).evaluate(calendar);
        for (const [key, value] of Object.entries(expected))
            assert.equal(result[key], value, `${userRule.action}: ${key}`);
        assert.equal(result.activity, null, `${userRule.action}: consume`);
    }
    const unmatched = policyService([rule({ pattern: "Mail" })], overriding).evaluate(calendar);
    assert.equal(unmatched.hideFromCenter, true);
    assert.deepEqual(unmatched.activity, { source: "plugin", payload: { title: "Swallowed" } });
});

test("no rules and no interceptors skips matching entirely", () => {
    const { calls, evaluate } = policyService([], null);
    assert.equal(evaluate({ appName: "Calendar" }).drop, false);
    assert.equal(calls.evaluate, 0);
});
