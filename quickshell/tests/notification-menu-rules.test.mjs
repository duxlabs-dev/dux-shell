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
    const functions = ["_resolveAppNameForRule", "_ruleFieldValue", "_coerceRuleUrgency", "_matchesNotificationRule", "_applyPluginInterceptor", "_evaluateNotificationPolicy"];
    const context = load(serviceSource, { SettingsData: { notificationRules: rules, isNotificationRuleExpired: ruleExpiry.isRuleExpired }, NotificationInterceptorService: { entries: [], evaluate: () => null }, DesktopEntries: { heuristicLookup: () => null }, NotificationUrgency: { Low: 0, Normal: 1, Critical: 2 } }, functions);
    return plain(context._evaluateNotificationPolicy(notif));
}

const rule = overrides => ({ enabled: true, field: "appName", pattern: "firefox", matchType: "exact", action: "default", urgency: "default", bypassDnd: false, ...overrides });
const plain = value => JSON.parse(JSON.stringify(value));

test("unmute and stop allowing in DND remove the app's own rule", () => {
    let s = settings([rule({ action: "mute" })]);
    s.removeMuteRuleForApp("Firefox", "");
    assert.deepEqual(plain(s.notificationRules), []);

    s = settings([rule({ bypassDnd: true })]);
    s.setAppDndBypass("Firefox", "", false);
    assert.deepEqual(plain(s.notificationRules), []);
});

test("header actions never edit a rule built in the editor", () => {
    const manual = [rule({ action: "mute", bypassDnd: true }), rule({ action: "no_history", bypassDnd: true }), rule({ action: "mute", urgency: "critical" })];
    const s = settings(plain(manual));
    s.removeMuteRuleForApp("Firefox", "");
    s.setAppDndBypass("Firefox", "", false);
    assert.deepEqual(plain(s.notificationRules), manual);
    assert.equal(s.isAppMuted("Firefox", ""), true);
    assert.equal(s.hasOwnAppRule("Firefox", "", "mute", false), false);
    assert.equal(s.isAppDndBypassed("Firefox", ""), true);
    assert.equal(s.hasOwnAppRule("Firefox", "", "default", true), false);
    assert.equal(settings([rule({ action: "mute", expiresAt: 1 })]).hasOwnAppRule("Firefox", "", "mute", false), false);
    assert.deepEqual([rule({ action: "ignore" }), rule({ action: "ignore", bypassDnd: true }), rule({ action: "ignore", matchType: "contains" }), rule({ action: "ignore", conditions: [rule()] }), rule({ action: "ignore", field: "summary" })].map(r => s.isOwnAppRule(r, "ignore", false)), [true, false, false, false, false]);

    const critical = rule({ urgency: "critical" });
    const later = Date.now() + 60000;
    const t = settings([critical]);
    t.addMuteRuleForApp("Firefox", "", later);
    assert.deepEqual(plain(t.notificationRules), [critical, rule({ pattern: "Firefox", action: "mute", expiresAt: later })]);
    t.addMuteRuleForApp("Firefox", "");
    assert.deepEqual(plain(t.notificationRules), [critical, rule({ pattern: "Firefox", action: "mute" })]);
});

test("block, mute and DND each own a rule, ordered so none shadows a manual rule", () => {
    const manual = rule({ pattern: "fire", matchType: "contains", urgency: "low" });
    const notif = { appName: "Firefox", summary: "", body: "" };
    const s = settings([manual]);
    s.addMuteRuleForApp("Firefox", "");
    s.setAppDndBypass("Firefox", "", true);
    s.addIgnoreRuleForApp("Firefox", "");
    const mute = rule({ pattern: "Firefox", action: "mute" });
    const dnd = rule({ pattern: "Firefox", bypassDnd: true });
    assert.deepEqual(plain(s.notificationRules), [rule({ pattern: "Firefox", action: "ignore" }), manual, mute, dnd]);

    s.removeNotificationRule(0);
    assert.deepEqual(plain(s.notificationRules), [manual, mute, dnd]);
    assert.equal(s.hasOwnAppRule("Firefox", "", "mute", false), true);
    assert.equal(s.hasOwnAppRule("Firefox", "", "default", true), true);
    const p = policy(plain(s.notificationRules), notif);
    assert.equal(p.urgency, 0);
    assert.equal(p.disablePopup, true);
    assert.equal(p.bypassDnd, true);
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

test("a sender with no app name or desktop entry can be muted without muting named senders", () => {
    const s = settings([]);
    s.addMuteRuleForApp("", "");
    assert.equal(s.isAppMuted("", ""), true);
    assert.equal(s.isAppMuted("App", ""), false);

    const notif = overrides => ({ appName: "", desktopEntry: "", summary: "5 Apps Updated", body: "", urgency: 1, ...overrides });
    assert.equal(policy(s.notificationRules, notif()).disablePopup, true);
    assert.equal(policy(s.notificationRules, notif({ appName: "App" })).disablePopup, false);
    assert.equal(policy(s.notificationRules, notif({ desktopEntry: "my-tool" })).disablePopup, false);

    s.removeMuteRuleForApp("", "");
    assert.deepEqual(plain(s.notificationRules), []);

    s.addIgnoreRuleForApp("", "");
    s.addIgnoreRuleForApp("", "");
    assert.equal(s.notificationRules.length, 1);
    assert.equal(s.isOwnAppRule(s.notificationRules[0], "ignore", false), true);
});

test("block drops the app even behind an earlier matching rule and is added once", () => {
    const broad = rule({ pattern: "fire", matchType: "contains", urgency: "low" });
    const s = settings([broad]);
    s.addIgnoreRuleForApp("Firefox", "");
    s.addIgnoreRuleForApp("Firefox", "");
    assert.deepEqual(plain(s.notificationRules), [rule({ pattern: "Firefox", action: "ignore" }), broad]);
    assert.equal(policy(plain(s.notificationRules), { appName: "Firefox", summary: "", body: "" }).drop, true);

    const ignore = rule({ action: "ignore" });
    const t = settings([broad, ignore]);
    t.addIgnoreRuleForApp("Firefox", "");
    assert.deepEqual(plain(t.notificationRules), [ignore, broad]);
    assert.equal(policy(plain(t.notificationRules), { appName: "Firefox", summary: "", body: "" }).drop, true);
});
