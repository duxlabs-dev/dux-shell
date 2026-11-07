import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.DCommon.Widgets
import "../../../Common/IslandKit.js" as Kit

// Icon inside a progress ring; without progress it is the bare icon.
Item {
    id: root

    property string iconName: ""
    property real progress: -1

    // A plain Item has no value interface: the percent is read as its description (the face names the activity).
    Accessible.role: root.progress >= 0 ? Accessible.ProgressBar : Accessible.Graphic
    Accessible.description: root.progress >= 0 ? Math.round(root.progress * 100) + "%" : ""
    property color accent: Theme.primary
    property color iconColor: root.accent
    property real ringWidth: 3
    // Per side: the stroke and its gap to the icon, so the face keeps one size with or without the ring.
    readonly property real ringInset: root.ringWidth * 2
    property real iconSize: root.progress >= 0 ? Theme.iconSizeSmall : Theme.iconSize
    // The track under the level, faint enough to read as empty (the faces pick a tone that stands off it).
    readonly property real trackAlpha: Kit.readyTrackAlpha

    implicitWidth: Theme.iconSize + root.ringInset * 2
    implicitHeight: implicitWidth

    Shape {
        anchors.fill: parent
        visible: root.progress >= 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.withAlpha(root.accent, root.trackAlpha)
            strokeWidth: root.ringWidth

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: (root.width - root.ringWidth) / 2
                radiusY: radiusX
                startAngle: 0
                sweepAngle: 360
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.accent
            strokeWidth: root.ringWidth
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: (root.width - root.ringWidth) / 2
                radiusY: radiusX
                startAngle: -90
                sweepAngle: 360 * Math.max(0, root.progress)
            }
        }
    }

    DIcon {
        anchors.centerIn: parent
        visible: root.iconName !== ""
        name: root.iconName
        size: root.iconSize
        color: root.iconColor
    }
}
