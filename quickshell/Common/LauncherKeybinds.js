.pragma library

.import "KeyUtils.js" as KeyUtils

const ACTIONS = [
    {
        id: "nextMode",
        combos: ["Ctrl+Tab"]
    },
    {
        id: "previousMode",
        combos: ["Ctrl+Shift+Tab"]
    },
    {
        id: "modeAll",
        mode: "all",
        combos: ["Ctrl+1", "Alt+1"]
    },
    {
        id: "modeApps",
        mode: "apps",
        combos: ["Ctrl+2", "Alt+2"]
    },
    {
        id: "modeFiles",
        mode: "files",
        combos: ["Ctrl+3", "Alt+3"]
    },
    {
        id: "modePlugins",
        mode: "plugins",
        combos: ["Ctrl+4", "Alt+4"]
    }
];

const QT_KEYPAD_MODIFIER = 0x20000000;

// The digit row resolves from the physical key, so Ctrl+1 also fires where it types "&" (AZERTY).
function chordFromEvent(event) {
    const mods = KeyUtils.modsFromEvent(event.modifiers);
    const digit = KeyUtils.digitFromScanCode(event.nativeScanCode);
    if (digit && !(event.modifiers & QT_KEYPAD_MODIFIER))
        return KeyUtils.formatToken(mods, digit);
    return KeyUtils.chordToken(event.key, event.modifiers, mods, event.nativeScanCode, "", "");
}

function combosFor(action, overrides) {
    return overrides?.[action.id] ?? action.combos;
}

function actionForEvent(event, overrides) {
    const chord = KeyUtils.normalizeKeyCombo(chordFromEvent(event), "", "");
    if (!chord)
        return null;
    return ACTIONS.find(action => combosFor(action, overrides).some(combo => KeyUtils.normalizeKeyCombo(combo, "", "") === chord)) ?? null;
}
