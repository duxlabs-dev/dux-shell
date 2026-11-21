import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const rules = loadScript(new URL("../Common/DockIconRules.js", import.meta.url));

test("titleKey drops leading spinners and status glyphs", () => {
    assert.equal(rules.titleKey("✳ irc-client"), "irc-client");
    assert.equal(rules.titleKey("⠂ irc-client"), "irc-client");
    assert.equal(rules.titleKey("🔥 build"), "build");
    assert.equal(rules.titleKey("NeAI · claude"), "NeAI · claude");
    assert.equal(rules.titleKey("Äijä"), "Äijä");
    assert.equal(rules.titleKey(""), "");
});

test("findRule matches app and title key, not other apps", () => {
    const list = rules.withRule([], "foot", "irc-client", "material:chat");
    assert.equal(rules.findRule(list, "foot", "◐ irc-client").icon, "material:chat");
    assert.equal(rules.findRule(list, "kitty", "irc-client"), null);
    assert.equal(rules.findRule(list, "foot", "irc"), null);
});

test("withRule replaces an existing rule and withoutRule removes it", () => {
    let list = rules.withRule([], "foot", "irc-client", "material:chat");
    list = rules.withRule(list, "foot", "irc-client", "unicode:I");
    assert.equal(list.length, 1);
    assert.equal(list[0].icon, "unicode:I");
    assert.deepEqual(JSON.parse(JSON.stringify(rules.withoutRule(list, "foot", "irc-client"))), []);
});
