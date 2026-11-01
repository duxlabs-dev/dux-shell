.pragma library

function _number(value, fallback) {
    var n = Number(value);
    return isNaN(n) ? fallback : n;
}

function snap(value, dpr) {
    var scale = dpr || 1;
    return Math.round(_number(value, 0) * scale) / scale;
}

function isHorizontal(side) {
    return side === "top" || side === "bottom";
}

function isVertical(side) {
    return side === "left" || side === "right";
}

// Overflow chrome (the edit strip) is part of the silhouette, so it rolls out with the body.
function bodyRect(descriptor, dpr) {
    var source = descriptor && descriptor.bodyRect ? descriptor.bodyRect : descriptor || {};
    var overflowTop = Math.max(0, _number(descriptor && descriptor.overflowTop, 0));
    var overflowBottom = Math.max(0, _number(descriptor && descriptor.overflowBottom, 0));
    return {
        "x": snap(source.x !== undefined ? source.x : source.bodyX, dpr),
        "y": snap(_number(source.y !== undefined ? source.y : source.bodyY, 0) - overflowTop, dpr),
        "width": Math.max(0, snap(source.width !== undefined ? source.width : source.bodyW, dpr)),
        "height": Math.max(0, snap(_number(source.height !== undefined ? source.height : source.bodyH, 0) + overflowTop + overflowBottom, dpr))
    };
}

function animatedBodyRect(descriptor, dpr) {
    var rect = bodyRect(descriptor, dpr);
    var offset = descriptor && descriptor.animationOffset ? descriptor.animationOffset : descriptor || {};
    var side = descriptor && descriptor.barSide ? descriptor.barSide : "bottom";
    var dx = isVertical(side) ? Math.max(-rect.width, Math.min(_number(offset.x !== undefined ? offset.x : offset.animX, 0), rect.width)) : 0;
    var dy = isHorizontal(side) ? Math.max(-rect.height, Math.min(_number(offset.y !== undefined ? offset.y : offset.animY, 0), rect.height)) : 0;

    return {
        "x": snap(rect.x + (side === "right" ? dx : 0), dpr),
        "y": snap(rect.y + (side === "bottom" ? dy : 0), dpr),
        "width": Math.max(0, snap(rect.width - (side === "left" ? -dx : dx), dpr)),
        "height": Math.max(0, snap(rect.height - (side === "top" ? -dy : dy), dpr)),
        "dx": snap(dx, dpr),
        "dy": snap(dy, dpr)
    };
}

function translatedBodyRect(descriptor, dpr) {
    var rect = bodyRect(descriptor, dpr);
    var offset = descriptor && descriptor.animationOffset ? descriptor.animationOffset : {};
    return {
        "x": snap(rect.x + _number(offset.x, 0), dpr),
        "y": snap(rect.y + _number(offset.y, 0), dpr),
        "width": rect.width,
        "height": rect.height
    };
}

function connectorRadii(descriptor, rect, connectedRadius, surfaceRadius, dpr, nearIncludesSurface) {
    var side = descriptor && descriptor.barSide ? descriptor.barSide : "bottom";
    var horizontal = isHorizontal(side);
    var extent = horizontal ? rect.height : rect.width;
    var crossSize = horizontal ? rect.width : rect.height;
    var nearLimit = nearIncludesSurface ? Math.min(connectedRadius, surfaceRadius, extent, crossSize / 2) : Math.min(connectedRadius, extent, crossSize / 2);
    var farLimit = Math.min(connectedRadius, surfaceRadius, crossSize / 2);
    var near = snap(Math.max(0, nearLimit), dpr);
    var far = snap(Math.max(0, farLimit), dpr);
    var omitStart = !!(descriptor && descriptor.omitStartConnector);
    var omitEnd = !!(descriptor && descriptor.omitEndConnector);
    return {
        "near": near,
        "far": far,
        "start": omitStart ? 0 : near,
        "end": omitEnd ? 0 : near,
        "farStart": omitStart ? far : 0,
        "farEnd": omitEnd ? far : 0,
        "farExtent": Math.max(omitStart ? far : 0, omitEnd ? far : 0)
    };
}

function _connectorWidth(side, spacing, radius) {
    return isVertical(side) ? spacing + radius : radius;
}

function _connectorHeight(side, spacing, radius) {
    return isVertical(side) ? radius : spacing + radius;
}

function connectorRect(side, rect, placement, spacing, radius, dpr) {
    var width = _connectorWidth(side, spacing, radius);
    var height = _connectorHeight(side, spacing, radius);
    var seamX = isVertical(side) ? (side === "left" ? rect.x : rect.x + rect.width) : (placement === "left" ? rect.x : rect.x + rect.width);
    var seamY = side === "top" ? rect.y : (side === "bottom" ? rect.y + rect.height : (placement === "left" ? rect.y : rect.y + rect.height));
    var x = isVertical(side) ? (side === "left" ? seamX : seamX - width) : (placement === "left" ? seamX - width : seamX);
    var y = side === "top" ? seamY : (side === "bottom" ? seamY - height : (placement === "left" ? seamY - height : seamY));
    return {
        "x": snap(x, dpr),
        "y": snap(y, dpr),
        "width": Math.max(0, snap(width, dpr)),
        "height": Math.max(0, snap(height, dpr))
    };
}

function farConnectorRect(side, rect, placement, radius, dpr) {
    var x;
    var y;
    if (isHorizontal(side)) {
        x = placement === "left" ? rect.x : rect.x + rect.width - radius;
        y = side === "top" ? rect.y + rect.height : rect.y - radius;
    } else {
        x = side === "left" ? rect.x + rect.width : rect.x - radius;
        y = placement === "left" ? rect.y : rect.y + rect.height - radius;
    }
    return {
        "x": snap(x, dpr),
        "y": snap(y, dpr),
        "width": Math.max(0, snap(radius, dpr)),
        "height": Math.max(0, snap(radius, dpr))
    };
}

function farBodyCapRect(side, rect, placement, radius, dpr) {
    var x;
    var y;
    if (isHorizontal(side)) {
        x = placement === "left" ? rect.x : rect.x + rect.width - radius;
        y = side === "top" ? rect.y + rect.height - radius : rect.y;
    } else {
        x = side === "left" ? rect.x + rect.width - radius : rect.x;
        y = placement === "left" ? rect.y : rect.y + rect.height - radius;
    }
    return {
        "x": snap(x, dpr),
        "y": snap(y, dpr),
        "width": Math.max(0, snap(radius, dpr)),
        "height": Math.max(0, snap(radius, dpr))
    };
}

function chromeBounds(rect, side, startRadius, endRadius, farExtent, dpr) {
    var horizontal = isHorizontal(side);
    var bodyOffsetX = horizontal ? startRadius : (side === "right" ? farExtent : 0);
    var bodyOffsetY = horizontal ? (side === "bottom" ? farExtent : 0) : startRadius;
    return {
        "x": snap(rect.x - bodyOffsetX, dpr),
        "y": snap(rect.y - bodyOffsetY, dpr),
        "width": Math.max(0, snap(horizontal ? rect.width + startRadius + endRadius : rect.width + farExtent, dpr)),
        "height": Math.max(0, snap(horizontal ? rect.height + farExtent : rect.height + startRadius + endRadius, dpr)),
        "bodyOffsetX": snap(bodyOffsetX, dpr),
        "bodyOffsetY": snap(bodyOffsetY, dpr)
    };
}

function fillBounds(rect, side, seamOverlap, dpr) {
    var overlapX = isHorizontal(side) ? seamOverlap : 0;
    var overlapY = isVertical(side) ? seamOverlap : 0;
    return {
        "x": snap(rect.x - overlapX, dpr),
        "y": snap(rect.y - overlapY, dpr),
        "width": Math.max(0, snap(rect.width + overlapX * 2, dpr)),
        "height": Math.max(0, snap(rect.height + overlapY * 2, dpr))
    };
}

function blurRegions(descriptor, rect, radii, dpr) {
    var side = descriptor.barSide;
    var regions = [bodyRect(rect, dpr)];
    if (radii.start > 0)
        regions.push(connectorRect(side, rect, "left", 0, radii.start, dpr));
    if (radii.end > 0)
        regions.push(connectorRect(side, rect, "right", 0, radii.end, dpr));
    if (radii.farStart > 0) {
        regions.push(farConnectorRect(side, rect, "left", radii.farStart, dpr));
        regions.push(farBodyCapRect(side, rect, "left", radii.farStart, dpr));
    }
    if (radii.farEnd > 0) {
        regions.push(farConnectorRect(side, rect, "right", radii.farEnd, dpr));
        regions.push(farBodyCapRect(side, rect, "right", radii.farEnd, dpr));
    }
    return regions;
}

function _touchesEdge(rect, edges, edge) {
    switch (edge) {
    case "left":
        return rect.x <= edges.left;
    case "top":
        return rect.y <= edges.top;
    case "right":
        return rect.x + rect.width >= edges.right;
    default:
        return rect.y + rect.height >= edges.bottom;
    }
}

function bandPaddedRect(rect, pad, edges, side) {
    var out = {
        "x": Math.round(_number(rect.x, 0)),
        "y": Math.round(_number(rect.y, 0)),
        "width": Math.round(_number(rect.width, 0)),
        "height": Math.round(_number(rect.height, 0))
    };
    if (!(pad > 0) || out.width <= 0 || out.height <= 0)
        return out;
    var touches = function (edge) {
        return side ? side === edge : _touchesEdge(out, edges, edge);
    };
    if (touches("left")) {
        out.x -= pad;
        out.width += pad;
    }
    if (touches("top")) {
        out.y -= pad;
        out.height += pad;
    }
    if (touches("right"))
        out.width += pad;
    if (touches("bottom"))
        out.height += pad;
    return out;
}

function unionBounds(rects, padding, dpr) {
    var minX = Infinity;
    var minY = Infinity;
    var maxX = -Infinity;
    var maxY = -Infinity;
    for (var i = 0; i < rects.length; i++) {
        var rect = rects[i];
        if (!rect || rect.width <= 0 || rect.height <= 0)
            continue;
        minX = Math.min(minX, rect.x);
        minY = Math.min(minY, rect.y);
        maxX = Math.max(maxX, rect.x + rect.width);
        maxY = Math.max(maxY, rect.y + rect.height);
    }
    if (minX === Infinity)
        return {
            "x": 0,
            "y": 0,
            "width": 0,
            "height": 0
        };
    var pad = Math.max(0, _number(padding, 0));
    return {
        "x": snap(minX - pad, dpr),
        "y": snap(minY - pad, dpr),
        "width": Math.max(0, snap(maxX - minX + pad * 2, dpr)),
        "height": Math.max(0, snap(maxY - minY + pad * 2, dpr))
    };
}
