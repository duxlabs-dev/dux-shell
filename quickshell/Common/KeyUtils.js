.pragma library

// qmlformat off
const KEY_MAP = {
    16777234: "Left",
    16777236: "Right",
    16777235: "Up",
    16777237: "Down",
    44: "Comma",
    46: "Period",
    47: "Slash",
    59: "Semicolon",
    39: "Apostrophe",
    91: "BracketLeft",
    93: "BracketRight",
    92: "Backslash",
    45: "Minus",
    61: "Equal",
    96: "grave",
    32: "space",
    16777225: "Print",
    16777226: "Print",
    16777220: "Return",
    16777221: "Return",
    16777217: "Tab",
    16777219: "BackSpace",
    16777223: "Delete",
    16777222: "Insert",
    16777232: "Home",
    16777233: "End",
    16777238: "Page_Up",
    16777239: "Page_Down",
    16777216: "Escape",
    16777252: "Caps_Lock",
    16777253: "Num_Lock",
    16777254: "Scroll_Lock",
    16777224: "Pause",
    16777330: "XF86AudioRaiseVolume",
    16777328: "XF86AudioLowerVolume",
    16777329: "XF86AudioMute",
    16842808: "XF86AudioMicMute",
    16777488: "XF86TouchpadToggle",
    16777489: "XF86TouchpadOn",
    16777490: "XF86TouchpadOff",
    16777344: "XF86AudioPlay",
    16777345: "XF86AudioStop",
    16777346: "XF86AudioPrev",
    16777347: "XF86AudioNext",
    16777348: "XF86AudioPause",
    16777349: "XF86AudioMedia",
    16777350: "XF86AudioRecord",
    16842798: "XF86MonBrightnessUp",
    16777394: "XF86MonBrightnessUp",
    16842797: "XF86MonBrightnessDown",
    16777395: "XF86MonBrightnessDown",
    16842800: "XF86KbdBrightnessUp",
    16842799: "XF86KbdBrightnessDown",
    16842796: "XF86PowerOff",
    16842803: "XF86Sleep",
    16842804: "XF86WakeUp",
    16842802: "XF86Eject",
    16842791: "XF86Calculator",
    16842806: "XF86Explorer",
    16777360: "XF86HomePage",
    16842794: "XF86HomePage",
    16777362: "XF86Search",
    16777426: "XF86Search",
    16777376: "XF86Mail",
    16777427: "XF86Mail",
    16777377: "XF86AudioMedia",
    16777419: "XF86Calculator",
    16777429: "XF86Explorer",
    16777442: "XF86Launch0",
    16777443: "XF86Launch1",
    196: "Adiaeresis",
    214: "Odiaeresis",
    220: "Udiaeresis",
    228: "adiaeresis",
    246: "odiaeresis",
    252: "udiaeresis",
    223: "ssharp",
    201: "Eacute",
    233: "eacute",
    200: "Egrave",
    232: "egrave",
    202: "Ecircumflex",
    234: "ecircumflex",
    203: "Ediaeresis",
    235: "ediaeresis",
    192: "Agrave",
    224: "agrave",
    194: "Acircumflex",
    226: "acircumflex",
    199: "Ccedilla",
    231: "ccedilla",
    206: "Icircumflex",
    238: "icircumflex",
    207: "Idiaeresis",
    239: "idiaeresis",
    212: "Ocircumflex",
    244: "ocircumflex",
    217: "Ugrave",
    249: "ugrave",
    219: "Ucircumflex",
    251: "ucircumflex",
    209: "Ntilde",
    241: "ntilde",
    191: "questiondown",
    161: "exclamdown"
};
// qmlformat on

// Preserve unshifted symbols from the active layout
const SYMBOL_KEYSYM = {
    33: "exclam",
    34: "quotedbl",
    35: "numbersign",
    36: "dollar",
    37: "percent",
    38: "ampersand",
    40: "parenleft",
    41: "parenright",
    42: "asterisk",
    43: "plus",
    58: "colon",
    60: "less",
    62: "greater",
    63: "question",
    64: "at",
    94: "asciicircum",
    95: "underscore",
    123: "braceleft",
    124: "bar",
    125: "braceright",
    126: "asciitilde"
};

// Preserve the existing shifted-US physical-key mapping
const SHIFTED_US_FALLBACK = {
    33: "1",
    34: "Apostrophe",
    35: "3",
    36: "4",
    37: "5",
    38: "7",
    40: "9",
    41: "0",
    42: "8",
    43: "Equal",
    58: "Semicolon",
    60: "Comma",
    62: "Period",
    63: "Slash",
    64: "2",
    94: "6",
    95: "Minus",
    123: "BracketLeft",
    124: "Backslash",
    125: "BracketRight",
    126: "grave"
};

// Numpad (keypad) keys. Qt reuses the same Qt::Key_* values for the numpad and
// the main rows/nav cluster; only Qt.KeypadModifier distinguishes them. niri and
// the other compositors bind against the xkb KP_* keysym names, so we must emit
// those instead of the collapsed twin. With NumLock off the numpad sends the
// navigation keysyms (KP_Home, KP_End, ...); with NumLock on it sends KP_0..KP_9
// (handled by the digit range in xkbKeyFromQtKey). Operators/Enter are the same
// in both states.
// qmlformat off
const KP_MAP = {
    16777232: "KP_Home",
    16777235: "KP_Up",
    16777238: "KP_Prior",
    16777234: "KP_Left",
    16777227: "KP_Begin",
    16777236: "KP_Right",
    16777233: "KP_End",
    16777237: "KP_Down",
    16777239: "KP_Next",
    16777222: "KP_Insert",
    16777223: "KP_Delete",
    16777221: "KP_Enter",
    43: "KP_Add",
    45: "KP_Subtract",
    42: "KP_Multiply",
    47: "KP_Divide",
    46: "KP_Decimal"
};
// qmlformat on

// Shift+digit arrives as the layout's shifted symbol (latam Shift+0 is "="),
// but compositors match binds on the unshifted keysym, so resolve the digit
// row from the physical key instead. xkb keycodes 10..19 are evdev KEY_1..KEY_0.
function digitFromScanCode(scanCode) {
    if (!(scanCode >= 10 && scanCode <= 19))
        return "";
    return String((scanCode - 9) % 10);
}

function xkbKeyFromQtKey(qk, isKeypad, hasShift, scanCode) {
    if (isKeypad) {
        if (qk >= 48 && qk <= 57)
            return "KP_" + (qk - 48);
        if (KP_MAP[qk])
            return KP_MAP[qk];
    }
    if (hasShift) {
        const digit = digitFromScanCode(scanCode);
        if (digit)
            return digit;
    }
    if (!hasShift && SYMBOL_KEYSYM[qk])
        return SYMBOL_KEYSYM[qk];
    if (hasShift && SHIFTED_US_FALLBACK[qk])
        return SHIFTED_US_FALLBACK[qk];
    if (qk >= 65 && qk <= 90)
        return String.fromCharCode(qk);
    if (qk >= 97 && qk <= 122)
        return String.fromCharCode(qk - 32);
    if (qk >= 48 && qk <= 57)
        return String.fromCharCode(qk);
    if (qk >= 16777264 && qk <= 16777298)
        return "F" + (qk - 16777264 + 1);
    if (qk >= 16777378 && qk <= 16777387)
        return "XF86Launch" + (qk - 16777378);
    if (qk >= 16777388 && qk <= 16777393)
        return "XF86Launch" + String.fromCharCode(65 + qk - 16777388);
    return KEY_MAP[qk] || "";
}

function keyFromToken(token) {
    const parts = String(token || "").split("+");
    return parts[parts.length - 1];
}

// A compositor resolves a bind's keysym on the first level of the active layout,
// so a keysym that lives only above it can never match: de:neo puts every
// bracket on layer 4, which is how "Mod+bracketleft" gets stored and then never
// fires (#3585). keymap is what `dms keybinds keymap` reports, and a key outside
// its `named` vocabulary is one we could not name, so it counts as fine.
function keysymUnreachable(key, keymap) {
    if (!key || !keymap)
        return false;
    const vocabulary = keymap.named ?? [];
    const byKeycode = keymap.keysyms ?? {};
    if (vocabulary.length === 0)
        return false;

    const wanted = String(key).toLowerCase();
    if (!vocabulary.some(name => String(name).toLowerCase() === wanted))
        return false;

    const keycodes = Object.keys(byKeycode);
    for (let i = 0; i < keycodes.length; i++) {
        const syms = byKeycode[keycodes[i]] ?? [];
        for (let j = 0; j < syms.length; j++) {
            if (String(syms[j]).toLowerCase() === wanted)
                return false;
        }
    }
    return true;
}

function modsFromEvent(mods) {
    var result = [];
    if (mods & 0x10000000)
        result.push("Super");
    if (mods & 0x08000000)
        result.push("Alt");
    if (mods & 0x04000000)
        result.push("Ctrl");
    if (mods & 0x02000000)
        result.push("Shift");
    return result;
}

function formatToken(mods, key) {
    return (mods.length ? mods.join("+") + "+" : "") + key;
}

const QT_MODIFIER_NAMES = {
    16777248: "Shift",
    16777249: "Ctrl",
    16777250: "Super",
    16777251: "Alt",
    16777299: "Super",
    16777300: "Super"
};
const CAPTURE_MODIFIER_ORDER = ["Super", "Alt", "Ctrl", "Shift"];

function modifierFromQtKey(qtKey) {
    return QT_MODIFIER_NAMES[qtKey] || "";
}

// The pressed modifier key may be missing from the event's modifier mask.
function heldModifiers(qtKey, modifiers, previous) {
    const held = (previous || []).concat(modsFromEvent(modifiers), modifierFromQtKey(qtKey));
    return CAPTURE_MODIFIER_ORDER.filter(mod => held.includes(mod));
}

function bareModifierToken(mods, modKey, modSymbol) {
    return withSymbolicMod(mods, modKey, modSymbol).join("+");
}

function triggerName(key) {
    const parts = String(key || "").toLowerCase().split("+");
    return parts[parts.length - 1].trim();
}

function isScrollTrigger(key) {
    const trigger = triggerName(key);
    return trigger.startsWith("wheelscroll") || trigger.startsWith("touchpadscroll");
}

// niri only passes keyboard binds through to the focused window.
function isKeyboardTrigger(key) {
    const trigger = triggerName(key);
    return !["mouse", "wheelscroll", "touchpadscroll", "tabletstylusbutton"].some(prefix => trigger.startsWith(prefix));
}

const MODIFIER_ALIASES = {
    "control": "ctrl",
    "win": "super",
    "meta": "super",
    "logo": "super",
    "mod4": "super",
    "mod1": "alt",
    "iso_level3_shift": "mod5",
    "iso_level5_shift": "mod3"
};

function canonicalModifier(modifier) {
    var normalized = (modifier || "").toLowerCase();
    return MODIFIER_ALIASES[normalized] || normalized;
}

function withSymbolicMod(mods, modKey, modSymbol) {
    var configuredMod = canonicalModifier(modKey);
    if (!configuredMod || !modSymbol)
        return mods;
    return mods.map(function (modifier) {
        return canonicalModifier(modifier) === configuredMod ? modSymbol : modifier;
    });
}

const QT_KEY_TAB = 16777217;
const QT_KEY_BACKTAB = 16777218;
const QT_KEYPAD_MODIFIER = 0x20000000;
const QT_SHORTCUT_MODIFIERS = 0x10000000 | 0x08000000;
const QT_CONTROL_MODIFIER = 0x04000000;
// keys a text field owns: escape, tab, backtab, backspace, return, enter, insert, delete, home, end, arrows, page up/down
const TEXT_EDIT_KEYS = [16777216, 16777217, 16777218, 16777219, 16777220, 16777221, 16777222, 16777223, 16777232, 16777233, 16777234, 16777235, 16777236, 16777237, 16777238, 16777239];
const QT_MODIFIER_KEYS = [16777248, 16777249, 16777250, 16777251, 16777252, 16777253, 16777254, 16777299, 16777300];

function chordToken(qtKey, modifiers, mods, scanCode, modKey, modSymbol) {
    if (qtKey === QT_KEY_BACKTAB) {
        qtKey = QT_KEY_TAB;
        if (!mods.includes("Shift"))
            mods = mods.concat("Shift");
    }
    const key = xkbKeyFromQtKey(qtKey, !!(modifiers & QT_KEYPAD_MODIFIER), mods.includes("Shift"), scanCode);
    if (!key)
        return "";
    return formatToken(withSymbolicMod(mods, modKey, modSymbol), key);
}

// A focused search field keeps typing and editing keys. Super or Alt chords and
// keys that never produce text (function, media, Print) read as a shortcut.
function shortcutFromSearchKey(event, modKey, modSymbol) {
    if (QT_MODIFIER_KEYS.includes(event.key))
        return "";
    const chord = !!(event.modifiers & QT_SHORTCUT_MODIFIERS);
    if (!chord && (event.text !== "" || (event.modifiers & QT_CONTROL_MODIFIER) || TEXT_EDIT_KEYS.includes(event.key)))
        return "";
    return chordToken(event.key, event.modifiers, modsFromEvent(event.modifiers), event.nativeScanCode, modKey, modSymbol);
}

const NORMALIZED_MODIFIER_ORDER = ["super", "ctrl", "alt", "shift", "mod5", "mod3"];
// Imply their modifier but stay distinct triggers.
const MODIFIER_KEYSYMS = {
    "control_l": "ctrl",
    "control_r": "ctrl",
    "shift_l": "shift",
    "shift_r": "shift",
    "alt_l": "alt",
    "alt_r": "alt",
    "super_l": "super",
    "super_r": "super"
};

// Mirrors core normalizeNiriBindKey, so Shift+Alt equals Alt+Shift.
function normalizeKeyCombo(keyCombo, modKey, modSymbol) {
    if (!keyCombo)
        return "";
    const configuredMod = canonicalModifier(modKey) || "super";
    const symbol = (modSymbol || "mod").toLowerCase();
    const canonical = token => token === symbol ? configuredMod : canonicalModifier(token);
    let combo = String(keyCombo).toLowerCase();
    let trigger = "";
    if (combo.length > 1 && combo.endsWith("++")) {
        trigger = "+";
        combo = combo.slice(0, -2);
    }
    const parts = combo.split("+").map(part => part.trim());
    if (!trigger)
        trigger = parts.pop();

    const mods = new Set();
    const unknown = [];
    for (const part of parts) {
        const mod = canonical(part);
        if (NORMALIZED_MODIFIER_ORDER.includes(mod))
            mods.add(mod);
        else if (!unknown.includes(mod))
            unknown.push(mod);
    }

    const triggerMod = canonical(trigger);
    const bareModifier = NORMALIZED_MODIFIER_ORDER.includes(triggerMod);
    if (bareModifier)
        mods.add(triggerMod);
    else if (MODIFIER_KEYSYMS[trigger])
        mods.add(MODIFIER_KEYSYMS[trigger]);

    const out = NORMALIZED_MODIFIER_ORDER.filter(mod => mods.has(mod)).concat(unknown.sort());
    if (!bareModifier)
        out.push(trigger);
    return out.join("+");
}

function comboTrigger(keyCombo) {
    const combo = String(keyCombo).toLowerCase();
    if (combo.length > 1 && combo.endsWith("++"))
        return "+";
    return combo.slice(combo.lastIndexOf("+") + 1).trim();
}

// Mirrors core niriBindsConflict: Alt also takes Alt_L and Alt_R, which stay distinct.
function keyCombosConflict(a, b, modKey, modSymbol) {
    const na = normalizeKeyCombo(a, modKey, modSymbol);
    const nb = normalizeKeyCombo(b, modKey, modSymbol);
    if (na === nb)
        return true;
    const ta = comboTrigger(a);
    const tb = comboTrigger(b);
    if (MODIFIER_KEYSYMS[ta])
        return nb + "+" + ta === na;
    if (MODIFIER_KEYSYMS[tb])
        return na + "+" + tb === nb;
    return false;
}

function getConflictingBinds(keyCombo, currentAction, allBinds, modKey, modSymbol) {
    if (!keyCombo)
        return [];
    var conflicts = [];
    for (var i = 0; i < allBinds.length; i++) {
        var bind = allBinds[i];
        if (bind.action === currentAction)
            continue;
        for (var k = 0; k < bind.keys.length; k++) {
            if (keyCombosConflict(keyCombo, bind.keys[k].key, modKey, modSymbol)) {
                conflicts.push({
                    action: bind.action,
                    desc: bind.desc || bind.action
                });
                break;
            }
        }
    }
    return conflicts;
}

function qtKeyFromName(name) {
    var n = (name || "").toUpperCase();
    if (n.length === 1 && n >= "A" && n <= "Z")
        return Qt.Key_A + (n.charCodeAt(0) - 65);
    if (n.length === 1 && n >= "0" && n <= "9")
        return Qt.Key_0 + (n.charCodeAt(0) - 48);
    if (n.length >= 2 && n[0] === "F") {
        var f = parseInt(n.slice(1), 10);
        if (f >= 1 && f <= 12)
            return Qt.Key_F1 + (f - 1);
    }
    var named = {
        "SPACE": Qt.Key_Space,
        "TAB": Qt.Key_Tab,
        "RETURN": Qt.Key_Return,
        "ENTER": Qt.Key_Enter,
        "BACKSPACE": Qt.Key_Backspace,
        "DELETE": Qt.Key_Delete,
        "HOME": Qt.Key_Home,
        "END": Qt.Key_End,
        "UP": Qt.Key_Up,
        "DOWN": Qt.Key_Down,
        "LEFT": Qt.Key_Left,
        "RIGHT": Qt.Key_Right
    };
    return named[n] || 0;
}

// Mirrors QPlatformInputContextFactory::requested(): QT_IM_MODULES wins, Qt loads the first entry that exists.
function compositorTextInputSelected(imModules, imModule) {
    const requested = (imModules || "").split(";").filter(Boolean);
    const first = requested.length ? requested[0] : (imModule || "");
    return first === "" || first === "wayland";
}

function isModifierKey(qk) {
    return qk === Qt.Key_Control || qk === Qt.Key_Shift || qk === Qt.Key_Alt || qk === Qt.Key_Meta || qk === Qt.Key_NumLock || qk === Qt.Key_CapsLock || qk === Qt.Key_ScrollLock;
}

function eventMatchesCombo(event, combo) {
    if (!combo)
        return false;
    var parts = combo.split("+");
    var keyName = parts[parts.length - 1].trim().toUpperCase();
    var wantsShift = false;
    var hasCtrl = false;
    for (var i = 0; i < parts.length - 1; i++) {
        var mod = parts[i].trim().toLowerCase();
        if (mod === "shift")
            wantsShift = true;
        else if (mod === "ctrl" || mod === "control")
            hasCtrl = true;
        else
            return false;
    }
    if (hasCtrl && !(event.modifiers & Qt.ControlModifier))
        return false;
    if (event.modifiers & (Qt.AltModifier | Qt.MetaModifier))
        return false;
    if (((event.modifiers & Qt.ShiftModifier) !== 0) !== wantsShift)
        return false;
    return event.key === qtKeyFromName(keyName);
}

const KEY_GLYPH_MAP_COMMON = {
    "shift_l": "⇧ L",
    "shift_r": "⇧ R",
    "control_l": "⌃ L",
    "control_r": "⌃ R",
    "alt_l": "⌥ L",
    "alt_r": "⌥ R",
    "super_l": "⌘ L",
    "super_r": "⌘ R",
    "return": "⏎",
    "enter": "⏎",
    "tab": "⇥",
    "backspace": "⌫",
    "space": "␣",
    "escape": "Esc",
    "esc": "Esc",
    "up": "↑",
    "down": "↓",
    "left": "←",
    "right": "→",
    "home": "Home",
    "end": "End",
    "delete": "Del",
    "del": "Del",
    "insert": "Ins",
    "print": "PrtSc",
    "printscreen": "PrtSc",
    "prtscr": "PrtSc",
    "prtsc": "PrtSc",
    "sysrq": "PrtSc",
    "plus": "+",
    "minus": "-",
    "equal": "=",
    "slash": "/",
    "backslash": "\\",
    "bracketleft": "[",
    "bracketright": "]",
    "semicolon": ";",
    "apostrophe": "'",
    "comma": ",",
    "period": ".",
    "grave": "`",
    "wheelscrolldown": "󰍽 ↓",
    "wheelscrollup": "󰍽 ↑",
    "wheelscrollleft": "󰍽 ←",
    "wheelscrollright": "󰍽 →",
    "mousescrolldown": "󰍽 ↓",
    "mousescrollup": "󰍽 ↑",
    "mouse_down": "󰍽 ↓",
    "mouse_up": "󰍽 ↑",
    "mouse_left": "󰍽 ←",
    "mouse_right": "󰍽 →",
    "scrolldown": "󰍽 ↓",
    "scrollup": "󰍽 ↑",

    // Audio & Volume
    "xf86audioraisevolume": "󰕾 +",
    "audioraisevolume": "󰕾 +",
    "xf86audiolowervolume": "󰕾 -",
    "audiolowervolume": "󰕾 -",
    "xf86audiomute": "󰖁",
    "audiomute": "󰖁",
    "xf86audiomicmute": "󰍭",
    "audiomicmute": "󰍭",

    // Media Playback
    "xf86audioplay": "󰐊",
    "audioplay": "󰐊",
    "xf86audiopause": "󰏤",
    "audiopause": "󰏤",
    "xf86audioplaypause": "󰐎",
    "audioplaypause": "󰐎",
    "xf86audionext": "󰒭",
    "audionext": "󰒭",
    "xf86audioprev": "󰒮",
    "audioprev": "󰒮",
    "xf86audiostop": "󰓛",
    "audiostop": "󰓛",
    "xf86audiorecord": "Rec",
    "audiorecord": "Rec",
    "xf86audiomedia": "Media",
    "audiomedia": "Media",

    // Display & Brightness
    "xf86monbrightnessup": "󰃠 +",
    "monbrightnessup": "󰃠 +",
    "xf86monbrightnessdown": "󰃠 -",
    "monbrightnessdown": "󰃠 -",
    "xf86kbdbrightnessup": "󰌌 +",
    "kbdbrightnessup": "󰌌 +",
    "xf86kbdbrightnessdown": "󰌌 -",
    "kbdbrightnessdown": "󰌌 -",

    // Hardware & System
    "xf86calculator": "Calc",
    "xf86search": "Search",
    "xf86mail": "Mail",
    "xf86homepage": "Web",
    "xf86explorer": "Files",
    "xf86poweroff": "Power",
    "xf86sleep": "Sleep",
    "xf86wakeup": "Wake",
    "xf86eject": "Eject",
    "xf86launch0": "Launch 0",
    "xf86launch1": "PrtSc",
    "launch1": "PrtSc"
};

const MAC_MODIFIERS = {
    "shift": "⇧",
    "ctrl": "⌃",
    "control": "⌃",
    "alt": "⌥",
    "mod": "⌘",
    "super": "⌘",
    "meta": "⌘",
    "win": "⌘",
    "return": "⏎",
    "enter": "⏎",
    "tab": "⇥",
    "backspace": "⌫",
    "space": "␣",
    "page_up": "⇞",
    "pageup": "⇞",
    "page_down": "⇟",
    "pagedown": "⇟"
};

const WIN_MODIFIERS = {
    "shift": "Shift",
    "ctrl": "Ctrl",
    "control": "Ctrl",
    "alt": "Alt",
    "mod": "Mod",
    "super": "Mod",
    "meta": "Mod",
    "win": "Mod",
    "return": "Enter",
    "enter": "Enter",
    "tab": "Tab",
    "backspace": "⌫",
    "space": "Space",
    "page_up": "PgUp",
    "pageup": "PgUp",
    "page_down": "PgDn",
    "pagedown": "PgDn"
};

const KEY_GLYPH_MAP_MAC = Object.assign({}, KEY_GLYPH_MAP_COMMON, MAC_MODIFIERS);
const KEY_GLYPH_MAP_WIN = Object.assign({}, KEY_GLYPH_MAP_COMMON, WIN_MODIFIERS);

function formatKeyTokens(keyString, modKey, modSymbol, style) {
    if (!keyString)
        return [];
    var symbol = (modSymbol || "mod").toLowerCase();
    var resolvedMod = canonicalModifier(modKey) || "super";
    var str = keyString;
    var plusEnds = false;
    if (str.endsWith("++")) {
        plusEnds = true;
        str = str.slice(0, -2);
    }
    var parts = str.split("+");
    var tokens = [];
    var map = style === "mac" ? KEY_GLYPH_MAP_MAC : KEY_GLYPH_MAP_WIN;
    for (var i = 0; i < parts.length; i++) {
        var part = parts[i].trim();
        if (!part)
            continue;
        var lower = part.toLowerCase();
        if (lower === symbol)
            lower = resolvedMod;
        if (map[lower] !== undefined) {
            tokens.push(map[lower]);
        } else if (part.length === 1) {
            tokens.push(part.toUpperCase());
        } else {
            tokens.push(part);
        }
    }
    if (plusEnds) {
        tokens.push("+");
    }
    return tokens;
}
