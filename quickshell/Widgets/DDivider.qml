import QtQuick
import qs.Common

Item {
    id: root

    property bool vertical: false
    property real thickness: Theme.dividerWidth
    property real inset: 0
    property color color: Theme.outlineVariant

    width: vertical ? thickness : (parent ? parent.width : 0)
    height: vertical ? (parent ? parent.height : 0) : thickness
    implicitWidth: vertical ? thickness : 0
    implicitHeight: vertical ? 0 : thickness

    Rectangle {
        anchors.centerIn: parent
        width: root.vertical ? root.thickness : Math.max(0, root.width - root.inset * 2)
        height: root.vertical ? Math.max(0, root.height - root.inset * 2) : root.thickness
        color: root.color
    }
}
