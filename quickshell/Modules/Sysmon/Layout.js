.pragma library

function fitScale(naturalW, naturalH, box, floor) {
    const s = Math.min(1, box.w / Math.max(1, naturalW), box.h / Math.max(1, naturalH));
    return Math.max(floor, s);
}

function measure(box, frame, bodyW, bodyH, beside, extra) {
    const procH = frame.processesH || 0;
    const w = beside ? bodyW + frame.gap + frame.processesW : Math.max(bodyW, procH > 0 ? frame.processesW : 0);
    const h = frame.headerH + (beside ? Math.max(bodyH, procH) : bodyH + (procH > 0 ? frame.gap + procH : 0));
    const out = {
        "beside": beside,
        "bodyW": bodyW,
        "bodyH": bodyH,
        "w": w,
        "h": h,
        "scale": Math.min(1, box.w / Math.max(1, w), box.h / Math.max(1, h))
    };
    Object.keys(extra || {}).forEach(k => out[k] = extra[k]);
    return out;
}

// The least scaled candidate. Of those within 0.02 of it the lower key wins, or the earliest without a key.
function choose(candidates, key) {
    let top = -Infinity;
    for (const c of candidates)
        top = Math.max(top, c.scale);
    let best = null;
    for (const c of candidates) {
        if (c.scale >= top - 0.02 && (!best || (key && key(c) < key(best))))
            best = c;
    }
    return best;
}

// Every column count, processes below or beside; ties skip a lone last tile, then go to squarer tiles. opts: frame, tileW, tileH.
function tilePlan(count, box, opts) {
    const n = Math.max(1, count);
    const procH = opts.processesH || 0;
    const candidates = [];
    for (const beside of procH > 0 ? [false, true] : [false]) {
        for (let c = 1; c <= n; c++) {
            const rows = Math.ceil(n / c);
            candidates.push(measure(box, opts, c * opts.tileW + (c - 1) * opts.gap, rows * opts.tileH + (rows - 1) * opts.gap, beside, {
                "cols": c,
                "rows": rows
            }));
        }
    }
    return choose(candidates, p => {
        const tileBoxW = (box.w - (p.beside ? opts.processesW + opts.gap : 0)) / p.cols;
        const tileBoxH = (box.h - opts.headerH - (p.beside ? 0 : procH)) / p.rows;
        const lone = n > 3 && p.cols > 1 && n % p.cols === 1;
        return (lone ? 100 : 0) + Math.abs(Math.log(Math.max(1, tileBoxW) / Math.max(1, tileBoxH)));
    });
}
