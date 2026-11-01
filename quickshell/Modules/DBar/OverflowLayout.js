.pragma library
.import "CenterLayout.js" as CenterLayout

function pinned(widgetId) {
    return ["spacer", "separator", "island"].includes(widgetId);
}

function placement(entry, fallback = "bar") {
    if (pinned(entry?.widgetId))
        return "bar";
    const mode = entry?.overflowMode === "section" ? fallback : (entry?.overflowMode ?? fallback);
    return mode === "auto" || mode === "always" ? mode : "bar";
}

function priority(entry) {
    const value = Number(entry?.overflowPriority);
    return Number.isFinite(value) ? value : 0;
}

function defaultPosition(name, count) {
    return name === "right" ? 0 : count;
}

function expanderIcon(edge, open) {
    switch (edge) {
    case "left":
        return open ? "keyboard_arrow_left" : "keyboard_arrow_right";
    case "right":
        return open ? "keyboard_arrow_right" : "keyboard_arrow_left";
    case "bottom":
        return open ? "keyboard_arrow_down" : "keyboard_arrow_up";
    default:
        return open ? "keyboard_arrow_up" : "keyboard_arrow_down";
    }
}

function section(entries, hidden, spacing, triggerSize, triggerIndex) {
    const sizes = [];
    const indices = [];
    const hasOverflow = hidden.some(index => entries[index]?.size > 0);
    const insertion = Math.max(0, Math.min(entries.length, triggerIndex));
    for (let index = 0; index <= entries.length; index++) {
        if (index === insertion && hasOverflow) {
            sizes.push(triggerSize);
            indices.push(-1);
        }
        if (index === entries.length)
            break;
        sizes.push(entries[index]?.size > 0 && !hidden.includes(index) ? entries[index].size : null);
        indices.push(index);
    }
    const layout = CenterLayout.resolve(sizes, 0, spacing, "geometric");
    const positions = entries.map(() => null);
    let buttonPosition = null;
    const start = -layout.totalSize / 2;
    for (let index = 0; index < indices.length; index++) {
        const position = layout.positions[index] === null ? null : layout.positions[index] - start;
        if (indices[index] === -1)
            buttonPosition = position;
        else
            positions[indices[index]] = position;
    }
    const middle = Math.floor(entries.length / 2);
    const anchor = {
        count: entries.length,
        middle: indices.indexOf(middle),
        previous: indices.indexOf(middle - 1)
    };
    return {
        sizes,
        indices,
        positions,
        buttonPosition,
        totalSize: layout.totalSize,
        anchor
    };
}

function measure(sections, hidden, options) {
    const names = ["left", "center", "right"];
    const layouts = {};
    for (const name of names) {
        layouts[name] = section(sections[name], hidden[name], options.spacing, options.triggerSize, options.positions?.[name] ?? defaultPosition(name, sections[name].length));
    }
    const min = options.start ?? 0;
    const max = options.length - (options.end ?? 0);
    const gap = options.spacing;
    const leading = layouts.left.totalSize;
    const trailing = layouts.right.totalSize;
    const center = layouts.center;
    const bounds = options.confineCenter ? {
        min: min + (leading > 0 ? leading + gap : 0),
        max: max - (trailing > 0 ? trailing + gap : 0)
    } : null;
    const centered = CenterLayout.resolve(center.sizes, options.length, gap, options.centeringMode ?? "geometric", bounds, center.anchor);
    const livePositions = centered.positions.filter(position => position !== null);
    const centerStart = livePositions.length ? Math.min(...livePositions) : 0;
    const intervals = {
        left: {
            start: min,
            end: min + leading,
            size: leading
        },
        center: {
            start: centerStart,
            end: centerStart + centered.totalSize,
            size: centered.totalSize
        },
        right: {
            start: max - trailing,
            end: max,
            size: trailing
        }
    };
    const collisions = new Set();
    const reserve = options.reserve;
    for (const name of names) {
        const interval = intervals[name];
        if (interval.size > 0 && (interval.start < min || interval.end > max || (reserve && interval.start < reserve.end && interval.end > reserve.start)))
            collisions.add(name);
    }
    const live = names.filter(name => intervals[name].size > 0);
    for (let index = 0; index < live.length; index++) {
        for (let other = index + 1; other < live.length; other++) {
            const a = live[index];
            const b = live[other];
            if (intervals[a].end + gap > intervals[b].start) {
                collisions.add(a);
                collisions.add(b);
            }
        }
    }
    return {
        fits: collisions.size === 0,
        collisions: [...collisions],
        layouts,
        intervals
    };
}

const names = ["left", "center", "right"];

function minimumOf(entry) {
    return typeof entry.min === "number" ? Math.min(entry.min, entry.size) : entry.size;
}

function preferredSizes(sections) {
    const sizes = {};
    for (const name of names)
        sizes[name] = sections[name].map(entry => entry.size);
    return sizes;
}

function sized(sections, sizes) {
    const result = {};
    for (const name of names)
        result[name] = sections[name].map((entry, index) => Object.assign({}, entry, {
                size: sizes[name][index]
            }));
    return result;
}

function flexibleEntries(sections, hidden, scope) {
    const entries = [];
    for (const name of scope) {
        for (let index = 0; index < sections[name].length; index++) {
            const entry = sections[name][index];
            if (entry.size > 0 && minimumOf(entry) < entry.size && !hidden[name].includes(index))
                entries.push({
                    name,
                    index
                });
        }
    }
    return entries;
}

// Flexible widgets give up width down to their minimum before anything leaves the bar; the colliding sections shrink first.
function shrinkToFit(sections, hidden, options) {
    const preferred = preferredSizes(sections);
    let measured = measure(sections, hidden, options);
    if (measured.fits)
        return {
            sizes: preferred,
            measured
        };
    let floor = null;
    for (const scope of [measured.collisions, names]) {
        const candidates = flexibleEntries(sections, hidden, scope);
        if (!candidates.length)
            continue;
        const at = t => {
            const sizes = preferredSizes(sections);
            for (const {
                name,
                index
            } of candidates) {
                const entry = sections[name][index];
                const minimum = minimumOf(entry);
                sizes[name][index] = Math.floor(minimum + (entry.size - minimum) * t);
            }
            return {
                sizes,
                measured: measure(sized(sections, sizes), hidden, options)
            };
        };
        floor = at(0);
        if (!floor.measured.fits)
            continue;
        let low = 0;
        let high = 1;
        let best = floor;
        for (let step = 0; step < 12; step++) {
            const mid = (low + high) / 2;
            const trial = at(mid);
            if (trial.measured.fits) {
                best = trial;
                low = mid;
            } else {
                high = mid;
            }
        }
        return best;
    }
    return floor ?? {
        sizes: preferred,
        measured
    };
}

function resolve(sections, options, previous = {}) {
    const hidden = {};
    for (const name of names) {
        hidden[name] = [];
        for (let index = 0; index < sections[name].length; index++) {
            const entry = sections[name][index];
            if (entry.size > 0 && entry.mode === "always")
                hidden[name].push(index);
        }
    }

    let fit = shrinkToFit(sections, hidden, options);
    while (!fit.measured.fits) {
        const measured = fit.measured;
        // The center anchors the bar, so the sides yield first; between them the longer one gives up a widget.
        const colliding = measured.collisions.slice().sort((a, b) => (a === "center") - (b === "center") || measured.intervals[b].size - measured.intervals[a].size);
        // The lowest priority yields first; ties keep the section and proximity order.
        let candidate = null;
        for (const name of colliding) {
            const position = options.positions?.[name] ?? defaultPosition(name, sections[name].length);
            const eligible = [];
            for (let index = 0; index < sections[name].length; index++) {
                const entry = sections[name][index];
                if (entry.size > 0 && entry.mode === "auto" && !hidden[name].includes(index))
                    eligible.push(index);
            }
            eligible.sort((a, b) => Math.abs(a + 0.5 - position) - Math.abs(b + 0.5 - position));
            for (const index of eligible) {
                const rank = sections[name][index].priority ?? 0;
                if (!candidate || rank < candidate.rank)
                    candidate = {
                        name,
                        index,
                        rank
                    };
            }
        }
        if (!candidate)
            break;
        hidden[candidate.name].push(candidate.index);
        fit = shrinkToFit(sections, hidden, options);
    }

    const fresh = {};
    for (const name of names)
        fresh[name] = hidden[name].slice();
    const freshFits = fit.measured.fits;

    // Hysteresis: a restored widget must also fit the margin at its minimum, or it would bounce in and out at the boundary.
    const restoring = [];
    for (const name of names) {
        for (const index of previous[name] ?? []) {
            if (sections[name][index]?.size > 0 && sections[name][index].mode === "auto" && !hidden[name].includes(index)) {
                hidden[name].push(index);
                restoring.push({
                    name,
                    index
                });
            }
        }
    }
    restoring.sort((a, b) => (sections[b.name][b.index].priority ?? 0) - (sections[a.name][a.index].priority ?? 0));
    for (const {
        name,
        index
    } of restoring) {
        const trial = {};
        for (const key of names)
            trial[key] = hidden[key].filter(value => key !== name || value !== index);
        const floor = minimumOf(sections[name][index]) + (options.restoreMargin ?? 0);
        const padded = Object.assign({}, sections, {
            [name]: sections[name].map((entry, entryIndex) => entryIndex === index ? Object.assign({}, entry, {
                    size: floor,
                    min: floor
                }) : entry)
        });
        if (shrinkToFit(padded, trial, options).measured.fits)
            hidden[name] = trial[name];
    }
    const result = freshFits && !shrinkToFit(sections, hidden, options).measured.fits ? fresh : hidden;
    for (const name of names)
        result[name].sort((a, b) => a - b);
    fit = shrinkToFit(sections, result, options);
    return Object.assign({
        hidden: result,
        sizes: fit.sizes
    }, fit.measured);
}
