.pragma library

// A bind names a keysym, not a physical key: on AZERTY, Super+Q sits where QWERTY prints A.
// Letters per row, then the printed-only keys after the home row, then the bottom row keysyms.
const LAYOUTS = {
    "us": {
        "top": "QWERTYUIOP",
        "home": "ASDFGHJKL",
        "homeExtra": [";", "'"],
        "bottom": ["Z", "X", "C", "V", "B", "N", "M", "Comma", "Period", "Slash"]
    },
    "fr": {
        "top": "AZERTYUIOP",
        "home": "QSDFGHJKLM",
        "homeExtra": ["ù"],
        "bottom": ["W", "X", "C", "V", "B", "N", "Comma", "Semicolon", "Colon", "Exclam"]
    },
    "de": {
        "top": "QWERTZUIOP",
        "home": "ASDFGHJKL",
        "homeExtra": ["ö", "ä"],
        "bottom": ["Y", "X", "C", "V", "B", "N", "M", "Comma", "Period", "Minus"]
    }
};

const LABELS = {
    "Comma": ",",
    "Period": ".",
    "Slash": "/",
    "Semicolon": ";",
    "Colon": ":",
    "Exclam": "!",
    "Minus": "-",
    "Return": "return",
    "Delete": "delete",
    "Print": "prt sc",
    "Space": "",
    "Up": "↑",
    "Down": "↓",
    "Left": "←",
    "Right": "→"
};

const MOD_ALIASES = {
    "win": "super",
    "logo": "super",
    "meta": "super",
    "mod4": "super",
    "control": "ctrl",
    "primary": "ctrl",
    "mod1": "alt",
    "iso_level3_shift": "altgr"
};
const MOD_ORDER = ["super", "ctrl", "alt", "altgr", "shift"];

// niri reports xkb descriptions ("French (AZERTY)"), not layout codes.
// shortcut: three keysym tables, any other layout draws as QWERTY; add a table when someone needs it.
function layoutOf(niriName) {
    const name = String(niriName ?? "").toLowerCase();
    if (name.startsWith("french"))
        return "fr";
    if (name.startsWith("german"))
        return "de";
    return "us";
}

// Laptop rows on a 60-column grid, 1u = 4 columns. A key with `sym` takes binds; a key with only
// `label` is printed, `mod` names the layer it stands for. Arrow keys share one row height (`half`).
function rows(layoutId) {
    const l = LAYOUTS[layoutId] ?? LAYOUTS.us;
    const out = [];
    const build = items => {
        let col = 0;
        const row = [];
        for (const it of items) {
            const key = typeof it === "string" ? { "sym": it, "w": 4 } : it;
            key.col = key.col ?? col;
            if (key.sym !== undefined && key.label === undefined)
                key.label = LABELS[key.sym] ?? key.sym;
            if (key.half !== "top")
                col = key.col + key.w;
            row.push(key);
        }
        out.push(row);
    };
    const printed = (label, w, mod) => ({ label, w, mod });
    const fkeys = [];
    for (let i = 1; i <= 12; i++)
        fkeys.push("F" + i);

    build([printed("esc", 6), ...fkeys, { "sym": "Print", "w": 6 }]);
    build([printed("`", 4), ..."1234567890".split(""), printed("-", 4), printed("=", 4), { "sym": "Delete", "w": 8 }]);
    build([printed("tab", 6), ...l.top.split(""), printed("[", 4), printed("]", 4), printed("\\", 6)]);
    build([printed("caps", 7), ...l.home.split(""), ...l.homeExtra.map(t => printed(t, 4)), { "sym": "Return", "w": 60 - 7 - (l.home.length + l.homeExtra.length) * 4 }]);
    build([printed("shift", 9, "Shift"), ...l.bottom, printed("shift", 11, "Shift")]);
    build([printed("ctrl", 5, "Ctrl"), printed("fn", 4), { "super": true, "label": "", "w": 5 }, printed("alt", 5, "Alt"), { "sym": "Space", "w": 19 }, printed("alt", 5, "Alt"), printed("ctrl", 5, "Ctrl"), { "sym": "Left", "w": 4, "half": "bottom" }, { "sym": "Up", "w": 4, "col": 52, "half": "top" }, { "sym": "Down", "w": 4, "half": "bottom" }, { "sym": "Right", "w": 4, "half": "bottom" }]);
    return out;
}

// One spelling per chord: modifiers aliased and sorted, "Mod" resolved to the configured key.
function chordId(combo, modKey) {
    const parts = String(combo ?? "").toLowerCase().split("+").map(p => p.trim()).filter(p => p !== "");
    if (parts.length === 0)
        return "";
    const key = parts.pop();
    const mod = String(modKey || "super").toLowerCase();
    const mods = [];
    for (const p of parts) {
        const m = p === "mod" ? (MOD_ALIASES[mod] ?? mod) : (MOD_ALIASES[p] ?? p);
        if (!mods.includes(m))
            mods.push(m);
    }
    mods.sort((a, b) => MOD_ORDER.indexOf(a) - MOD_ORDER.indexOf(b));
    return [...mods, key].join("+");
}

// The layer of `layers` a chord sits on, "" when none fits (a bare key sits on every layer).
function layerOf(chord, layers, modKey) {
    const mods = chordId(chord, modKey).split("+").slice(0, -1).join("+");
    if (mods === "")
        return "";
    return (layers ?? []).find(l => chordId(l + "+x", modKey) === chordId(mods + "+x", modKey)) ?? "";
}

// Qt.Key_* codes and Qt.*Modifier flags by modifier name: this library also runs under node, without Qt.
// shortcut: Super, Alt and Ctrl only, another mod-key reads as Super; add ISO_Level3/5_Shift when someone sets them
const QT_KEYS = {
    "super": [0x01000053, 0x01000054, 0x01000022],
    "alt": [0x01000023],
    "ctrl": [0x01000021]
};
const QT_MODIFIERS = {
    "shift": 0x02000000,
    "ctrl": 0x04000000,
    "alt": 0x08000000,
    "super": 0x10000000
};

function modName(modKey) {
    const m = String(modKey || "super").toLowerCase();
    return MOD_ALIASES[m] ?? m;
}

// Whether a Qt key event's key is the configured Mod key itself
function isModKey(key, modKey) {
    return (QT_KEYS[modName(modKey)] ?? QT_KEYS.super).includes(key);
}

// The layer a Qt modifier mask stands for while Mod is held: Mod's own flag adds nothing
function heldLayer(modifiers, modKey) {
    const held = modifiers & ~(QT_MODIFIERS[modName(modKey)] ?? QT_MODIFIERS.super);
    for (const [name, label] of [["shift", "Shift"], ["ctrl", "Ctrl"], ["alt", "Alt"]])
        if (held & QT_MODIFIERS[name])
            return modKey + "+" + label;
    return modKey;
}

// KeybindsService.getFlatBinds() groups -> {chordId: [{category, action, desc, key, ...}]}
function bindMap(groups, modKey) {
    const map = {};
    for (const g of groups ?? []) {
        for (const k of g?.keys ?? []) {
            const id = chordId(k?.key, modKey);
            if (!id)
                continue;
            (map[id] = map[id] ?? []).push({
                "category": g.category,
                "action": g.action,
                "desc": k.desc || g.desc || "",
                "key": k.key,
                "dms": k.isDMSManaged === true,
                "cooldownMs": k.cooldownMs || 0,
                "flags": k.flags || "",
                "allowWhenLocked": k.allowWhenLocked === true,
                "allowInhibiting": k.allowInhibiting,
                "repeat": k.repeat,
                "trigger": k.trigger,
                "releaseAction": k.releaseAction,
                "passThrough": k.passThrough
            });
        }
    }
    return map;
}

// A double is one key bound more than once; the same action on several keys (arrows and HJKL) is not.
// Only a copy in dms/binds.kdl can go (config.kdl is not ours), and one binding of the key always stays.
// Each record keeps the fields saveBind takes, so removing the copies can be undone.
function doubleBinds(groups, modKey) {
    const found = [];
    const map = bindMap(groups, modKey);
    for (const id in map) {
        const binds = map[id];
        const kept = binds.find(b => !b.dms) ?? binds[0];
        for (const b of binds)
            if (b !== kept && b.dms)
                found.push(b);
    }
    // The provider lists a key once and hides the config.kdl binding of the same key in `conflict`
    for (const g of groups ?? []) {
        const hidden = chordId(g?.conflict?.key, modKey);
        for (const k of hidden ? g.keys ?? [] : []) {
            if (!k?.isDMSManaged || chordId(k.key, modKey) !== hidden || found.some(b => b.key === k.key))
                continue;
            found.push(bindMap([{
                "category": g.category,
                "action": g.action,
                "desc": g.desc,
                "keys": [k]
            }], modKey)[hidden][0]);
        }
    }
    return found.map(b => {
        const record = {
            "key": b.key,
            "action": b.action,
            "desc": b.desc,
            "cooldownMs": b.cooldownMs,
            "flags": b.flags,
            "allowWhenLocked": b.allowWhenLocked,
            "allowInhibiting": b.allowInhibiting,
            "repeat": b.repeat
        };
        // saveBind sends the trigger fields only when they are set, so an unset one stays out of the record
        for (const field of ["trigger", "releaseAction", "passThrough"])
            if (b[field] !== undefined)
                record[field] = b[field];
        return record;
    });
}

function doubleKeys(groups, modKey) {
    return doubleBinds(groups, modKey).map(b => b.key);
}

// Cheat-sheet spelling of a bind name for a keycap a few words wide: hyphens become spaces and
// the long tokens take their usual short form. Tooltips and lists keep the full name.
const CAP_SHORT = {
    "workspace": "ws",
    "workspaces": "ws",
    "column": "col",
    "columns": "cols",
    "window": "win",
    "windows": "wins",
    "monitor": "mon",
    "monitors": "mons",
    "application": "app",
    "applications": "apps",
    "screenshot": "shot",
    "fullscreen": "full",
    "maximize": "max",
    "minimize": "min",
    "keyboard": "kbd",
    "brightness": "bright",
    "volume": "vol",
    "notification": "notif",
    "notifications": "notifs",
    "clipboard": "clip",
    "overview": "ovw",
    "terminal": "term"
};

function capName(name) {
    return String(name ?? "").split(/[-\s]+/).filter(Boolean).map(w => {
        const short = CAP_SHORT[w.toLowerCase()];
        return short ? (w[0] === w[0].toUpperCase() ? short[0].toUpperCase() + short.slice(1) : short) : w;
    }).join(" ");
}
