import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const keys = loadScript(new URL("../Common/KeyUtils.js", import.meta.url));
const norm = key => keys.normalizeKeyCombo(key, "Super", "Mod");

test("symbolic Mod renders with the resolved modifier's glyph", () => {
    assert.deepEqual([...keys.formatKeyTokens("Mod+T", "Alt", "Mod")], ["⌥", "T"]);
});

test("conflict normalization treats sway Mod4 as Super", () => {
    assert.equal(keys.normalizeKeyCombo("Mod4+Return", "Super", ""), keys.normalizeKeyCombo("Super+Return", "Super", ""));
});

test("captured modifiers stay literal when the provider has no symbol", () => {
    assert.deepEqual([...keys.withSymbolicMod(["Super", "Shift"], "Super", "")], ["Super", "Shift"]);
});

test("IME commit sink follows Qt's first requested input-context module", () => {
    assert.equal(keys.compositorTextInputSelected(null, null), true, "unset env loads the wayland text-input context");
    assert.equal(keys.compositorTextInputSelected(null, "fcitx"), false, "an in-process module never enables text-input-v3");
    assert.equal(keys.compositorTextInputSelected("fcitx;wayland", "wayland"), false, "QT_IM_MODULES wins and its first entry decides");
    assert.equal(keys.compositorTextInputSelected(";;", "wayland"), true, "empty QT_IM_MODULES entries fall back to QT_IM_MODULE");
});

test("conflict normalization ignores modifier order like niri does", () => {
    const same = [
        ["Shift+Alt+T", "Alt+Shift+T"],
        ["Mod+Shift+Ctrl+Q", "Ctrl+Super+Shift+Q"],
        ["Shift+Alt", "Alt+Shift"],
        ["ISO_Level3_Shift+T", "Mod5+T"]
    ];
    for (const [a, b] of same)
        assert.equal(norm(a), norm(b), `${a} vs ${b}`);
    assert.equal(norm("Alt+Shift_L"), "alt+shift+shift_l", "a modifier keysym trigger keeps its own name");
    assert.notEqual(norm("Mod"), norm("Mod+T"));
});

test("a bare modifier conflicts with its sided keysyms like niri's conflicts_with", () => {
    const cases = [
        ["Alt", "Alt_L", true],
        ["Alt_R", "Alt", true],
        ["Alt_L", "Alt_R", false],
        ["Ctrl+Alt", "Ctrl+Alt_L", true],
        ["Alt", "Ctrl+Alt_L", false],
        ["Alt+T", "Alt_L+T", false]
    ];
    for (const [a, b, want] of cases)
        assert.equal(keys.keyCombosConflict(a, b, "Super", "Mod"), want, `${a} vs ${b}`);

    const binds = [{ action: "spawn user", keys: [{ key: "Alt_L" }, { key: "Alt_R" }] }, { action: "spawn other", keys: [{ key: "Alt_R" }] }];
    assert.equal(keys.getConflictingBinds("Alt", "spawn dms", binds, "Super", "Mod").length, 2);
    assert.equal(keys.getConflictingBinds("Alt_L", "spawn dms", binds, "Super", "Mod").length, 1);
});

test("bare modifier keysyms render as glyphs", () => {
    assert.deepEqual([...keys.formatKeyTokens("Super_L", "Super", "Mod")], ["⌘ L"]);
    assert.deepEqual([...keys.formatKeyTokens("Mod+Control_R", "Super", "Mod")], ["⌘", "⌃ R"]);
});

test("a lone modifier capture becomes a bare-modifier trigger", () => {
    const meta = 16777250, superL = 16777299, shift = 16777248, altMask = 0x08000000;
    assert.equal(keys.bareModifierToken(keys.heldModifiers(superL, 0, []), "Super", "Mod"), "Mod");
    assert.equal(keys.bareModifierToken(keys.heldModifiers(meta, 0x10000000, []), "Alt", "Mod"), "Super");
    const alt = keys.heldModifiers(16777251, 0, []);
    assert.equal(keys.bareModifierToken(keys.heldModifiers(shift, altMask, alt), "Super", "Mod"), "Alt+Shift");
});

test("release and pass-through follow niri's trigger rules", () => {
    const cases = [
        ["Mod+T", true, false],
        ["Mod", true, false],
        ["Mod+MouseLeft", false, false],
        ["Mod+WheelScrollDown", false, true],
        ["Mod+TouchpadScrollUp", false, true],
        ["TabletStylusButton1", false, false]
    ];
    for (const [key, keyboard, scroll] of cases) {
        assert.equal(keys.isKeyboardTrigger(key), keyboard, key);
        assert.equal(keys.isScrollTrigger(key), scroll, key);
    }
});
