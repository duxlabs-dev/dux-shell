import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const source = readFileSync(new URL("../Common/SettingsData.qml", import.meta.url), "utf8");
const serviceSource = readFileSync(new URL("../Services/NotificationService.qml", import.meta.url), "utf8");
const ruleExpiry = loadScript(new URL("../Common/NotificationRuleExpiry.js", import.meta.url));

function load(text, globals, only) {
    const context = vm.createContext(globals);
    const pattern = /^    function (\w+)\(([^)]*)\)(?:: \w+)? \{([\s\S]*?)^    \}/gm;
    for (const [, name, parameters, body] of text.matchAll(pattern))
        if (!only || only.includes(name))
            vm.runInContext(`function ${name}(${parameters.replace(/:\s*\w+/g, "")}) {${body}}`, context);
    return context;
}

function settings(rules) {
    const context = load(source, { notificationRules: rules, RuleExpiry: ruleExpiry });
    context.saveSettings = () => {};
    return context;
}

function policy(rules, notif) {
    const functions = ["_resolveAppNameForRule", "_ruleFieldValue", "_coerceRuleUrgency", "_matchesNotificationRule", "_evaluateNotificationPolicy"];
    const context = load(serviceSource, { SettingsData: { notificationRules: rules, isNotificationRuleExpired: ruleExpiry.isRuleExpired }, NotificationUrgency: { Low: 0, Normal: 1, Critical: 2 } }, functions);
    return plain(context._evaluateNotificationPolicy(notif));
}

const rule = overrides => ({ enabled: true, field: "appName", pattern: "firefox", matchType: "exact", action: "default", urgency: "default", bypassDnd: false, ...overrides });
const plain = value => JSON.parse(JSON.stringify(value));

test("unmute keeps a rule that also bypasses DND", () => {
    const s = settings([rule({ action: "mute", bypassDnd: true })]);
    s.removeMuteRuleForApp("Firefox", "");
    assert.deepEqual(plain(s.notificationRules), [rule({ bypassDnd: true })]);
    assert.equal(s.isAppMuted("Firefox", ""), false);
    assert.equal(s.isAppDndBypassed("Firefox", ""), true);
});

test("block in DND keeps a rule with an action", () => {
    const s = settings([rule({ action: "no_history", bypassDnd: true })]);
    s.setAppDndBypass("Firefox", "", false);
    assert.deepEqual(plain(s.notificationRules), [rule({ action: "no_history" })]);
});

test("rule is removed only when nothing meaningful is left", () => {
    let s = settings([rule({ action: "mute" })]);
    s.removeMuteRuleForApp("Firefox", "");
    assert.deepEqual(plain(s.notificationRules), []);

    s = settings([rule({ bypassDnd: true })]);
    s.setAppDndBypass("Firefox", "", false);
    assert.deepEqual(plain(s.notificationRules), []);

    s = settings([rule({ action: "mute", urgency: "critical" })]);
    s.removeMuteRuleForApp("Firefox", "");
    assert.deepEqual(plain(s.notificationRules), [rule({ urgency: "critical" })]);
});

test("disabled rules are never edited or deleted", () => {
    const disabled = rule({ enabled: false, action: "mute", bypassDnd: true });
    const s = settings([disabled]);
    s.removeMuteRuleForApp("Firefox", "");
    s.setAppDndBypass("Firefox", "", false);
    assert.deepEqual(plain(s.notificationRules), [disabled]);

    s.addMuteRuleForApp("Firefox", "");
    assert.deepEqual(plain(s.notificationRules), [disabled, rule({ pattern: "Firefox", action: "mute" })]);
});

test("mute and DND bypass share one rule instead of shadowing each other", () => {
    const s = settings([rule({ bypassDnd: true })]);
    s.addMuteRuleForApp("Firefox", "");
    assert.deepEqual(plain(s.notificationRules), [rule({ action: "mute", bypassDnd: true })]);

    const t = settings([rule({ action: "no_history" })]);
    t.setAppDndBypass("Firefox", "", true);
    assert.deepEqual(plain(t.notificationRules), [rule({ action: "no_history", bypassDnd: true })]);
});

test("mute next to an exact no_history rule appends a mute rule and unmute removes only it", () => {
    const noHistory = rule({ action: "no_history" });
    const s = settings([noHistory]);
    s.addMuteRuleForApp("Firefox", "");
    assert.deepEqual(plain(s.notificationRules), [noHistory, rule({ pattern: "Firefox", action: "mute" })]);
    assert.equal(s.isAppMuted("Firefox", ""), true);

    s.removeMuteRuleForApp("Firefox", "");
    assert.deepEqual(plain(s.notificationRules), [noHistory]);
    assert.equal(s.isAppMuted("Firefox", ""), false);
});

test("mute applies alongside an earlier rule's action", () => {
    const notif = { appName: "Firefox", summary: "", body: "" };
    let p = policy([rule({ action: "no_history" }), rule({ action: "mute" })], notif);
    assert.equal(p.disablePopup, true);
    assert.equal(p.disableHistory, true);

    p = policy([rule({ pattern: "fire", matchType: "contains" }), rule({ action: "mute" })], notif);
    assert.equal(p.disablePopup, true);

    p = policy([rule({ action: "mute", enabled: false })], notif);
    assert.equal(p.disablePopup, false);
});

test("rules that are not exact app or desktop-entry rules are never read or edited", () => {
    const summary = rule({ field: "summary", matchType: "contains" });
    const s = settings([summary]);
    assert.equal(s.isAppMuted("Firefox", ""), false);
    s.addMuteRuleForApp("Firefox", "");
    assert.deepEqual(plain(s.notificationRules), [summary, rule({ pattern: "Firefox", action: "mute" })]);

    const exactSummary = rule({ field: "summary", action: "mute" });
    const e = settings([exactSummary]);
    assert.equal(e.isAppMuted("Firefox", ""), false);
    e.removeMuteRuleForApp("Firefox", "");
    assert.deepEqual(plain(e.notificationRules), [exactSummary]);

    const regex = rule({ matchType: "regex", action: "mute" });
    const t = settings([regex]);
    assert.equal(t.isAppMuted("Firefox", ""), false);
    t.setAppDndBypass("Firefox", "", true);
    assert.deepEqual(plain(t.notificationRules), [regex, rule({ pattern: "Firefox", bypassDnd: true })]);

    const desktop = rule({ field: "desktopEntry", pattern: "org.mozilla.firefox", action: "mute" });
    const u = settings([desktop]);
    assert.equal(u.isAppMuted("org.mozilla.firefox", "firefox"), false, "a desktopEntry rule is not matched against the app name");
    assert.equal(u.isAppMuted("Firefox", "org.mozilla.firefox"), true);
});

test("an expired timed mute releases the popup but keeps the rule's other settings", () => {
    const notif = { appName: "Firefox", summary: "", body: "" };
    const p = policy([rule({ action: "mute", bypassDnd: true, expiresAt: 1 })], notif);
    assert.equal(p.disablePopup, false);
    assert.equal(p.bypassDnd, true);

    const s = settings([rule({ action: "mute", bypassDnd: true, expiresAt: 1 }), rule({ action: "mute", expiresAt: 1 })]);
    s.pruneExpiredNotificationRules();
    assert.deepEqual(plain(s.notificationRules), [rule({ bypassDnd: true })]);
});
