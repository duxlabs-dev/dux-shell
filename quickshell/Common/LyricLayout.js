.pragma library

const FILLER = /\s|[♩♪♫♬.…·*~()\[\]\-–—]|🎵|🎶|🎼|\uD834[\uDD00-\uDDFF]/g;

function hasWords(text) {
    return String(text ?? "").replace(FILLER, "") !== "";
}

// Halving a too-wide median line gives two even pages instead of a full page and a stub;
// slack absorbs the word the greedy pager pushes over the half.
function pageWidth(widths, cap, minimum, slack) {
    const sorted = widths.filter(width => width > 0).sort((a, b) => a - b);
    if (sorted.length === 0)
        return 0;
    const mid = sorted.length >> 1;
    const median = sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
    let width = cap;
    if (median <= cap)
        width = median;
    else if (median / 2 + slack <= cap)
        width = median / 2 + slack;
    return Math.ceil(Math.max(minimum, width));
}
