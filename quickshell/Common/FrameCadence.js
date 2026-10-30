.pragma library
.import "IslandKit.js" as Kit

// A short frame is folded into the next with its time, so a spring stays exact; the kit's slack keeps an off-vsync tick
// at 126 Hz from counting as a faster screen.
var minimumStep = 1 / (Kit.decorMaxHz * (1 + Kit.rateSlack));

// The time to step with (> 0), or minus the time now folded (<= 0); a bad frame time is dropped so the fold never runs
// backwards nor turns into NaN.
function fold(pending, frameTime) {
    if (!(frameTime >= 0 && Number.isFinite(frameTime)))
        return -pending;
    const time = pending + frameTime;
    return time >= minimumStep ? time : -time;
}
