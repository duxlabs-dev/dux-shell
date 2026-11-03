import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const schema = loadScript(new URL("../Common/fcitx5Schema.js", import.meta.url));

const fcitxSchema = {
    root: "GlobalConfig",
    structs: [
        { name: "Entry", fields: [{ name: "Key", type: "String", description: "Key", props: {} }, { name: "Enable", type: "Boolean", description: "Enable", props: {} }, { name: "Words", type: "List|String", description: "Words", props: {} }] },
        { name: "GlobalConfig", fields: [{ name: "Hotkey", type: "Hotkey$HotkeyConfig", description: "Hotkey", props: {} }] },
        {
            name: "Hotkey$HotkeyConfig",
            fields: [
                { name: "TriggerKeys", type: "List|Key", description: "Toggle Input Method", props: { ListConstrain: { AllowModifierLess: "True", AllowModifierOnly: "True" } } },
                { name: "Style", type: "Enum", description: "Style", props: { Enum: ["a", "b"], EnumI18n: ["Alpha", "Beta"] } },
                { name: "Theme", type: "String", description: "Theme", props: { IsEnum: "True", LaunchSubConfig: "True", Enum: ["a", "b"], EnumI18n: ["Alpha", "Beta"] } },
                { name: "Font", type: "String", description: "Font", props: { Font: "True" } },
                { name: "Launcher", type: "External", description: "Editor", props: {} },
                { name: "Backends", type: "List|Enum", description: "Backends", props: { Enum: ["a", "b"] } },
                { name: "Entries", type: "List|Entry", description: "Entries", default: [], props: {} },
                { name: "Phrases", type: "External", description: "Manage Phrases", props: { External: "fcitx://config/addon/pinyin/customphrase" } },
                { name: "Cloud", type: "External", description: "Configure Cloud", props: { External: "fcitx://config/addon/cloudpinyin" } },
            ],
        },
    ],
};
const value = { Hotkey: { TriggerKeys: ["Control+space"], Style: "b" } };

test("rows come from the schema: kinds, enum labels, constraints, unsupported listed", () => {
    const { rows, hidden } = schema.buildRows(fcitxSchema, "GlobalConfig", []);
    assert.deepEqual([...hidden], ["Editor", "Manage Phrases"], "External editors are listed by label, not drawn");
    assert.deepEqual([...rows.map(r => r.kind)], ["group", "keys", "enum", "enum", "font", "enums", "structs", "sub"]);
    assert.equal(rows[rows.length - 1].addon, "cloudpinyin");
    assert.deepEqual([...rows[rows.length - 2].fields.map(f => f.kind)], ["string", "bool", "strings"]);
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

test("pango font strings split into family, style and size and rebuild unchanged", () => {
    const p = schema.parseFont("Noto Sans Bold Italic 10");
    assert.deepEqual({ ...p }, { family: "Noto Sans", style: "Bold Italic", size: "10" });
    assert.equal(schema.buildFont({ ...p, size: "12" }), "Noto Sans Bold Italic 12");
    assert.deepEqual({ ...schema.parseFont("Sans") }, { family: "Sans", style: "", size: "" });
    assert.equal(schema.buildFont(schema.parseFont("Sans 10")), "Sans 10");
});

test("groups split rows into titled sections, leading rows stay untitled", () => {
    const out = schema.sections([{ kind: "bool", name: "a" }, { kind: "group", label: "Fuzzy" }, { kind: "bool", name: "b" }, { kind: "int", name: "c" }]);
    assert.equal(out.length, 2);
    assert.deepEqual([...out.map(x => x.title)], ["", "Fuzzy"]);
    assert.deepEqual([...out[1].rows.map(r => r.name)], ["b", "c"]);
});

test("string lists edit as comma separated text", () => {
    assert.equal(schema.fieldKind("List|String", {}), "strings");
    assert.equal(schema.joinList(""), "");
    assert.equal(schema.joinList(["a", "b"]), "a, b");
    assert.deepEqual([...schema.splitList(" a,b , ,c ")], ["a", "b", "c"]);
});

test("list rows get their own section, and rows after one start a fresh untitled section", () => {
    const out = schema.sections([{ kind: "enums", label: "Backends" }, { kind: "bool", name: "after" }]);
    assert.equal(out.length, 2);
    assert.equal(out[0].list.kind, "enums");
    assert.equal(out[1].title, "");
    assert.equal(out[1].list, null);
});

test("new list items start enabled and empty", () => {
    const item = schema.newItem([{ name: "Key", kind: "string" }, { name: "On", kind: "bool" }, { name: "W", kind: "strings" }]);
    assert.equal(item.On, "True");
    assert.deepEqual([...item.W], []);
});

test("enum list values show their label and fall back to the raw value", () => {
    const choices = { values: ["a", "b"], labels: ["Alpha", "Beta"] };
    assert.equal(schema.enumLabel(choices, "b"), "Beta");
    assert.equal(schema.enumLabel(choices, "z"), "z");
});
