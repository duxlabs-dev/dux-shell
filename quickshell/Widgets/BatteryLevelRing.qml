import QtQuick
import QtQuick.Shapes
import qs.Common
import "../Common/BatteryGauge.js" as BatteryGauge

Item {
    id: root

    property real value: 0
    property real limit: 100
    property bool charging: false
    property bool wavy: true
    property color fillColor: Theme.primary
    property color trackColor: Theme.secondaryContainer
    property real strokeWidth: 4
    // Qt angles: 0 is 3 o'clock, clockwise
    property real startAngle: -90
    property real spanAngle: 360
    property bool moving: true

    default property alias content: inner.data

    readonly property real wavelength: 15
    readonly property real waveAmplitude: 1.6
    readonly property real inset: 6
    readonly property real segmentGap: 8
    readonly property real markerReach: 6
    readonly property real dimOpacity: 0.5
    readonly property real size: Math.min(root.width, root.height)
    readonly property real radius: Math.max(1, root.size / 2 - root.inset)
    readonly property real centerX: root.width / 2
    readonly property real centerY: root.height / 2
    readonly property bool waveOn: BatteryGauge.waveActive(root.value, root.charging, root.wavy)

    property real phase: 0
    property real shownValue: root.value
    property real currentAmp: root.waveOn ? root.waveAmplitude : 0
    readonly property bool waving: root.currentAmp > 0.01
    readonly property var layout: BatteryGauge.ringLayout(root.shownValue, root.spanAngle, root.radius, root.limit, root.segmentGap)
    readonly property var fillPath: root.layout.hasFill && root.waving ? BatteryGauge.arcPoints(root.centerX, root.centerY, root.radius, root.startAngle, root.layout.fillSpan, root.currentAmp, BatteryGauge.waveCount(root.radius, root.wavelength), root.phase, root.wavelength).map(p => Qt.point(p.x, p.y)) : []
    readonly property real markerAngle: (root.startAngle + root.layout.limitAt) * Math.PI / 180

    Behavior on shownValue {
        enabled: !Theme.reduceMotion
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveSlowEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveSlowEffects
        }
    }

    Behavior on currentAmp {
        enabled: !Theme.reduceMotion
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveSlowEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveSlowEffects
        }
    }

    Timer {
        interval: Timing.cappedTick
        repeat: true
        running: root.moving && root.visible && (root.Window.window?.visible ?? false) && root.waveOn && !Theme.reduceMotion
        onTriggered: root.phase = (root.phase + 2 * Math.PI * interval / 1000) % (2 * Math.PI)
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.layout.trackFrom < root.layout.trackTo ? root.trackColor : "transparent"
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.centerX
                centerY: root.centerY
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.startAngle + root.layout.trackFrom
                sweepAngle: Math.max(0, root.layout.trackTo - root.layout.trackFrom)
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.layout.limited && root.layout.dimFrom < root.layout.dimTo ? Theme.withAlpha(root.trackColor, root.trackColor.a * root.dimOpacity) : "transparent"
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.centerX
                centerY: root.centerY
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.startAngle + root.layout.dimFrom
                sweepAngle: Math.max(0, root.layout.dimTo - root.layout.dimFrom)
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.layout.limited ? root.fillColor : "transparent"
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.RoundCap
            startX: root.centerX + Math.cos(root.markerAngle) * (root.radius - root.markerReach)
            startY: root.centerY + Math.sin(root.markerAngle) * (root.radius - root.markerReach)

            PathLine {
                x: root.centerX + Math.cos(root.markerAngle) * (root.radius + root.markerReach)
                y: root.centerY + Math.sin(root.markerAngle) * (root.radius + root.markerReach)
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.layout.hasFill && !root.waving ? root.fillColor : "transparent"
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.centerX
                centerY: root.centerY
                radiusX: root.radius
                radiusY: root.radius
                startAngle: root.startAngle
                sweepAngle: root.layout.fillSpan
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.layout.hasFill && root.waving ? root.fillColor : "transparent"
            strokeWidth: root.strokeWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathPolyline {
                path: root.fillPath
            }
        }
    }

    Item {
        id: inner

        anchors.centerIn: parent
        width: Math.max(0, 2 * (root.radius - root.strokeWidth / 2))
        height: width
    }
}
