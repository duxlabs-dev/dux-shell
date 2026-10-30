.pragma library

// The gestures over an arrival in the island (wheel, touchpad, finger, click, hover), split from IslandArrival.js,
// which re-exports them: the island reads them as Arrival.*.

// `island arrival <action>`, the keyboard's way (a bound key) to what a pull, a swipe or a click does on the info arriving
// in the island: open its card, turn to the next or previous one, tidy it away; on arrival (IslandArrivalState). A
// notification's own action has none here: the keyboard reaches it in DMS's notification center.
function ipcArrival(arrival, action, tag) {
    const done = runArrival(arrival, action);
    if (done === undefined)
        return `${tag}_ARRIVAL_ACTION_UNKNOWN: ${action}`;
    return done ? `${tag}_ARRIVAL_${action.toUpperCase()}` : `${tag}_ARRIVAL_UNAVAILABLE: ${action}`;
}

// A swipe's or the keyboard's action on the arrival: whether it took, undefined for no such action.
function runArrival(arrival, action) {
    const run = {
        "open": () => arrival.open(),
        "next": () => arrival.step(1),
        "prev": () => arrival.step(-1),
        "tidy": () => arrival.tidy()
    }[action];
    return run ? run() : undefined;
}

// Wheel and touchpad: notches add up to a page; a pause forgets them; a page turned locks the wheel a moment so one
// flick turns one page.
const wheelPage = 40;
const wheelForget = 220;
const wheelLock = 260;

function wheelIdle() {
    return {
        "acc": 0,
        "at": -1e9,
        "lock": -1e9,
        "step": 0
    };
}

// One wheel event as a signed page delta: the touchpad's pixels if any, else the notches; the wheel turned up (away
// from you) goes to the next info.
function wheelDelta(pixelDelta, angleDelta) {
    const d = pixelDelta.x !== 0 || pixelDelta.y !== 0 ? pixelDelta : {
        "x": angleDelta.x / 3,
        "y": angleDelta.y / 3
    };
    return Math.abs(d.x) > Math.abs(d.y) ? d.x : d.y;
}

function wheel(state, delta, now) {
    const acc = now - state.at > wheelForget ? 0 : state.acc;
    if (now < state.lock)
        return {
            "acc": 0,
            "at": now,
            "lock": state.lock,
            "step": 0
        };
    const sum = acc + delta;
    if (Math.abs(sum) < wheelPage)
        return {
            "acc": sum,
            "at": now,
            "lock": state.lock,
            "step": 0
        };
    return {
        "acc": 0,
        "at": now,
        "lock": now + wheelLock,
        "step": Math.sign(sum)
    };
}

// A finger or a drag let go: sideways turns the page (left = next), toward the screen edge tidies everything away,
// away from it opens the full card. farEdge: the island hangs from the bottom.
const swipeSlop = 36;
// How much of the finger's way the card follows sideways.
const follow = 0.45;
// A newcomer rolling over the card bumps the island's height this fast, in compact thicknesses per second.
const nudge = 3.6;
// Where a page rolls in from, in theme spacings (the old one leaves over a shorter way).
const rollReach = 1;
const rollOutReach = 0.77;

// A click on an info in the island grows it where it is, never into a bubble beside: folded, its card opens again;
// open, it opens whole. Nothing of a burst left, the click keeps the island's own role ("").
function click(phase, count) {
    if (!(count > 0))
        return "";
    return phase === "compact" ? "reopen" : phase === "big" ? "open" : "";
}

function swipe(dx, dy, threshold, farEdge) {
    const t = threshold ?? swipeSlop;
    if (Math.abs(dx) > Math.abs(dy) * 1.5)
        return dx <= -t ? "next" : dx >= t ? "prev" : "";
    if (Math.abs(dy) > Math.abs(dx) * 1.5 && Math.abs(dy) >= t) {
        const toEdge = farEdge === true ? dy > 0 : dy < 0;
        return toEdge ? "tidy" : "open";
    }
    return "";
}

// The face that swelled on arrival swells again while hovered once folded. owner: whose the
// kept swell is, face: who holds the island now (a plugin token, else the activity).
function hoverSwell(s) {
    return !!s.hovered && !!s.owner && s.owner === s.face && !s.notification && !s.expanded && !s.vertical;
}
