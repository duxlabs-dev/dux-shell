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

// Absolute playback time lets seeks rewind a line and keeps pauses out of its travel time.
function scrollState(motion, at, limit) {
    if (!motion || !(limit > 0))
        return { offset: 0, wait: Infinity };
    if (!(motion.to > motion.from))
        return { offset: Math.max(0, Math.min(limit, motion.to)), wait: Infinity };
    const span = motion.end - motion.start;
    const timed = Number.isFinite(span) && span > 0;
    const hold = timed ? Math.min(motion.hold, span * 0.4) : motion.hold;
    const travel = timed ? span - hold : (motion.to - motion.from) / motion.speed;
    const progress = Math.max(0, Math.min(1, (at - motion.start - hold) / travel));
    const offset = Math.max(0, Math.min(limit, motion.from + (motion.to - motion.from) * progress));
    if (progress >= 1 || offset >= limit || motion.to <= 0)
        return { offset, wait: Infinity };
    const firstMove = motion.start + hold + travel * Math.max(0, -motion.from) / (motion.to - motion.from);
    return { offset, wait: Math.max(0, firstMove - at) };
}
