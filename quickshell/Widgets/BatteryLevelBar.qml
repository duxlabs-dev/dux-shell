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
    property real strokeWidth: 8
    property bool moving: true

    readonly property real wavelength: 40
    readonly property real waveAmplitude: root.strokeWidth >= 8 ? 3 : 2
    readonly property real waveRoom: 8
    readonly property real segmentGap: 5
    readonly property real markerWidth: 4
    readonly property real dimOpacity: 0.5
    readonly property bool mirrored: root.LayoutMirroring.enabled
    readonly property bool waveOn: BatteryGauge.waveActive(root.value, root.charging, root.wavy)
    readonly property real centerY: root.height / 2

    property real phase: 0
    property real shownValue: root.value
    property real currentAmp: root.waveOn ? root.waveAmplitude : 0
    readonly property var layout: BatteryGauge.barLayout(root.shownValue, root.width, root.strokeWidth, root.limit, root.segmentGap)
    readonly property var fillPath: root.layout.hasFill ? BatteryGauge.linePoints(root.layout.fillFrom, root.layout.fillEnd, root.centerY, root.currentAmp, root.wavelength, root.phase).map(p => Qt.point(p.x, p.y)) : []

    width: root.parent ? root.parent.width : 0
    implicitHeight: root.strokeWidth + root.waveRoom

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

    Item {
        id: canvas

        anchors.fill: parent
        transform: Scale {
            origin.x: canvas.width / 2
            xScale: root.mirrored ? -1 : 1
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.layout.trackFrom < root.layout.trackTo ? root.trackColor : "transparent"
                strokeWidth: root.strokeWidth
                capStyle: ShapePath.RoundCap
                startX: root.layout.trackFrom
                startY: root.centerY

                PathLine {
                    x: root.layout.trackTo
                    y: root.centerY
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.layout.limited && root.layout.dimFrom < root.layout.dimTo ? Theme.withAlpha(root.trackColor, root.trackColor.a * root.dimOpacity) : "transparent"
                strokeWidth: root.strokeWidth
                capStyle: ShapePath.RoundCap
                startX: root.layout.dimFrom
                startY: root.centerY

                PathLine {
                    x: root.layout.dimTo
                    y: root.centerY
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.layout.hasFill ? root.fillColor : "transparent"
                strokeWidth: root.strokeWidth
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                PathPolyline {
                    path: root.fillPath
                }
            }
        }

        Rectangle {
            visible: root.layout.limited
            x: root.layout.limitX - width / 2
            width: root.markerWidth
            height: root.height
            radius: width / 2
            color: root.fillColor
        }

        Rectangle {
            visible: root.layout.showStop
            x: root.layout.stopX - width / 2
            y: root.centerY - height / 2
            width: root.strokeWidth / 2
            height: width
            radius: width / 2
            color: root.fillColor
        }
    }
}
