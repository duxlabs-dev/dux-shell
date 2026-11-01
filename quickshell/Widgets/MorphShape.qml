import "../DCommon/Widgets/MaterialShapes.js" as Shapes
import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    property string fromShape: "circle"
    property string toShape: "circle"
    property color color: Theme.primary
    property real progress: 0

    readonly property int samples: 128
    readonly property real clampedProgress: Math.max(0, Math.min(1, progress))
    readonly property bool morphing: clampedProgress > 0 && clampedProgress < 1 && Theme.shapeScale !== 0
    readonly property var fromProfile: Shapes.polarProfile(fromShape, samples)
    readonly property var toProfile: Shapes.polarProfile(toShape, samples)
    readonly property var outline: {
        if (!morphing)
            return [];
        const size = Math.min(width, height);
        const points = [];
        for (let i = 0; i <= samples; i++) {
            const index = i % samples;
            const angle = -Math.PI + 2 * Math.PI * index / samples;
            const radius = (fromProfile[index] + (toProfile[index] - fromProfile[index]) * clampedProgress) * size;
            points.push(Qt.point(width / 2 + Math.cos(angle) * radius, height / 2 + Math.sin(angle) * radius));
        }
        return points;
    }

    DMaterialShape {
        anchors.fill: parent
        shape: root.clampedProgress >= 1 ? root.toShape : root.fromShape
        color: root.color
        visible: !root.morphing
    }

    Shape {
        anchors.fill: parent
        visible: root.morphing
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: root.color

            PathPolyline {
                path: root.outline
            }
        }
    }
}
