.pragma library

// One timestamp ring shared by every series; each series is a value ring aligned to it, NaN where a sample lacked it.

function create(capacity) {
    return {
        capacity: capacity,
        times: new Float64Array(capacity),
        head: -1,
        count: 0,
        series: {}
    };
}

function key(deviceKey, value) {
    return deviceKey + "/" + value;
}

function deviceOf(seriesKey) {
    return seriesKey.slice(0, seriesKey.lastIndexOf("/"));
}

function finite(v) {
    return typeof v === "number" && isFinite(v);
}

function record(store, time, pairs) {
    if (!pairs.some(p => finite(p[1])))
        return false;
    // A wall clock that jumped back would leave every new sample before the old ones.
    if (store.count > 0 && time < store.times[store.head]) {
        store.head = -1;
        store.count = 0;
    }
    const slot = (store.head + 1) % store.capacity;
    store.head = slot;
    store.times[slot] = time;
    if (store.count < store.capacity)
        store.count++;
    for (const k in store.series)
        store.series[k].values[slot] = NaN;
    for (const pair of pairs) {
        if (!finite(pair[1]))
            continue;
        let s = store.series[pair[0]];
        if (!s) {
            s = {
                values: new Float32Array(store.capacity).fill(NaN),
                newest: 0
            };
            store.series[pair[0]] = s;
        }
        s.values[slot] = pair[1];
        s.newest = time;
    }
    return true;
}

function dropDevices(store, prefix, liveDeviceKeys) {
    let changed = false;
    for (const k in store.series) {
        const device = deviceOf(k);
        if (device.startsWith(prefix + ":") && liveDeviceKeys.indexOf(device) === -1) {
            delete store.series[k];
            changed = true;
        }
    }
    return changed;
}

function prune(store, cutoffTime) {
    let changed = false;
    for (const k in store.series) {
        if (store.series[k].newest < cutoffTime) {
            delete store.series[k];
            changed = true;
        }
    }
    return changed;
}

// Oldest-first bucket averages over the rangeMs before now; NaN marks a gap.
function range(store, seriesKey, rangeMs, buckets, minGapMs, now) {
    const s = store.series[seriesKey];
    if (!s || store.count === 0)
        return [];
    const n = Math.max(1, Math.round(buckets));
    const w = rangeMs / n;
    const gap = Math.max(2 * w, minGapMs);
    // Anchored half a bucket past the newest entry so a sample's timing jitter doesn't move it into a neighbor bucket.
    const newest = store.times[store.head];
    const end = now - newest > gap ? now : newest + w / 2;
    const start = end - rangeMs;
    const sums = new Float64Array(n);
    const counts = new Int32Array(n);
    const firstT = new Float64Array(n);
    const lastT = new Float64Array(n);
    let beforeT = NaN;
    let beforeV = NaN;
    let found = false;
    for (let i = 0; i < store.count; i++) {
        const idx = (store.head - i + store.capacity) % store.capacity;
        const t = store.times[idx];
        const v = s.values[idx];
        if (t < start) {
            if (t < start - gap)
                break;
            if (isFinite(v)) {
                beforeT = t;
                beforeV = v;
                break;
            }
            continue;
        }
        if (!isFinite(v))
            continue;
        const b = Math.min(n - 1, Math.floor((t - start) / w));
        if (counts[b] === 0)
            lastT[b] = t;
        firstT[b] = t;
        sums[b] += v;
        counts[b]++;
        found = true;
    }
    if (!found)
        return [];
    const nextT = new Float64Array(n);
    let next = NaN;
    for (let b = n - 1; b >= 0; b--) {
        nextT[b] = next;
        if (counts[b] > 0)
            next = firstT[b];
    }
    const out = [];
    let prevT = beforeT;
    let prevV = beforeV;
    for (let b = 0; b < n; b++) {
        if (counts[b] > 0) {
            prevV = sums[b] / counts[b];
            prevT = lastT[b];
            out.push(prevV);
        } else {
            out.push(nextT[b] - prevT <= gap ? prevV : NaN);
        }
    }
    return out;
}

// Adds each run of finite values to ctx's path; with a baseline, each run is closed down to it as a fill area.
function traceRuns(ctx, values, step, yOf, baseline) {
    const fill = baseline !== undefined;
    let first = -1;
    for (let i = 0; i <= values.length; i++) {
        if (i < values.length && finite(values[i])) {
            const x = step * i;
            if (first < 0) {
                first = i;
                if (fill)
                    ctx.moveTo(x, baseline);
            }
            if (fill || i > first)
                ctx.lineTo(x, yOf(values[i]));
            else
                ctx.moveTo(x, yOf(values[i]));
            continue;
        }
        if (first >= 0 && fill) {
            ctx.lineTo(step * (i - 1), baseline);
            ctx.closePath();
        }
        first = -1;
    }
}
