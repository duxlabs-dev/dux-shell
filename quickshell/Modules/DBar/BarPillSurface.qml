import QtQuick
import qs.Common

Rectangle {
    id: root

    property real thickness: Math.min(width, height)
    property string style: "pills"
    property bool vertical: false
    property bool joinedStart: false
    property bool joinedEnd: false
    property bool pressed: false
    property real pressProgress: pressed ? 1 : 0
    property real joinedStartProgress: joinedStart ? 1 : 0
    property real joinedEndProgress: joinedEnd ? 1 : 0
    property real radiusOverride: -1
    readonly property bool mirrored: !vertical && LayoutMirroring.enabled
    readonly property real freeRadius: radiusOverride >= 0 ? radiusOverride : BarMetrics.cornerRadius(thickness, style, false, pressProgress)
    readonly property real joinedRadius: BarMetrics.cornerRadius(thickness, style, true, pressProgress)
    readonly property real startRadius: freeRadius + (joinedRadius - freeRadius) * (mirrored ? joinedEndProgress : joinedStartProgress)
    readonly property real endRadius: freeRadius + (joinedRadius - freeRadius) * (mirrored ? joinedStartProgress : joinedEndProgress)

    radius: freeRadius
    topLeftRadius: startRadius
    topRightRadius: vertical ? startRadius : endRadius
    bottomLeftRadius: vertical ? endRadius : startRadius
    bottomRightRadius: endRadius

    Behavior on pressProgress {
        enabled: !Theme.reduceMotion && !Theme.springMotionDisabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    Behavior on joinedStartProgress {
        enabled: !Theme.reduceMotion && !Theme.springMotionDisabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    Behavior on joinedEndProgress {
        enabled: !Theme.reduceMotion && !Theme.springMotionDisabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }
}
