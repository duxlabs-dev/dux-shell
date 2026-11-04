.pragma library

const MODIFIERS = new Map([
    ["super", "Super"], ["win", "Super"], ["meta", "Super"], ["logo", "Super"], ["mod4", "Super"],
    ["ctrl", "Ctrl"], ["control", "Ctrl"], ["primary", "Ctrl"],
    ["alt", "Alt"], ["mod1", "Alt"], ["altgr", "AltGr"], ["iso_level3_shift", "AltGr"],
    ["shift", "Shift"]
]);
const KEY_NAMES = new Map([
    ["tab", "Tab"], ["enter", "Return"], ["return", "Return"], ["space", "Space"],
    ["backspace", "BackSpace"], ["esc", "Escape"], ["escape", "Escape"],
    ["del", "Delete"], ["delete", "Delete"], ["ins", "Insert"], ["insert", "Insert"],
    ["home", "Home"], ["end", "End"], ["pgup", "Page_Up"], ["pageup", "Page_Up"],
    ["pgdn", "Page_Down"], ["pagedown", "Page_Down"], ["up", "Up"], ["down", "Down"],
    ["left", "Left"], ["right", "Right"], ["print", "Print"], ["printscreen", "Print"],
    ["prtsc", "Print"], ["pause", "Pause"], ["menu", "Menu"],
    ["comma", "Comma"], ["period", "Period"], ["slash", "Slash"], ["semicolon", "Semicolon"],
    ["colon", "Colon"], ["exclam", "Exclam"], ["minus", "Minus"], ["equal", "Equal"],
    ["plus", "Plus"], ["bracketleft", "BracketLeft"], ["bracketright", "BracketRight"],
    ["backslash", "Backslash"], ["apostrophe", "Apostrophe"], ["grave", "grave"]
]);
const MOD_ORDER = ["Super", "Ctrl", "Alt", "AltGr", "Shift"];

// A free combination lights its key only when the text parses as a chord of known modifiers
// and a real key name; anything else gives "" and stays out of the key pick.
// modKey: what "Mod" stands for (KeybindsService.modKey).
function parseChord(text, modKey) {
    const parts = String(text ?? "").split("+").map(part => part.trim()).filter(part => part !== "");
    if (parts.length < 2)
        return "";
    const last = parts[parts.length - 1].toLowerCase();
    let key = KEY_NAMES.get(last) ?? "";
    if (!key && /^f([1-9]|1[0-2])$/.test(last))
        key = last.toUpperCase();
    if (!key && /^xf86[a-z0-9]+$/.test(last))
        key = parts[parts.length - 1];
    if (!key && parts[parts.length - 1].length === 1)
        key = last.toUpperCase();
    if (!key)
        return "";
    const mods = [];
    for (const part of parts.slice(0, -1)) {
        const name = part.toLowerCase() === "mod" ? (modKey || "Super") : MODIFIERS.get(part.toLowerCase());
        if (!name || mods.includes(name))
            return "";
        mods.push(name);
    }
    mods.sort((a, b) => MOD_ORDER.indexOf(a) - MOD_ORDER.indexOf(b));
    return [...mods, key].join("+");
}
