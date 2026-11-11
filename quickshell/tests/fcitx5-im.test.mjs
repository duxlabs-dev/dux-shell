import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const schema = loadScript(new URL("../Common/fcitx5Schema.js", import.meta.url));

// Expected values are what libFcitx5Utils' Key::normalize() returns for the same key press.
test("fcitx5: recorded keys are stored in the form fcitx5 matches", () => {
    const cases = [
        ["A", false, "a"],
        ["A", true, "A"],
        ["Ctrl+A", false, "Control+A"],
        ["Ctrl+A", true, "Control+Shift+A"],
        ["Super+Alt+Ctrl+P", true, "Control+Alt+Shift+Super+P"],
        ["Comma", false, "comma"],
        ["Ctrl+Comma", false, "Control+comma"],
        ["BracketLeft", false, "bracketleft"],
        ["Minus", false, "minus"],
        ["exclam", true, "exclam"],
        ["Ctrl+exclam", true, "Control+exclam"],
        ["Shift+Tab", true, "Shift+Tab"],
        ["Ctrl+Shift+Tab", true, "Control+Shift+Tab"],
        ["space", true, "Shift+space"],
        ["F1", true, "Shift+F1"],
        ["KP_1", true, "KP_1"],
        ["Adiaeresis", false, "adiaeresis"],
        ["Ctrl+Adiaeresis", false, "Control+adiaeresis"],
        ["Adiaeresis", true, "Adiaeresis"],
        ["Ctrl+Adiaeresis", true, "Control+Adiaeresis"],
        ["Ctrl+BackSpace", true, "Control+BackSpace"],
        ["XF86AudioMute", false, "AudioMute"]
    ];
    for (const [token, shift, want] of cases)
        assert.equal(schema.fcitxKey(token, shift), want, `${token} shift=${shift}`);
});

test("fcitx5: released modifiers keep the last pressed as the key", () => {
    const cases = [
        [["Shift_L"], "Shift_L"],
        [["Alt_L", "Shift_L"], "Alt+Shift_L"],
        [["Shift_L", "Alt_L"], "Shift+Alt_L"],
        [["Alt_R", "Shift_R"], "Alt+Shift_R"],
        [["Shift_L", "Alt_L", "Control_L"], "Alt+Shift+Control_L"],
        [["Super_L", "Control_R", "Shift_L"], "Control+Super+Shift_L"]
    ];
    for (const [held, want] of cases)
        assert.equal(schema.modifierChord(held), want, held.join(" then "));
});

test("fcitx5: modifier keys follow the layout and take their side from the scan code", () => {
    const LEFT_ALT = 64, RIGHT_ALT = 108, LEFT_WIN = 133, CAPS = 66;
    const cases = [
        ["Shift", 62, false, "Shift_R"],
        ["Ctrl", 37, false, "Control_L"],
        ["Alt", RIGHT_ALT, false, "Alt_R"],
        ["Super", LEFT_WIN, false, "Super_L"],
        ["Super", LEFT_ALT, false, "Super_L"],
        ["Alt", LEFT_WIN, false, "Alt_L"],
        ["Ctrl", CAPS, false, "Control_L"],
        ["Super", LEFT_ALT, true, "Alt_L"],
        ["Super", LEFT_WIN, true, "Super_L"],
        ["", 50, true, "Shift_L"],
        ["", CAPS, false, ""]
    ];
    for (const [modifier, scan, shift, want] of cases)
        assert.equal(schema.modifierOnlyKey(modifier, scan, shift), want, `${modifier} scan=${scan} shift=${shift}`);
});

test("fcitx5: key rows only allow what the schema flags, on lists and single keys", () => {
    const flags = props => {
        const built = schema.buildRows({ structs: [{ name: "C", fields: [{ name: "K", type: "List|Key", props }] }] }, "C", []);
        return [built.rows[0].modifierless, built.rows[0].modifierOnly];
    };
    assert.deepEqual(flags({ ListConstrain: "" }), [false, false]);
    assert.deepEqual(flags({ ListConstrain: { AllowModifierLess: "True" } }), [true, false]);
    assert.deepEqual(flags({ ListConstrain: { AllowModifierLess: "True", AllowModifierOnly: "True" } }), [true, true]);
    assert.deepEqual(flags({ AllowModifierLess: "True" }), [true, false]);
    assert.deepEqual(flags({}), [true, true]);
    assert.deepEqual(flags({ Tooltip: "tip" }), [true, true]);
});

const source = readFileSync(new URL("../Services/Fcitx5Service.qml", import.meta.url), "utf8");
const extract = name => {
    const found = source.match(new RegExp(`^    function ${name}\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
    if (!found)
        throw new Error(`${name} not found in Fcitx5Service.qml`);
    return found[0];
};

const calls = [];
const root = {
    active: true,
    editable: true,
    currentIM: "",
    request(method, params, callback, quiet) {
        calls.push({ method, params, callback, quiet });
    }
};
const scope = vm.createContext({
    root,
    get active() {
        return root.active;
    },
    get editable() {
        return root.editable;
    },
    request: (...args) => root.request(...args)
});
for (const fn of ["displayName", "resolve"])
    vm.runInContext(extract(fn), scope);

const resolveWith = (result, error) => {
    calls.length = 0;
    scope.resolve();
    assert.equal(calls.length, 1, "resolve sends exactly one request");
    calls[0].callback(result, error);
};

test("fcitx5: only the last segment of a keyboard tooltip title is kept", () => {
    assert.equal(scope.displayName("Keyboard - English (US)", "keyboard-us"), "English (US)");
    assert.equal(scope.displayName("Tastatur - Englisch (US)", "keyboard-de"), "Englisch (US)");
    assert.equal(scope.displayName("Hangul", "hangul"), "Hangul");
});

test("fcitx5: a keyboard variant shows its variant description without the layout name", () => {
    assert.equal(
        scope.displayName("Keyboard - English (US) - English (US, intl., with dead keys)", "keyboard-us-intl"),
        "English (US, intl., with dead keys)"
    );
    assert.equal(
        scope.displayName("Keyboard - Berber (Algeria, Latin) - Kabyle (AZERTY, with dead keys)", "keyboard-dz-azerty-deadkeys"),
        "Kabyle (AZERTY, with dead keys)"
    );
});

test("fcitx5: a missing or generic tooltip title falls back to the raw name", () => {
    assert.equal(scope.displayName("", "keyboard-us"), "keyboard-us");
    assert.equal(scope.displayName("   ", "keyboard-us"), "keyboard-us");
    assert.equal(scope.displayName("Input Method", "keyboard-us"), "keyboard-us");
    assert.equal(scope.displayName("  Keyboard - English (US)  ", "keyboard-us"), "English (US)");
});

test("fcitx5: no consumers or no editable backend means no request", () => {
    root.active = false;
    root.editable = true;
    root.currentIM = "pinyin";
    scope.resolve();
    assert.equal(calls.length, 0);

    root.active = true;
    root.editable = false;
    scope.resolve();
    assert.equal(calls.length, 0);
    assert.equal(root.currentIM, "pinyin");
});

test("fcitx5: the resolved name is the trimmed currentIM result", () => {
    root.active = true;
    root.editable = true;
    root.currentIM = "keyboard-us";
    resolveWith({ name: "  pinyin\n" }, "");
    assert.equal(calls[0].method, "currentIM");
    assert.equal(calls[0].quiet, true, "a background query never shows an error toast");
    assert.equal(root.currentIM, "pinyin");
});

test("fcitx5: a failed or empty query leaves the last known name alone", () => {
    root.active = true;
    root.editable = true;
    root.currentIM = "pinyin";
    resolveWith(null, "boom");
    assert.equal(root.currentIM, "pinyin");
    resolveWith({ name: "  " }, "");
    assert.equal(root.currentIM, "pinyin");
});
