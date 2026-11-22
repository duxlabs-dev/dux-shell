pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Sysmon
import "../../Services/ProcessSort.js" as ProcessSort
import "../../Services/SysmonCatalog.js" as SysmonCatalog
import "../../Services/SysmonDevices.js" as Devices

Column {
    id: root

    property string deviceKey: ""
    property string entryType: ""
    property bool active: false
    property string chosenKey: ""

    readonly property int processRows: 4
    readonly property real processRowHeight: Theme.buttonHeightS
    // From six tabs on, side-by-side captions are cut to a letter or two at the popout's width.
    readonly property bool stackedTabs: tabs.length >= 6
    readonly property real tabHeight: stackedTabs ? Theme.buttonHeightM : Theme.buttonHeightS + Theme.spacingXS

    readonly property var own: SysmonService.parseKey(deviceKey)
    readonly property var tabs: SysmonService.popoutDevices(deviceKey)
    readonly property string currentKey: SysmonService.popoutSelection(tabs, chosenKey || deviceKey, entryType)
    readonly property string monitorTarget: currentKey
    readonly property var current: SysmonService.parseKey(currentKey)
    readonly property var gpu: current.type === "gpu" ? SysmonService.gpuFor(current.id) : null
    readonly property bool gpuLive: gpu !== null && gpu.state !== "suspended" && Devices.gpuMonitored(DgopService.gpuPciIds, gpu.pciId, gpu.busId)
    // Per-process GPU use isn't split by device, so it only means something with a single GPU.
    readonly property bool gpuProcesses: gpuLive && SysmonService.hostGpuCount() === 1
    readonly property string sortKey: current.type === "gpu" ? (gpuProcesses ? "gpu" : "") : current.type
    readonly property var modules: {
        const procs = ({
                "cpu": ["processes"],
                "memory": ["processes"],
                "gpu": gpuProcesses ? ["processes", "process-gpu"] : [],
                "disk": ["processes", "process-io"],
                "net": ["processes", "process-net"]
            })[current.type] ?? [];
        const base = SysmonCatalog.paneModules(currentKey);
        const list = base.concat(procs);
        return own.type === "net" && own.id && list.indexOf("net-rate") < 0 ? list.concat("net-rate") : list;
    }
    readonly property var topProcesses: {
        if (!active || sortKey === "")
            return [];
        const value = p => ProcessSort.rawValue(sortKey, p) ?? 0;
        return (DgopService.allProcesses ?? []).filter(p => value(p) > 0).sort((a, b) => value(b) - value(a) || a.pid - b.pid).slice(0, processRows);
    }
    // A rate needs two samples, so for two intervals after a switch every process may still read unknown.
    readonly property bool processesPending: active && sortKey !== "" && pendingTimer.running && (DgopService.allProcesses ?? []).every(p => ProcessSort.rawValue(sortKey, p) === null)

    onSortKeyChanged: pendingTimer.restart()
    onActiveChanged: pendingTimer.restart()

    function selectStep(from, step) {
        const i = Math.max(0, Math.min(tabs.length - 1, from + step));
        chosenKey = tabs[i].key;
        tabRepeater.itemAt(i)?.forceActiveFocus(Qt.TabFocusReason);
    }

    spacing: Theme.spacingM

    Timer {
        id: pendingTimer
        interval: DgopService.updateInterval * 2
        running: true
    }

    Ref {
        service: DgopService
        modules: root.modules
        active: root.active && root.modules.length > 0
    }

    // dgop cuts its list to the top rows of its own sort, so another resource needs the whole list.
    FullProcessListRef {
        active: root.active && root.sortKey !== "" && root.sortKey !== DgopService.dgopSort()
    }

    // A single drive's tab is captioned by its model, which comes from the drive data.
    Ref {
        service: DriveService
        active: root.active && (root.current.type === "disk" || (root.own.type === "disk" && root.own.id !== ""))
    }

    RowLayout {
        width: parent.width
        spacing: Theme.pillControls ? Theme.groupedListGap : Theme.spacingXS
        LayoutMirroring.enabled: I18n.isRtl
        LayoutMirroring.childrenInherit: true
        Accessible.role: Accessible.PageTabList

        Repeater {
            id: tabRepeater

            model: root.tabs.length

            DButtonGroupSegment {
                id: tab

                required property int index
                readonly property var entry: root.tabs[index] ?? ({})

                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: root.tabHeight
                first: index === 0
                last: index === root.tabs.length - 1
                outerRadius: Theme.pillControls && !root.stackedTabs ? Theme.fullRadius(height, height) : Theme.cornerRadiusL
                checked: entry.key === root.currentKey
                focusPolicy: checked ? Qt.StrongFocus : Qt.ClickFocus
                Accessible.role: Accessible.PageTab
                Accessible.name: entry.name ?? ""
                tooltipText: caption.truncated || caption.text !== entry.name ? entry.name ?? "" : ""
                onClicked: root.chosenKey = entry.key
                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Left && event.key !== Qt.Key_Right)
                        return;
                    root.selectStep(index, (event.key === Qt.Key_Right) !== I18n.isRtl ? 1 : -1);
                    event.accepted = true;
                }

                Grid {
                    anchors.centerIn: parent
                    columns: root.stackedTabs ? 1 : 2
                    columnSpacing: Theme.spacingXS
                    rowSpacing: Theme.spacingXXS
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter

                    DeviceIcon {
                        id: tabIcon
                        name: tab.entry.icon ?? ""
                        size: root.stackedTabs ? Theme.iconSize : Theme.iconSizeSmall
                        color: tab.contentColor
                    }

                    StyledText {
                        id: caption
                        width: Math.min(Math.ceil(implicitWidth), tab.width - Theme.spacingS * 2 - (root.stackedTabs ? 0 : tabIcon.width + Theme.spacingXS))
                        text: tab.entry.gpu ? Devices.shortGpuName(tab.entry.gpu.displayName || tab.entry.name) : tab.entry.name || ""
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: tab.contentColor
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }
        }
    }

    DevicePaneLoader {
        width: parent.width
        height: implicitHeight
        active: root.active
        key: root.currentKey
        variant: "device"
    }

    // A GPU without per-process data gets no process section rather than an empty one.
    SettingsSectionLabel {
        visible: root.sortKey !== ""
        text: I18n.tr("Top processes", "system monitor popout: processes using the most of the shown device")
        topGap: 0
        bottomGap: 0
    }

    Item {
        visible: root.sortKey !== ""
        width: parent.width
        height: root.processRows * root.processRowHeight + (root.processRows - 1) * Theme.groupedListGap

        DSpinner {
            anchors.centerIn: parent
            size: Theme.iconSize
            visible: root.processesPending
        }

        StyledText {
            visible: root.topProcesses.length === 0 && !root.processesPending
            anchors.centerIn: parent
            text: I18n.tr("No matching processes", "empty state in process list")
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
        }

        MonitorProcesses {
            width: parent.width
            meter: true
            rowHeight: root.processRowHeight
            processes: root.topProcesses
            sortBy: root.sortKey
            tileColor: ProcessListMetrics.cardColor
        }
    }
}
