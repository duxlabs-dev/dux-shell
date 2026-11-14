.pragma library

function pageOf(widget) {
    const page = widget?.page;
    return Number.isInteger(page) && page > 0 ? page : 0;
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

// Members of a group that no longer exists fall back to the grid.
function groupOf(widgets, widget) {
    if (!widget?.group)
        return null;
    return widgets.find(other => other !== widget && other?.instanceId === widget.group) ?? null;
}

function onGrid(widgets, widget, isShown) {
    return !!widget && !groupOf(widgets, widget) && isShown(widget);
}

function pageCount(widgets, isShown = () => true) {
    return widgets.reduce((count, widget) => onGrid(widgets, widget, isShown) ? Math.max(count, pageOf(widget) + 1) : count, 1);
}

// The pages with a shown tile, ascending; compacting renumbers them to their index here.
function usedPages(widgets, isShown = () => true) {
    return Array.from(new Set(widgets.filter(widget => onGrid(widgets, widget, isShown)).map(pageOf))).sort((a, b) => a - b);
}

function nearestIndex(pages, page) {
    return pages.reduce((best, kept, i) => Math.abs(kept - page) < Math.abs(pages[best] - page) ? i : best, 0);
}

// Hidden tiles alone do not keep a page; theirs folds into a neighbor and they lose their cell.
function compactPages(widgets, isShown = () => true) {
    const used = usedPages(widgets, isShown);
    const last = Math.max(0, used.length - 1);
    const target = page => Math.min(used.filter(kept => kept < page).length, last);
    let changed = false;
    const next = widgets.map(widget => {
        if (!widget || typeof widget !== "object")
            return widget;
        const group = groupOf(widgets, widget);
        const page = pageOf(group ?? widget);
        let moved = withPage(widget, target(page));
        if (!group && !used.includes(page) && (Number.isFinite(widget.col) || Number.isFinite(widget.row))) {
            moved = Object.assign({}, moved);
            delete moved.col;
            delete moved.row;
        }
        changed = changed || moved !== widget;
        return moved;
    });
    return changed ? next : widgets;
}

// Without a cell the packer places the moved tile on its new page; a group's members follow it.
function movedToPage(widgets, index, page, cell) {
    const widget = widgets[index];
    const to = Math.max(0, Math.floor(Number(page) || 0));
    if (!widget || groupOf(widgets, widget) || pageOf(widget) === to)
        return widgets;
    const moved = withPage(widget, to);
    delete moved.col;
    delete moved.row;
    if (Number.isFinite(cell?.col) && Number.isFinite(cell?.row)) {
        moved.col = cell.col;
        moved.row = cell.row;
    }
    return widgets.map((other, i) => {
        if (i === index)
            return moved;
        return widget.instanceId && other?.group === widget.instanceId ? withPage(other, to) : other;
    });
}
