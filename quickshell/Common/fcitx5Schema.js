.pragma library

const MODIFIER_ONLY_KEYSYMS = {
    50: "Shift_L",
    62: "Shift_R",
    37: "Control_L",
    105: "Control_R",
    64: "Alt_L",
    108: "Alt_R",
    133: "Super_L",
    134: "Super_R"
};

const FCITX_MODIFIER_NAMES = {
    "Ctrl": "Control"
};

const ADDON_URI_PREFIX = "fcitx://config/addon/";
// Deeper URIs are mostly file editors (pinyin/customphrase, quickphrase/editor) that GetConfig cannot serve; only these list editors work.
const SUB_ADDON_URI = /^fcitx:\/\/config\/addon\/([^\/]+|keyboard\/longpress|punctuation\/punctuationmap\/[^\/]+)$/;

function boolValue(raw) {
    return raw === true || raw === "True";
}

function boolString(value) {
    return value ? "True" : "False";
}

// KeyUtils.chordToken gives "Ctrl+Shift+Tab"; fcitx5 spells the modifier "Control".
function fcitxKey(token) {
    return String(token).split("+").map(part => FCITX_MODIFIER_NAMES[part] || part).join("+");
}

// Key to store when only modifiers were pressed and then released, e.g. a lone Shift as a toggle.
function modifierOnlyKey(scanCode) {
    return MODIFIER_ONLY_KEYSYMS[scanCode] || "";
}

// Rows reach delegates as Qt-wrapped copies, so their lists fail Array.isArray, which DDropdown requires.
function toArray(list) {
    return Array.from(list ?? []);
}

function keyList(value) {
    if (typeof value === "object" && value !== null)
        return toArray(value);
    return value ? [value] : [];
}

function joinList(value) {
    return keyList(value).join(", ");
}

function splitList(text) {
    return String(text).split(",").map(part => part.trim()).filter(part => part !== "");
}

function fieldKind(type, props) {
    if (type === "String" && props?.IsEnum === "True")
        return "enum";
    if (type === "String" && props?.Font === "True")
        return "font";
    if (type === "External" && SUB_ADDON_URI.test(String(props?.External ?? "")))
        return "sub";
    switch (type) {
        case "Boolean":
            return "bool";
        case "Integer":
            return "int";
        case "String":
            return "string";
        case "Enum":
            return "enum";
        case "Key":
            return "key";
        case "List|Key":
            return "keys";
        case "List|String":
            return "strings";
        case "List|Enum":
            return "enums";
        default:
            return "unsupported";
    }
}

const fontStyleWords = ["thin", "ultralight", "extralight", "light", "semilight", "book", "regular", "medium", "semibold", "demibold", "bold", "ultrabold", "extrabold", "heavy", "black", "italic", "oblique", "condensed", "expanded"];

// Pango description: "Family [style words] [size]". Style words stay with the value so editing family or size never drops them.
function parseFont(str) {
    const words = String(str ?? "").trim().split(/\s+/).filter(w => w !== "");
    let size = "";
    if (words.length > 1 && /^\d+(\.\d+)?$/.test(words[words.length - 1]))
        size = words.pop();
    const style = [];
    while (words.length > 1 && fontStyleWords.includes(words[words.length - 1].toLowerCase().replace(/-/g, "")))
        style.unshift(words.pop());
    return {
        "family": words.join(" "),
        "style": style.join(" "),
        "size": size
    };
}

function buildFont(parts) {
    return [parts.family, parts.style, parts.size].filter(p => p).join(" ");
}

function structFields(schema, name) {
    const found = (schema?.structs ?? []).find(s => s.name === name);
    return found ? found.fields : [];
}

function enumChoices(field) {
    const values = field.props?.Enum ?? [];
    const labels = field.props?.EnumI18n ?? values;
    return {
        "values": values,
        "labels": labels.length === values.length ? labels : values
    };
}

function enumLabel(choices, value) {
    const i = toArray(choices?.values).indexOf(value);
    return i < 0 ? value : toArray(choices.labels)[i];
}

function buildRows(schema, structName, path) {
    const rows = [];
    const hidden = [];
    const base = path ?? [];
    for (const field of structFields(schema, structName)) {
        const fieldPath = base.concat(field.name);
        const itemStruct = field.type.startsWith("List|") ? field.type.slice(5) : "";
        if (itemStruct !== "" && structFields(schema, itemStruct).length > 0) {
            rows.push({
                "kind": "structs",
                "name": field.name,
                "label": field.description || field.name,
                "tooltip": field.props?.Tooltip ?? "",
                "path": fieldPath,
                "fields": buildRows(schema, itemStruct, []).rows.filter(r => r.kind !== "group")
            });
            continue;
        }
        const kind = fieldKind(field.type, field.props);
        if (kind === "unsupported") {
            const nested = structFields(schema, field.type);
            if (nested.length === 0) {
                hidden.push(field.description || field.name);
                continue;
            }
            const inner = buildRows(schema, field.type, fieldPath);
            if (inner.rows.length > 0)
                rows.push({
                    "kind": "group",
                    "label": field.description || field.name,
                    "path": fieldPath
                });
            rows.push(...inner.rows);
            hidden.push(...inner.hidden);
            continue;
        }
        const choices = kind === "enum" || kind === "enums" ? enumChoices(field) : null;
        rows.push({
            "kind": kind,
            "name": field.name,
            "label": field.description || field.name,
            "tooltip": field.props?.Tooltip ?? "",
            "path": fieldPath,
            "addon": kind === "sub" ? field.props.External.slice(ADDON_URI_PREFIX.length) : "",
            "choices": choices,
            "modifierless": field.props?.ListConstrain?.AllowModifierLess !== "False",
            "modifierOnly": field.props?.ListConstrain?.AllowModifierOnly === "True"
        });
    }
    return {
        "rows": rows,
        "hidden": hidden
    };
}

// Each group row opens a titled section; rows before the first group form an untitled one.
function sections(rows) {
    const out = [];
    for (const row of rows) {
        if (row.kind === "group" || row.kind === "structs" || row.kind === "enums") {
            out.push({
                "title": row.label,
                "rows": [],
                "list": row.kind === "group" ? null : row
            });
            continue;
        }
        if (out.length === 0 || out[out.length - 1].list)
            out.push({
                "title": "",
                "rows": [],
                "list": null
            });
        out[out.length - 1].rows.push(row);
    }
    return out;
}

function newItem(fields) {
    const item = {};
    for (const f of fields)
        item[f.name] = f.kind === "strings" ? [] : (f.kind === "bool" ? boolString(true) : "");
    return item;
}

function getPath(tree, path) {
    let node = tree;
    for (const part of path) {
        if (node === null || typeof node !== "object")
            return undefined;
        node = node[part];
    }
    return node;
}

function setPath(tree, path, newValue) {
    if (path.length === 0)
        return newValue;
    const copy = Array.isArray(tree) ? tree.slice() : Object.assign({}, tree);
    copy[path[0]] = setPath(copy[path[0]] ?? {}, path.slice(1), newValue);
    return copy;
}

function applyOrder(items, order) {
    return order.map(i => items[i]);
}

function isKeyboardIM(name) {
    return String(name).startsWith("keyboard-");
}

// DDropdown draws an empty value as a muted placeholder, so the default layout needs a real option value.
function layoutKey(layout) {
    return layout || "default";
}

function layoutFromKey(key) {
    return key === "default" ? "" : key;
}

function layoutOptions(layouts, defaultLabel) {
    const values = [layoutKey("")];
    const labels = [defaultLabel];
    for (const layout of layouts) {
        values.push(layout.name);
        labels.push(layout.description + " (" + layout.name + ")");
        for (const variant of layout.variants) {
            values.push(layout.name + "-" + variant.name);
            labels.push(layout.description + " - " + variant.description + " (" + layout.name + "-" + variant.name + ")");
        }
    }
    return {
        "values": values,
        "labels": labels
    };
}

function curatedRows(schema, section, table) {
    const field = structFields(schema, schema?.root).find(f => f.name === section);
    if (!field)
        return [];
    const rows = buildRows(schema, field.type, [section]).rows;
    const out = [];
    for (const entry of table) {
        const row = rows.find(r => r.name === entry.name);
        if (row)
            out.push(Object.assign({}, row, {
                "label": entry.label,
                "tooltip": entry.description ?? ""
            }));
    }
    return out;
}
