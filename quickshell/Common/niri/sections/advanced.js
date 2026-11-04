.pragma library
.import "../../niriKdl.js" as Kdl

// Boolean flags of niri's debug block worth a switch; the rest needs values and goes through the KDL drawer.
var debugFlags = ["disable-direct-scanout", "disable-cursor-plane", "enable-overlay-planes", "wait-for-frame-completion-before-queueing", "keep-max-bpc-unchanged", "skip-cursor-only-updates-during-vrr", "honor-xdg-activation-with-invalid-serial", "deactivate-unfocused-windows"];

var defaults = {
    "advanced.modKey": "Super",
    "advanced.powerKey": false,
    "advanced.xwayland": true,
    "advanced.debug": false
};
debugFlags.forEach(flag => defaults["advanced.dbg." + flag] = false);

var stored = {};
Object.keys(defaults).forEach(key => stored[key] = "page");

// DMS's own reload toast, not a niri key: it stays out of defaults and toKdl.
stored["advanced.configToast"] = "SessionData:showConfigReloadToast";

// Each can cut the keyboard or the screen: the section asks "keep?" and goes back after 15 s.
var risky = Object.keys(defaults);

var search = [
    { key: "advanced.modKey", title: "Mod key", words: ["mod", "super", "alt", "modifier", "logo"] },
    { key: "advanced.powerKey", title: "DMS handles the power button", words: ["power", "button", "key"] },
    { key: "advanced.xwayland", title: "X11 apps", words: ["x11", "xwayland", "satellite", "xorg", "apps", "applications"] },
    { key: "advanced.debug", title: "Debug options", words: ["debug", "scanout", "overlay", "drm", "options"] },
    { key: "advanced.configToast", title: "Show \"config reloaded\" toast", words: ["toast", "notification", "reload", "reloaded", "config", "configuration"] }
];

function toKdl(state) {
    const input = [];
    if (state["advanced.modKey"] !== defaults["advanced.modKey"])
        input.push("mod-key " + Kdl.kdlString(state["advanced.modKey"]));
    if (state["advanced.powerKey"])
        input.push("disable-power-key-handling");
    const debug = state["advanced.debug"] ? debugFlags.filter(flag => state["advanced.dbg." + flag]) : [];
    return [
        { block: "input", lines: input },
        { block: "xwayland-satellite", lines: state["advanced.xwayland"] ? [] : ["off"] },
        { block: "debug", lines: debug }
    ];
}
