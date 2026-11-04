.pragma library

// The 11 niri animations, their defaults (niri-config/src/animations.rs) and the motion math of niri (src/animation).
var names = ["workspace-switch", "window-open", "window-close", "horizontal-view-movement", "window-movement", "window-resize", "config-notification-open-close", "exit-confirmation-open-close", "screenshot-ui-open", "overview-open-close", "recent-windows-close"];
var fields = ["kind", "damping", "stiffness", "epsilon", "ms", "curve"];
var curves = ["ease-out-quad", "ease-out-cubic", "ease-out-expo", "linear"];
var epsilons = [0.0001, 0.001, 0.01];
// How each animation moves the sample window in a preview
var effects = {
    "workspace-switch": "v",
    "window-open": "open",
    "window-close": "close",
    "horizontal-view-movement": "h",
    "window-movement": "h",
    "window-resize": "resize",
    "config-notification-open-close": "v",
    "exit-confirmation-open-close": "open",
    "screenshot-ui-open": "open",
    "overview-open-close": "open",
    "recent-windows-close": "close"
};
// Previews stop here: a very soft spring would otherwise run for seconds
var maxMs = 3000;

// The kind not in use keeps niri's fallback, so switching kind starts from what niri would do.
function spring(damping, stiffness, epsilon) {
    return { kind: "spring", damping: damping, stiffness: stiffness, epsilon: epsilon, ms: 250, curve: "ease-out-cubic" };
}

function curve(ms, name) {
    return { kind: "curve", damping: 1, stiffness: 800, epsilon: 0.0001, ms: ms, curve: name };
}

var niri = {
    "workspace-switch": spring(1, 1000, 0.0001),
    "window-open": curve(150, "ease-out-expo"),
    "window-close": curve(150, "ease-out-quad"),
    "horizontal-view-movement": spring(1, 800, 0.0001),
    "window-movement": spring(1, 800, 0.0001),
    "window-resize": spring(1, 800, 0.0001),
    "config-notification-open-close": spring(0.6, 1000, 0.001),
    "exit-confirmation-open-close": spring(0.6, 500, 0.01),
    "screenshot-ui-open": curve(200, "ease-out-quad"),
    "overview-open-close": spring(1, 800, 0.0001),
    "recent-windows-close": spring(1, 800, 0.001)
};

function ease(name, x) {
    switch (name) {
    case "ease-out-quad":
        return 1 - (1 - x) * (1 - x);
    case "ease-out-cubic":
        return 1 - Math.pow(1 - x, 3);
    case "ease-out-expo":
        return 1 - Math.pow(2, -10 * x);
    default:
        return x;
    }
}

// Spring from 0 to 1 at rest, mass 1, as niri's Spring::oscillate (t in seconds).
function springAt(a, t) {
    const omega0 = Math.sqrt(a.stiffness);
    const beta = a.damping * omega0;
    const envelope = Math.exp(-beta * t);
    if (Math.abs(beta - omega0) <= 1.2e-7)
        return 1 + envelope * (-1 - beta * t);
    if (beta < omega0) {
        const omega1 = Math.sqrt(omega0 * omega0 - beta * beta);
        return 1 + envelope * (-Math.cos(omega1 * t) - beta / omega1 * Math.sin(omega1 * t));
    }
    const omega2 = Math.sqrt(beta * beta - omega0 * omega0);
    return 1 + envelope * (-Math.cosh(omega2 * t) - beta / omega2 * Math.sinh(omega2 * t));
}

// niri's Spring::duration: the envelope bound below critical damping, else the first time it is within epsilon.
function springMs(a) {
    const omega0 = Math.sqrt(a.stiffness);
    const beta = a.damping * omega0;
    if (beta <= 0)
        return maxMs;
    if (beta <= omega0 + 1.2e-7)
        return Math.min(maxMs, Math.ceil(-Math.log(a.epsilon) / beta * 1000));
    for (let ms = 1; ms < maxMs; ms++) {
        if (1 - springAt(a, ms / 1000) <= a.epsilon)
            return ms;
    }
    return maxMs;
}

// Progress 0..1 (a spring may pass 1), one sample per ms, the last one at rest.
function samples(a) {
    const out = [];
    if (a.kind === "curve") {
        const ms = Math.max(1, Math.round(a.ms));
        for (let i = 0; i < ms; i++)
            out.push(ease(a.curve, i / ms));
    } else {
        const ms = springMs(a);
        for (let i = 0; i < ms; i++)
            out.push(springAt(a, i / 1000));
    }
    out.push(1);
    return out;
}

// niri reads damping-ratio and epsilon as floats and stiffness as an integer.
function float(x) {
    return Number.isInteger(x) ? x.toFixed(1) : String(x);
}

function kdlLines(a) {
    if (a.kind === "spring")
        return ["spring damping-ratio=" + float(a.damping) + " stiffness=" + Math.round(a.stiffness) + " epsilon=" + float(a.epsilon)];
    return ["duration-ms " + Math.round(a.ms), "curve \"" + a.curve + "\""];
}

function changed(a, def) {
    if (a.kind !== def.kind)
        return true;
    const used = a.kind === "spring" ? ["damping", "stiffness", "epsilon"] : ["ms", "curve"];
    return used.some(f => a[f] !== def[f]);
}

function preset(style, name) {
    const a = Object.assign({}, niri[name]);
    const isSpring = a.kind === "spring";
    if (style === "snappy") {
        if (isSpring)
            Object.assign(a, { damping: 1, stiffness: 1400 });
        else
            a.ms = 100;
    } else if (style === "bouncy") {
        if (isSpring)
            Object.assign(a, { damping: 0.55, stiffness: 600 });
        else
            a.ms = 220;
    }
    return a;
}

// "default", "snappy", "bouncy" or "" when the animations match no preset; get(name) gives an animation's fields.
function styleOf(get) {
    for (const style of ["default", "snappy", "bouncy"]) {
        if (names.every(n => !changed(get(n), preset(style, n))))
            return style;
    }
    return "";
}
