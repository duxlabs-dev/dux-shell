pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Modules.ProcessList
import qs.Modules.Sysmon

Column {
    id: root

    property var processes: []
    property string sortBy: "cpu"
    property color tileColor: Theme.surfaceContainerLow
    property color contentColor: Theme.surfaceText
    property color mutedColor: Theme.surfaceVariantText
    property bool halo: false

    readonly property real cpuWidth: Theme.fontSizeSmall * 6
    readonly property real memoryWidth: Theme.fontSizeSmall * 8

    spacing: Theme.groupedListGap

    Repeater {
        model: root.processes.length

        Rectangle {
            id: row

            required property int index
            readonly property var modelData: root.processes[index] ?? ({})
            readonly property var entry: ProcessListMetrics.appEntry(modelData)
            readonly property string name: ProcessListMetrics.displayName(modelData, entry)

            width: root.width
            height: MonitorMetrics.processRowHeight
            color: root.tileColor
            radius: Theme.groupedListInnerRadius
            topLeftRadius: index === 0 ? Theme.groupedListOuterRadius : radius
            topRightRadius: topLeftRadius
            bottomLeftRadius: index === root.processes.length - 1 ? Theme.groupedListOuterRadius : radius
            bottomRightRadius: bottomLeftRadius
            Accessible.role: Accessible.StaticText
            Accessible.name: name + " " + cpuText.text + " " + memoryText.text

            IconImage {
                id: appIcon
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                width: ProcessListMetrics.appIconSize
                height: width
                source: ProcessListMetrics.appIcon(row.modelData, row.entry)
                smooth: true
                asynchronous: true
                visible: status === Image.Ready
            }

            Rectangle {
                anchors.fill: appIcon
                visible: !appIcon.visible
                radius: Theme.cornerRadiusXS
                color: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)

                MonitorText {
                    halo: root.halo
                    anchors.centerIn: parent
                    text: (row.modelData.command ?? "").charAt(0).toUpperCase()
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: root.mutedColor
                }
            }

            MonitorText {
                halo: root.halo
                anchors.left: appIcon.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: cpuText.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: row.name
                font.pixelSize: Theme.fontSizeSmall
                color: root.contentColor
                textFormat: Text.PlainText
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            MonitorText {
                id: cpuText
                halo: root.halo
                anchors.right: memoryText.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.cpuWidth
                horizontalAlignment: Text.AlignRight
                text: (row.modelData.cpu ?? 0).toFixed(1) + "%"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: root.sortBy === "cpu" ? Theme.fontWeightMedium : Font.Normal
                font.features: {
                    "tnum": 1
                }
                color: root.sortBy === "cpu" ? root.contentColor : root.mutedColor
            }

            MonitorText {
                id: memoryText
                halo: root.halo
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                width: root.memoryWidth
                horizontalAlignment: Text.AlignRight
                text: DgopService.formatSystemMemory(row.modelData.memoryKB)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: root.sortBy === "memory" ? Theme.fontWeightMedium : Font.Normal
                font.features: {
                    "tnum": 1
                }
                color: root.sortBy === "memory" ? root.contentColor : root.mutedColor
            }
        }
    }
}
