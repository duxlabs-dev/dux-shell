.pragma library
.import "GridLayout.js" as Grid

var GROUP_ID = "quickTiles";

function pageOf(widget) {
    return Number.isInteger(widget?.page) && widget.page > 0 ? widget.page : 0;
}

function withPage(widget, page) {
    if (pageOf(widget) === page)
        return widget;
    const next = Object.assign({}, widget);
    if (page > 0)
        next.page = page;
    else
        delete next.page;
    return next;
}

// Spilled cells still commit; the active slot stays alive so masking cannot cancel its pointer grab.
function pageLayout(layout, rows, activeIndex = -1) {
    if (!(rows > 0) || layout.rows <= rows)
        return layout;
    return Object.assign({}, layout, {
        "slots": layout.slots.map((slot, index) => slot && (index === activeIndex || slot.row + slot.rows <= rows) ? slot : null),
        "commitSlots": layout.slots,
        "rows": rows,
        "bandTops": layout.bandTops?.slice(0, Math.round(rows / layout.step)),
        "totalHeight": Math.max(0, Grid.bandTop(layout, Math.round(rows / layout.step)) - layout.gap)
    });
}

// `center` (in columns) centers the tile under a drag ghost.
function placedInRoom(widget, columns, col, row, room, clamp, center) {
    if (!room)
        return { "col": col, "row": row };
    const run = Grid.freeRun(room.layout, col, row);
    if (!(run.to > run.from))
        return null;
    const start = w => center === undefined ? col : Math.round((center - w / 2) / room.layout.step) * room.layout.step;
    const fit = Grid.fitInRun(run, start(widget.w), widget.w);
    const rows = room.rowLimit > 0 ? room.rowLimit - row : Infinity;
    const size = clamp(Object.assign({}, widget, { "w": fit.w }), columns, rows);
    if (size.w > run.to - run.from || size.h > rows)
        return null;
    const cell = Object.assign({}, size, Grid.fitInRun(run, start(size.w), size.w), { "row": row });
    if (room.layout.slots.some(slot => slot && cell.col < slot.col + slot.cols && slot.col < cell.col + cell.w && row < slot.row + slot.rows && slot.row < row + cell.h))
        return null;
    return cell;
}

function externalPlacement(widget, layout, x, y, bottom, rowLimit, clamp) {
    const spot = Grid.freeCellAt(layout, x, y, bottom, rowLimit, layout.step);
    if (spot) {
        const center = (layout.mirror ? layout.width - x : x) / (layout.colW + layout.gap);
        return placedInRoom(widget, layout.columns, spot.col, spot.row, { "layout": layout, "rowLimit": rowLimit }, clamp, center);
    }
    if (widget.h !== 1 || !Grid.inRows(layout, y, rowLimit))
        return null;
    const slot = layout.slots.find(slot => slot && x >= slot.x && x < slot.x + slot.w && y >= slot.y && y < slot.y + slot.h);
    if (!slot || slot.rows !== 1 || slot.cols <= 1 || slot.cols >= widget.w)
        return null;
    const rows = rowLimit > 0 ? rowLimit - slot.row : Infinity;
    const size = clamp(Object.assign({}, widget, { "w": slot.cols }), layout.columns, rows);
    if (size.w > slot.cols || size.h !== widget.h || size.h > rows)
        return null;
    return Object.assign({}, size, { "col": slot.col, "row": slot.row });
}

// Empty rows borrow the fullest page's row heights, so short tiles never make another page taller.
function heightForRows(layouts, rows, rowUnit, gap, step = 0.5) {
    const reference = layouts.reduce((best, layout) => layout.rows > best.rows ? layout : best, { "rows": 0 });
    const count = Math.round(rows / step);
    const full = step * rowUnit - (1 - step) * gap;
    function band(layout, index) {
        if (index >= Math.round(layout.rows / step))
            return undefined;
        if (!layout.bandTops)
            return full;
        return index + 1 < layout.bandTops.length ? layout.bandTops[index + 1] - layout.bandTops[index] - gap : layout.totalHeight - layout.bandTops[index];
    }
    const defaults = Array.from({ "length": count }, (_, i) => band(reference, i) ?? full);
    const sum = heights => Math.max(0, heights.reduce((height, value) => height + value + gap, 0) - gap);
    return Math.max(sum(defaults), ...layouts.map(layout => sum(defaults.slice(0, Math.round(layout.rows / step)).map((value, i) => band(layout, i) ?? value))));
}

// Spill before the next page's own tiles; a group's members follow their owner.
function paginate(widgets, columns, rows, isShown = () => true, pull = false) {
    if (!(rows > 0) || !(columns > 0))
        return widgets;
    const owners = new Map(widgets.filter(widget => widget?.id === GROUP_ID && widget.instanceId).map(widget => [widget.instanceId, widget]));
    const pages = [];
    widgets.forEach((widget, index) => {
        if (!widget || owners.has(widget.group) || !isShown(widget))
            return;
        const page = pageOf(widget);
        pages[page] = pages[page] ?? [];
        pages[page].push({
            "index": index,
            "widget": Object.assign({}, widget, {
                "w": Math.max(0.5, Math.min(columns, Number(widget.w) || 1)),
                "h": Math.max(0.5, Math.min(rows, Number(widget.h) || 1))
            })
        });
    });

    function pack(items) {
        return Grid.packCells(items.map(item => item.widget), items.map((item, index) => index), columns, null, 0.5, true).cells;
    }

    for (let page = 0; page < pages.length; page++) {
        const items = pages[page] ?? [];
        const cells = pack(items);
        const kept = [];
        const spill = [];
        items.forEach((item, index) => {
            const cell = cells[index];
            item.widget = Object.assign({}, item.widget, { "col": cell.col, "row": cell.row });
            (cell.row + cell.rows <= rows ? kept : spill).push(item);
        });
        pages[page] = kept;
        if (!spill.length)
            continue;
        spill.sort((a, b) => a.widget.row - b.widget.row || a.widget.col - b.widget.col);
        const top = Math.min(...spill.map(item => item.widget.row));
        spill.forEach(item => item.widget.row -= top);
        pages[page + 1] = spill.concat(pages[page + 1] ?? []);
    }

    if (pull) {
        for (let page = 0; page < pages.length - 1; page++) {
            const current = pages[page];
            const next = pages[page + 1];
            let moved = false;
            while (next.length) {
                const top = Math.min(...next.map(item => item.widget.row));
                let end = top;
                for (let previous = -1; previous !== end;) {
                    previous = end;
                    next.forEach(item => {
                        const widget = item.widget;
                        if (widget.row <= top || widget.row < end)
                            end = Math.max(end, widget.row + widget.h);
                    });
                }
                const band = next.filter(item => item.widget.row < end);
                const bottom = current.reduce((height, item) => Math.max(height, item.widget.row + item.widget.h), 0);
                if (bottom + end - top > rows)
                    break;
                band.forEach(item => {
                    next.splice(next.indexOf(item), 1);
                    item.widget.row += bottom - top;
                    current.push(item);
                });
                moved = true;
                const cells = pack(current);
                current.forEach((item, index) => Object.assign(item.widget, { "col": cells[index].col, "row": cells[index].row }));
            }
            // A pull can fill an empty predecessor; revisit it until every band has moved as far back as it fits.
            if (moved)
                page = Math.max(-1, page - 2);
        }
        pages.forEach(items => {
            const cells = pack(items);
            items.forEach((item, index) => Object.assign(item.widget, { "col": cells[index].col, "row": cells[index].row }));
        });
    }

    const result = widgets.slice();
    pages.forEach((items, page) => items.forEach(item => result[item.index] = withPage(item.widget, page)));
    const ownerPages = new Map(result.filter(widget => widget?.id === GROUP_ID && widget.instanceId).map(widget => [widget.instanceId, pageOf(widget)]));
    result.forEach((widget, index) => {
        if (ownerPages.has(widget?.group))
            result[index] = withPage(widget, ownerPages.get(widget.group));
    });
    return JSON.stringify(result) === JSON.stringify(widgets) ? widgets : result;
}
