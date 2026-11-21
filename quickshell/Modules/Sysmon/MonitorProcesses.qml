pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.ProcessList
import qs.Modules.Sysmon
import "../ProcessList/ProcessColumns.js" as ProcessColumns
import "../../Services/ProcessSort.js" as ProcessSort
import "../../Common/Format.js" as Format

Column {
    id: root

    property var processes: []
    property string sortBy: "cpu"
    property color tileColor: Theme.surfaceContainerLow
    property color contentColor: Theme.surfaceText
    property color mutedColor: Theme.surfaceVariantText
    property bool halo: false
    // One sortBy value per row with a meter scaled to the largest, instead of CPU and memory.
    property bool meter: false
    property real rowHeight: MonitorMetrics.processRowHeight

    readonly property real cpuWidth: Theme.fontSizeSmall * 6
    readonly property real memoryWidth: Theme.fontSizeSmall * 8
    readonly property real meterNameWidth: Theme.fontSizeSmall * 12
    readonly property real meterValueWidth: Theme.fontSizeSmall * 7
    readonly property real meterMaximum: meter ? processes.reduce((m, p) => Math.max(m, meterValue(p)), 0) : 0

    function meterValue(process) {
        return ProcessSort.rawValue(sortBy, process ?? {}) ?? 0;
    }

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
            height: root.rowHeight
            color: root.tileColor
            radius: Theme.groupedListInnerRadius
            topLeftRadius: index === 0 ? Theme.groupedListOuterRadius : radius
            topRightRadius: topLeftRadius
            bottomLeftRadius: index === root.processes.length - 1 ? Theme.groupedListOuterRadius : radius
            bottomRightRadius: bottomLeftRadius
            Accessible.role: Accessible.StaticText
            Accessible.name: name + " " + (root.meter ? meterText.text : cpuText.text + " " + memoryText.text)

            ProcessAppIcon {
                id: appIcon
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                process: row.modelData
                appEntry: row.entry
                fallbackColor: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)
                textColor: root.mutedColor
                halo: root.halo
            }

            MonitorText {
                halo: root.halo
                anchors.left: appIcon.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: root.meter ? track.left : cpuText.left
                anchors.rightMargin: root.meter ? Theme.spacingM : Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: row.name
                font.pixelSize: Theme.fontSizeSmall
                color: root.contentColor
                textFormat: Text.PlainText
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            MonitorTrack {
                id: track
                visible: root.meter
                anchors.left: appIcon.right
                anchors.leftMargin: Theme.spacingS + root.meterNameWidth + Theme.spacingM
                anchors.right: meterText.left
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                height: MonitorMetrics.cardBarThickness
                color: Theme.withAlpha(Theme.primary, Theme.stateLayerFocus)
                fraction: root.meterMaximum > 0 ? Math.min(1, root.meterValue(row.modelData) / root.meterMaximum) : 0
            }

            MonitorText {
                id: meterText
                visible: root.meter
                halo: root.halo
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                width: root.meterValueWidth
                horizontalAlignment: Text.AlignRight
                text: !root.meter ? "" : root.sortBy === "gpu" ? root.meterValue(row.modelData).toFixed(1) + "%" : ProcessColumns.formatCell(root.sortBy, row.modelData) ?? "—"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                font.features: {
                    "tnum": 1
                }
                color: root.contentColor
            }

            MonitorText {
                id: cpuText
                visible: !root.meter
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
                visible: !root.meter
                halo: root.halo
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                width: root.memoryWidth
                horizontalAlignment: Text.AlignRight
                text: Format.formatBytes(row.modelData.memoryKB * 1024, true)
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
