import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const km = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/niri/keymaps.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), km);

const place = (rows, sym) => {
    for (let r = 0; r < rows.length; r++) {
        const key = rows[r].find(k => k.sym === sym);
        if (key)
            return [r, key.col];
    }
    return null;
};

test("Super+Q on AZERTY sits on the key QWERTY prints A", () => {
    assert.deepEqual(place(km.rows("fr"), "Q"), place(km.rows("us"), "A"));
    assert.deepEqual(place(km.rows("fr"), "A"), place(km.rows("us"), "Q"));
    assert.deepEqual(place(km.rows("de"), "Z"), place(km.rows("us"), "Y"));
});

test("every row fills the 60 columns without overlap", () => {
    for (const id of ["us", "fr", "de"]) {
        for (const row of km.rows(id)) {
            const flat = row.filter(k => k.half !== "top");
            let col = 0;
            for (const k of flat) {
                assert.equal(k.col, col, id + " " + (k.sym || k.label));
                col += k.w;
            }
            assert.equal(col, 60, id);
        }
    }
});

test("niri layout names pick a keysym table", () => {
    assert.equal(km.layoutOf("French (AZERTY)"), "fr");
    assert.equal(km.layoutOf("French"), "fr");
    assert.equal(km.layoutOf("German (no dead keys)"), "de");
    assert.equal(km.layoutOf("English (US)"), "us");
    assert.equal(km.layoutOf(""), "us");
    assert.equal(km.layoutOf(undefined), "us");
});

test("chords compare whatever the spelling and order", () => {
    assert.equal(km.chordId("Mod+Shift+q", "Super"), km.chordId("Shift+Super+Q", "Super"));
    assert.equal(km.chordId("Mod+Q", "Alt"), km.chordId("Alt+Q", "Super"));
    assert.equal(km.chordId("Win+Control+slash", "Super"), km.chordId("Super+Ctrl+Slash", "Super"));
    assert.notEqual(km.chordId("Mod+Q", "Super"), km.chordId("Mod+Shift+Q", "Super"));
});

test("binds index by chord, every key of a group", () => {
    const groups = [
        { category: "Window", action: "close-window", desc: "Close", keys: [{ key: "Mod+Q" }, { key: "Mod+W" }] },
        { category: "Execute", action: "spawn alacritty", desc: "", keys: [{ key: "Super+Q" }] }
    ];
    const map = km.bindMap(groups, "Super");
    assert.equal(map[km.chordId("Super+Q", "Super")].length, 2);
    assert.equal(map[km.chordId("Super+W", "Super")][0].category, "Window");
    assert.equal(map[km.chordId("Super+E", "Super")], undefined);
});

test("the same action on several keys is not a double", () => {
    const groups = [
        { category: "Focus", action: "focus-column-left", keys: [{ key: "Mod+Left", isDMSManaged: true }, { key: "Mod+H", isDMSManaged: true }] },
        { category: "Focus", action: "focus-column-right", keys: [{ key: "Mod+Right", isDMSManaged: true }, { key: "Mod+L", isDMSManaged: true }] }
    ];
    assert.deepEqual(Array.from(km.doubleKeys(groups, "Super")), []);
});

test("a key bound twice offers its DMS copy, the other binding stays", () => {
    const groups = [
        { category: "Execute", action: "spawn alacritty", keys: [{ key: "Mod+T", isDMSManaged: false }] },
        { category: "Execute", action: "spawn foot", keys: [{ key: "Super+T", isDMSManaged: true }, { key: "Mod+Return", isDMSManaged: true }] },
        { category: "Window", action: "close-window", keys: [{ key: "Mod+Q", isDMSManaged: true }] },
        { category: "Window", action: "close-window", keys: [{ key: "Super+Q", isDMSManaged: true }] }
    ];
    assert.deepEqual(Array.from(km.doubleKeys(groups, "Super")), ["Super+T", "Super+Q"]);
});

test("a key the config binds too, behind a DMS bind, is a double", () => {
    const groups = [
        { category: "Execute", action: "spawn foot", conflict: { key: "Mod+T", action: "spawn alacritty" }, keys: [{ key: "Mod+T", isDMSManaged: true }, { key: "Mod+Return", isDMSManaged: true }] }
    ];
    assert.deepEqual(Array.from(km.doubleKeys(groups, "Super")), ["Mod+T"]);
});

test("a key bound twice only in config.kdl offers nothing to remove", () => {
    const groups = [
        { category: "Execute", action: "spawn alacritty", keys: [{ key: "Mod+T", isDMSManaged: false }] },
        { category: "Execute", action: "spawn foot", keys: [{ key: "Super+T", isDMSManaged: false }] }
    ];
    assert.deepEqual(Array.from(km.doubleKeys(groups, "Super")), []);
});

test("the clean-up plan carries what an undo needs to re-add each bind", () => {
    const groups = [
        { category: "Execute", action: "spawn alacritty", keys: [{ key: "Mod+T", isDMSManaged: false }] },
        {
            category: "Execute",
            action: "spawn foot",
            keys: [{
                key: "Super+T",
                isDMSManaged: true,
                desc: "Foot",
                cooldownMs: 250,
                flags: "lock",
                allowWhenLocked: true,
                allowInhibiting: false,
                repeat: false
            }]
        }
    ];
    assert.deepEqual(Array.from(km.doubleBinds(groups, "Super")).map(b => ({ ...b })), [{
        key: "Super+T",
        action: "spawn foot",
        desc: "Foot",
        cooldownMs: 250,
        flags: "lock",
        allowWhenLocked: true,
        allowInhibiting: false,
        repeat: false
    }]);
});

test("the clean-up plan covers the copy hidden behind a conflict and stays unique", () => {
    const groups = [
        { category: "Execute", action: "spawn foot", desc: "Foot", conflict: { key: "Mod+T", action: "spawn alacritty" }, keys: [{ key: "Mod+T", isDMSManaged: true }, { key: "Mod+Return", isDMSManaged: true }] }
    ];
    assert.deepEqual(Array.from(km.doubleBinds(groups, "Super")).map(b => b.key), ["Mod+T"]);
    assert.equal(km.doubleBinds(groups, "Super")[0].action, "spawn foot");
    assert.equal(km.doubleBinds(groups, "Super")[0].desc, "Foot");
});

test("the keycap name spells hyphens as spaces and shortens the long tokens, keeping the case", () => {
    assert.equal(km.capName("focus-workspace-1"), "focus ws 1");
    assert.equal(km.capName("Close Workspace Windows"), "Close Ws Wins");
    assert.equal(km.capName("Open Terminal"), "Open Term");
    assert.equal(km.capName("Dash"), "Dash");
    assert.equal(km.capName(""), "");
    assert.equal(km.capName(undefined), "");
});

test("the configured Mod key, and only it, makes a Qt key event a Mod press", () => {
    const [superL, superR, meta, alt, ctrl] = [0x01000053, 0x01000054, 0x01000022, 0x01000023, 0x01000021];
    for (const k of [superL, superR, meta])
        assert.equal(km.isModKey(k, "Super"), true);
    assert.equal(km.isModKey(alt, "Super"), false);
    assert.equal(km.isModKey(alt, "Alt"), true);
    assert.equal(km.isModKey(superL, "Alt"), false);
    assert.equal(km.isModKey(ctrl, "Alt"), false);
    assert.equal(km.isModKey(superL, ""), true);
});

test("the held layer follows the Qt modifiers, the Mod key itself adding nothing", () => {
    const [shift, ctrl, alt, meta] = [0x02000000, 0x04000000, 0x08000000, 0x10000000];
    assert.equal(km.heldLayer(meta, "Super"), "Super");
    assert.equal(km.heldLayer(meta | shift, "Super"), "Super+Shift");
    assert.equal(km.heldLayer(meta | alt, "Super"), "Super+Alt");
    assert.equal(km.heldLayer(alt, "Alt"), "Alt");
    assert.equal(km.heldLayer(alt | ctrl, "Alt"), "Alt+Ctrl");
    assert.equal(km.heldLayer(0, "Alt"), "Alt");
});

test("a chord sits on the layer of its modifiers, a bare key on none", () => {
    const layers = ["Super", "Super+Shift", "Super+Ctrl", "Super+Alt"];
    assert.equal(km.layerOf("Mod+Shift+Q", layers, "Super"), "Super+Shift");
    assert.equal(km.layerOf("shift+super+q", layers, "Super"), "Super+Shift");
    assert.equal(km.layerOf("Super+Q", layers, "Super"), "Super");
    assert.equal(km.layerOf("Print", layers, "Super"), "");
    assert.equal(km.layerOf("Ctrl+Alt+Delete", layers, "Super"), "");
    assert.equal(km.layerOf("Mod+Q", ["Alt", "Alt+Shift", "Alt+Ctrl"], "Alt"), "Alt");
});
