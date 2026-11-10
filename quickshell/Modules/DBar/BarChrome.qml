pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import "../../Common/ConnectedSurfaceGeometry.js" as SurfaceGeometry

ShaderEffect {
    id: root

    required property Item leading
    property Item trailing: null
    required property string screenName
    required property string barSide
    required property string barId
    required property real originX
    required property real originY
    required property real windowWidth
    required property real windowHeight
    required property real alongExtent
    required property real dpr
    required property color fillColor
    required property real edgeRadius
    required property real cornerRadius
    property real nearRadius: 0
    property real endRadiusStart: 0
    property real endRadiusEnd: 0
    property color outlineColor: "transparent"
    property real borderWidth: 0
    property bool alwaysPainted: false
    property real windowX: 0
    property real windowY: 0

    readonly property bool horizontal: barSide === "top" || barSide === "bottom"
    readonly property bool nearSide: barSide === "top" || barSide === "left"
    readonly property real joinRadius: edgeRadius > 0 ? edgeRadius : Theme.connectedCornerRadius
    readonly property var descriptor: ConnectedModeState.surfaceDescriptor(screenName, "popout")
    readonly property bool popoutActive: descriptor.visible && descriptor.barSide === barSide && descriptor.barId === barId
    readonly property var body: popoutActive ? _windowRect(SurfaceGeometry.animatedBodyRect(descriptor, dpr)) : ({
            "x": 0,
            "y": 0,
            "width": 0,
            "height": 0
        })
    readonly property real seamOverlap: 2
    // How far the popout has come out of the bar; the bar or satellite reaches for its edge over the first stretch of that.
    readonly property real emerged: Math.max(0, Math.min(1, ((horizontal ? body.height : body.width) - seamOverlap) / Math.max(1, joinRadius * 2)))

    function _alongStart(rect) {
        return horizontal ? rect.x : rect.y;
    }

    function _alongEnd(rect) {
        return horizontal ? rect.x + rect.width : rect.y + rect.height;
    }

    function _corners(startRadius, endRadius, n) {
        switch (barSide) {
        case "bottom":
            return Qt.vector4d(startRadius, endRadius, n, n);
        case "left":
            return Qt.vector4d(n, startRadius, endRadius, n);
        case "right":
            return Qt.vector4d(startRadius, n, n, endRadius);
        default:
            return Qt.vector4d(n, n, endRadius, startRadius);
        }
    }

    function _windowRect(screenRect) {
        return {
            "x": screenRect.x - windowX,
            "y": screenRect.y - windowY,
            "width": screenRect.width,
            "height": screenRect.height
        };
    }

    function _rectOf(surface) {
        return {
            "x": originX + surface.chromeRect.x,
            "y": originY + surface.chromeRect.y,
            "width": surface.chromeRect.width,
            "height": surface.chromeRect.height,
            "surface": surface
        };
    }

    function _painted(surface) {
        return surface?.visible && surface.chromeRect.width > 0 && surface.chromeRect.height > 0;
    }

    readonly property var anchor: {
        for (const surface of [leading, trailing]) {
            if (!_painted(surface))
                continue;
            const rect = _rectOf(surface);
            if (_alongStart(body) < _alongEnd(rect) && _alongEnd(body) > _alongStart(rect))
                return rect;
        }
        return null;
    }
    readonly property bool passesStart: !!anchor && _alongStart(body) <= _alongStart(anchor)
    readonly property bool passesEnd: !!anchor && _alongEnd(body) >= _alongEnd(anchor)
    readonly property real paintedStart: passesStart ? _alongStart(anchor) + (_alongStart(body) - _alongStart(anchor)) * emerged : _alongStart(body)
    readonly property real paintedEnd: passesEnd ? _alongEnd(anchor) + (_alongEnd(body) - _alongEnd(anchor)) * emerged : _alongEnd(body)

    // Tucks the body under the satellite so their seam stays solid where they share a straight edge.
    readonly property vector4d paintedBody: {
        const extent = horizontal ? body.height : body.width;
        if (extent <= seamOverlap)
            return Qt.vector4d(0, 0, 0, 0);
        const along = paintedEnd - paintedStart;
        if (horizontal)
            return Qt.vector4d(paintedStart, body.y - (barSide === "top" ? seamOverlap : 0), along, extent + seamOverlap);
        return Qt.vector4d(body.x - (barSide === "left" ? seamOverlap : 0), paintedStart, extent + seamOverlap, along);
    }

    // Satellites know which of their ends sits on the screen edge; a bar is rounded at both.
    function _cornerAt(surface, atStart) {
        if (!alwaysPainted)
            return cornerRadius;
        return atStart ? surface.alongStartRadius : surface.alongEndRadius;
    }

    // Close to a satellite's end its corner and the join share the room, so the two arcs stay tangent.
    function _fit(gap, corner) {
        return Math.min(1, gap / (corner + joinRadius));
    }

    // Where the popout runs past a satellite they share one straight edge, and a fillet there would bulge out of it.
    function _joinRadius(atStart) {
        if (!anchor)
            return 0;
        const extent = horizontal ? body.height : body.width;
        if (atStart ? passesStart : passesEnd)
            return Math.min(joinRadius * (1 - emerged), extent);
        const gap = Math.abs((atStart ? _alongStart(body) : _alongEnd(body)) - (atStart ? _alongStart(anchor) : _alongEnd(anchor)));
        return Math.min(joinRadius * _fit(gap, _cornerAt(anchor.surface, atStart)), extent);
    }

    function _satellite(surface) {
        if (!_painted(surface))
            return {
                "rect": Qt.vector4d(0, 0, 0, 0),
                "corner": Qt.vector4d(0, 0, 0, 0)
            };
        const rect = _rectOf(surface);
        let start = _alongStart(rect);
        let end = _alongEnd(rect);
        let startRadius = _cornerAt(surface, true);
        let endRadius = _cornerAt(surface, false);
        const bodyStart = _alongStart(body);
        const bodyEnd = _alongEnd(body);
        if (emerged > 0 && bodyStart < end && bodyEnd > start) {
            if (bodyStart <= start) {
                start += (bodyStart - start) * emerged;
                startRadius *= 1 - emerged;
            } else {
                startRadius *= 1 - (1 - _fit(bodyStart - start, startRadius)) * emerged;
            }
            if (bodyEnd >= end) {
                end += (bodyEnd - end) * emerged;
                endRadius *= 1 - emerged;
            } else {
                endRadius *= 1 - (1 - _fit(end - bodyEnd, endRadius)) * emerged;
            }
        }
        return {
            "rect": horizontal ? Qt.vector4d(start, rect.y, end - start, rect.height) : Qt.vector4d(rect.x, start, rect.width, end - start),
            "corner": _corners(startRadius, endRadius, nearRadius)
        };
    }

    // The square a concave corner fills, and the circle cut out of it, so blur can follow the curve.
    function _concave(atStart, alongEdge, crossEdge, r) {
        if (r <= 0)
            return {
                "square": Qt.vector4d(0, 0, 0, 0),
                "disc": Qt.vector4d(0, 0, 0, 0)
            };
        const along = atStart ? alongEdge - r : alongEdge;
        const cross = nearSide ? crossEdge : crossEdge - r;
        const discAlong = atStart ? along - r : along;
        const discCross = nearSide ? cross : cross - r;
        return {
            "square": horizontal ? Qt.vector4d(along, cross, r, r) : Qt.vector4d(cross, along, r, r),
            "disc": horizontal ? Qt.vector4d(discAlong, discCross, r * 2, r * 2) : Qt.vector4d(discCross, discAlong, r * 2, r * 2)
        };
    }

    function _crossEdge(far) {
        if (!anchor)
            return 0;
        return horizontal ? (far ? anchor.y + anchor.height : anchor.y) : (far ? anchor.x + anchor.width : anchor.x);
    }

    function _fillet(atStart) {
        const r = !anchor || emerged <= 0 || (atStart ? passesStart : passesEnd) ? 0 : _joinRadius(atStart);
        return _concave(atStart, atStart ? _alongStart(body) : _alongEnd(body), _crossEdge(nearSide), r);
    }

    // Where the satellite's end follows the body out, its corner at the screen edge moves along.
    function _wing(atStart) {
        const r = anchor && emerged > 0 && (atStart ? passesStart : passesEnd) ? edgeRadius : 0;
        return _concave(atStart, atStart ? paintedStart : paintedEnd, _crossEdge(!nearSide), r);
    }

    readonly property var startFillet: _fillet(true)
    readonly property var endFillet: _fillet(false)
    readonly property var startWing: _wing(true)
    readonly property var endWing: _wing(false)

    readonly property var _lead: _satellite(leading)
    readonly property var _trail: _satellite(trailing)
    readonly property var _level: Theme.elevationLevel2
    // The joined shape is one surface, so it keeps a shadow if either half has one.
    readonly property bool _shadow: Theme.elevationEnabled && popoutActive && (SettingsData.popoutElevationEnabled || SettingsData.barElevationEnabled)
    readonly property string _shadowDirection: Theme.elevationLightDirection === "autoBar" ? barSide : Theme.elevationLightDirection
    readonly property color _shadowTint: Theme.elevationShadowColor(_level)
    readonly property var _ambient: Theme.elevationAmbient(_level)
    readonly property real _shadowReach: !_shadow ? 0 : Math.max(shadowParam.x + shadowParam.y + Math.hypot(shadowParam.z, shadowParam.w), ambientParam.x + ambientParam.y)
    readonly property real _reach: Math.max(edgeRadius, joinRadius, endRadiusStart, endRadiusEnd) + _shadowReach + 1

    // Only the strip the shapes and their shadow can touch is shaded; the uniforms stay in window coordinates.
    readonly property rect paintBounds: {
        let x0 = Infinity;
        let y0 = Infinity;
        let x1 = -Infinity;
        let y1 = -Infinity;
        for (const r of [leadRect, trailRect, bodyRect]) {
            if (r.z <= 0 || r.w <= 0)
                continue;
            x0 = Math.min(x0, r.x);
            y0 = Math.min(y0, r.y);
            x1 = Math.max(x1, r.x + r.z);
            y1 = Math.max(y1, r.y + r.w);
        }
        if (x1 <= x0 || y1 <= y0)
            return Qt.rect(0, 0, 0, 0);
        x0 = Math.max(0, Math.floor(x0 - _reach));
        y0 = Math.max(0, Math.floor(y0 - _reach));
        return Qt.rect(x0, y0, Math.min(windowWidth, Math.ceil(x1 + _reach)) - x0, Math.min(windowHeight, Math.ceil(y1 + _reach)) - y0);
    }

    x: paintBounds.x
    y: paintBounds.y
    width: paintBounds.width
    height: paintBounds.height
    visible: (alwaysPainted || popoutActive) && paintBounds.width > 0 && paintBounds.height > 0
    fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/bar_chrome.frag.qsb")

    property real widthPx: width
    property real heightPx: height
    property vector4d viewPx: Qt.vector4d(paintBounds.x, paintBounds.y, windowWidth, windowHeight)
    property vector4d surfaceColor: Qt.vector4d(fillColor.r, fillColor.g, fillColor.b, fillColor.a)
    property vector4d borderColor: Qt.vector4d(outlineColor.r, outlineColor.g, outlineColor.b, outlineColor.a)
    property vector4d shadowColor: Qt.vector4d(_shadowTint.r, _shadowTint.g, _shadowTint.b, _shadow ? _shadowTint.a * emerged : 0)
    property vector4d shadowParam: Qt.vector4d(Math.max(0, _level.blurPx), Math.max(0, _level.spreadPx), Theme.elevationOffsetXFor(_level, _shadowDirection, Theme.spacingXS), Theme.elevationOffsetYFor(_level, _shadowDirection, Theme.spacingXS))
    property vector4d ambientParam: Qt.vector4d(_ambient.blurPx, _ambient.spreadPx, _shadow ? _ambient.alpha * emerged : 0, 0)
    property vector4d edgeParam: Qt.vector4d(barSide === "top" ? 0 : (barSide === "bottom" ? 1 : (barSide === "left" ? 2 : 3)), edgeRadius, _joinRadius(true), _joinRadius(false))
    property vector4d endParam: Qt.vector4d(horizontal ? originX : originY, (horizontal ? originX : originY) + alongExtent, endRadiusStart, endRadiusEnd)
    property vector4d leadRect: _lead.rect
    property vector4d leadCorner: _lead.corner
    property vector4d trailRect: _trail.rect
    property vector4d trailCorner: _trail.corner
    property vector4d bodyRect: paintedBody
    property vector4d bodyCorner: _corners(Theme.connectedSurfaceRadius, Theme.connectedSurfaceRadius, 0)
}
