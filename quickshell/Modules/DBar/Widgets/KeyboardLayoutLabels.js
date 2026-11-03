.pragma library
.import "../../../DCommon/Common/LayoutCodes.js" as LayoutCodes

var VALID_VARIANTS = ["US", "UK", "GB", "AZERTY", "QWERTY", "Dvorak", "Colemak", "Mac", "Intl", "International"];

// Overrides are keyed by whatever string would otherwise be displayed, so the same
// map applies after any compositor-specific shortening (compact vs. vertical mode).
function applyOverride(label, overrides) {
    return (overrides && overrides[label]) ?? label;
}

function displayLabel(layoutName, compactMode, codesOnly, validVariants, overrides) {
    if (!layoutName)
        return "";
    if (!compactMode || codesOnly)
        return applyOverride(layoutName, overrides);
    const match = layoutName.match(/^(\S+)(?:.*\(([^)]+)\))?/);
    if (!match)
        return applyOverride(LayoutCodes.layoutCode(layoutName), overrides);
    const lang = match[1].toLowerCase();
    const code = LayoutCodes.LANG_CODES[lang] || lang.substring(0, 2);
    if (!match[2])
        return applyOverride(code.toUpperCase(), overrides);
    const variant = match[2].trim();
    const isValid = validVariants.some(v => variant.toUpperCase().includes(v.toUpperCase())) || variant.length <= 3;
    return applyOverride(isValid ? code + "-" + variant : code.toUpperCase(), overrides);
}

function verticalLabel(layoutName, overrides) {
    return applyOverride(LayoutCodes.layoutCode(layoutName), overrides);
}
