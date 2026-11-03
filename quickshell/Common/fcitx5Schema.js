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

function fieldKind(type) {
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
        default:
            return "unsupported";
    }
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

function buildRows(schema, structName, path) {
    const rows = [];
    let skipped = 0;
    const base = path ?? [];
    for (const field of structFields(schema, structName)) {
        const kind = fieldKind(field.type);
        const fieldPath = base.concat(field.name);
        if (kind === "unsupported") {
            const nested = structFields(schema, field.type);
            if (nested.length === 0) {
                skipped++;
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
            skipped += inner.skipped;
            continue;
        }
        const choices = kind === "enum" ? enumChoices(field) : null;
        rows.push({
            "kind": kind,
            "name": field.name,
            "label": field.description || field.name,
            "tooltip": field.props?.Tooltip ?? "",
            "path": fieldPath,
            "choices": choices,
            "modifierless": field.props?.ListConstrain?.AllowModifierLess !== "False",
            "modifierOnly": field.props?.ListConstrain?.AllowModifierOnly === "True"
        });
    }
    return {
        "rows": rows,
        "skipped": skipped
    };
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
