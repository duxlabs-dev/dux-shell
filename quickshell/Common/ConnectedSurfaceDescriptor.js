.pragma library

var VALID_KINDS = {
    "popout": true,
    "modal": true,
    "launcher": true,
    "dock": true,
    "notification": true,
    "island": true,
    "slideout": true
};

var VALID_PHASES = {
    "opening": true,
    "open": true,
    "closing": true,
    "hidden": true,
    "recovering": true
};

function _number(value, fallback) {
    var n = Number(value);
    return isNaN(n) ? fallback : n;
}

function _bool(value, fallback) {
    return value === undefined ? fallback : !!value;
}

function _kind(value, fallback) {
    if (VALID_KINDS[value])
        return value;
    return VALID_KINDS[fallback] ? fallback : "modal";
}

function _defaultBarSide(kind) {
    return kind === "popout" || kind === "notification" || kind === "island" ? "top" : "bottom";
}

function _barSide(value, fallback) {
    if (value === "top" || value === "bottom" || value === "left" || value === "right")
        return value;
    return fallback;
}

function _layer(value, fallback) {
    if (value === "overlay" || value === "top")
        return value;
    return fallback === "overlay" ? "overlay" : "top";
}

function slotForKind(kind) {
    return kind === "launcher" ? "modal" : _kind(kind, "modal");
}

function inferPhase(visible, presented, requestedPhase) {
    if (VALID_PHASES[requestedPhase])
        return requestedPhase;
    if (!visible && !presented)
        return "hidden";
    if (!visible && presented)
        return "closing";
    return "open";
}

function normalize(input, defaults) {
    var source = input || {};
    var base = defaults || {};
    var kind = _kind(source.kind, base.kind);
    var defaultSide = _defaultBarSide(kind);
    var sourceRect = source.bodyRect || {};
    var baseRect = base.bodyRect || {};
    var sourceOffset = source.animationOffset || {};
    var baseOffset = base.animationOffset || {};
    var visible = _bool(source.visible !== undefined ? source.visible : source.reveal, _bool(base.visible !== undefined ? base.visible : base.reveal, false));
    var presented = _bool(source.presented, _bool(base.presented, visible));
    var bodyRect = {
        "x": _number(sourceRect.x !== undefined ? sourceRect.x : source.bodyX, _number(baseRect.x !== undefined ? baseRect.x : base.bodyX, 0)),
        "y": _number(sourceRect.y !== undefined ? sourceRect.y : source.bodyY, _number(baseRect.y !== undefined ? baseRect.y : base.bodyY, 0)),
        "width": Math.max(0, _number(sourceRect.width !== undefined ? sourceRect.width : source.bodyW, _number(baseRect.width !== undefined ? baseRect.width : base.bodyW, 0))),
        "height": Math.max(0, _number(sourceRect.height !== undefined ? sourceRect.height : source.bodyH, _number(baseRect.height !== undefined ? baseRect.height : base.bodyH, 0)))
    };
    var animationOffset = {
        "x": _number(sourceOffset.x !== undefined ? sourceOffset.x : (source.animX !== undefined ? source.animX : source.slideX), _number(baseOffset.x !== undefined ? baseOffset.x : (base.animX !== undefined ? base.animX : base.slideX), 0)),
        "y": _number(sourceOffset.y !== undefined ? sourceOffset.y : (source.animY !== undefined ? source.animY : source.slideY), _number(baseOffset.y !== undefined ? baseOffset.y : (base.animY !== undefined ? base.animY : base.slideY), 0))
    };
    var screenName = source.screenName !== undefined ? source.screenName : (source.screen !== undefined ? source.screen : (base.screenName !== undefined ? base.screenName : base.screen));
    var opacity = Math.max(0, Math.min(1, _number(source.opacity, _number(base.opacity, 1))));

    return {
        "ownerId": String(source.ownerId !== undefined ? source.ownerId : (base.ownerId || "")),
        "kind": kind,
        "screenName": String(screenName || ""),
        "phase": inferPhase(visible, presented, source.phase !== undefined ? source.phase : base.phase),
        "visible": visible,
        "presented": presented,
        "layer": _layer(source.layer, _layer(base.layer, "top")),
        "barSide": _barSide(source.barSide, _barSide(base.barSide, defaultSide)),
        "bodyRect": bodyRect,
        "animationOffset": animationOffset,
        "surfaceRadius": Math.max(-1, _number(source.surfaceRadius, _number(base.surfaceRadius, -1))),
        "scale": Math.max(0, _number(source.scale, _number(base.scale, 1))),
        "opacity": opacity,
        "omitStartConnector": _bool(source.omitStartConnector, _bool(base.omitStartConnector, false)),
        "omitEndConnector": _bool(source.omitEndConnector, _bool(base.omitEndConnector, false)),
        "dockRetractSide": String(source.dockRetractSide !== undefined ? source.dockRetractSide : (base.dockRetractSide || "")),
        // Chrome hung off the body; only the blur covers it.
        "overflowTop": Math.max(0, _number(source.overflowTop, _number(base.overflowTop, 0))),
        "overflowBottom": Math.max(0, _number(source.overflowBottom, _number(base.overflowBottom, 0))),
        "revision": Math.max(0, Math.floor(_number(source.revision, _number(base.revision, 0))))
    };
}

function empty(kind, screenName) {
    return normalize({
        "kind": kind,
        "screenName": screenName || "",
        "phase": "hidden",
        "visible": false,
        "presented": false
    });
}

function withRevision(descriptor, revision) {
    var next = normalize(descriptor);
    next.revision = Math.max(0, Math.floor(_number(revision, next.revision)));
    return next;
}

function same(a, b, threshold) {
    if (!a || !b)
        return false;
    var epsilon = threshold === undefined ? 0.5 : Math.max(0, Number(threshold));
    return a.ownerId === b.ownerId
        && a.kind === b.kind
        && a.screenName === b.screenName
        && a.phase === b.phase
        && a.visible === b.visible
        && a.presented === b.presented
        && a.layer === b.layer
        && a.barSide === b.barSide
        && Math.abs(a.bodyRect.x - b.bodyRect.x) < epsilon
        && Math.abs(a.bodyRect.y - b.bodyRect.y) < epsilon
        && Math.abs(a.bodyRect.width - b.bodyRect.width) < epsilon
        && Math.abs(a.bodyRect.height - b.bodyRect.height) < epsilon
        && Math.abs(a.animationOffset.x - b.animationOffset.x) < epsilon
        && Math.abs(a.animationOffset.y - b.animationOffset.y) < epsilon
        && Math.abs(a.surfaceRadius - b.surfaceRadius) < epsilon
        && Math.abs(a.scale - b.scale) < 0.0001
        && Math.abs(a.opacity - b.opacity) < 0.0001
        && a.omitStartConnector === b.omitStartConnector
        && a.omitEndConnector === b.omitEndConnector
        && Math.abs(a.overflowTop - b.overflowTop) < epsilon
        && Math.abs(a.overflowBottom - b.overflowBottom) < epsilon
        && a.dockRetractSide === b.dockRetractSide;
}
