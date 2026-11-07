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
    // An arriving info's tint fading.
    "tint": 2.08,
    // An arriving info: the page rolling in and out, a new page dot popping, a frozen dot emptying.
    "roll": 1.36,
    "rollOut": 0.88,
    "pop": 1.28,
    "drain": 1.8,
    // An important info rings like a phone: its second ring leaves this long after the first.
    "ringGap": 1.6,
    // A ringing call rings again after this pause, like a phone.
    "ringPause": 4
};
// How far a ringing call's shape swings each ring, in degrees at the spring's peak.
var ringTilt = 12;
// The shown page's countdown, [fill, track alpha] in theme (Theme): the text tone, else the far end (white on a dark
// theme, black on a light one), with the opacity of it laid as a track that stands markContrast off every island ground
// while the fill stands markContrast off the track on each (the middle of the opacities that do). Where none does (a
// ground under 9:1 from the far end, as Monochrome dark's brightest), the opacity that comes closest.
function countdownTones(theme, light) {
    const grounds = islandGrounds.map(role => theme[role]);
    const far = light ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1);
    let best = [far, 0.5], bestWorst = 0;
    for (const fill of [theme.surfaceText, far]) {
        const fits = [];
        for (let i = 20; i <= 80; i++) {
            const worst = Math.min(...grounds.map(ground => {
                const track = Contrast.mix(ground, fill, i / 100);
                return Math.min(Contrast.ratio(track, ground), Contrast.ratio(fill, track));
            }));
            if (worst >= markContrast)
                fits.push(i / 100);
            if (worst > bestWorst) {
                best = [fill, i / 100];
                bestWorst = worst;
            }
        }
        if (fits.length > 0)
            return [fill, fits[fits.length >> 1]];
    }
    return best;
}

// A bubble's wing comes in on a spring this underdamped (a small overshoot); a ringing call's shape rocks back on it.
var bubbleInDampingRatio = 0.6;
// A card's content shows early in its growth (the kit's card opening, Interior's SURFACE: content early).
var revealFrom = 0.35;
// A presence, fade or spring (0..1) below this counts as none: nothing is drawn for it, nothing waits on it.
var shownFrom = 0.01;

// A shape moving on to its next one beats out by this much (the app icon's poke, a replaced face on the wing).
var morphPulse = 0.15;

// A gauge's liquid and its track, as alphas of one hue (trackAlpha alone: behind an opaque liquid). On a light theme a
// 0.24 track leaves the liquid at 2.5:1; lightTrackAlpha keeps it at 3:1, and the dark value on it at 4.5:1.
var fillAlpha = 0.75;
var trackAlpha = 0.24;
var lightTrackAlpha = 0.08;
function waveTrackAlpha(light) {
    return light ? lightTrackAlpha : trackAlpha;
}

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

function mix(a, b, t) {
    return a + (b - a) * t;
}

// A bubble born floating fades in faster than it grows (opaque at two thirds), from half its size at the island's edge.
var appearGain = 1.5;
var appearScaleFrom = 0.5;
function appearOpacity(presence) {
    return unit(presence * appearGain);
}
function appearScale(presence) {
    return mix(appearScaleFrom, 1, unit(presence));
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

// A ready face's ring (a script's or plugin's shell-drawn face): its track is the face's tone at this alpha.
var readyTrackAlpha = 0.25;

// The source's accent if it stands markContrast off every island ground and off its track, else the surface's text.
function readyTone(accent, theme) {
    const grounds = islandGrounds.map(role => theme[role]);
    // The ground the island paints by default counts too: the host surface pick (a container, the inverse surface).
    if (theme.hostSurface)
        grounds.push(theme.hostSurface);
    const stands = tone => grounds.every(ground => Contrast.ratio(tone, ground) >= markContrast && Contrast.ratio(tone, Contrast.mix(ground, tone, readyTrackAlpha)) >= markContrast);
    const picked = theme[accent] ?? theme.primary;
    return stands(picked) ? picked : theme.surfaceText;
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

// Air between a glyph's box edge and its ink, for a glyph centred in its box (icons).
function boxBearing(box, advance, inkX) {
    return (box - advance) / 2 + inkX;
}

// Whole-pixel x that centres a row on its ink in a face, given the air before its first ink and after its last.
function inkCentredX(width, rowWidth, lead, trail) {
    return Math.round((width - rowWidth + trail - lead) / 2);
}

// The upright pill's gauge (track and liquid), t = 0 flat to 1 upright: the whole pill inside its inset while flat (never
// empty: its liquid's spring settles by the pixel), under the icon's shape by the flat track's gap once upright.
function uprightGaugeTop(iconSide, gap, inset, t) {
    return inset + (iconSide + gap - inset) * t;
}

function uprightGaugeHeight(height, iconSide, gap, inset, t) {
    return Math.max(0, height - uprightGaugeTop(iconSide, gap, inset, t) - inset);
}

// DMS's animation speed stretches time: k / f² and c / f keep the spring's shape, at most 1 / minStretch times faster.
var minStretch = 0.05;
function spring(name, baseDuration) {
    return stretch(springs[name] ?? springs.cell, baseDuration);
}

// The same stretch for any [stiffness, damping, mass] (the island's own spring, read from its settings).
function stretch(s, baseDuration) {
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

// A critically damped spring released at 0 toward 1, at x = ω·t (x <= 0: not yet released).
function criticalStep(x) {
    return x <= 0 ? 0 : 1 - (1 + x) * Math.exp(-x);
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

// How a bubble closing where it stands leaves: "fuse" (into the island), "fade" (reduced motion) or "shrink" (back along
// its spring). It fuses when it goes on its own, or when the island takes its own info in the same turn (its media
// face): it goes in. Any other change of the island's occupant (a face or activity closing, another
// one opening) makes it just withdraw.
function closeStyle(s) {
    if (!s.inPlace || s.occupantBefore !== s.occupantNow && !tookIn(s.occupantNow, s.source))
        return "shrink";
    return s.reduced ? "fade" : "fuse";
}

// Whether the island's occupant ("activity|plugin token") is the bubble's own source, as its activity.
function tookIn(occupant, source) {
    return !!source && String(occupant).split("|")[0] === source;
}

// A bubble merging into the island, read off one critically damped spring (the wing's exit spring: the island's
// stiffness, damping ratio 1) at wt = ω·t. Its position P eases from 0 to 1 with no jump in speed: the text fades over
// fuseTextShare of the hand-off and the wing gathers onto its shape until P reaches the hand-off, then the shape flows on
// along its way (along, 0..1, still on P, so the speed carries over), stretched along and thinned across by its own
// speed, losing fuseShrink of its size as it goes in, landing softly as the spring settles. contact: the share of its way
// where it touches the island; from there a halo spreads from that point like a wave on the same spring (wave 0..1 of its
// reach) while it pales (glow), and the island's edge swells there and back (swell, 1 at its height).
var fuseHandoff = 0.2;
// Flow speed (along per unit of wt) at which the shape is stretched the most, and that stretch.
var fuseFastest = 0.33;
var fuseStretch = 0.6;
var fuseTextShare = 0.6;
var fuseShrink = 0.8;
// Inside the island the shader hides it; it fades from this share of its way so nothing is left to draw.
var fuseBlobFade = 0.85;
// The spring and the halo count as landed this close to rest.
var fuseLanded = 0.995;
function fusionPhases(wt, contact) {
    const smooth = (a, b, x) => {
        const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
        return t * t * (3 - 2 * t);
    };
    const h = fuseHandoff;
    const flowAt = x => {
        const q = Math.max(0, (criticalStep(x) - h) / (1 - h));
        return q * q;
    };
    const P = criticalStep(wt);
    const along = flowAt(wt);
    const q = Math.max(0, (P - h) / (1 - h));
    const speed = P > h ? 2 * q / (1 - h) * Math.max(0, wt) * Math.exp(-wt) : 0;
    const stretch = fuseStretch * Math.min(1, speed / fuseFastest);
    const size = 1 - fuseShrink * along;
    // The moment of contact (the flow rises with wt).
    const touch = contact >= 0 && along >= contact ? solveRising(flowAt, contact, Math.max(0, wt)) : -1;
    const wave = touch < 0 ? 0 : criticalStep(wt - touch);
    return {
        "text": 1 - smooth(0, fuseTextShare * h, P),
        "gather": smooth(0, h, P),
        "flowing": P >= h,
        "along": along,
        "scaleAlong": size * (1 + stretch),
        "scaleCross": size / (1 + stretch),
        "blob": 1 - smooth(fuseBlobFade, 1, along),
        "wave": wave,
        "glow": touch < 0 ? 0 : 1 - wave,
        "swell": 4 * wave * (1 - wave),
        "done": P > fuseLanded && (touch < 0 || wave > fuseLanded)
    };
}

// Where along its way the fusing shape touches the island: it flows from where the wing gathered (one pill of size, gap
// away from the island's edge), the same flat or upright, whatever the open pill's length was.
function fuseContact(gap, size, reach) {
    return Math.max(0, Math.min(1, (gap + size / 2) / (size * reach)));
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

// Whether a wing's card is open: a click toggled its list, the pointer dwelt on it, or IPC holds it, on a bar that is not
// vertical. w.carded, a function, is read only past half a sheet: opening moves the spring that sets it (else a loop).
function cardOpen(w) {
    if (!w.has || w.vertical)
        return false;
    if (w.tileOpen && w.tileOpenable)
        return true;
    const asked = w.hovered && w.dwelt || w.heldOpen;
    return !!asked && (!(w.cardness >= 0.5) || !!w.carded());
}

// The bubble a card held open over IPC (island bubble card) belongs to: the machine's bubbles share one id, their kind
// tells them apart.
function heldKey(bubble) {
    return bubble.id + "|" + (bubble.kind ?? "");
}

// Whether that card's bubble (held, its heldKey) is still on the wing: the card goes with it, never stays for the one
// that takes the wing after it.
function cardHeld(held, items) {
    return held !== "" && items.some(bubble => heldKey(bubble) === held);
}

// The page of the wing's card that shows the held bubble: the face's (0) once it is let go or has left.
function heldPage(held, items) {
    return Math.max(0, items.findIndex(bubble => heldKey(bubble) === held));
}

// The WCAG ratio of Contrast.ratio, on two luminances: Contrast.ratio takes colours, and a logo's luminance is a mean over
// its pixels that no colour has.
function contrastOfLuminances(la, lb) {
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

// The mean luminance of a logo, from its RGBA pixels (a canvas's getImageData, 0..255), each weighted by its alpha so a
// silhouette on a clear ground counts only where it is drawn; -1 when nothing is drawn.
function logoLuminance(pixels) {
    let sum = 0, weight = 0;
    for (let i = 0; i + 3 < pixels.length; i += 4) {
        const a = pixels[i + 3] / 255;
        if (a === 0)
            continue;
        sum += Contrast.relativeLuminance({ "r": pixels[i] / 255, "g": pixels[i + 1] / 255, "b": pixels[i + 2] / 255 }) * a;
        weight += a;
    }
    return weight > 0 ? sum / weight : -1;
}

// The shape under an app's logo (IslandAppIcon): of two tones, the one that contrasts most with the logo's mean luminance
// (logoLuminance): a white Android silhouette sits on the dark one, a black glyph on the light one, a photo on whichever
// reads. Unknown (-1) keeps the first.
function logoShapeTone(logoLum, first, second) {
    if (logoLum < 0)
        return first;
    return contrastOfLuminances(logoLum, Contrast.relativeLuminance(second)) > contrastOfLuminances(logoLum, Contrast.relativeLuminance(first)) ? second : first;
}

// A liquid tone that reads on its pill: the first of `tones` that, laid at `alpha` over `surface`, keeps `min` contrast
// with the surface and with its own track (the tone at `trackAlpha` over it), else the one that reads best (a stock
// light theme's tertiary and error are pale; its text tone, last, is not).
var legibleMin = 3;
// Contrast.mix on plain {r, g, b}: Contrast.mix returns a Qt.rgba, which the node tests have no Qt for.
function laidOver(tone, surface, alpha) {
    return {
        "r": surface.r + (tone.r - surface.r) * alpha,
        "g": surface.g + (tone.g - surface.g) * alpha,
        "b": surface.b + (tone.b - surface.b) * alpha
    };
}
function legible(tones, surface, alpha, trackAlpha, min) {
    let best = tones[0], bestRatio = -1;
    for (const tone of tones) {
        const liquid = laidOver(tone, surface, alpha);
        const worst = Math.min(Contrast.ratio(liquid, surface), Contrast.ratio(liquid, laidOver(tone, surface, trackAlpha)));
        if (worst >= min)
            return tone;
        if (worst > bestRatio) {
            best = tone;
            bestRatio = worst;
        }
    }
    return best;
}
