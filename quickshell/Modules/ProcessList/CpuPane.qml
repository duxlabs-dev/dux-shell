pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import "../../Services/SysmonDevices.js" as Devices
import "../../Common/Format.js" as Format

DevicePane {
    id: root

    readonly property var info: DgopService.cpuInfo
    readonly property var cache: info?.cache ?? null
    readonly property var freqs: info?.coreFrequencies ?? []
    // MHz; offline CPUs report 0
    readonly property real meanMHz: {
        const online = freqs.filter(f => f > 0);
        return online.length > 0 ? online.reduce((a, b) => a + b, 0) / online.length : 0;
    }
    readonly property real clockMHz: meanMHz > 0 ? meanMHz : DgopService.cpuFrequency
    readonly property int threads: info?.count ?? 0
    readonly property bool perThread: ProcessListMetrics.cpuPerThread && DgopService.perCoreCpuUsage.length > 0

    function ghz(mhz) {
        return mhz > 0 ? (mhz / 1000).toFixed(2) + " GHz" : null;
    }

    function size(bytes) {
        return bytes > 0 ? Format.formatBytes(bytes, true) : null;
    }

    function count(n) {
        return n > 0 ? n.toLocaleString(Qt.locale(), "f", 0) : null;
    }

    loaded: info !== null
    title: I18n.tr("CPU", "processor label in system monitor")
    subtitle: DgopService.cpuModel
    subtitle2: info?.physicalCores > 0 && threads > 0 ? I18n.tr("%1 cores, %2 threads", "CPU core and thread count").arg(info.physicalCores).arg(threads) : ""
    showChart: !perThread
    chartLabel: I18n.tr("Usage", "chart legend: CPU or GPU utilization")
    chartValue: DgopService.cpuSampleCount === 0 ? "—" : DgopService.cpuUsage.toFixed(0) + "%"
    values: DgopService.history("cpu", "usage")
    maximum: 100
    maximumText: "100%"

    typeKey: "cpu"
    mainFraction: DgopService.cpuSampleCount === 0 ? -1 : DgopService.cpuUsage / 100
    briefSubtitle: [subtitle, subtitle2].filter(s => s).join(" · ")
    extraLabel: I18n.tr("Temperature", "CPU temperature")
    extraValue: DgopService.cpuTemperature > 0 ? Devices.formatTemp(DgopService.cpuTemperature) : ""
    compactSecondaryLabel: extraLabel
    compactSecondaryValue: extraValue
    compactSecondaryValues: DgopService.history("cpu", "temp")

    headerActions: DButtonGroup {
        visible: DgopService.perCoreCpuUsage.length > 0
        size: "small"
        checkEnabled: false
        model: [I18n.tr("Overall", "CPU chart: usage of all threads together"), I18n.tr("Per thread", "CPU chart mode: one graph per thread")]
        currentIndex: ProcessListMetrics.cpuPerThread ? 1 : 0
        onSelectionChanged: (index, selected) => {
            if (selected)
                ProcessListMetrics.cpuPerThread = index === 1;
        }
    }

    leftStats: [
        {
            tile: true,
            label: I18n.tr("Clock", "CPU clock speed", true),
            value: root.ghz(root.clockMHz),
            tooltip: info?.governor ? I18n.tr("Governor", "CPU frequency scaling governor") + ": " + info.governor : ""
        },
        {
            label: I18n.tr("Max clock", "highest clock speed of a CPU or GPU"),
            value: root.ghz(info?.maxFrequency ?? 0)
        },
        {
            label: I18n.tr("Temperature"),
            value: DgopService.cpuTemperature > 0 ? Devices.formatTemp(DgopService.cpuTemperature) : null
        },
        {
            advanced: true,
            label: I18n.tr("Base clock", "CPU nominal frequency"),
            value: root.ghz(info?.baseFrequency ?? 0)
        },
        {
            advanced: true,
            label: I18n.tr("Virtualization", "CPU hardware virtualization, e.g. AMD-V"),
            value: info?.virtualization || null
        },
        {
            advanced: true,
            label: I18n.tr("L3 cache", "CPU cache level"),
            value: root.size(cache?.l3 ?? 0),
            tooltip: [[I18n.tr("L1 cache", "CPU cache level"), root.size((cache?.l1d ?? 0) + (cache?.l1i ?? 0))], [I18n.tr("L2 cache", "CPU cache level"), root.size(cache?.l2 ?? 0)]].filter(p => p[1] !== null).map(p => p[0] + ": " + p[1]).join("\n")
        }
    ]

    rightStats: [
        {
            tile: true,
            label: I18n.tr("Processes"),
            value: root.count(DgopService.processCount)
        },
        {
            label: I18n.tr("Threads", "number of threads, CPU or process"),
            value: root.count(DgopService.threadCount)
        },
        {
            label: I18n.tr("Uptime"),
            value: DgopService.uptime ? DgopService.uptime.slice(3) : null
        },
        {
            advanced: true,
            label: I18n.tr("Load Average", "system info label"),
            value: DgopService.loadAverage || null
        },
        {
            advanced: true,
            label: I18n.tr("Open files", "system-wide open file handles"),
            value: root.count(DgopService.openFileCount ?? 0)
        },
        {
            advanced: true,
            label: I18n.tr("Sockets", "CPU sockets on the motherboard"),
            value: root.count(info?.sockets ?? 0)
        }
    ]

    Rectangle {
        visible: root.perThread
        width: parent.width
        height: Math.max(root.chartCardHeight, threadGrid.implicitHeight + threadGrid.inset * 2)
        radius: Theme.cornerRadiusL
        color: root.compactGrid ? "transparent" : ProcessListMetrics.cardColor

        Grid {
            id: threadGrid

            readonly property int count: DgopService.perCoreCpuUsage.length
            // Past what fits at the normal gap, the gap shrinks so more cells fit.
            readonly property bool dense: root.compactGrid && count > ProcessListMetrics.threadMaxColumns * rowsFit(Theme.spacingS)
            readonly property int rows: Math.max(1, Math.ceil(count / columns))
            readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
            // Fills the overall chart's height so the stats below stay put; past that the card grows instead of the cells shrinking.
            readonly property real inset: root.compactGrid ? 0 : Theme.spacingL
            readonly property real cellHeight: Math.max(root.compactGrid ? ProcessListMetrics.threadCellMinHeight : Theme.listItemHeight, (root.chartCardHeight - inset * 2 - spacing * (rows - 1)) / rows)
            readonly property real cellMinWidth: numberReserve.reservedWidth + Theme.spacingS * 2

            function rowsFit(gap) {
                return Math.max(1, Math.floor((root.chartCardHeight + gap) / (ProcessListMetrics.threadCellMinHeight + gap)));
            }

            x: inset
            y: inset
            width: parent.width - inset * 2
            columns: {
                const most = ProcessListMetrics.threadMaxColumns;
                if (!root.compactGrid)
                    return Math.max(1, Math.min(most, count));
                const widthFit = Math.max(1, Math.floor((width + spacing) / (cellMinWidth + spacing)));
                return Math.max(1, Math.min(count, widthFit, Math.max(most, Math.ceil(count / rowsFit(spacing)))));
            }
            spacing: dense ? Theme.spacingXXS : Theme.spacingS

            NumericText {
                id: numberReserve
                visible: false
                reserveText: "100%"
                font.pixelSize: Theme.fontSizeSmall
            }

            Repeater {
                model: root.perThread ? DgopService.perCoreCpuUsage.length : 0

                Rectangle {
                    id: thread

                    required property int index
                    readonly property real usage: DgopService.perCoreCpuUsage[index] ?? 0
                    readonly property real mhz: root.freqs[index] ?? 0
                    readonly property string usageText: Math.round(usage) + "%"

                    width: threadGrid.cellWidth
                    height: threadGrid.cellHeight
                    radius: Theme.cornerRadiusS
                    color: ProcessListMetrics.cardInsetColor
                    clip: true

                    MetricChart {
                        anchors.fill: parent
                        anchors.topMargin: threadLabel.visible ? threadLabel.height : 0
                        compact: true
                        values: DgopService.history("cpu", "thread" + thread.index)
                        maximum: 100
                        historyLength: DgopService.historySize
                    }

                    StyledText {
                        id: threadLabel
                        visible: !root.compactGrid
                        x: Theme.spacingS
                        topPadding: Theme.spacingXS
                        text: String(thread.index)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    NumericText {
                        id: threadNumber
                        reserveText: "100%"
                        visible: thread.height >= ProcessListMetrics.threadNumberMinHeight && thread.width >= reservedWidth + Theme.spacingS * 2
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        topPadding: Theme.spacingXS
                        text: thread.usageText
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }

                    MouseArea {
                        id: threadHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    DTooltipHost {
                        text: [root.compactGrid ? String(thread.index) : "", threadNumber.visible ? "" : thread.usageText, thread.mhz > 0 ? root.ghz(thread.mhz) : ""].filter(s => s).join(" · ")
                        target: thread
                        hoverArea: threadHover
                    }
                }
            }
        }
    }
}
