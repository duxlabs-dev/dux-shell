import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../Services/Fcitx5Service.qml", import.meta.url), "utf8");
const extract = name => {
    const found = source.match(new RegExp(`^    function ${name}\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
    if (!found)
        throw new Error(`${name} not found in Fcitx5Service.qml`);
    return found[0];
};

const calls = [];
const root = { active: true, available: true, currentIM: "" };
const scope = vm.createContext({
    root,
    get active() {
        return root.active;
    },
    get available() {
        return root.available;
    },
    Proc: {
        runCommand(id, command, callback) {
            calls.push({ id, command, callback });
        }
    }
});
for (const fn of ["findItem", "trayIdentityOf", "displayName", "resolve"])
    vm.runInContext(extract(fn), scope);

const resolveWith = (output, exitCode) => {
    calls.length = 0;
    scope.resolve();
    assert.equal(calls.length, 1, "resolve spawns exactly one query");
    calls[0].callback(output, exitCode);
};

test("fcitx5: only the tray item with the fixed Fcitx id is picked", () => {
    const fcitx = { id: "Fcitx", icon: "fcitx-pinyin", tooltipTitle: "Pinyin" };
    const other = { id: "org.kde.StatusNotifierItem-1-1", icon: "x", tooltipTitle: "y" };
    assert.equal(scope.findItem([other, fcitx]), fcitx);
    assert.equal(scope.findItem([other]), null);
    assert.equal(scope.findItem([]), null);
});

test("fcitx5: tray identity changes with either icon or tooltip title", () => {
    const base = { icon: "fcitx-pinyin", tooltipTitle: "Pinyin" };
    assert.equal(scope.trayIdentityOf(base), scope.trayIdentityOf({ icon: "fcitx-pinyin", tooltipTitle: "Pinyin" }));
    assert.notEqual(scope.trayIdentityOf(base), scope.trayIdentityOf({ icon: "fcitx-keyboard-us", tooltipTitle: "Pinyin" }));
    assert.notEqual(scope.trayIdentityOf(base), scope.trayIdentityOf({ icon: "fcitx-pinyin", tooltipTitle: "Hangul" }));
    assert.equal(scope.trayIdentityOf(null), "");
});

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

test("fcitx5: no consumers or no tray item means no fcitx5-remote spawn", () => {
    root.active = false;
    root.available = true;
    root.currentIM = "pinyin";
    scope.resolve();
    assert.equal(calls.length, 0);

    root.active = true;
    root.available = false;
    scope.resolve();
    assert.equal(calls.length, 0);
    assert.equal(root.currentIM, "pinyin");
});

test("fcitx5: the resolved name is the trimmed fcitx5-remote -n output", () => {
    root.active = true;
    root.available = true;
    root.currentIM = "keyboard-us";
    resolveWith("  pinyin\n", 0);
    assert.deepEqual([...calls[0].command], ["fcitx5-remote", "-n"]);
    assert.equal(root.currentIM, "pinyin");
});

test("fcitx5: a failed or empty query leaves the last known name alone", () => {
    root.active = true;
    root.available = true;
    root.currentIM = "pinyin";
    resolveWith("", 1);
    assert.equal(root.currentIM, "pinyin");
    resolveWith("  \n", 0);
    assert.equal(root.currentIM, "pinyin");
});
