.pragma library

function findParentFlickable(item) {
    while (item) {
        if (item.hasOwnProperty("contentY") && item.hasOwnProperty("contentItem"))
            return item;
        item = item.parent;
    }
    return null;
}

function findParentCollapsible(item) {
    while (item) {
        if (item.collapsible === true && item.expanded !== undefined)
            return item;
        item = item.parent;
    }
    return null;
}

function findSettings(item) {
    while (item) {
        if (item.saveValue !== undefined && item.loadValue !== undefined)
            return item;
        item = item.parent;
    }
    return null;
}

// mapToGlobal ignores a layer window's margins, so detached popouts need them added back
function screenPointOf(window, item, x, y) {
    const screen = window?.screen;
    if (!window || !screen || !item)
        return null;
    const pos = item.mapToGlobal(x, y);
    const originX = window.anchors.left ? window.margins.left : window.anchors.right ? screen.width - window.margins.right - window.width : 0;
    const originY = window.anchors.top ? window.margins.top : window.anchors.bottom ? screen.height - window.margins.bottom - window.height : 0;
    return {
        x: pos.x - screen.x + originX,
        y: pos.y - screen.y + originY
    };
}

function normalizePinList(value) {
    if (Array.isArray(value))
        return value.filter(v => v);
    if (typeof value === "string" && value.length > 0)
        return [value];
    return [];
}

function togglePinEntry(pins, key, entry, maxPins) {
    const next = JSON.parse(JSON.stringify(pins || {}));
    let pinned = normalizePinList(next[key]);
    const index = pinned.indexOf(entry);
    if (index !== -1)
        pinned.splice(index, 1);
    else
        pinned = [entry].concat(pinned).slice(0, maxPins);
    if (pinned.length > 0)
        next[key] = pinned;
    else
        delete next[key];
    return next;
}
