.pragma library

function unite(a, b) {
    if (a.width <= 0 || a.height <= 0)
        return b;
    if (b.width <= 0 || b.height <= 0)
        return a;
    const x = Math.min(a.x, b.x);
    const y = Math.min(a.y, b.y);
    return {
        x,
        y,
        width: Math.max(a.x + a.width, b.x + b.width) - x,
        height: Math.max(a.y + a.height, b.y + b.height) - y
    };
}

function clip(area, screenWidth, screenHeight) {
    if (area.width <= 0 || area.height <= 0 || screenWidth <= 0 || screenHeight <= 0)
        return {
            x: 0,
            y: 0,
            width: 0,
            height: 0
        };
    const x = Math.max(0, Math.min(screenWidth - 1, area.x));
    const y = Math.max(0, Math.min(screenHeight - 1, area.y));
    const right = Math.min(screenWidth, area.x + area.width);
    const bottom = Math.min(screenHeight, area.y + area.height);
    return {
        x,
        y,
        width: Math.max(1, right - x),
        height: Math.max(1, bottom - y)
    };
}

function strip(screenWidth, screenHeight, vertical, body, origin, padding) {
    const area = unite(body, origin);
    const x = vertical ? 0 : Math.max(0, Math.min(screenWidth - 1, Math.floor(area.x - padding)));
    const y = vertical ? Math.max(0, Math.min(screenHeight - 1, Math.floor(area.y - padding))) : 0;
    const right = vertical ? screenWidth : Math.min(screenWidth, Math.ceil(area.x + area.width + padding));
    const bottom = vertical ? Math.min(screenHeight, Math.ceil(area.y + area.height + padding)) : screenHeight;
    return {
        x,
        y,
        width: Math.max(1, right - x),
        height: Math.max(1, bottom - y)
    };
}
