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

function motion(screenWidth, screenHeight, body, origin, offsetX, offsetY, collapsedScale, padding, spring) {
    const ratio = spring.damping / (2 * Math.sqrt(spring.stiffness * spring.mass));
    const lobeDecay = ratio < 1 ? Math.exp(-Math.PI * ratio / Math.sqrt(1 - ratio * ratio)) : 0;
    const overshoot = lobeDecay / (1 - lobeDecay);
    let area = unite(body, origin);
    for (const progress of [-overshoot, 1 + overshoot]) {
        const scale = collapsedScale + (1 - collapsedScale) * progress;
        const scalePaddingX = body.width * Math.max(0, scale - 1);
        const scalePaddingY = body.height * Math.max(0, scale - 1);
        area = unite(area, {
            x: body.x + offsetX * (1 - progress) - scalePaddingX,
            y: body.y + offsetY * (1 - progress) - scalePaddingY,
            width: body.width + scalePaddingX * 2,
            height: body.height + scalePaddingY * 2
        });
    }
    const x = Math.floor(area.x - padding);
    const y = Math.floor(area.y - padding);
    return clip({
        x,
        y,
        width: Math.ceil(area.x + area.width + padding) - x,
        height: Math.ceil(area.y + area.height + padding) - y
    }, screenWidth, screenHeight);
}
