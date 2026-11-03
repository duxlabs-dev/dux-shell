import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const shortcuts = loadScript(new URL("../Modules/Notifications/NotificationShortcuts.js", import.meta.url));

test("a slot offers every action except its own, the other slot's, and history when it is off", () => {
    const cases = [
        [["", "", true], ["dnd", "history", "hints", "settings"]],
        [["", "dnd", true], ["history", "hints", "settings"]],
        [["settings", "dnd", true], ["history", "hints"]],
        [["", "dnd", false], ["hints", "settings"]],
        [["", "history", false], ["dnd", "hints", "settings"]]
    ];
    for (const [args, expected] of cases)
        assert.deepEqual([...shortcuts.choices(...args)], expected, args.join(","));
});

test("a stored shortcut is shown only while its action exists", () => {
    assert.equal(shortcuts.isAvailable("history", true), true);
    assert.equal(shortcuts.isAvailable("history", false), false);
    assert.equal(shortcuts.isAvailable("removed-action", true), false);
    assert.equal(shortcuts.isAvailable("", true), false);
});
