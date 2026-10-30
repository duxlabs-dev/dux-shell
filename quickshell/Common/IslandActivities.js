.pragma library

const kinds = ["alert", "live", "glance"];
// A glance without a timeout of its own lives a notification's lifetime on the island, held here alone: the
// controller's notificationTimeout is no constant but each notification's own DMS timeout (IslandNotificationSource).
const glanceTimeoutMs = 5000;

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
