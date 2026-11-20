import QtQuick
import qs.Common
import qs.Modules.Sysmon

Rectangle {
    id: root

    property real fraction: 0
    property color fillColor: Theme.primary
    property bool primary: true
    property bool vertical: false

    radius: Theme.fullRadius(width, height)

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: root.vertical ? parent.width : parent.width * root.fraction
        height: root.vertical ? parent.height * root.fraction : parent.height
        radius: parent.radius
        color: root.fillColor
        opacity: root.primary ? 1 : MonitorMetrics.secondaryFillOpacity

        MeterBehavior on width {}
        MeterBehavior on height {}
    }
}
