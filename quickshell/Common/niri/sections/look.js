.pragma library

// Colors are a DMS theme role or "#rrggbb"; "primary" is what DMS colors.kdl already writes.
var defaults = {
    "look.ringOn": true,
    "look.ringColor": "primary",
    "look.borderOn": false,
    "look.borderColor": "primary",
    "look.shadowOn": false,
    "look.blurOn": false,
    "look.xray": true,
    "look.barXray": true
};

// Slider from/to; min reaches below the slider for DMS's own values: gaps -2/-1 "my config"/"auto",
// widths -1 "default" (LookCard); the radius sentinel -1 is the toggle row's "auto" (LookRadiusRow).
// Style import and the sliders both read these.
var limits = {
    "look.gaps": { min: -2, from: 0, to: 64 },
    "look.ringWidth": { min: -1, from: 1, to: 16 },
    "look.borderWidth": { min: -1, from: 1, to: 16 },
    "look.radius": { min: -1, from: 0, to: 32 }
};

// One writer per niri key: DMS layout.kdl writes both the ring and the border width from one setting.
var stored = {
    "look.gaps": "SettingsData:niriLayoutGapsOverride",
    "look.ringOn": "page",
    "look.ringWidth": "SettingsData:niriLayoutBorderSize",
    "look.ringColor": "page",
    "look.borderOn": "page",
    "look.borderWidth": "SettingsData:niriLayoutBorderSize",
    "look.borderColor": "page",
    "look.radius": "SettingsData:niriLayoutRadiusOverride",
    "look.shadowOn": "page",
    "look.blurOn": "page",
    "look.blurStrength": "SettingsData:blurStrength",
    "look.xray": "NiriService:layoutXrayEnabled:setLayoutXray",
    "look.barXray": "NiriService:layoutBarXrayEnabled:setLayoutBarXray"
};

var search = [
    { key: "look.gaps", title: "Gaps", words: ["gaps", "space", "spacing", "room", "espace", "écart", "marge", "plus d'espace"] },
    { key: "look.ringOn", title: "Window focus ring", words: ["focus", "ring", "active", "outline", "anneau"] },
    { key: "look.ringWidth", title: "Ring width", words: ["focus", "ring", "width", "thickness", "anneau", "épaisseur", "largeur"] },
    { key: "look.ringColor", title: "Ring color", words: ["ring", "color", "colour", "accent", "theme", "anneau", "couleur"] },
    { key: "look.borderOn", title: "Border", words: ["border", "bordure"] },
    { key: "look.borderWidth", title: "Border width", words: ["border", "width", "bordure", "épaisseur", "largeur"] },
    { key: "look.borderColor", title: "Border color", words: ["border", "color", "colour", "bordure", "couleur"] },
    { key: "look.radius", title: "Override window radius", words: ["corner", "radius", "rounded", "round", "corners", "coins", "arrondis", "override", "window"] },
    { key: "look.shadowOn", title: "Window shadows", words: ["shadow", "ombre", "ombres"] },
    { key: "look.blurOn", title: "Blur", words: ["blur", "frosted", "transparent", "flou", "verre"] },
    { key: "look.blurStrength", title: "Blur strength", words: ["blur", "strength", "amount", "flou", "force"] }
];

// The radius sentinel -1 follows the DMS theme (Theme.qml windowRadius); 0 is a real size
// that squares every DMS surface, so the toggle row writes -1 when off, never a stray 0.
function radiusAuto(v) {
    return v < 0;
}

function radiusWrite(on, themeRadius) {
    return on ? Math.max(0, Math.round(themeRadius)) : -1;
}

// NiriPageService turns theme roles into hex before this runs; "primary" stays, colors.kdl writes it.
function colorLine(value) {
    // Qt writes alpha first (#aarrggbb), niri last, so only opaque colors go through.
    return /^#[0-9a-fA-F]{6}$/.test(value || "") ? ["active-color \"" + value + "\""] : [];
}

function toKdl(state) {
    const ring = state["look.ringOn"] === false ? ["off"] : colorLine(state["look.ringColor"]);
    const border = state["look.borderOn"] ? ["on"].concat(colorLine(state["look.borderColor"])) : [];
    const blur = state["look.blurOn"] ? ["window-rule {\n    background-effect {\n        blur true\n    }\n}"] : [];
    return [
        { block: "layout.focus-ring", lines: ring },
        { block: "layout.border", lines: border },
        { block: "layout.shadow", lines: state["look.shadowOn"] ? ["on"] : [] },
        { block: null, lines: blur }
    ];
}
