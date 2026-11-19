.pragma library

function waveActive(level, charging, wavy) {
    return !!wavy && !!charging && level > 10 && level < 95;
}

function waveCount(radius, wavelength) {
    return Math.max(1, Math.round(2 * Math.PI * radius / wavelength));
}

function linePoints(x0, x1, cy, amplitude, wavelength, phase) {
    // A zero-length segment would draw no round cap, so a flat line keeps a sliver of length.
    if (!(amplitude > 0) || x1 <= x0)
        return [{ x: x0, y: cy }, { x: Math.max(x0 + 0.01, x1), y: cy }];
    const point = x => ({ x: x, y: cy + amplitude * Math.sin(x / wavelength * 2 * Math.PI - phase) });
    const points = [];
    for (let x = x0; x < x1; x += 2)
        points.push(point(x));
    points.push(point(x1));
    return points;
}

// Angles use Qt's convention: 0 is 3 o'clock, positive is clockwise.
function arcPoints(cx, cy, r, startDeg, spanDeg, amplitude, waveCount, phase, taper) {
    const length = Math.abs(spanDeg) / 180 * Math.PI * r;
    const steps = Math.max(2, Math.round(length / 0.75));
    const points = [];
    for (let i = 0; i <= steps; i++) {
        const fraction = i / steps;
        const along = length * fraction;
        const ease = taper > 0 ? Math.min(1, along / taper, (length - along) / taper) : 1;
        const distance = r + amplitude * ease * Math.sin(fraction * spanDeg / 360 * waveCount * 2 * Math.PI - phase);
        const angle = (startDeg + spanDeg * fraction) * Math.PI / 180;
        points.push({ x: cx + distance * Math.cos(angle), y: cy + distance * Math.sin(angle) });
    }
    return points;
}

// Positions along the bar's main axis; a segment is drawn only when from < to. A negative level is unknown (no fill).
function barLayout(level, width, stroke, limit, gap) {
    const half = stroke / 2;
    const unknown = level < 0;
    const clamped = Math.max(0, Math.min(100, level));
    const limited = limit > 0 && limit < 100;
    const limitX = limited ? width * limit / 100 : 0;
    const fillEnd = Math.max(half, Math.min(Math.max(half, width * clamped / 100), limited ? limitX - half - gap : width - half));
    const trackFrom = unknown ? half : fillEnd + stroke + gap;
    const last = width - half;
    return {
        hasFill: !unknown,
        fillFrom: half,
        fillEnd: fillEnd,
        trackFrom: trackFrom,
        trackTo: limited ? limitX - half - gap : last,
        dimFrom: limited ? limitX + half + gap : last,
        dimTo: last,
        limited: limited,
        limitX: limitX,
        stopX: last,
        showStop: limited || trackFrom < last
    };
}

// Degrees measured from the arc's start. A full circle leaves a gap before its start so the track does not touch the fill.
function ringLayout(level, spanDeg, radius, limit, gapPx) {
    const gap = gapPx / radius * 180 / Math.PI;
    const unknown = level < 0;
    const clamped = Math.max(0, Math.min(100, level));
    const limited = limit > 0 && limit < 100;
    const limitAt = limited ? spanDeg * limit / 100 : 0;
    const fillSpan = Math.max(0, Math.min(clamped / 100 * spanDeg, limited ? limitAt - gap : spanDeg));
    const tail = spanDeg >= 360 ? spanDeg - gap : spanDeg;
    const trackFrom = unknown ? 0 : fillSpan + gap;
    return {
        hasFill: !unknown && clamped > 0,
        fillSpan: fillSpan,
        trackFrom: trackFrom,
        trackTo: limited ? limitAt - gap : tail,
        dimFrom: limited ? limitAt + gap : tail,
        dimTo: tail,
        limited: limited,
        limitAt: limitAt
    };
}
