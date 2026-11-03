import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const binds = loadScript(new URL("../Common/LauncherKeybinds.js", import.meta.url));

const CTRL = 0x04000000;
const ALT = 0x08000000;
const SHIFT = 0x02000000;
const KEYPAD = 0x20000000;

function actionId(key, modifiers, nativeScanCode = 0, overrides = {}) {
    return binds.actionForEvent({ key, modifiers, nativeScanCode }, overrides)?.id ?? "";
}

test("digit row matches by physical key on AZERTY", () => {
    assert.equal(actionId(38, CTRL, 10), "modeAll", "Ctrl+& is Ctrl+1");
    assert.equal(actionId(201, ALT, 11), "modeApps", "Alt+é is Alt+2, a key KeyUtils cannot name");
    assert.equal(actionId(0x31, CTRL | KEYPAD, 87), "", "keypad 1 is not the digit row");
});

test("ctrl+shift+tab arrives as backtab and cycles backwards", () => {
    assert.equal(actionId(16777218, CTRL | SHIFT), "previousMode");
    assert.equal(actionId(16777217, CTRL), "nextMode");
});

test("overrides replace an action's defaults", () => {
    const overrides = { nextMode: ["Alt+Right"], modeAll: [] };
    assert.equal(actionId(16777236, ALT, 0, overrides), "nextMode");
    assert.equal(actionId(16777217, CTRL, 0, overrides), "", "the default is gone once overridden");
    assert.equal(actionId(0x31, CTRL, 10, overrides), "", "an empty list unbinds");
    assert.equal(actionId(16777218, CTRL | SHIFT, 0, overrides), "previousMode", "other actions keep their defaults");
});
