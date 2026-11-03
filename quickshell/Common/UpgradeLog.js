.pragma library

// Line shapes shared by dnf, pacman, apt, zypper, xbps and flatpak upgrade output.
var COUNTER_RE = /^(\s*[\[(]\s*\d+\/\d+\s*[\])])(.*)$/;
var STATS_RE = /\s+\d+%\s*\|.*$/;
var SUMMARY_RE = /^(\s*[A-Z][A-Za-z ]*:)(\s+\d.*)$/;
var SECTION_RE = /^(\s*[A-Z][A-Za-z ,]*:?|::\s.*)$/;
var TABLE_ROW_RE = /^(\s+)(\S+)(\s{2,}\S.*)$/;

function segments(line) {
    const text = String(line ?? "");
    if (/^== .+ ==$/.test(text))
        return [{ text, kind: "header" }];
    if (/^\s*(error|e|fatal|problem)\s*:/i.test(text))
        return [{ text, kind: "error" }];
    if (/^\s*(warning|w)\s*:/i.test(text) || text === "Upgrade stopped.")
        return [{ text, kind: "warning" }];
    if (/^\s*(complete!|upgrade complete\.|nothing to do\.?)\s*$/i.test(text))
        return [{ text, kind: "success" }];

    const counter = COUNTER_RE.exec(text);
    if (counter) {
        const rest = counter[2];
        const stats = STATS_RE.exec(rest);
        const out = [{ text: counter[1], kind: "counter" }];
        if (!stats)
            return out.concat([{ text: rest, kind: "plain" }]);
        return out.concat([{ text: rest.slice(0, stats.index), kind: "plain" }, { text: stats[0], kind: "dim" }]);
    }

    const summary = SUMMARY_RE.exec(text);
    if (summary)
        return [{ text: summary[1], kind: "section" }, { text: summary[2], kind: "plain" }];
    if (SECTION_RE.test(text))
        return [{ text, kind: "section" }];

    const row = TABLE_ROW_RE.exec(text);
    if (row)
        return [{ text: row[1], kind: "plain" }, { text: row[2], kind: "name" }, { text: row[3], kind: "dim" }];

    return [{ text, kind: "plain" }];
}

// StyledText collapses runs of spaces, which breaks the column alignment package managers print.
function escape(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/^ +| {2,}/g, (run, offset) => offset === 0 ? "&nbsp;".repeat(run.length) : " " + "&nbsp;".repeat(run.length - 1));
}

// palette maps a segment kind to a color string; kinds without one inherit the Text color.
function markup(lines, palette) {
    return (lines || []).map(line => segments(line).map(seg => {
        const body = escape(seg.text);
        const color = palette[seg.kind];
        if (!color)
            return body;
        const bold = seg.kind === "header" || seg.kind === "section";
        const span = "<font color=\"" + color + "\">" + body + "</font>";
        return bold ? "<b>" + span + "</b>" : span;
    }).join("")).join("<br>");
}
