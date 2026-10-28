function packCells(cards, order, columns, isAvailable, step = 1, gravity = false) {
    const steps = Math.round(columns / step);
    const cells = [];
    const taken = [];
    let rows = 0;

    for (let p = 0; p < order.length; p++) {
        const sourceIndex = order[p];
        const card = cards[sourceIndex];
        if (!card)
            continue;
        if (isAvailable && !isAvailable(card.id)) {
            cells[sourceIndex] = null;
            continue;
        }

        const w = Math.max(1, Math.min(steps, Math.round((card.w || 1) / step)));
        const h = Math.max(1, Math.round((card.h || 1) / step));
        const cell = positioned(card) ? settle(taken, Math.max(0, Math.min(steps - w, Math.round(card.col / step))), Math.max(0, Math.round(card.row / step)), w, h) : firstFit(taken, steps, w, h);
        taken.push(cell);
        cells[sourceIndex] = cell;
    }

    if (gravity)
        compact(taken);
    for (let i = 0; i < cells.length; i++) {
        const cell = cells[i];
        if (!cell)
            continue;
        rows = Math.max(rows, cell.y + cell.h);
        cells[i] = {
            "col": cell.x * step,
            "row": cell.y * step,
            "cols": cell.w * step,
            "rows": cell.h * step
        };
    }

    return {
        "cells": cells,
        "rows": rows * step
    };
}

// Saved positions only settle downward, so a shrink or removal above leaves a hole; gravity pulls everything up into it.
function compact(taken) {
    const ordered = taken.slice().sort((a, b) => a.y - b.y || a.x - b.x);
    for (const cell of ordered) {
        const others = taken.filter(other => other !== cell);
        while (cell.y > 0 && !overlaps(others, cell.x, cell.y - 1, cell.w, cell.h))
            cell.y--;
    }
}

function positioned(card) {
    return Number.isFinite(card.col) && Number.isFinite(card.row);
}

function overlaps(taken, x, y, w, h) {
    return taken.some(cell => x < cell.x + cell.w && cell.x < x + w && y < cell.y + cell.h && cell.y < y + h);
}

function settle(taken, x, y, w, h) {
    while (overlaps(taken, x, y, w, h))
        y++;
    return {
        "x": x,
        "y": y,
        "w": w,
        "h": h
    };
}

function firstFit(taken, steps, w, h) {
    const ceiling = taken.reduce((top, cell) => Math.max(top, cell.y + cell.h), 0);
    for (let y = 0; y < ceiling; y++) {
        for (let x = 0; x + w <= steps; x++) {
            if (!overlaps(taken, x, y, w, h))
                return {
                    "x": x,
                    "y": y,
                    "w": w,
                    "h": h
                };
        }
    }
    return {
        "x": 0,
        "y": ceiling,
        "w": w,
        "h": h
    };
}

function packCards(cards, order, columns, width, gap, rowUnit, mirror, isAvailable, step = 1, gravity = false) {
    const packed = packCells(cards, order, columns, isAvailable, step, gravity);
    const layout = {
        "slots": [],
        "rows": packed.rows,
        "totalHeight": packed.rows > 0 ? packed.rows * rowUnit + (packed.rows - 1) * gap : 0,
        "columns": columns,
        "width": width,
        "colW": (width - gap * (columns - 1)) / columns,
        "rowUnit": rowUnit,
        "gap": gap,
        "step": step,
        "mirror": mirror
    };
    layout.slots = packed.cells.map(cell => cell ? Object.assign(slotRect(layout, cell.col, cell.row, cell.cols, cell.rows), cell) : null);
    return layout;
}

function slotRect(layout, col, row, cols, rows) {
    const px = col * (layout.colW + layout.gap);
    const pw = cols * layout.colW + (cols - 1) * layout.gap;
    return {
        "x": layout.mirror ? layout.width - px - pw : px,
        "y": row * (layout.rowUnit + layout.gap),
        "w": pw,
        "h": rows * layout.rowUnit + (rows - 1) * layout.gap
    };
}

// Rows held only by shrinkable slots drop to `unit`; a slot sharing any row with a full one keeps the full height.
function shrinkRows(layout, shrinkable, unit) {
    const step = layout.step;
    const bands = Math.round(layout.rows / step);
    if (bands === 0 || !shrinkable.some(flag => flag))
        return layout;
    const span = slot => [Math.round(slot.row / step), Math.round(slot.rows / step)];
    const holders = Array.from({
        "length": bands
    }, () => []);
    layout.slots.forEach((slot, i) => {
        if (!slot)
            return;
        const [first, count] = span(slot);
        for (let b = first; b < first + count; b++)
            holders[b].push(i);
    });
    const open = holders.map(indices => indices.every(i => shrinkable[i]));
    const shrinks = layout.slots.map((slot, i) => {
        if (!slot || !shrinkable[i])
            return false;
        const [first, count] = span(slot);
        return open.slice(first, first + count).every(flag => flag);
    });
    const fullBand = step * layout.rowUnit - (1 - step) * layout.gap;
    const shortBand = step * unit - (1 - step) * layout.gap;
    const heights = holders.map(indices => indices.length > 0 && indices.every(i => shrinks[i]) ? shortBand : fullBand);
    const tops = [];
    let y = 0;
    for (const height of heights) {
        tops.push(y);
        y += height + layout.gap;
    }
    const slots = layout.slots.map(slot => {
        if (!slot)
            return slot;
        const [first, count] = span(slot);
        const h = heights.slice(first, first + count).reduce((sum, band) => sum + band, 0) + layout.gap * (count - 1);
        return Object.assign({}, slot, {
            "y": tops[first],
            "h": h
        });
    });
    return Object.assign({}, layout, {
        "slots": slots,
        "totalHeight": y - layout.gap,
        "bandTops": tops
    });
}

// Opens a full-width band of `extent` at the cut under the slot at `index`, or under the last row when there is
// none, pushing every slot below the cut down by exactly that much. The extent carries the band's own gaps, so an
// animated extent moves the rows without a step at either end. The cut sits below any taller neighbour straddling
// the slot's bottom edge.
function insertBand(layout, index, extent) {
    if (extent <= 0)
        return layout;
    const slots = layout.slots;
    const anchor = slots[index] ?? null;
    let cut = anchor ? anchor.y + anchor.h : layout.totalHeight;
    for (let moved = true; moved && anchor; ) {
        moved = false;
        for (const slot of slots) {
            if (!slot || slot.y >= cut || slot.y + slot.h <= cut)
                continue;
            cut = slot.y + slot.h;
            moved = true;
        }
    }
    const shifted = slots.map(slot => slot && slot.y >= cut ? Object.assign({}, slot, {
            "y": slot.y + extent
        }) : slot);
    const below = slots.some(slot => slot && slot.y >= cut);
    return Object.assign({}, layout, {
        "slots": shifted,
        "bandY": cut,
        "bandExtent": extent,
        "totalHeight": (below ? layout.totalHeight : cut) + extent
    });
}

function rowAt(layout, y) {
    const pitch = (layout.rowUnit + layout.gap) * layout.step;
    const tops = layout.bandTops;
    if (!tops)
        return Math.round(y / pitch) * layout.step;
    const end = layout.totalHeight + layout.gap;
    if (y >= end)
        return (tops.length + Math.round((y - end) / pitch)) * layout.step;
    const edges = tops.concat([end]);
    let band = 0;
    edges.forEach((edge, b) => {
        if (Math.abs(y - edge) <= Math.abs(y - edges[band]))
            band = b;
    });
    return band * layout.step;
}

function cellAt(layout, x, y, cols, rows) {
    const px = layout.mirror ? layout.width - x - (cols * layout.colW + (cols - 1) * layout.gap) : x;
    const col = Math.round(px / (layout.colW + layout.gap) / layout.step) * layout.step;
    return {
        "col": Math.max(0, Math.min(layout.columns - cols, col)),
        "row": Math.max(0, rowAt(layout, y))
    };
}

// With gravity, a tile dropped onto the stack it came from rises back toward the hole it left. So the drop tries
// the target row and the rows below it, packing each, and keeps the one that settles nearest the target.
function dropInto(items, cells, index, target, pack, step = 1) {
    const origin = cells[index];
    if (!origin || !target || !pack)
        return items;
    if (target.col < origin.col + origin.cols && origin.col < target.col + origin.cols && target.row < origin.row + origin.rows && origin.row < target.row + origin.rows)
        return items;
    const limit = cells.reduce((bottom, cell) => cell ? Math.max(bottom, cell.row + cell.rows) : bottom, 0) + origin.rows;
    let best = null;
    for (let row = target.row; row <= limit; row += step) {
        const trial = items.map((item, i) => i === index ? Object.assign({}, item, {
                "row": row
            }) : item);
        const landed = pack(trial)[index]?.row;
        if (landed === undefined)
            return items;
        const distance = Math.abs(landed - target.row);
        if (!best || distance < best.distance || (distance === best.distance && landed >= target.row))
            best = {
                "trial": trial,
                "distance": distance
            };
        if (landed >= target.row)
            break;
    }
    return best.trial;
}

function placedItems(items, slots) {
    return items.map((item, i) => slots[i] ? Object.assign({}, item, {
            "col": slots[i].col,
            "row": slots[i].row
        }) : item);
}

function rowLimit(cards, order, columns, rows, isAvailable) {
    return Math.max(rows, packCells(cards, order, columns, isAvailable).rows);
}

function fitWithin(cards, order, columns, limit, index, want, min, isAvailable) {
    let best = null;
    for (let w = Math.min(columns, want.w); w >= min.w; w--) {
        for (let h = want.h; h >= min.h; h--) {
            const trial = cards.slice();
            trial[index] = Object.assign({}, cards[index], {
                "w": w,
                "h": h
            });
            if (packCells(trial, order, columns, isAvailable).rows > limit)
                continue;
            const distance = want.w - w + want.h - h;
            const better = !best || distance < best.distance || (distance === best.distance && w * h > best.w * best.h);
            if (better)
                best = {
                    "w": w,
                    "h": h,
                    "distance": distance
                };
            break;
        }
    }
    return best ? {
        "w": best.w,
        "h": best.h
    } : null;
}

function fitResize(cards, order, columns, rows, index, want, min, isAvailable) {
    const limit = rowLimit(cards, order, columns, rows, isAvailable);
    return fitWithin(cards, order, columns, limit, index, want, min, isAvailable);
}

function fitNewCard(cards, columns, rows, id, want, min, isAvailable) {
    const order = cards.map((card, i) => i);
    const limit = rowLimit(cards, order, columns, rows, isAvailable);
    const trial = cards.concat([
        {
            "id": id,
            "w": want.w,
            "h": want.h
        }
    ]);
    return fitWithin(trial, order.concat([cards.length]), columns, limit, cards.length, want, min, isAvailable);
}

function neighborInDirection(rects, index, direction) {
    const from = rects[index];
    let best = -1;
    let bestScore = Infinity;
    rects.forEach((rect, i) => {
        if (i === index)
            return;
        const score = directionalScore(from, rect, direction);
        if (score >= bestScore)
            return;
        bestScore = score;
        best = i;
    });
    return best;
}

function directionalScore(from, to, direction) {
    switch (direction) {
    case "left":
        return axisScore(from.x - (to.x + to.w), crossGap(from.y, from.h, to.y, to.h));
    case "right":
        return axisScore(to.x - (from.x + from.w), crossGap(from.y, from.h, to.y, to.h));
    case "up":
        return axisScore(from.y - (to.y + to.h), crossGap(from.x, from.w, to.x, to.w));
    case "down":
        return axisScore(to.y - (from.y + from.h), crossGap(from.x, from.w, to.x, to.w));
    }
    return Infinity;
}

function axisScore(gap, cross) {
    return gap < 0 ? Infinity : gap + cross * 2;
}

function crossGap(a, aSize, b, bSize) {
    return Math.max(0, b - (a + aSize), a - (b + bSize));
}

function nearestStep(edgeFor, from, minStep, maxStep, wanted) {
    const distance = step => Math.abs(edgeFor(step) - wanted);
    let best = Math.max(minStep, Math.min(maxStep, from));
    for (const direction of [1, -1]) {
        for (let step = best + direction; step >= minStep && step <= maxStep; step += direction) {
            const gap = distance(step);
            if (gap > distance(best))
                break;
            if (gap < distance(best))
                best = step;
        }
    }
    return best;
}

function dimension(value, minimum, maximum, fallback, step = 1) {
    const min = minimum ?? 1;
    const max = Math.max(min, maximum ?? fallback ?? min);
    return Math.max(min, Math.min(max, typeof value === "number" && Number.isInteger(value / step) ? value : (fallback ?? min)));
}
