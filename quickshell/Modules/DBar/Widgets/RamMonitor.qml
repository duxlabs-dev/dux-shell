import qs.Common
import qs.Services

MonitorPill {
    id: root

    signal ramClicked

    readonly property bool showSwap: SettingsData.widgetOption("memUsage", widgetData, "showSwap")
    readonly property bool showInGb: SettingsData.widgetOption("memUsage", widgetData, "showInGb")
    readonly property real usage: DgopService.memoryUsage
    readonly property real swapUsage: DgopService.totalSwapKB > 0 ? (DgopService.usedSwapKB / DgopService.totalSwapKB) * 100 : 0
    readonly property bool swapShown: showSwap && DgopService.totalSwapKB > 0
    readonly property string usedText: showInGb ? (DgopService.usedMemoryMB / 1024).toFixed(1) : usage.toFixed(0)

    widgetType: "memUsage"
    dgopModules: ["memory"]
    iconName: "developer_board"
    level: usage
    warnLevel: 75
    dangerLevel: 90
    verticalText: usage ? usedText : "--"
    verticalSecondaryText: swapShown ? swapUsage.toFixed(0) : ""
    horizontalText: {
        if (!usage)
            return showInGb ? "-- GB" : "--%";
        const base = showInGb ? usedText + " GB" : usedText + "%";
        return swapShown ? base + " · " + swapUsage.toFixed(0) + "%" : base;
    }
    reserveText: {
        const base = showInGb ? "88.8 GB" : "88%";
        if (!showSwap)
            return base;
        return swapUsage < 10 ? base + " · 0%" : base + " · 88%";
    }
    sortKey: "memory"
    onActivated: ramClicked()
}
