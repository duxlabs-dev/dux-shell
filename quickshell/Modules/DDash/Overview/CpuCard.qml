import QtQuick
import qs.Common
import qs.Services
import qs.Modules.DDash

MetricCard {
    entryId: "cpu"
    dgopModules: ["cpu"]
    label: I18n.tr("CPU")
    iconName: "memory"
    usage: (DgopService.cpuUsage || 0) / 100
    valueText: Math.round(DgopService.cpuUsage || 0) + "%"
    supportingText: DgopService.cpuModel
    badgeText: options.temperature === true && DgopService.cpuTemperature > 0 ? Math.round(DgopService.cpuTemperature) + "°" : ""
    showTrend: options.trend === true
    trend: DgopService.cpuHistory
}
