import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const expiry = loadScript(new URL("../Common/NotificationRuleExpiry.js", import.meta.url));

// The script runs inside a vm context, so returned objects live in another
// realm; clone them into plain host objects before deep comparisons
// (bar-content.test.mjs pattern).
const plain = value => JSON.parse(JSON.stringify(value));

test("rules without expiresAt never expire", () => {
    assert.equal(expiry.isRuleExpired(null, 1000), false);
    assert.equal(expiry.isRuleExpired({ expiresAt: 0 }, 1000), false);
});

test("timed rules expire strictly after their timestamp", () => {
    const rule = { action: "mute", expiresAt: 5000 };
    assert.equal(expiry.isRuleExpired(rule, 5000), false);
    assert.equal(expiry.isRuleExpired(rule, 5001), true);
});

test("hasTimedRule reports whether any rule carries an expiry", () => {
    assert.equal(expiry.hasTimedRule(null), false);
    assert.equal(expiry.hasTimedRule([{}, { action: "mute" }, { expiresAt: 0 }]), false);
    assert.equal(expiry.hasTimedRule([null, { expiresAt: 0 }, { expiresAt: 5000 }]), true);
});
