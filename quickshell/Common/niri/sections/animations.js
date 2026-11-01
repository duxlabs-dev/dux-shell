.pragma library
.import "../anim.js" as Anim

var prefix = "animations.";

var defaults = (function () {
    const d = {
        "animations.on": true,
        "animations.slowdown": 1
    };
    for (const name of Anim.names) {
        for (const field of Anim.fields)
            d[prefix + name + "." + field] = Anim.niri[name][field];
    }
    return d;
})();

// Slider from/to; style import reads the same bounds.
var limits = {
    "animations.slowdown": { from: 0.2, to: 4 }
};

var stored = (function () {
    const s = {};
    for (const key in defaults)
        s[key] = "page";
    return s;
})();

var search = [
    {
        key: "animations.window-open.kind",
        title: "Animation style",
        words: ["animation", "style", "preset", "snappy", "bouncy"]
    },
    {
        key: "animations.on",
        title: "Window animations",
        words: ["animations", "off", "disable", "on", "motion"]
    },
    {
        key: "animations.slowdown",
        title: "Slowdown",
        words: ["slowdown", "speed", "faster", "slower"]
    },
    {
        key: "animations.window-open.ms",
        title: "Fine tune",
        words: ["spring", "curve", "damping", "stiffness", "epsilon", "duration", "easing"]
    }
];

function read(state, name) {
    const a = {};
    for (const field of Anim.fields)
        a[field] = state[prefix + name + "." + field];
    return a;
}

// niri replaces each animation sub-block whole, so a changed one is written with all its values and an unchanged one not at all.
function toKdl(state) {
    const top = [];
    if (state["animations.on"] === false)
        top.push("off");
    if (state["animations.slowdown"] !== defaults["animations.slowdown"])
        top.push("slowdown " + Anim.float(state["animations.slowdown"]));
    const blocks = [{ block: "animations", lines: top }];
    for (const name of Anim.names) {
        const a = read(state, name);
        if (Anim.changed(a, Anim.niri[name]))
            blocks.push({ block: "animations." + name, lines: Anim.kdlLines(a) });
    }
    return blocks;
}
