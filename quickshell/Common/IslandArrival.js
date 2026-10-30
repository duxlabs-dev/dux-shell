.pragma library
.import "IslandActivities.js" as Activities
.import "IslandKit.js" as Kit

// How an info arrives in the island: the swell, the burst of infos rolling over each other, the countdown dot and its
// freeze (the gestures: IslandArrivalGestures.js). Plain functions over plain state; the controller and the wing hold
// the state and the clock.

// A notification or a plugin's activity (Activities.tiers): important for a call, a critical alert or a plugin's alert.
function tierOf(info) {
    return info?.critical === true || info?.urgent === true ? Activities.tiers.important : Activities.tiers.normal;
}

// Whether a notification takes the island now: when it is free or already shows one; a critical one (a call) also over
// an open face, but never over the launcher, where it stands as a bubble beside it like every other info.
function takesIsland(showing, expanded, critical, activity) {
    return showing || !expanded || (critical === true && activity !== "launcher");
}

// A notification of an incoming call (its freedesktop category hint): it rings until it goes.
function ringing(category) {
    return category === "call" || category === "call.incoming";
}

// An info's notice icon alert (IslandNoticeIcon.alert). A call is a call, whatever the app: never the red alert
// shape, it rings in DMS's main color.
function alertOf(info) {
    return info?.call === true ? "" : info?.critical === true ? "critical" : info?.important === true ? "important" : "";
}

// An info goes by itself once its time is up; a ringing call never does: it stays until answered, refused or gone.
function expires(info) {
    return info?.call !== true;
}

// "bc": Apple's step with more detail (the card) and Google's bounce and tint (default); "c": the bounce only;
// "a": one quiet breath, the same for all.
const styles = ["bc", "c", "a"];
// How long the island stays grown, per tier: B + C takes the lifetimes (big, also the countdown of a burst page); C and A
// only swell, for their own short beat.
const holds = {
    "c": [420, 650, 900],
    "a": [380, 380, 380]
};
// A swell without the card, in compact thicknesses: [along, cross] per tier.
const swells = {
    "bc": [[0.4, 0.16], [0.65, 0.32], [0.9, 0.5]],
    "c": [[0.4, 0.16], [0.65, 0.32], [0.9, 0.5]],
    "a": [[0.32, 0.16], [0.32, 0.16], [0.32, 0.16]]
};
const bounceRatios = {
    "none": 1,
    "light": 0.8,
    "medium": 0.62,
    "strong": 0.48
};
const tintLevels = {
    "none": 0,
    "light": 0.5,
    "normal": 0.8,
    "strong": 1
};
const bounceNames = ["none", "light", "medium", "strong"];
const tintNames = ["none", "light", "normal", "strong"];
const defaultBounce = ["light", "light", "medium"];
const defaultTint = ["light", "normal", "strong"];

// The arrival of one info: big (the card) or a swell, how long, the spring's damping ratio, the tint's strength.
function pulse(style, tier, card, bounce, tint, reduced) {
    const s = styles.indexOf(style) !== -1 ? style : "bc";
    const t = Activities.tierIndex(tier);
    const big = s === "bc" && t >= Activities.tiers.normal && card === true;
    const quiet = s === "a";
    return {
        "big": big,
        "holdMs": s === "bc" ? Activities.bigMs(t) : holds[s][t],
        "swell": big ? [0, 0] : swells[s][t],
        "ratio": quiet || reduced === true ? 1 : bounceRatios[(bounce ?? defaultBounce)[t]] ?? bounceRatios[defaultBounce[t]],
        "tint": quiet ? 0 : tintLevels[(tint ?? defaultTint)[t]] ?? tintLevels[defaultTint[t]]
    };
}

// While the island's shape springs (a swell, its card, the fold back), its content stays in the middle of it: equal room
// above and below at every frame, never pinned to the edge the island hangs from.
function centered(outer, inner) {
    return Math.round((outer - inner) / 2);
}

// How far the island has grown from its compact face (0) to its card (1), read from its spring's cross size: the content
// moves on the island's own spring, one gesture. Not clamped, so it rides the bounce; reduced motion: only the two ends.
// A face's target swollen by swell ([along, across], in thick).
function swollen(target, swell, thick, vertical) {
    const along = swell[0] * thick, across = swell[1] * thick;
    return Object.assign({}, target, {
        "width": target.width + (vertical ? across : along),
        "height": target.height + (vertical ? along : across)
    });
}

function grow(cross, compact, big, reduced) {
    const span = big - compact;
    if (span < 1)
        return 0;
    const t = (cross - compact) / span;
    return reduced === true ? (t >= 0.5 ? 1 : 0) : t;
}

// An element both layouts show (the icon, the title), both centred in the island: its offset and scale in its own
// layout at t (0 = its own place, 1 = the other's place and size). own, other: {x, y, size, w, h}, the element's anchor
// and size in its layout, and that layout's box.
function fly(own, other, t) {
    return {
        "x": (other.x + (own.w - other.w) / 2 - own.x) * t,
        "y": (other.y + (own.h - other.h) / 2 - own.y) * t,
        "scale": 1 + (other.size / own.size - 1) * t
    };
}

// Opacities at t (0 compact, 1 card): the shared elements hand over on the way while both fly together (the compact
// one at 1 - shared); what only the card has comes in over the last part of the way and leaves first on the fold, so
// the flying ones never cross it; what only the compact face has is gone by reveal.
function handover(t, reveal) {
    return {
        "shared": Kit.unit((t - reveal / 3) / (reveal * 2 / 3)),
        "cardOwn": Kit.unit((2 * t - 1 - reveal) / (1 - reveal)),
        "compactOwn": 1 - Kit.unit(t / reveal)
    };
}

// Burst: the infos since the island left the clock, and the one it shows. A newcomer rolls in from below (axis "y", the
// old one leaves at the top); going through them rolls sideways (axis "x": dir 1 from the right, -1 from the left).
// dir 0 does not roll.
function emptyBurst() {
    return {
        "items": [],
        "index": -1,
        "dir": 0,
        "axis": "y"
    };
}

// A newcomer takes the island at once, unless it is held: then it waits as one more dot, the read one stays.
function arrive(burst, item, frozen) {
    const items = burst.items.concat([item]);
    const index = burst.index < 0 ? 0 : frozen ? burst.index : items.length - 1;
    return {
        "items": items,
        "index": index,
        "dir": burst.index < 0 || index === burst.index ? 0 : 1,
        "axis": "y"
    };
}

function go(burst, to) {
    if (to < 0 || to >= burst.items.length || to === burst.index)
        return null;
    return {
        "items": burst.items,
        "index": to,
        "dir": Math.sign(to - burst.index),
        "axis": "x"
    };
}

// The countdown is over: the next info if one is left, else null (the island folds to compact).
// The burst without the info it shows (read: dismissed, acted on), or null once none is left.
function drop(burst) {
    const items = burst.items.filter((_, i) => i !== burst.index);
    return items.length === 0 ? null : {
        "items": items,
        "index": Math.min(burst.index, items.length - 1),
        "dir": 0,
        "axis": "x"
    };
}

function afterCountdown(burst) {
    return go(burst, burst.index + 1);
}

function topTier(items) {
    return items.reduce((top, i) => Math.max(top, i.tier ?? Activities.tiers.normal), -1);
}

// Page dots: five at most; past that the row slides with the shown one and the dots at a hidden end shrink (iOS).
// Each dot: "on" | "dot" | "edge" | "gone".
function pager(count, index, max) {
    const most = max ?? 5;
    const start = Math.max(0, Math.min(index - 2, count - most));
    const dots = [];
    for (let i = 0; i < count; i++) {
        if (i === index)
            dots.push("on");
        else if (i < start || i >= start + most)
            dots.push("gone");
        else if ((i === start && start > 0) || (i === start + most - 1 && start + most < count))
            dots.push("edge");
        else
            dots.push("dot");
    }
    return {
        "start": start,
        "dots": dots
    };
}

// Countdown of the shown page, read as the active dot filling. Frozen (pointer, finger, keyboard focus on the island):
// the dot empties gently from where it was, then nothing ticks; let go, it starts over.
const drainMs = 450;

function countdown(duration, now) {
    return {
        "start": now,
        "duration": duration,
        "frozenAt": -1,
        "frozenFill": 0,
        "drain": drainMs
    };
}

function fill(cd, now) {
    if (cd.frozenAt < 0)
        return Kit.unit((now - cd.start) / Math.max(1, cd.duration));
    return Math.max(0, cd.frozenFill * (1 - (now - cd.frozenAt) / Math.max(1, cd.drain)));
}

function freeze(cd, now, drain) {
    if (cd.frozenAt >= 0)
        return cd;
    return Object.assign({}, cd, {
        "frozenAt": now,
        "frozenFill": fill(cd, now),
        "drain": drain ?? drainMs
    });
}

function freezeEmpty(cd, now, drain) {
    return Object.assign({}, cd, {
        "frozenAt": now,
        "frozenFill": 0,
        "drain": drain ?? drainMs
    });
}

function done(cd, now) {
    return cd.frozenAt < 0 && now - cd.start >= cd.duration;
}

// ms left before the countdown is done, -1 while frozen.
function remaining(cd, now) {
    return cd.frozenAt < 0 ? Math.max(0, cd.start + cd.duration - now) : -1;
}

function ticking(cd, now) {
    return cd.frozenAt < 0 || fill(cd, now) > 0;
}

// The smallest fill step worth a frame: half a pixel of the dot.
function quantum(widthPx) {
    return 0.5 / Math.max(1, widthPx);
}

// The ms the fill takes to move one quantum: running, over its duration; frozen, draining from its frozen fill over its
// drain time. Never under minStepMs, a 60 Hz image.
const minStepMs = 16;
function stepMs(cd, widthPx) {
    const q = quantum(widthPx);
    const ms = cd.frozenAt < 0 ? cd.duration * q : cd.drain * q / Math.max(q, cd.frozenFill);
    return Math.max(minStepMs, Math.round(ms));
}

function shown(current, next, widthPx) {
    return next === 0 || next === 1 || Math.abs(next - current) >= quantum(widthPx) ? next : current;
}
