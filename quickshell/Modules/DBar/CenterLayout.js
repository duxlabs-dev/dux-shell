.pragma library

function indexCenter(sizes, indices, offsets, spacing, anchor) {
    const configuredMiddle = anchor?.middle ?? Math.floor(sizes.length / 2);
    const configuredCount = anchor?.count ?? sizes.length;
    const configuredPrevious = anchor?.previous ?? (configuredMiddle - 1);
    const middle = indices.indexOf(configuredMiddle);
    if (configuredCount % 2 === 1 && middle >= 0)
        return offsets[middle] + sizes[configuredMiddle] / 2;
    const previous = indices.indexOf(configuredPrevious);
    if (configuredCount % 2 === 0 && middle >= 0 && previous >= 0)
        return (offsets[previous] + sizes[configuredPrevious] + offsets[middle]) / 2;

    const visibleMiddle = Math.floor(indices.length / 2);
    if (indices.length % 2 === 1)
        return offsets[visibleMiddle] + sizes[indices[visibleMiddle]] / 2;
    return offsets[visibleMiddle] - spacing / 2;
}

function confine(start, totalSize, bounds) {
    if (!bounds)
        return start;
    const min = bounds.min ?? -Infinity;
    const max = bounds.max ?? Infinity;
    if (max - min < totalSize)
        return (min + max - totalSize) / 2;
    return Math.min(Math.max(start, min), max - totalSize);
}

// A short bar inside the notch has no room to split.
function usableGap(gap, min, max, room) {
    if (!gap || gap.start - min < room || max - gap.end < room)
        return null;
    return gap;
}

// The extent spans the gap so the next section clears it.
function split(sizes, indices, offsets, spacing, gap) {
    const positions = sizes.map(() => null);
    const before = Math.ceil(indices.length / 2);
    const lead = offsets[before - 1] + sizes[indices[before - 1]];
    for (let i = 0; i < before; i++)
        positions[indices[i]] = gap.start - lead + offsets[i];
    let cursor = gap.end;
    for (let i = before; i < indices.length; i++) {
        positions[indices[i]] = cursor;
        cursor += sizes[indices[i]] + spacing;
    }
    const end = before < indices.length ? cursor - spacing : gap.end;
    return {
        positions,
        totalSize: end - (gap.start - lead),
        split: indices[before] ?? -1
    };
}

function resolve(sizes, length, spacing, mode, bounds, anchor, gap) {
    const indices = [];
    const offsets = [];
    const positions = sizes.map(() => null);
    let totalSize = 0;
    for (let index = 0; index < sizes.length; index++) {
        if (sizes[index] === null)
            continue;
        if (indices.length > 0)
            totalSize += spacing;
        indices.push(index);
        offsets.push(totalSize);
        totalSize += sizes[index];
    }

    if (indices.length === 0)
        return {
            positions,
            totalSize: 0
        };
    if (gap)
        return split(sizes, indices, offsets, spacing, gap);

    const centerOffset = mode === "geometric" ? totalSize / 2 : indexCenter(sizes, indices, offsets, spacing, anchor);
    const start = confine(length / 2 - centerOffset, totalSize, bounds);
    for (let i = 0; i < indices.length; i++)
        positions[indices[i]] = start + offsets[i];
    return {
        positions,
        totalSize
    };
}
