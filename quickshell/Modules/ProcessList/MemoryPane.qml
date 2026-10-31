import QtQuick
import qs.Common
import qs.Services
import "../../Common/Format.js" as Format
import "../../Services/SysmonDevices.js" as Devices

DevicePane {
    id: root

    readonly property var info: DgopService.memoryInfo
    readonly property var mods: DgopService.memoryModules?.modules ?? []
    readonly property int slots: DgopService.memoryModules?.slots ?? 0

    // "2 × 16 GiB, 1 × 8 GiB", largest first
    readonly property string moduleSummary: {
        const counts = {};
        mods.forEach(m => counts[m.size] = (counts[m.size] ?? 0) + 1);
        return Object.keys(counts).map(Number).sort((a, b) => b - a).map(size => counts[size] + " × " + Format.formatBytes(size * 1024, true)).join(", ");
    }
    readonly property var channels: Devices.memoryChannelCount(mods)
    readonly property real speedMT: mods.length > 0 ? (mods[0].configuredSpeed || mods[0].speed || 0) : 0
    readonly property bool hasZram: (info?.zramOrig ?? 0) > 0 && (info?.zramCompr ?? 0) > 0

    function bytes(kb) {
        return kb === null || kb === undefined ? null : Format.formatBytes(kb * 1024, true);
    }

    function of(usedKb, totalKb) {
        return usedKb === null || usedKb === undefined || !(totalKb > 0) ? null : bytes(usedKb) + " / " + bytes(totalKb);
    }

    function swapTooltip() {
        const lines = (info?.swapDevices ?? []).map(d => d.name + " (" + d.kind + "): " + of(d.used, d.size));
        if (hasZram)
            lines.push(I18n.tr("Compression", "memory compression (zram) ratio") + ": " + (info.zramOrig / info.zramCompr).toFixed(1) + "×");
        return lines.join("\n");
    }

    loaded: info !== null && (DgopService.memoryModules !== null || !DgopService.isModuleAvailable("memory-modules"))
    title: I18n.tr("Memory", "system RAM label in system monitor")
    subtitle: Devices.memoryModulesSummary(mods)
    subtitle2: moduleSummary
    chartLabel: I18n.tr("Used", "memory in use")
    chartValue: info ? bytes(DgopService.usedMemoryKB) : "—"
    maximum: 100
    maximumText: DgopService.totalMemoryKB > 0 ? bytes(DgopService.totalMemoryKB) : ""

    leftStats: [
        {
            label: I18n.tr("Used", "memory in use"),
            value: info ? bytes(DgopService.usedMemoryKB) : null,
            tooltip: info?.shared !== undefined ? I18n.tr("Shared", "RAM shared between processes (shmem)") + ": " + bytes(info.shared) : ""
        },
        {
            label: I18n.tr("Available"),
            value: bytes(info?.available)
        },
        {
            label: I18n.tr("Cached", "memory used as file cache"),
            value: info?.cached !== undefined ? bytes(info.cached + (info.buffers ?? 0)) : null
        },
        {
            advanced: true,
            label: I18n.tr("Committed", "memory committed by processes, of the commit limit"),
            value: root.of(info?.committed, info?.commitLimit)
        }
    ]

    rightStats: [
        {
            label: I18n.tr("Swap"),
            value: root.of(DgopService.usedSwapKB, DgopService.totalSwapKB),
            tooltip: root.swapTooltip()
        },
        {
            label: I18n.tr("Speed"),
            value: speedMT > 0 ? speedMT + " MT/s" : null
        },
        {
            label: I18n.tr("Slots used", "memory slots with a module installed, of all slots"),
            value: slots > 0 && mods.length > 0 ? mods.length + " / " + slots : null
        },
        {
            advanced: true,
            label: I18n.tr("Channels", "memory channels in use"),
            value: channels !== null ? String(channels) : null
        },
        {
            advanced: true,
            label: I18n.tr("Form factor", "memory module form factor, e.g. DIMM"),
            value: mods.length > 0 ? (mods[0].formFactor || null) : null
        }
    ]
}
