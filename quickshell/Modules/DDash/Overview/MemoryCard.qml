import QtQuick
import qs.Common
import qs.Services
import qs.Modules.DDash

MetricCard {
    entryId: "memory"
    dgopModules: ["memory"]
    label: I18n.tr("Memory")
    iconName: "developer_board"
    usage: (DgopService.memoryUsage || 0) / 100
    warnUsage: DashMetrics.memoryWarnPercent / 100
    criticalUsage: DashMetrics.memoryCriticalPercent / 100
    valueText: Math.round(DgopService.memoryUsage || 0) + "%"
    supportingText: DgopService.totalMemoryKB > 0 ? DgopService.formatSystemMemory(DgopService.usedMemoryKB) + " / " + DgopService.formatSystemMemory(DgopService.totalMemoryKB) : ""
    badgeText: options.swap === true && DgopService.totalSwapKB > 0 ? Math.round(DgopService.usedSwapKB / DgopService.totalSwapKB * 100) + "%" : ""
    badgeIcon: "swap_horiz"
    showTrend: options.trend === true
    trend: DgopService.memoryHistory
}
