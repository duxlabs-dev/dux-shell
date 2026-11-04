import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/Format.js" as Format
import "../../Services/SysmonDevices.js" as Devices

DevicePane {
    id: root

    property string slot: ""

    readonly property var stat: (DgopService.availableGpus ?? []).find(g => Devices.gpuSlot(g) === slot) ?? null
    readonly property bool monitored: stat !== null && Devices.gpuMonitored(DgopService.gpuPciIds, stat.pciId, stat.busId)
    readonly property bool off: stat !== null && !monitored
    readonly property bool suspended: stat?.state === "suspended"
    readonly property bool live: stat !== null && !off && !suspended
    readonly property var history: DgopService.deviceHistory[Devices.deviceKey("gpu", slot)] ?? ({})

    // allProcesses can be only the top 100 by the table's sort, so a GPU-heavy process can be missing.
    // Per-process GPU use is not per device, so it is only meaningful with a single GPU.
    readonly property bool singleGpu: (DgopService.availableGpus ?? []).length === 1
    readonly property var topProcess: {
        if (!singleGpu || !live)
            return null;
        let best = null;
        for (const p of DgopService.allProcesses ?? []) {
            if (typeof p.gpu === "number" && p.gpu > 0 && (best === null || p.gpu > best.gpu))
                best = p;
        }
        return best;
    }

    Ref {
        service: DgopService
        modules: ["processes", "process-gpu"]
        active: root.visible && root.live && root.singleGpu
    }

    function num(v, unit) {
        return v === null || v === undefined ? null : Math.round(v) + " " + unit;
    }

    function pct(v) {
        return v === null || v === undefined ? null : Math.round(v) + "%";
    }

    function temp(v) {
        return v === null || v === undefined ? null : Devices.formatTemp(v);
    }

    function usedOf(usedKB, totalKB) {
        return usedKB === null || usedKB === undefined || !(totalKB > 0) ? null : Format.formatBytes(usedKB * 1024, true) + " / " + Format.formatBytes(totalKB * 1024, true);
    }

    function withMax(max, unit) {
        return max === null || max === undefined ? "" : I18n.tr("Max clock", "highest clock speed of a CPU or GPU") + ": " + num(max, unit);
    }

    loaded: off || suspended || (history.a ?? []).length > 0
    title: stat?.fullName ?? slot
    titleTooltip: title
    subtitle: stat?.driver ?? ""
    subtitle2: stat?.memoryTotal > 0 ? I18n.tr("%1 VRAM", "GPU memory size, e.g. 24 GiB VRAM").arg(Format.formatBytes(stat.memoryTotal * 1024, true)) : ""
    showChart: live
    chartLabel: I18n.tr("Usage", "chart legend: CPU or GPU utilization")
    chartValue: pct(stat?.usage) ?? "—"
    chartSecondaryLabel: (history.b ?? []).length > 0 ? I18n.tr("VRAM", "GPU video memory") : ""
    chartSecondaryValue: stat?.memoryTotal > 0 && stat?.memoryUsed != null ? Math.round(stat.memoryUsed / stat.memoryTotal * 100) + "%" : ""
    values: live ? (history.a ?? []) : []
    secondaryValues: live ? (history.b ?? []) : []
    maximum: 100
    maximumText: "100%"

    leftStats: live ? [
        {
            label: I18n.tr("VRAM", "GPU video memory"),
            value: root.usedOf(stat.memoryUsed, stat.memoryTotal)
        },
        {
            label: I18n.tr("Core clock", "GPU core clock speed"),
            value: root.num(stat.coreClock, "MHz"),
            tooltip: root.withMax(stat.coreClockMax, "MHz")
        },
        {
            label: I18n.tr("Temperature"),
            value: root.temp(stat.temperature || null)
        },
        {
            advanced: true,
            label: I18n.tr("Shared memory", "GPU memory borrowed from system RAM (GTT)"),
            value: root.usedOf(stat.gttUsed, stat.gttTotal)
        },
        {
            advanced: true,
            label: I18n.tr("Memory controller", "GPU memory controller busy percentage"),
            value: root.pct(stat.memoryBusy)
        },
        {
            advanced: true,
            label: I18n.tr("Memory clock", "GPU memory clock speed"),
            value: root.num(stat.memoryClock, "MHz"),
            tooltip: root.withMax(stat.memoryClockMax, "MHz")
        }
    ] : []

    rightStats: live ? [
        {
            label: I18n.tr("Power", "battery stat label, charge or discharge rate in watts", true),
            value: root.num(stat.power, "W"),
            tooltip: stat.powerLimit != null ? I18n.tr("Power limit", "GPU power limit in watts") + ": " + root.num(stat.powerLimit, "W") : ""
        },
        {
            label: I18n.tr("Fan", "GPU fan speed"),
            value: stat.fanRpm != null ? stat.fanRpm + " rpm" : root.pct(stat.fanPercent)
        },
        {
            label: I18n.tr("Top process", "process using the most of a resource, e.g. GPU memory"),
            value: root.topProcess ? root.topProcess.command : null,
            tooltip: root.topProcess ? Math.round(root.topProcess.gpu) + "%" : ""
        },
        {
            advanced: true,
            label: I18n.tr("Video encode", "GPU video encoder busy percentage"),
            value: root.pct(stat.encoderUsage)
        },
        {
            advanced: true,
            label: I18n.tr("Video decode", "GPU video decoder busy percentage"),
            value: root.pct(stat.decoderUsage)
        },
        {
            advanced: true,
            label: I18n.tr("Hotspot", "GPU hotspot temperature", true),
            value: root.temp(stat.hotspot)
        }
    ] : []

    StyledText {
        visible: root.off || root.suspended
        width: parent.width
        text: root.off ? I18n.tr("Monitoring off", "GPU monitoring is turned off in settings") : I18n.tr("Idle", "adjective, printer state", true)
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.surfaceVariantText
    }

    topContent: SettingsGroup {
        visible: root.stat !== null
        width: parent.width

        SettingsToggleRow {
            readonly property bool heldByWidget: root.stat !== null && DgopService.gpuHeldByWidget(root.stat.pciId)
            text: I18n.tr("GPU Monitoring")
            checked: root.monitored || heldByWidget
            enabled: !heldByWidget
            description: heldByWidget ? I18n.tr("Bar widgets") : ""
            onToggled: on => DgopService.setGpuMonitoring(root.stat.pciId, on)
        }
    }
}
