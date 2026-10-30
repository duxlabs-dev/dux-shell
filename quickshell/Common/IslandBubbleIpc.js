.pragma library

// A bubble's name, as the island's status lists it and its bubble IPC takes it: its own id (a plugin's or script's token,
// "notification:<id>", "media"), so two bubbles of one kind never share a name.
function bubbleName(bubble) {
    return String(bubble.id || bubble.source);
}

// The bubble IPC on a host's body (IslandBarHost): "open" brings the bubble named which into the island, "dismiss" puts
// it away, as a click and a right click do.
function ipcBubble(body, action, which, screenName) {
    if (!body?.bringBubble)
        return "DANK_ISLAND_UNAVAILABLE";
    const bubble = bubbleNamed(body.bubbleSides, which);
    if (!bubble)
        return `DANK_ISLAND_BUBBLE_UNKNOWN: ${which}`;
    if (action === "open")
        body.bringBubble(bubble);
    else if (action === "dismiss")
        body.dismissBubble(bubble);
    else
        return `DANK_ISLAND_BUBBLE_ACTION_UNKNOWN: ${action}`;
    return `DANK_ISLAND_BUBBLE_${action.toUpperCase()}: ${which}\t${screenName}`;
}

// The bubble beside the island of that name ("machine", or an app bubble's bubbleName), or null.
function bubbleNamed(sides, name) {
    if (name === "machine")
        return sides?.machine ?? null;
    return (sides?.apps ?? []).find(bubble => bubbleName(bubble) === name) ?? null;
}
