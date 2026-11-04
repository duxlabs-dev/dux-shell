import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const rules = loadScript(new URL("../Common/niri/sections/rules.js", import.meta.url));

const windows = [
    { app_id: "org.demo.Mail", title: "Inbox · 12 unread" },
    { app_id: "org.demo.Mail", title: "Drafts · 1" },
    { app_id: "orgXdemoXMail", title: "Inbox" },
    { app_id: "kitty", title: "Inbox (tmux)" }
];

test("titleStem keeps the head before a separator", () => {
    assert.equal(rules.titleStem("Inbox · 12 unread"), "Inbox");
    assert.equal(rules.titleStem("Page — Mozilla Firefox"), "Page");
    assert.equal(rules.titleStem("a-b - c"), "a-b");
    assert.equal(rules.titleStem("  plain  "), "plain");
    assert.equal(rules.titleStem(null), "");
});

test("parsePicked reads niri's window object and ignores a cancel", () => {
    assert.deepEqual({ ...rules.parsePicked('{"id":3,"app_id":"kitty","title":"zsh"}\n') }, { appId: "kitty", title: "zsh" });
    for (const out of ["null\n", "", "garbage", "3"])
        assert.equal(rules.parsePicked(out), null, JSON.stringify(out));
});

test("criteria escape the app-id so dots match only dots", () => {
    const crit = rules.criteria({ appId: "org.demo.Mail", title: "Inbox · 12 unread" }, true, false);
    assert.equal(crit.appId, "^org\\.demo\\.Mail$");
    assert.equal(rules.matchCount(windows, crit), 2);
});

test("matchCount combines app-id and title", () => {
    const crit = rules.criteria({ appId: "org.demo.Mail", title: "Inbox · 12 unread" }, true, true);
    assert.equal(rules.matchCount(windows, crit), 1);
    assert.equal(rules.matchCount(windows, rules.criteria({ appId: "", title: "Inbox · 3" }, false, true)), 3);
});

test("matchCount refuses an empty match and a bad regex", () => {
    assert.equal(rules.matchCount(windows, {}), -1);
    assert.equal(rules.matchCount(windows, { appId: "(" }), -1);
});

test("buildRule writes only the chosen actions", () => {
    const win = { appId: "org.demo.Mail", title: "Inbox" };
    const bare = rules.buildRule(win, { useAppId: true, useTitle: false });
    assert.deepEqual(JSON.parse(JSON.stringify(bare)), { name: "org.demo.Mail", matchCriteria: { appId: "^org\\.demo\\.Mail$" }, actions: {}, enabled: true });
    const full = rules.buildRule(win, { useAppId: true, useTitle: true, workspace: "mail", floating: true, blockOut: true });
    assert.deepEqual(JSON.parse(JSON.stringify(full.actions)), { openOnWorkspace: "mail", openFloating: true, blockOutFrom: "screencast" });
});
