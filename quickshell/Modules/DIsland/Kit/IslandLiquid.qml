pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Common
import "../../../Common/IslandKit.js" as Kit

// The front slops only while the fill spring moves, so a settled meter draws nothing new.
Item {
    id: liquid

    // 0..1, where the liquid is heading (NaN reads as empty, IslandKit.unit).
    property real level: 0
    property color color: Theme.primary
    property real radius: 0
    readonly property bool still: Theme.currentAnimationBaseDuration <= 0 || SettingsData.reduceMotion
    readonly property real line: liquid.height * (1 - Math.max(0, Math.min(1, fill.value)))
    readonly property real amp: liquid.still ? 0 : Math.min(Theme.spacingS, Math.abs(fill.velocity) * Theme.spacingM)
    // Half-turns of the front's wave from empty to full: its travel as it fills.
    readonly property real fillHalfTurns: 4
    readonly property real phase: fill.value * Math.PI * liquid.fillHalfTurns

    // Five points across the front (d = 1, 0.5, 0, 0.5, 1) joined by cubics from the wave's slope: numbers only, no array
    // per frame.
    readonly property real quarter: liquid.width / 4
    readonly property real y0: liquid.line - Kit.wave(1, liquid.amp, liquid.phase)
    readonly property real y1: liquid.line - Kit.wave(0.5, liquid.amp, liquid.phase)
    readonly property real y2: liquid.line - Kit.wave(0, liquid.amp, liquid.phase)
    // dy/dx on the left half (d falls as x grows); the right half mirrors it.
    function slope(d) {
        return Kit.waveSlope(d, liquid.amp, liquid.phase) * 2 / Math.max(1, liquid.width);
    }
    readonly property real s0: liquid.slope(1)
    readonly property real s1: liquid.slope(0.5)
    readonly property real s2: liquid.slope(0)

    // Under this level the liquid is a hairline: nothing is drawn.
    readonly property real emptyLevel: 0.001

    visible: fill.value > liquid.emptyLevel

    SpringMotion {
        id: fill

        readonly property var spec: Kit.spring("fill", Theme.currentAnimationBaseDuration)
        enabled: !liquid.still
        stiffness: spec.stiffness
        damping: spec.damping
        mass: spec.mass
        // Settles (and its frame loop stops) once the front is within half a pixel and its wave under half a pixel.
        positionEpsilon: 0.5 / Math.max(1, liquid.height)
        velocityEpsilon: 0.5 / Theme.spacingM
    }
    onLevelChanged: fill.retarget(Kit.unit(liquid.level))
    Component.onCompleted: fill.snapTo(Kit.unit(liquid.level))

    Rectangle {
        id: mask

        anchors.fill: parent
        radius: liquid.radius
        color: "black"
        visible: false
        layer.enabled: liquid.visible
    }

    Shape {
        id: body

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: liquid.visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            // Soft mask edge instead of a stair-stepped cut.
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        ShapePath {
            fillColor: liquid.color
            strokeColor: "transparent"
            strokeWidth: 0
            startX: 0
            startY: liquid.height

            PathLine {
                x: 0
                y: liquid.y0
            }
            PathCubic {
                x: liquid.quarter
                y: liquid.y1
                control1X: liquid.quarter / 3
                control1Y: liquid.y0 + liquid.s0 * liquid.quarter / 3
                control2X: liquid.quarter * 2 / 3
                control2Y: liquid.y1 - liquid.s1 * liquid.quarter / 3
            }
            PathCubic {
                x: liquid.quarter * 2
                y: liquid.y2
                control1X: liquid.quarter * 4 / 3
                control1Y: liquid.y1 + liquid.s1 * liquid.quarter / 3
                control2X: liquid.quarter * 5 / 3
                control2Y: liquid.y2 - liquid.s2 * liquid.quarter / 3
            }
            PathCubic {
                x: liquid.quarter * 3
                y: liquid.y1
                control1X: liquid.quarter * 7 / 3
                control1Y: liquid.y2 - liquid.s2 * liquid.quarter / 3
                control2X: liquid.quarter * 8 / 3
                control2Y: liquid.y1 + liquid.s1 * liquid.quarter / 3
            }
            PathCubic {
                x: liquid.width
                y: liquid.y0
                control1X: liquid.quarter * 10 / 3
                control1Y: liquid.y1 - liquid.s1 * liquid.quarter / 3
                control2X: liquid.quarter * 11 / 3
                control2Y: liquid.y0 + liquid.s0 * liquid.quarter / 3
            }
            PathLine {
                x: liquid.width
                y: liquid.height
            }
        }
    }
}
