pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Common

Item {
    id: root

    property string corner
    property real implicitSize: Theme.cornerRadiusL
    property color color: Theme.screenOffColor

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    readonly property bool isTop: corner === "topLeft" || corner === "topRight"
    readonly property bool isBottom: corner === "bottomLeft" || corner === "bottomRight"
    readonly property bool isLeft: corner === "topLeft" || corner === "bottomLeft"
    readonly property bool isRight: corner === "topRight" || corner === "bottomRight"

    Shape {
        anchors {
            top: root.isTop ? parent.top : undefined
            bottom: root.isBottom ? parent.bottom : undefined
            left: root.isLeft ? parent.left : undefined
            right: root.isRight ? parent.right : undefined
        }
        layer.enabled: true
        layer.smooth: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: shapePath
            strokeWidth: 0
            fillColor: root.color
            pathHints: ShapePath.PathSolid & ShapePath.PathNonIntersecting

            startX: switch (root.corner) {
            case "topLeft":
            case "bottomLeft": return 0;
            case "topRight":
            case "bottomRight": return root.implicitSize;
            }
            startY: switch (root.corner) {
            case "topLeft":
            case "topRight": return 0;
            case "bottomLeft":
            case "bottomRight": return root.implicitSize;
            }
            PathAngleArc {
                moveToStart: false
                centerX: root.implicitSize - shapePath.startX
                centerY: root.implicitSize - shapePath.startY
                radiusX: root.implicitSize
                radiusY: root.implicitSize
                startAngle: switch (root.corner) {
                case "topLeft": return 180;
                case "topRight": return -90;
                case "bottomLeft": return 90;
                case "bottomRight": return 0;
                }
                sweepAngle: 90
            }
            PathLine {
                x: shapePath.startX
                y: shapePath.startY
            }
        }
    }
}
