pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import "../../Services/SysmonDevices.js" as Devices
import "ProcessColumns.js" as ProcessColumns

// The pressed tile is the resource the process list is sorted by.
RowLayout {
    id: root

    property string deviceKey: ""
    property string entryType: ""
    property bool active: false

    // The GPU of the opened device when it is one, else the first listed GPU.
    readonly property var gpuEntry: {
        const own = entryType === "gpu" ? SysmonService.device(deviceKey) : null;
        const first = (DgopService.availableGpus ?? [])[0];
        return own ?? (first ? SysmonService.gpuEntry(first) : null);
    }
    readonly property bool hasGpu: gpuEntry !== null
    readonly property var types: hasGpu ? ["cpu", "memory", "gpu", "disk", "net"] : ["cpu", "memory", "disk", "net"]
    readonly property var sortOf: ({
            "cpu": "cpu",
            "memory": "memory",
            "gpu": "gpu",
            "disk": "diskRead",
            "net": "netRx"
        })
    readonly property string sortType: ProcessColumns.deviceType(DgopService.currentSort)

    spacing: Theme.pillControls ? Theme.groupedListGap : Theme.spacingXS
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Ref {
        service: DgopService
        modules: ["disk", "network"]
        active: root.active
    }

    Repeater {
        model: root.types.length

        DButtonGroupSegment {
            id: tile

            required property int index

            readonly property string type: root.types[index]
            readonly property var entry: type === "gpu" ? root.gpuEntry : SysmonService.device(type)
            readonly property var summary: SysmonService.summary(entry)
            readonly property string value: type === "memory" && DgopService.memoryInfo !== null ? Math.round(DgopService.memoryUsage) + "%" : summary.value ?? ""
            readonly property string detail: type === "memory" ? summary.value : summary.valueTooltip ?? ""
            readonly property bool blocked: type === "gpu" && (entry?.gpu?.state === "suspended" || !Devices.gpuMonitored(DgopService.gpuPciIds, entry?.gpu?.pciId, entry?.gpu?.busId))

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitHeight: Theme.buttonHeightM
            first: index === 0
            last: index === root.types.length - 1
            outerRadius: Theme.cornerRadiusL
            checked: type === root.sortType
            enabled: !blocked
            selectedColor: Theme.primaryContainer
            selectedContentColor: Theme.onPrimaryContainer
            unselectedColor: ProcessListMetrics.cardColor
            unselectedContentColor: Theme.surfaceText
            Accessible.name: SysmonService.typeName(type) + ", " + value
            Accessible.description: detail
            clip: true
            onClicked: DgopService.setSortBy(root.sortOf[type])
            onHoveredChanged: hovered && detail ? tip.schedule() : tip.dismiss()

            DTooltipHost {
                id: tip
                text: tile.detail
                multiline: true
                target: tile
            }

            MetricChart {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: tile.startRadius
                anchors.rightMargin: tile.endRadius
                anchors.bottom: parent.bottom
                height: Theme.iconSize
                compact: true
                values: tile.summary.values ?? []
                maximum: tile.summary.maximum ?? 0
                historyLength: DgopService.historySize
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingS
                anchors.bottomMargin: 0

                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingXS

                    DeviceIcon {
                        name: tile.entry.icon
                        size: Theme.iconSizeSmall
                        color: tile.contentColor
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: SysmonService.typeName(tile.type)
                        font.pixelSize: Theme.fontSizeSmall
                        color: tile.contentColor
                        elide: Text.ElideRight
                    }
                }

                NumericText {
                    width: parent.width
                    text: tile.value
                    reserveText: "000.0 MB/s"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: tile.contentColor
                    elide: Text.ElideRight
                }
            }
        }
    }
}
