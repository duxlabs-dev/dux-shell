pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import "../../Common/ConnectedSurfaceGeometry.js" as SurfaceGeometry

// Paints the satellites and the popout opened from them as one shape in the bar's own window.
ShaderEffect {
    id: root

    required property Item leading
    required property Item trailing
    required property string screenName
    required property string barSide
    required property real originX
    required property real originY
    required property real dpr
    required property color fillColor
    required property real edgeRadius
    required property real cornerRadius

    readonly property bool horizontal: barSide === "top" || barSide === "bottom"
    readonly property real joinRadius: edgeRadius > 0 ? edgeRadius : Theme.connectedCornerRadius
    readonly property var descriptor: {
        ConnectedModeState.surfaceRevisions[screenName];
        return ConnectedModeState.surfaceDescriptor(screenName, "popout");
    }
    readonly property bool popoutActive: descriptor.visible && descriptor.barSide === barSide
    readonly property var body: popoutActive ? SurfaceGeometry.animatedBodyRect(descriptor, dpr) : ({
            "x": 0,
            "y": 0,
            "width": 0,
            "height": 0
        })
    // How far the popout has come out of the bar; a satellite reaches for its edge over the first stretch of that.
    readonly property real seamOverlap: 2
    readonly property real emerged: Math.max(0, Math.min(1, ((horizontal ? body.height : body.width) - seamOverlap) / Math.max(1, joinRadius * 2)))

    function _alongStart(rect) {
        return horizontal ? rect.x : rect.y;
    }

    function _alongEnd(rect) {
        return horizontal ? rect.x + rect.width : rect.y + rect.height;
    }

    function _farCorners(startRadius, endRadius) {
        switch (barSide) {
        case "bottom":
            return Qt.vector4d(startRadius, endRadius, 0, 0);
        case "left":
            return Qt.vector4d(0, startRadius, endRadius, 0);
        case "right":
            return Qt.vector4d(startRadius, 0, 0, endRadius);
        default:
            return Qt.vector4d(0, 0, endRadius, startRadius);
        }
    }

    function _rectOf(surface) {
        return {
            "x": originX + surface.x,
            "y": originY + surface.y,
            "width": surface.width,
            "height": surface.height
        };
    }

    // The satellite the popout hangs from.
    readonly property var anchor: {
        for (const surface of [leading, trailing]) {
            if (!surface.visible)
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

    // Where the popout runs past a satellite they share one straight edge, and a fillet there would bulge out of it.
    function _joinRadius(passed) {
        return Math.min(passed ? joinRadius * (1 - emerged) : joinRadius, horizontal ? body.height : body.width);
    }

    function _satellite(surface) {
        if (!surface.visible)
            return {
                "rect": Qt.vector4d(0, 0, 0, 0),
                "corner": Qt.vector4d(0, 0, 0, 0)
            };
        const rect = _rectOf(surface);
        const limit = horizontal ? width : height;
        let start = _alongStart(rect);
        let end = _alongEnd(rect);
        let startRadius = start <= 1 ? 0 : cornerRadius;
        let endRadius = end >= limit - 1 ? 0 : cornerRadius;
        const bodyStart = _alongStart(body);
        const bodyEnd = _alongEnd(body);
        if (emerged > 0 && bodyStart < end && bodyEnd > start) {
            if (bodyStart <= start) {
                start += (bodyStart - start) * emerged;
                startRadius *= 1 - emerged;
            }
            if (bodyEnd >= end) {
                end += (bodyEnd - end) * emerged;
                endRadius *= 1 - emerged;
            }
        }
        return {
            "rect": horizontal ? Qt.vector4d(start, rect.y, end - start, rect.height) : Qt.vector4d(rect.x, start, rect.width, end - start),
            "corner": _farCorners(startRadius, endRadius)
        };
    }

    readonly property var _lead: _satellite(leading)
    readonly property var _trail: _satellite(trailing)
    readonly property var _level: Theme.elevationLevel2
    readonly property bool _shadow: Theme.elevationEnabled && SettingsData.popoutElevationEnabled
    readonly property color _shadowTint: Theme.elevationShadowColor(_level)
    readonly property var _ambient: Theme.elevationAmbient(_level)

    fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/island_chrome.frag.qsb")

    property real widthPx: width
    property real heightPx: height
    property vector4d surfaceColor: Qt.vector4d(fillColor.r, fillColor.g, fillColor.b, fillColor.a)
    property vector4d shadowColor: Qt.vector4d(_shadowTint.r, _shadowTint.g, _shadowTint.b, _shadow && popoutActive ? _shadowTint.a : 0)
    property vector4d shadowParam: Qt.vector4d(Math.max(0, _level.blurPx), Math.max(0, _level.spreadPx), Theme.elevationOffsetXFor(_level, Theme.elevationLightDirection, 4), Theme.elevationOffsetYFor(_level, Theme.elevationLightDirection, 4))
    property vector4d ambientParam: Qt.vector4d(_ambient.blurPx, _ambient.spreadPx, _shadow && popoutActive ? _ambient.alpha : 0, 0)
    property vector4d edgeParam: Qt.vector4d(barSide === "top" ? 0 : (barSide === "bottom" ? 1 : (barSide === "left" ? 2 : 3)), edgeRadius, _joinRadius(passesStart), _joinRadius(passesEnd))
    property vector4d leadRect: _lead.rect
    property vector4d leadCorner: _lead.corner
    property vector4d trailRect: _trail.rect
    property vector4d trailCorner: _trail.corner
    property vector4d bodyRect: paintedBody
    property vector4d bodyCorner: _farCorners(Theme.connectedSurfaceRadius, Theme.connectedSurfaceRadius)
}
