import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Modules.Sysmon

Item {
    id: root

    property var process: null
    property var appEntry: null
    property color fallbackColor: Theme.chipSurfaceNested
    property color textColor: Theme.surfaceVariantText
    property real radius: Theme.cornerRadiusXS
    property real fontSize: Theme.fontSizeSmall
    property bool mipmap: false
    property bool halo: false

    implicitWidth: ProcessListMetrics.appIconSize
    implicitHeight: implicitWidth

    IconImage {
        id: icon
        anchors.fill: parent
        source: ProcessListMetrics.appIcon(root.process, root.appEntry)
        smooth: true
        mipmap: root.mipmap
        asynchronous: true
        visible: status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        visible: !icon.visible
        radius: root.radius
        color: root.fallbackColor

        MonitorText {
            halo: root.halo
            anchors.centerIn: parent
            text: (root.process?.command ?? "").charAt(0).toUpperCase()
            font.pixelSize: root.fontSize
            font.weight: Theme.fontWeightMedium
            color: root.textColor
        }
    }
}
