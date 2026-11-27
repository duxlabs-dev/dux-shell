.pragma library

var NAMES = ["none", "fade", "wipe", "disc", "stripes", "iris bloom", "pixelate", "portal", "tiles", "ripple"];

function pick(transition, included) {
    if (transition !== "random")
        return transition;
    if (!Array.isArray(included) || included.length === 0)
        return "none";
    return included[Math.floor(Math.random() * included.length)];
}

function params(type) {
    switch (type) {
    case "wipe":
        return {
            direction: Math.random() * 4
        };
    case "disc":
    case "pixelate":
    case "portal":
        return {
            centerX: Math.random(),
            centerY: Math.random()
        };
    case "stripes":
        return {
            stripeCount: Math.round(Math.random() * 20 + 4),
            angle: Math.random() * 360
        };
    case "tiles":
        return {
            seed: Math.random()
        };
    }
    return {};
}
