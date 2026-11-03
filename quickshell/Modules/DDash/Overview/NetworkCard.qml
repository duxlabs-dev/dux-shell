import QtQuick
import qs.Common
import qs.Services
import qs.Modules.DDash
import "../../../Common/Format.js" as Format

MetricCard {
    entryId: "network"
    dgopModules: ["network"]
    label: I18n.tr("Network")
    iconName: "download"
    valueText: Format.formatRate(DgopService.networkRxRate || 0)
    supportingText: NetworkService.primaryConnection
    badgeText: Format.formatRate(DgopService.networkTxRate || 0)
    badgeIcon: "upload"
    trendMaximum: 0
    showTrend: options.trend === true
    trend: DgopService.networkHistory.rx
    secondaryTrend: DgopService.networkHistory.tx
}
