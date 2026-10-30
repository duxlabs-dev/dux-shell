.pragma library

const kinds = ["alert", "live", "glance"];
// Arrival tiers and their lifetimes, the one place for them (B4; var: IslandArrival.js and the island read them): in the
// island the info is big (its swell, its card), then compact; a bubble lives the total. A lasting state is big as long as
// a notification, then stays as long as it lasts.
var tiers = {
    "brief": 0,
    "normal": 1,
    "important": 2
};
const bigMsByTier = [400, 1400, 2000];
const compactMsByTier = [1600, 3600, 3600];

function tierIndex(tier) {
    return Math.max(tiers.brief, Math.min(tiers.important, tier ?? tiers.normal));
}
function bigMs(tier) {
    return bigMsByTier[tierIndex(tier)];
}
function compactMs(tier) {
    return compactMsByTier[tierIndex(tier)];
}
function lifetimeMs(tier) {
    return bigMs(tier) + compactMs(tier);
}

// Shared by every bubble and island face: a brief info, one with an Undo (its countdown too), a notification or glance,
// an important one (a call, a code).
const briefTimeoutMs = lifetimeMs(tiers.brief);
// An Undo is big as long as a notification but shorter compact (4 s in all), so it gets its own compact time.
const undoCompactMs = 2600;
const undoTimeoutMs = bigMs(tiers.normal) + undoCompactMs;
const glanceTimeoutMs = lifetimeMs(tiers.normal);
const importantTimeoutMs = lifetimeMs(tiers.important);

// One occupant per island; a newcomer needs a strictly higher rank, so equal ranks keep the oldest.
// A notification steps in front of a live activity, which comes back once it is gone.
const ranks = {
    "home": 0,
    "glance": 1,
    "live": 2,
    "notification": 3,
    "system": 4,
    "sheet": 5,
    "alert": 6,
    "critical": 7
};

function kindRank(kind) {
    return ranks[kinds.indexOf(kind) === -1 ? "live" : kind];
}

function occupantRank(occupant) {
    if (!occupant)
        return ranks.home;
    if (occupant.activity === "plugin")
        return kindRank(occupant.kind);
    if (occupant.activity === "notification")
        return occupant.critical ? ranks.critical : ranks.notification;
    if (occupant.system)
        return ranks.system;
    return occupant.expanded ? ranks.sheet : ranks.home;
}

function preempts(kind, occupant) {
    return kindRank(kind) > occupantRank(occupant);
}

// Do not disturb (a screen share turns it on) holds every request, alerts too, but those letThrough(request) passes.
function nextRequest(requests, island, quiet, letThrough) {
    let best = null;
    for (const request of requests || []) {
        if ((request.hosts || []).indexOf(island) === -1 || (quiet && !(letThrough && letThrough(request))))
            continue;
        if (!best || kindRank(request.kind) > kindRank(best.kind) || (kindRank(request.kind) === kindRank(best.kind) && request.seq < best.seq))
            best = request;
    }
    return best;
}

function heldOutcome(alive, active, locked) {
    if (!alive)
        return "end";
    return active && !locked ? "shown" : "interrupted";
}

function takesIsland(next, occupant, held, active) {
    if (!next || (next.token === held && active))
        return false;
    if (!preempts(next.kind, occupant))
        return false;
    // An activity pushed aside by the user's own sheet, or by what they brought in from a bubble, waits for it to close.
    if (occupant.held)
        return next.state === "waiting";
    return next.state === "waiting" || !occupant.expanded || active;
}

// A transient face holds a hidden bar out and the free island awake; a plugin activity with no timeout to end it does
// so only while arriving, then hides with the bar.
function holdsHost(transient, pluginActive, timeoutMs, arriving) {
    return transient && !(pluginActive && timeoutMs <= 0 && !arriving);
}

// A plugin activity counts down only while it holds the island, unhovered and with its sheet shut.
function countdownRuns(active, suspended, timeoutMs) {
    return active && !suspended && timeoutMs > 0;
}

// Bubbles: what loses the island waits beside it, the machine on the leading side, apps on the trailing one.
const levelKinds = ["volume", "brightness", "mic"];

function bubbleSide(bubble) {
    return bubble?.source === "system" ? "machine" : "apps";
}

function bubbleRank(bubble) {
    switch (bubble.source) {
    case "plugin":
        return kindRank(bubble.kind);
    case "notification":
        return bubble.critical ? ranks.critical : ranks.notification;
    }
    return ranks.home;
}

// The leading side keeps the newest machine change, the rest waiting behind it; the trailing side shows the most important app, then the newest.
function bubbleSides(bubbles, quiet, letThrough) {
    const machine = (bubbles || []).filter(b => bubbleSide(b) === "machine").sort((a, b) => b.seq - a.seq);
    // Do not disturb keeps app bubbles to a critical popup the service lets through, the call the user is in, and what the
    // user lets through as for the island (letThrough: a plugin's alert, a one-time code), never shown on a shared screen
    // otherwise.
    const quietShows = b => (b.source === "notification" && b.critical === true) || b.source === "call" || (!!letThrough && letThrough(b));
    const apps = (bubbles || []).filter(b => bubbleSide(b) === "apps" && (!quiet || quietShows(b))).sort((a, b) => bubbleRank(b) - bubbleRank(a) || b.seq - a.seq);
    return {
        "machine": machine.length > 0 ? machine[0] : null,
        "machines": machine,
        "apps": apps
    };
}

// "Always in a bubble" sends level changes beside an idle island instead of into it.
function levelInBubble(kind, always) {
    return always === true && levelKinds.indexOf(kind) !== -1;
}

// Brief info (and an Undo) lives in the island unless the user wants it in a bubble; lasting states and alerts stay.
// Battery: fully charged, unplugged and low are brief; plugging in is normal, critical important.
const briefKinds = ["capslock", "powerprofile", "idleinhibitor", "charged", "unplugged", "battery", "network", "dnd", "output", "reopen", "copy", "trash", "display", "periph"];
function briefInBubble(kind, always) {
    return always === true && briefKinds.indexOf(kind) !== -1;
}

// How long an island face stays: an Undo's lifetime when it offers one, briefMs (a brief info's by default) for a
// brief one; the island passes DMS's own OSD delay there.
// The power profile offers no Undo: it keeps DMS's OSD delay, as upstream.
const undoKinds = ["output", "trash", "display"];
// Machine faces that are notifications (5 s, frozen on hover); plugging in opens the charge face as long (M19).
const glanceKinds = ["weatheralert", "charging"];
// Machine faces that are important (a critical battery).
const importantKinds = ["batterycritical"];

function faceTimeoutMs(kind, briefMs = briefTimeoutMs) {
    if (importantKinds.indexOf(kind) !== -1)
        return importantTimeoutMs;
    if (glanceKinds.indexOf(kind) !== -1)
        return glanceTimeoutMs;
    return undoKinds.indexOf(kind) !== -1 ? undoTimeoutMs : briefMs;
}

// How a face arrives in the island: brief (a brief info, a level), normal (an Undo, a lasting state) or important.
function faceTier(kind) {
    if (importantKinds.indexOf(kind) !== -1)
        return tiers.important;
    if (undoKinds.indexOf(kind) !== -1)
        return tiers.normal;
    return briefKinds.indexOf(kind) !== -1 || levelKinds.indexOf(kind) !== -1 ? tiers.brief : tiers.normal;
}

// The face a launcher, an alert or another face pushed out takes the island back once it is idle, if its info lives on.
function faceToReturn(displaced, activity, expanded, alive) {
    return displaced && alive && !expanded && (activity === "home" || activity === "media") ? displaced : "";
}

function showSignal(state) {
    return state === "waiting" ? "shown" : state === "interrupted" ? "resumed" : "";
}

// An activity on every screen stays shown while any island shows it, and is interrupted once the last one lets go.
function shownChange(entry, island, showing) {
    const shownOn = (entry.shownOn || []).filter(host => host !== island);
    if (showing) {
        shownOn.push(island);
        return {
            "shownOn": shownOn,
            "state": "shown",
            "signal": showSignal(entry.state)
        };
    }
    const pushedAside = shownOn.length === 0 && entry.state === "shown";
    return {
        "shownOn": shownOn,
        "state": pushedAside ? "interrupted" : entry.state,
        "signal": pushedAside ? "interrupted" : ""
    };
}

// The live entry, or the one just ended while its faces fade out (the service forgets it at once).
function shownEntry(live, last, shown) {
    return live ?? (shown ? last : null);
}

// A request's own timeout (ms) is kept within these; without one, only a glance times out (glanceTimeoutMs).
const minTimeoutMs = 1000;
const maxTimeoutMs = 600000;
// An output's name (DP-1, HDMI-A-1) is far shorter: a longer one, which may come over IPC, is cut and matches no screen.
const maxScreenName = 64;

function normalizeOptions(options) {
    const o = options && typeof options === "object" ? options : {};
    const kind = kinds.indexOf(o.kind) === -1 ? "live" : o.kind;
    const timeout = o.timeoutMs;
    const glance = kind === "glance";
    return {
        "kind": kind,
        "expanded": typeof o.expanded === "boolean" ? o.expanded : kind === "alert",
        "timeoutMs": typeof timeout === "number" && isFinite(timeout) && timeout > 0 ? Math.max(minTimeoutMs, Math.min(maxTimeoutMs, Math.round(timeout))) : (glance ? glanceTimeoutMs : 0),
        "screen": typeof o.screen === "string" ? o.screen.slice(0, maxScreenName) : "",
        "showInFullscreen": o.showInFullscreen === true,
        "notifyApp": typeof o.notifyApp === "string" ? o.notifyApp.trim() : "",
        "data": o.data && typeof o.data === "object" ? o.data : {}
    };
}

// Whether a notification from appName belongs to one of these activities, which the island already shows. A request
// matches the app its plugin declared (notifyApp) and only that; without one, its id or its name (nameOf(pluginId)).
function holdsApp(requests, appName, nameOf) {
    const app = String(appName ?? "").trim().toLowerCase();
    if (!app)
        return false;
    return (requests || []).some(r => {
        const declared = String(r.notifyApp ?? "").trim().toLowerCase();
        if (declared)
            return declared === app;
        const id = String(r.pluginId ?? "");
        return id.replace(/^script:/, "").toLowerCase() === app || String((nameOf && nameOf(id)) ?? "").toLowerCase() === app;
    });
}

// held: holdsApp for the notification's app. A call or a critical one still shows, the app's activity waiting in its
// bubble meanwhile; the rest stays in the list only.
function notificationShows(held, critical) {
    return critical === true || !held;
}

// Each bubble wing rests at its own widest face, kept when the last item leaves so it melts back from its own width.
function wingRest(rest, need) {
    return need > 0 ? need : rest;
}

// How far a wing reaches out of the island for input: its gap, then its card while hovered open, else its rest.
function wingReach(has, hoverOpen, cardWant, rest, gap) {
    if (!has)
        return 0;
    return gap + (hoverOpen ? Math.max(cardWant, rest) : rest);
}
