import QtQuick
import qs.Common
import qs.Modules.DBar
import qs.DCommon.Widgets

Item {
    id: root

    property Item target: null
    property bool vertical: false
    property string barStyle: "pills"
    property real roundness: -1

    property Item goal: null
    property rect origin: Qt.rect(0, 0, 0, 0)
    property bool originShaped: false
    property string originShape: "circle"
    property int direction: 1
    property real travel: 1

    readonly property real quarterTurn: 90
    // the curve renderer leaves ragged edges at indicator size, so the shapes render oversized and filter down
    readonly property int supersampling: 4
    readonly property real shapeSize: Math.min(width, height)
    readonly property size shapeTextureSize: Qt.size(Math.ceil(shapeSize * supersampling), Math.ceil(shapeSize * supersampling))
    readonly property real progress: Math.max(0, Math.min(1, travel))
    readonly property bool goalShaped: goal?.indicatorShaped ?? false
    readonly property real goalWidth: goal?.indicatorWidth ?? 0
    readonly property real goalHeight: goal?.indicatorHeight ?? 0
    readonly property real goalX: goal ? goal.x + (goal.width - goalWidth) / 2 + (vertical ? 0 : goal.indicatorShift) : 0
    readonly property real goalY: goal ? goal.y + (goal.height - goalHeight) / 2 + (vertical ? goal.indicatorShift : 0) : 0
    readonly property real pillOpacity: (originShaped ? 0 : 1 - progress) + (goalShaped ? 0 : progress)
    readonly property color color: goal?.activeColor ?? Theme.primary

    function between(from, to) {
        return from + (to - from) * travel;
    }

    x: between(origin.x, goalX)
    y: between(origin.y, goalY)
    width: between(origin.width, goalWidth)
    height: between(origin.height, goalHeight)
    visible: goal?.isActive ?? false

    onTargetChanged: {
        if (!target)
            return;
        travelAnimation.stop();
        if (!goal || SettingsData.reduceMotion) {
            goal = target;
            travel = 1;
            return;
        }
        const shown = Qt.rect(x, y, width, height);
        originShaped = goal.indicatorShaped;
        originShape = goal.indicatorShape;
        origin = shown;
        travel = 0;
        goal = target;
        direction = (vertical ? goalY >= shown.y : goalX >= shown.x) ? 1 : -1;
        travelAnimation.start();
    }

    NumberAnimation {
        id: travelAnimation
        target: root
        property: "travel"
        from: 0
        to: 1
        duration: Theme.expressiveDurations.expressiveFastSpatial
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
    }

    BarPillSurface {
        anchors.fill: parent
        style: root.barStyle
        radiusOverride: BarMetrics.indicatorRadius("expressive", thickness, root.roundness)
        color: root.color
        opacity: root.pillOpacity
        visible: opacity > 0
    }

    DMaterialShape {
        anchors.centerIn: parent
        width: root.shapeSize
        height: root.shapeSize
        layer.enabled: true
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: root.shapeTextureSize
        shape: root.originShape
        color: root.color
        opacity: root.originShaped ? Math.min(1, 2 - 2 * root.progress) : 0
        visible: opacity > 0
        rotation: root.travel * root.quarterTurn * root.direction
    }

    DMaterialShape {
        anchors.centerIn: parent
        width: root.shapeSize
        height: root.shapeSize
        layer.enabled: true
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: root.shapeTextureSize
        shape: root.goal?.indicatorShape ?? "circle"
        color: root.color
        opacity: root.goalShaped ? Math.min(1, 2 * root.progress) : 0
        visible: opacity > 0
        rotation: (root.travel - 1) * root.quarterTurn * root.direction
    }
}
