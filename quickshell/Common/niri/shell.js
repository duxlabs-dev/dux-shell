.pragma library

// Pure rules of the niri shell (NiriShell.qml): the mockup's breakpoints and column sizes,
// where a section's side pane goes, and the nav list's modified counts.

// Breakpoints and column sizes of the validated mockup (a-final.html)
var maxWidth = 1440;
var wideMinWidth = 1181;
var narrowMaxWidth = 860;
var compactMaxWidth = 480;
var searchMinWidth = 220;
var menuWideWidth = 220;
var menuMediumWidth = 200;
var keysPaneWidth = 360;
var drawerColumnWidth = 560;

// Sections are untyped loader items: one may declare `sidePane`, shown in the right column instead of the desk
function paneOf(section) {
    return section && "sidePane" in section ? section.sidePane : null;
}

// Where the pane shows: "right" on a wide page, "below" or "inline" otherwise, "" when it stays hidden.
// Keybinds keeps its pane under the keyboard when the page is not wide. Workspaces draws its lanes
// in the Live card already: its pane would repeat them above when the page is not wide.
function place(sectionId, hasPane, wide) {
    if (!hasPane)
        return "";
    if (wide)
        return "right";
    if (sectionId === "workspaces")
        return "";
    return sectionId === "keybinds" ? "below" : "inline";
}

// Modified keys per section id. `custom.*` and `styles.*` belong to no section; one modified
// animation is one change, whatever how many of its fields moved.
function modifiedCounts(keys, isModified) {
    const counts = {};
    const counted = {};
    for (const key of keys) {
        if (key.startsWith("custom.") || key.startsWith("styles.") || !isModified(key))
            continue;
        const parts = key.split(".");
        const id = parts[0];
        if (id === "animations") {
            const name = parts[1] ?? key;
            if (counted[name])
                continue;
            counted[name] = true;
        }
        counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
}
