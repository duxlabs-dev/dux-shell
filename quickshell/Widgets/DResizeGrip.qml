import QtQuick
import QtQuick.Shapes
import qs.Common

Shape {
    id: root

    property real gripRadius: 0
    property bool mirrored: false
    readonly property real edgeInset: Theme.spacingS / 2 + Theme.outlineWidthFocused / 2
    readonly property real armLength: Math.max(gripRadius, Theme.spacingM)

    preferredRendererType: Shape.CurveRenderer

    transform: Scale {
        origin.x: root.width / 2
        xScale: root.mirrored ? -1 : 1
    }

    ShapePath {
        strokeColor: Theme.primary
        strokeWidth: Theme.spacingS
        capStyle: ShapePath.RoundCap
        fillColor: "transparent"

        PathMove {
            x: root.width - root.edgeInset
            y: root.height - root.edgeInset - root.armLength
        }
        PathLine {
            x: root.width - root.edgeInset
            y: root.height - root.edgeInset - root.gripRadius
        }
        PathArc {
            x: root.width - root.edgeInset - root.gripRadius
            y: root.height - root.edgeInset
            radiusX: root.gripRadius
            radiusY: root.gripRadius
        }
        PathLine {
            x: root.width - root.edgeInset - root.armLength
            y: root.height - root.edgeInset
        }
    }
}
