.pragma library
.import "IslandKit.js" as Kit

// The screen arbiters' hysteresis (Android's): frames a decor keeps its count before it may slow down, and the ms
// without a frame after which its vote (its last count) is forgotten.
var holdFrames = 5;
var voteForgetMs = 750;
// Periods after which the wall clock counts images skipped: a late image within half a period still counts one.
var skippedAfter = 1.5;

// The hold stops a decor near a threshold from flapping; forgetting an old vote lets a paused decor restart from its
// measured speed.
function framesHeld(refresh, speed, prev, held, idleMs) {
    const last = idleMs >= voteForgetMs ? 0 : prev;
    const k = Kit.framesBetween(refresh, speed, last);
    return last > 0 && k > last && held < holdFrames ? last : k;
}

// Skipped images round to whole periods so steps keep to the screen's grid; without a period, the elapsed time itself
// (never negative nor NaN).
function clockStep(period, elapsed) {
    if (!(period > 0))
        return elapsed > 0 ? elapsed : 0;
    return elapsed > period * skippedAfter ? Math.round(elapsed / period) * period : period;
}

// How many times a second a decor's clock ticks on any screen: the island's decors are spinners and slow motion (60 is
// enough), never the screen's full rate.
var clockHz = 60;

// How many refreshes apart a decor's clock ticks, so it ticks clockHz times a second (240 Hz: 4, 60 Hz: 1).
function clockEvery(refresh) {
    return Math.max(1, Math.round(refresh / clockHz));
}

// Math.max(1, NaN) is NaN: a refresh that is no positive number would leave the clock without a period. Past the
// fastest panel (Infinity, or a tick count beyond an int) the Timer would get a 0 or negative interval.
function clockRate(refresh) {
    return refresh > 0 ? Math.min(refresh, Kit.panelRates[Kit.panelRates.length - 1]) : Kit.fallbackHz;
}
