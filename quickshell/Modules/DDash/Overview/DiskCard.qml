import QtQuick
import qs.Common
import qs.Services
import qs.Modules.DDash
import "../../../Common/Format.js" as Format

MetricCard {
    id: root

    readonly property var mount: {
        const mounts = DgopService.diskMounts || [];
        return mounts.find(m => m.mount === "/") ?? mounts[0] ?? null;
    }
    readonly property real percent: mount?.percent ? (parseFloat(String(mount.percent).replace("%", "")) || 0) : 0

    entryId: "disk"
    dgopModules: ["disk", "diskmounts"]
    label: I18n.tr("Disk")
    iconName: "hard_drive"
    usage: mount ? percent / 100 : -1
    warnUsage: DashMetrics.diskWarnPercent / 100
    criticalUsage: DashMetrics.diskCriticalPercent / 100
    valueText: mount ? Math.round(percent) + "%" : "--"
    supportingText: mount ? (mount.used && mount.size ? mount.used + " / " + mount.size : mount.mount) : ""
    badgeText: options.io === true ? Format.formatRate(DgopService.diskReadRate || 0) : ""
    badgeIcon: "swap_vert"
    trendMaximum: 0
    showTrend: options.trend === true
    trend: DgopService.diskHistory.read
    secondaryTrend: DgopService.diskHistory.write
}
