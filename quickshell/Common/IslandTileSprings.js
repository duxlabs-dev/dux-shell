.pragma library
.import "IslandLiquidSplit.js" as Split

// The jelly and pivot tiles' springs, one frame: each sim s = { x, v, t, next, at } heads for t, which becomes next once
// the clock (s) passes at; springs[name] starts [stiffness, damping ratio], mass 1. The frame is capped at Split.maxFrame
// (as the wing's), so a stalled frame never jumps, and cut into Split.subStep slices. Writes the sims in place, allocates
// nothing; returns the clock.
function stepDelayed(sims, springs, names, clock, frame) {
    let left = Math.min(Split.maxFrame, frame);
    while (left > 0) {
        const d = Math.min(Split.subStep, left);
        clock += d;
        left -= d;
        for (let i = 0; i < names.length; i++) {
            const s = sims[names[i]], c = springs[names[i]];
            if (clock >= s.at)
                s.t = s.next;
            s.v += (-c[0] * (s.x - s.t) - 2 * c[1] * Math.sqrt(c[0]) * s.v) * d;
            s.x += s.v * d;
        }
    }
    return clock;
}

// Whether a sim rests on its last target (within settleEps), then snapped onto it.
var settleEps = 1e-3;
function settled(s) {
    if (s.t !== s.next || Math.abs(s.x - s.t) > settleEps || Math.abs(s.v) > settleEps)
        return false;
    s.x = s.t;
    s.v = 0;
    return true;
}

// Their liquid's slosh: pushed by the tile's motion up to sloshMax, it rings down by sloshDecay a second; its wave's phase
// runs at sloshWave rad/s.
var sloshDecay = 2.6;
var sloshMax = 5;
var sloshWave = 11;
// The tile's speed (its springs' units a second) to slosh.
var sloshGain = 2.2;
// Below this the slosh has rung down: it stops, and so does the tile's clock.
var sloshRest = 0.05;
function slosh(last, dt, push) {
    return Math.max(last * Math.exp(-dt * sloshDecay), Math.min(sloshMax, push));
}
