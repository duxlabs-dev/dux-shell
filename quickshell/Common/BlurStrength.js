.pragma library

// One shell-wide blur reach in logical px, per-compositor
var HYPRLAND_DEFAULT = 48;
var NIRI_DEFAULT = 42;
var AQUEOUS_DEFAULT = 40;

function defaultReach(compositor) {
    switch (compositor) {
    case "hyprland":
        return HYPRLAND_DEFAULT;
    case "niri":
        return NIRI_DEFAULT;
    case "aqueous":
        return AQUEOUS_DEFAULT;
    default:
        return 0;
    }
}

function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
}

// Dual kawase reach is 2 * size * (2^passes - 1); passes step up so size stays small enough to avoid banding
function hyprlandBlur(reach) {
    const passes = reach <= 20 ? 1 : reach <= 60 ? 2 : reach <= 140 ? 3 : 4;
    const size = clamp(Math.round(reach / (2 * ((1 << passes) - 1))), 1, 20);
    return { size, passes };
}

// Same kawase family; offset is free on the GPU while passes are not, so passes stay at niri's default 3
function niriBlur(reach) {
    return { offset: Math.round(reach / 14 * 10) / 10, passes: 3 };
}

// Separable gaussian whose width is independent of passes; sigma is about 0.26 * radius
function aqueousRadius(reach) {
    return clamp(Math.round(reach / 4), 1, 128);
}
