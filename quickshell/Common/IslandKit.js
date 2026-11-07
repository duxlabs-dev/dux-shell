.pragma library
.import "../DCommon/Common/Contrast.js" as Contrast

// The island kit's shared rules, plain arithmetic: motion and layout (springs of interior.dev, MIT), frame cadence, alerts.

// [stiffness, damping, mass] at DMS's default animation speed.
var springs = {
    "cell": [520, 34, 0.45],
    "fill": [210, 34, 0.9]
};

// Content micro-motions, in multiples of DMS's animation speed.
var beats = {
    // An important info rings like a phone: its second ring leaves this long after the first.
    "ringGap": 1.6,
    // A ringing call rings again after this pause, like a phone.
    "ringPause": 4
};
// How far a ringing call's shape swings each ring, in degrees at the spring's peak.
var ringTilt = 12;
// A shape moving on to its next one beats out by this much (the app icon's poke, a replaced face on the wing).
var morphPulse = 0.15;

// DMS's default animation duration: the speed the tables above are tuned at.
var baseMs = 250;

// A beat at DMS's animation speed (250 ms by default); 0 at speed 0, where content shows its final state.
function beat(name, baseDuration) {
    return baseDuration > 0 ? Math.round(baseDuration * (beats[name] ?? 1)) : 0;
}

// A share in 0..1 for a meter: a negative one or NaN reads as 0, one over 1 as 1.
function unit(v) {
    return v > 0 ? Math.min(1, v) : 0;
}

// The Theme roles a face on the island can sit on (DIslandSurface); a mark stands markContrast off each.
var islandGrounds = ["surface", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "surfaceBright", "surfaceDim"];
// WCAG's 3:1 for a shape or a glyph (a non-text mark).
var markContrast = 3;
// WCAG AA's 4.5:1 for text, as the sender's initial drawn in place of an icon.
var textContrast = 4.5;

// An alert's [shape, icon, text] colours (null without one): the first shape tone that stands markContrast off every
// island ground, then the first icon tone that stands markContrast on that shape, and the first at textContrast.
function alertTones(alert, theme) {
    if (!alert)
        return null;
    const critical = alert === "critical";
    const grounds = islandGrounds.map(role => theme[role]);
    const shape = Contrast.readableOnAll(grounds, critical ? [theme.errorContainer, theme.error, theme.surfaceText] : [theme.warning, theme.surfaceText], markContrast);
    const icons = critical ? [theme.onErrorContainer, theme.onError, theme.surface, theme.surfaceText] : [theme.surface, theme.surfaceText];
    return [shape, Contrast.readableOn(shape, icons, markContrast), Contrast.readableOn(shape, icons, textContrast)];
}

// An alert's rings, ms into them: a cycle sends a ring every gap, each lasting span, then pauses; cycles 0 never ends.
function ringCycle(span, gap, rings, pause) {
    return (rings - 1) * gap + span + pause;
}

function ringsOver(ms, span, gap, rings, pause, cycles) {
    return span <= 0 || (cycles > 0 && ms >= (cycles - 1) * ringCycle(span, gap, rings, pause) + (rings - 1) * gap + span);
}

function ringT(ms, span, gap, rings, pause, cycles, i) {
    if (ms < 0 || ringsOver(ms, span, gap, rings, pause, cycles))
        return 1;
    const t = (ms % ringCycle(span, gap, rings, pause) - i * gap) / span;
    return t >= 0 && t < 1 ? t : 1;
}

// The shape's swing (-1..1 at the peak): each ring kicks it, one way then the other, back on the spring (stiffness,
// damping ratio under swingMaxRatio so it peaks, mass). A negative ratio, no stiffness or no mass: no swing.
var swingMaxRatio = 0.95;
function ringSwing(ms, span, gap, rings, pause, cycles, stiffness, ratio, mass) {
    if (ms <= 0 || !(stiffness > 0) || !(mass > 0) || !(ratio >= 0) || ringsOver(ms, span, gap, rings, pause, cycles))
        return 0;
    const w = Math.sqrt(stiffness / mass), z = Math.min(swingMaxRatio, ratio), wd = w * Math.sqrt(1 - z * z);
    const tp = Math.atan(wd / (z * w)) / wd;
    const peak = Math.exp(-z * w * tp) * Math.sin(wd * tp);
    const local = ms % ringCycle(span, gap, rings, pause);
    let x = 0;
    for (let i = 0; i < rings; i++) {
        const s = (local - i * gap) / 1000;
        if (s > 0)
            x += (i % 2 ? -1 : 1) * Math.exp(-z * w * s) * Math.sin(wd * s);
    }
    return x / peak;
}

// DMS's animation speed stretches time: k / f² and c / f keep the spring's shape, at most 1 / minStretch times faster.
var minStretch = 0.05;
function spring(name, baseDuration) {
    const s = springs[name] ?? springs.cell;
    const f = Math.max(minStretch, (baseDuration > 0 ? baseDuration : baseMs) / baseMs);
    return {
        "stiffness": s[0] / (f * f),
        "damping": s[1] / f,
        "mass": s[2]
    };
}

// A full-width row split by weights (1 1 2 2 for the call card), whole pixels, ending exactly at the edge.
function rowLayout(total, weights, gap) {
    const n = weights.length;
    if (n === 0 || total <= 0)
        return [];
    const clean = weights.map(w => w > 0 ? w : 0);
    const sum = clean.reduce((a, w) => a + w, 0);
    const parts = sum > 0 ? clean : clean.map(() => 1);
    const partsSum = sum > 0 ? sum : n;
    const free = Math.max(0, Math.floor(total - gap * (n - 1)));
    let acc = 0;
    let edge = 0;
    return parts.map((w, i) => {
        acc += w;
        // Rounding the running edge, not each width, keeps every part within a pixel of its share.
        const next = Math.round(free * acc / partsSum);
        const cell = {
            "x": edge + i * gap,
            "width": next - edge
        };
        edge = next;
        return cell;
    });
}

// The liquid's front past its mean line at d (0 mid-front, 1 at its walls); amp follows its speed, phase its travel.
function wave(d, amp, phase) {
    return amp * Math.sin(phase + Math.PI * d);
}

// Its slope along d, for a front drawn as cubic curves (no point array per frame).
function waveSlope(d, amp, phase) {
    return amp * Math.PI * Math.cos(phase + Math.PI * d);
}

// Where in [0, hi] a rising f reaches y, by bisection: bisectSteps halvings land within a billionth of the range.
var bisectSteps = 30;
function solveRising(f, y, hi) {
    let lo = 0;
    for (let i = 0; i < bisectSteps; i++) {
        const mid = (lo + hi) / 2;
        if (f(mid) < y)
            lo = mid;
        else
            hi = mid;
    }
    return (lo + hi) / 2;
}

// A CSS cubic-bezier(x1, y1, x2, y2) easing at x (0..1), solved on its x.
function bezier(x1, y1, x2, y2, x) {
    if (x <= 0)
        return 0;
    if (x >= 1)
        return 1;
    const at = (a, b, t) => 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t;
    return at(y1, y2, solveRising(t => at(x1, x2, t), x, 1));
}

// A costly frame is redrawn once `every` refreshes went by (within half of one, as DMS's timer ticks off vsync) and
// something moved minStepPx.
var minStepPx = 0.5;
function cadenceDue(refreshes, every, movedPx) {
    return refreshes >= every - 0.5 && movedPx >= minStepPx;
}

// What is left once a frame is drawn, carried to the next (half a refresh at most), so frames do not drift late.
function cadenceCarry(refreshes, every) {
    return Math.max(-0.5, Math.min(0.5, refreshes - every));
}

// The refresh the kit's clocks count in while the screen's own is unknown (screenRefresh gives 0).
var fallbackHz = 60;
// The refresh of the screen named `name`, from niri's outputs (its current mode, mHz), 0 when unknown.
function screenRefresh(outputs, name) {
    const output = outputs?.[name];
    const mode = output?.modes?.[output?.current_mode];
    return mode?.refresh_rate > 0 ? mode.refresh_rate / 1000 : 0;
}

// Screens refresh at a known rate: the nearest one to a measured refresh, so a little jitter never shifts the range.
var panelRates = [24, 30, 48, 50, 60, 72, 75, 85, 90, 100, 120, 144, 165, 170, 175, 180, 200, 240, 280, 300, 360, 480];
function panelRate(refresh) {
    let best = panelRates[0];
    for (let i = 1; i < panelRates.length; i++) {
        if (Math.abs(panelRates[i] - refresh) < Math.abs(best - refresh))
            best = panelRates[i];
    }
    return best;
}

// Under this speed (px/s, NaN included) a decor reads as still: the slowest cadence, and no division by zero.
var stillSpeed = 1e-3;

// How many refreshes apart a step of `px` at `speed` px/s fits, within [fewest, most].
function stepsFit(px, hz, speed, fewest, most) {
    return Math.max(fewest, Math.min(most, Math.floor(px * hz / (speed > stillSpeed ? speed : stillSpeed))));
}

// A decor is drawn decorMinHz to decorMaxHz times a second; a measured refresh off by up to rateSlack of a step (121,
// 239) keeps the same range; it slows down only once a step would stay under slowStepPx.
var decorMaxHz = 120;
var decorMinHz = 24;
var rateSlack = 0.05;
var slowStepPx = 0.8;

// A divisor of the screen's rate, so a decor never judders; it slows one refresh at a time, and only once a step stays
// well under a pixel, so it never flaps.
function framesBetween(refresh, speed, prev) {
    const hz = panelRate(refresh);
    const fewest = Math.max(1, Math.ceil(hz / decorMaxHz - rateSlack));
    const most = Math.max(fewest, Math.floor(hz / decorMinHz + rateSlack));
    // No speed to read (0/0 on a first frame) counts as still.
    const k = stepsFit(1, hz, speed, fewest, most);
    if (!(prev > 0) || k < prev)
        return k;
    return Math.max(fewest, Math.min(most, stepsFit(slowStepPx, hz, speed, fewest, most) > prev ? prev + 1 : prev));
}
