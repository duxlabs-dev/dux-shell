.pragma library

function distanceToSegment(p, a, b) {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len2 = dx * dx + dy * dy;
    const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2));
    return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}

function outline(shape, viewScale) {
    const pts = shape.points;
    if (!pts)
        return [];
    if (shape.type === "rect") {
        const a = pts[0];
        const b = pts[pts.length - 1];
        return [a, { x: b.x, y: a.y }, b, { x: a.x, y: b.y }, a];
    }
    if (shape.type === "arrow") {
        const a = pts[0];
        const b = pts[pts.length - 1];
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const len = Math.hypot(dx, dy);
        if (len <= 0)
            return [a, b];
        const spread = Math.PI / 7;
        const headLen = Math.max(15 / (viewScale || 1), (shape.width || 1) * 4);
        const offset = headLen * Math.cos(spread);
        const shaftLen = Math.max(0, len - offset);
        const angle = Math.atan2(dy, dx);
        const endX = a.x + shaftLen * Math.cos(angle);
        const endY = a.y + shaftLen * Math.sin(angle);
        return [a, { x: endX, y: endY }];
    }
    return pts;
}

function hits(shape, p, tolerance, viewScale) {
    if (shape.type === "text")
        return p.x >= shape.x - tolerance && p.x <= shape.x + shape.w + tolerance && p.y >= shape.y - tolerance && p.y <= shape.y + shape.h + tolerance;
    const pts = outline(shape, viewScale);
    const reach = (shape.width || 1) / 2 + tolerance;
    for (let i = 1; i < pts.length; i++) {
        if (distanceToSegment(p, pts[i - 1], pts[i]) <= reach)
            return true;
    }
    return pts.length === 1 && Math.hypot(p.x - pts[0].x, p.y - pts[0].y) <= reach;
}

function shapeBounds(shape, viewScale, defaultFontSize) {
    if (!shape)
        return null;
    const scale = viewScale || 1;
    if (shape.type === "text") {
        const pad = 4 / scale;
        return {
            x: shape.x - pad,
            y: shape.y - pad,
            width: (shape.w || 0) + pad * 2,
            height: (shape.h || (shape.size || defaultFontSize || 16)) + pad * 2
        };
    }
    const pts = outline(shape, scale);
    if (!pts || pts.length === 0)
        return null;
    let minX = pts[0].x;
    let maxX = pts[0].x;
    let minY = pts[0].y;
    let maxY = pts[0].y;
    for (let i = 1; i < pts.length; i++) {
        minX = Math.min(minX, pts[i].x);
        maxX = Math.max(maxX, pts[i].x);
        minY = Math.min(minY, pts[i].y);
        maxY = Math.max(maxY, pts[i].y);
    }
    const pad = (((shape.width || 1) / 2) + 4) / scale;
    return {
        x: minX - pad,
        y: minY - pad,
        width: Math.max(1, maxX - minX + pad * 2),
        height: Math.max(1, maxY - minY + pad * 2)
    };
}

function translateShape(shape, dx, dy) {
    if (!shape)
        return shape;
    if (shape.type === "text") {
        return Object.assign({}, shape, {
            x: shape.x + dx,
            y: shape.y + dy
        });
    }
    if (!shape.points)
        return shape;
    const newPts = shape.points.map(pt => ({ x: pt.x + dx, y: pt.y + dy }));
    return Object.assign({}, shape, {
        points: newPts
    });
}

function resizeShape(shape, origBox, newBox, defaultFontSize) {
    if (!shape || !origBox || !newBox || origBox.width <= 0 || origBox.height <= 0 || newBox.width <= 0 || newBox.height <= 0)
        return shape;
    const scaleX = newBox.width / origBox.width;
    const scaleY = newBox.height / origBox.height;

    if (shape.type === "text") {
        const relX = (shape.x - origBox.x) * scaleX;
        const relY = (shape.y - origBox.y) * scaleY;
        const newSize = Math.max(8, (shape.size || defaultFontSize || 16) * Math.min(scaleX, scaleY));
        return Object.assign({}, shape, {
            x: newBox.x + relX,
            y: newBox.y + relY,
            size: newSize,
            w: (shape.w || 0) * scaleX,
            h: (shape.h || 0) * scaleY
        });
    }

    if (!shape.points)
        return shape;

    const newPts = shape.points.map(pt => {
        const relX = (pt.x - origBox.x) * scaleX;
        const relY = (pt.y - origBox.y) * scaleY;
        return { x: newBox.x + relX, y: newBox.y + relY };
    });

    return Object.assign({}, shape, {
        points: newPts
    });
}

function arrowHead(shape, viewScale) {
    const a = shape.points[0];
    const b = shape.points[shape.points.length - 1];
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    if (Math.hypot(dx, dy) <= 0)
        return [];
    const angle = Math.atan2(dy, dx);
    const headLength = Math.max(15 / (viewScale || 1), (shape.width || 1) * 4);
    const spreadAngle = Math.PI / 7;
    const strokeWidth = shape.width || 1;

    const tipRadius = Math.max(1.5, Math.min(strokeWidth * 0.5, headLength * 0.15));
    const sinHalf = Math.sin(spreadAngle);
    const tipApexInset = tipRadius * (1 / sinHalf - 1);
    const effectiveTipX = b.x + tipApexInset * Math.cos(angle);
    const effectiveTipY = b.y + tipApexInset * Math.sin(angle);

    const v1 = { x: effectiveTipX, y: effectiveTipY };
    const v2 = { x: b.x - headLength * Math.cos(angle - spreadAngle), y: b.y - headLength * Math.sin(angle - spreadAngle) };
    const v3 = { x: b.x - headLength * Math.cos(angle + spreadAngle), y: b.y - headLength * Math.sin(angle + spreadAngle) };

    return [v1, v2, v3, v1];
}

function snapPointToAngle(point, fixed) {
    const dx = point.x - fixed.x;
    const dy = point.y - fixed.y;
    const length = Math.hypot(dx, dy);
    if (length === 0)
        return point;
    const snapStep = Math.PI / 12;
    const angle = Math.atan2(dy, dx);
    const snapped = Math.round(angle / snapStep) * snapStep;
    return { x: fixed.x + length * Math.cos(snapped), y: fixed.y + length * Math.sin(snapped) };
}

function constrainSquarePoint(start, point) {
    if (!start || !point)
        return point || { x: 0, y: 0 };
    const dx = point.x - start.x;
    const dy = point.y - start.y;
    const size = Math.max(Math.abs(dx), Math.abs(dy));
    const sx = dx < 0 ? -1 : 1;
    const sy = dy < 0 ? -1 : 1;
    return { x: start.x + sx * size, y: start.y + sy * size };
}

function normalizedRect(a, b, boundaryWidth, boundaryHeight) {
    const x1 = Math.max(0, Math.min(a.x, b.x));
    const y1 = Math.max(0, Math.min(a.y, b.y));
    const x2 = boundaryWidth ? Math.min(boundaryWidth, Math.max(a.x, b.x)) : Math.max(a.x, b.x);
    const y2 = boundaryHeight ? Math.min(boundaryHeight, Math.max(a.y, b.y)) : Math.max(a.y, b.y);
    return { x: x1, y: y1, width: Math.max(0, x2 - x1), height: Math.max(0, y2 - y1) };
}
