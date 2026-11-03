import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const schema = loadScript(new URL("../Common/fcitx5Schema.js", import.meta.url));

const fcitxSchema = {
    root: "GlobalConfig",
    structs: [
        { name: "GlobalConfig", fields: [{ name: "Hotkey", type: "Hotkey$HotkeyConfig", description: "Hotkey", props: {} }] },
        {
            name: "Hotkey$HotkeyConfig",
            fields: [
                { name: "TriggerKeys", type: "List|Key", description: "Toggle Input Method", props: { ListConstrain: { AllowModifierLess: "True", AllowModifierOnly: "True" } } },
                { name: "Style", type: "Enum", description: "Style", props: { Enum: ["a", "b"], EnumI18n: ["Alpha", "Beta"] } },
                { name: "Theme", type: "String", description: "Theme", props: { IsEnum: "True", LaunchSubConfig: "True", Enum: ["a", "b"], EnumI18n: ["Alpha", "Beta"] } },
                { name: "Launcher", type: "External", description: "Editor", props: {} },
            ],
        },
    ],
};
const value = { Hotkey: { TriggerKeys: ["Control+space"], Style: "b" } };

test("rows come from the schema: kinds, enum labels, constraints, unsupported counted", () => {
    const { rows, skipped } = schema.buildRows(fcitxSchema, "GlobalConfig", []);
    assert.equal(skipped, 1, "External editors are skipped, not drawn");
    assert.deepEqual([...rows.map(r => r.kind)], ["group", "keys", "enum", "enum"]);
    const [, keys, style] = rows;
    assert.deepEqual([...keys.path], ["Hotkey", "TriggerKeys"]);
    assert.equal(keys.modifierOnly, true);
    assert.deepEqual([...style.choices.labels], ["Alpha", "Beta"]);
});

test("curated rows keep our order and labels, and drop what is not listed", () => {
    const rows = schema.curatedRows(fcitxSchema, "Hotkey", [
        { name: "Style", label: "Mine" },
        { name: "TriggerKeys", label: "Toggle", description: "d" },
        { name: "Missing", label: "x" },
    ]);
    assert.deepEqual([...rows.map(r => r.label)], ["Mine", "Toggle"]);
    assert.equal(rows[1].tooltip, "d");
});

test("setPath copies the tree, so unrelated fields survive a write", () => {
    const next = schema.setPath(value, ["Hotkey", "Style"], "a");
    assert.equal(next.Hotkey.Style, "a");
    assert.deepEqual([...next.Hotkey.TriggerKeys], ["Control+space"]);
    assert.equal(value.Hotkey.Style, "b");
});

test("captured chords use fcitx's modifier names and lone modifiers resolve by scan code", () => {
    assert.equal(schema.fcitxKey("Ctrl+Alt+P"), "Control+Alt+P");
    assert.equal(schema.modifierOnlyKey(62), "Shift_R");
    assert.equal(schema.modifierOnlyKey(1), "");
});

test("layout options pair variants with their layout, and the default maps back to empty", () => {
    const { values, labels } = schema.layoutOptions([{ name: "us", description: "English", variants: [{ name: "intl", description: "Intl" }] }], "Default");
    assert.deepEqual([...values], [schema.layoutKey(""), "us", "us-intl"]);
    assert.equal(labels[0], "Default");
    assert.notEqual(values[0], "");
    assert.equal(schema.layoutFromKey(values[0]), "");
    assert.equal(schema.layoutFromKey("us"), "us");
});

test("an empty key list arrives as an empty string and still yields an array", () => {
    assert.deepEqual([...schema.keyList("")], []);
    assert.deepEqual([...schema.keyList("Control+space")], ["Control+space"]);
    assert.deepEqual([...schema.keyList(["Tab"])], ["Tab"]);
});

test("list-like values become real arrays", () => {
    const wrapper = { 0: "a", 1: "b", length: 2 };
    assert.ok(Array.isArray(schema.toArray(wrapper)));
    assert.deepEqual([...schema.toArray(undefined)], []);
    assert.deepEqual([...schema.keyList({ 0: "Tab", length: 1 })], ["Tab"]);
});
