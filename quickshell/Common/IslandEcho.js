.pragma library

// Never the same info twice: an app's notification that only says what a bubble says (the battery, the one kind a bubble
// of this stack says) is told apart by its app and its words.
// [kind, the apps that say it, its words (read with the app's name)]; the first that matches wins.
const kinds = [
    ["battery", /^dms$|upower|power|batter/i, /batter/i]
];

// The kind of info a notification only repeats, "" when it says something of its own: its app, then its summary and body.
function kind(app, summary, body) {
    const a = String(app ?? "");
    const words = a + " " + String(summary ?? "") + " " + String(body ?? "");
    const hit = kinds.find(k => k[1].test(a) && k[2].test(words));
    return hit ? hit[0] : "";
}

// What each bubble (or island activity, by its id as a machine kind) says.
const said = {
    "charging": "battery"
};

// Whether an app's notification of this echo kind may take the island: never while the island or a bubble already says
// it (held: those kinds). Alerts always may.
function adoptable(kind, critical, held) {
    if (critical || !kind)
        return true;
    return (held ?? []).indexOf(kind) === -1;
}

function bubbleKind(face) {
    if (!face)
        return "";
    return said[face.source === "system" ? face.kind : face.source] ?? "";
}
