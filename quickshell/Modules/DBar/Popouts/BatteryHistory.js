function normalize(rows, start, end) {
    if (!Array.isArray(rows))
        return [];
    const samples = rows.filter(row => Array.isArray(row) && row.length >= 3 && row.every(value => typeof value === "number" && isFinite(value)) && row[0] >= start && row[0] <= end && row[1] >= 0 && row[1] <= 100);
    samples.sort((a, b) => a[0] - b[0]);
    return samples.filter((sample, index) => index === samples.length - 1 || sample[0] !== samples[index + 1][0]);
}

function windowSamples(rows, start, end, current) {
    const samples = normalize(rows, 0, end);
    const visible = samples.filter(sample => sample[0] >= start);
    const previous = samples.filter(sample => sample[0] < start).pop();
    if (previous && visible[0]?.[0] !== start)
        visible.unshift([start, previous[1], previous[2]]);
    const latest = normalize([current], end, end)[0];
    if (!latest)
        return visible;
    if (visible[visible.length - 1]?.[0] === end)
        visible.pop();
    visible.push(latest);
    return visible;
}

function kind(sample, lowThreshold) {
    switch (sample[2]) {
    case 1:
    case 4:
    case 5:
        return "plugged";
    default:
        return sample[1] <= lowThreshold ? "low" : "normal";
    }
}

function segments(samples, lowThreshold) {
    const result = [];
    let segment = null;
    for (const sample of samples) {
        if (sample[2] === 0) {
            segment = null;
            continue;
        }
        const sampleKind = kind(sample, lowThreshold);
        if (!segment || segment.kind !== sampleKind) {
            if (segment)
                segment.samples.push(sample);
            segment = {
                kind: sampleKind,
                samples: []
            };
            result.push(segment);
        }
        segment.samples.push(sample);
    }
    return result;
}

// upowerd writes a state 0 marker every time it loads history, at boot among others
function gaps(samples) {
    const result = [];
    let last = null;
    let broken = false;
    for (const sample of samples) {
        if (sample[2] === 0) {
            broken = last !== null;
            continue;
        }
        if (broken)
            result.push([last, sample]);
        broken = false;
        last = sample;
    }
    return result;
}

function pointAt(samples, time, snap) {
    let nearest = null;
    for (const sample of samples) {
        if (sample[2] !== 0 && (!nearest || Math.abs(sample[0] - time) < Math.abs(nearest[0] - time)))
            nearest = sample;
    }
    if (!nearest)
        return null;
    if (Math.abs(nearest[0] - time) <= snap)
        return nearest;
    const next = samples.findIndex(sample => sample[0] >= time);
    if (next <= 0)
        return null;
    const before = samples[next - 1];
    const after = samples[next];
    if (before[2] === 0 || after[2] === 0)
        return [time, 0, 0];
    return [time, before[1] + (after[1] - before[1]) * (time - before[0]) / (after[0] - before[0]), before[2]];
}

function ticks(start, end, hours) {
    const tick = new Date(start * 1000);
    tick.setHours(tick.getHours() - tick.getHours() % hours, 0, 0, 0);
    const result = [];
    for (; tick.getTime() <= end * 1000; tick.setHours(tick.getHours() + hours)) {
        if (tick.getTime() >= start * 1000)
            result.push(tick.getTime() / 1000);
    }
    return result;
}
