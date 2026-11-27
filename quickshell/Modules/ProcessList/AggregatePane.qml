import QtQuick
import qs.Common
import qs.Services
import "../../Common/Format.js" as Format
import "../../Services/SysmonDevices.js" as SysmonDevices
import "../../Services/Drives.js" as Drives

DevicePane {
    id: root

    property string type: "disk"

    readonly property bool isDisk: type === "disk"
    readonly property var historyA: DgopService.history(type, isDisk ? "read" : "down")
    readonly property var historyB: DgopService.history(type, isDisk ? "write" : "up")
    readonly property real axisMax: SysmonDevices.rateAxisMax(historyA, historyB, isDisk ? 1048576 : 102400)
    readonly property var members: SysmonService.devices().filter(e => e.type === root.type)
    readonly property var space: isDisk ? Drives.usedSpace(DriveService.drives, DgopService.diskMounts, "", "") : null
    readonly property real capacity: isDisk ? (DriveService.drives ?? []).reduce((sum, d) => sum + (d.size > 0 ? d.size : 0), 0) : 0

    loaded: historyA.length > 0
    typeKey: type
    title: SysmonService.typeName(type)
    chartLabel: isDisk ? I18n.tr("Disk read", "disk read rate") : I18n.tr("Down", "network direction")
    chartValue: Format.formatRateOr(isDisk ? DgopService.diskReadRate : DgopService.networkRxRate, "—")
    chartSecondaryLabel: isDisk ? I18n.tr("Disk write", "disk write rate") : I18n.tr("Up", "network direction")
    chartSecondaryValue: Format.formatRateOr(isDisk ? DgopService.diskWriteRate : DgopService.networkTxRate, "—")
    values: historyA
    secondaryValues: historyB
    maximum: axisMax
    maximumText: Format.formatRate(axisMax, 1)

    mainValue: isDisk ? (space ? Math.round(space.percent) + "%" : "—") : chartValue
    mainLabel: isDisk ? I18n.tr("Used", "disk space in use") : chartLabel
    mainFraction: space ? space.percent / 100 : -1
    extraLabel: isDisk ? "" : chartSecondaryLabel
    mainDetail: space?.total > 0 ? Format.formatBytes(space.used, true) + " / " + Format.formatBytes(space.total, true) : ""

    leftStats: {
        const stats = [
            {
                label: chartLabel,
                value: loaded ? chartValue : null
            },
            {
                label: chartSecondaryLabel,
                value: loaded ? chartSecondaryValue : null
            }
        ];
        if (isDisk) {
            stats.push({
                tile: true,
                label: I18n.tr("Capacity", "total size of all drives"),
                value: capacity > 0 ? Format.formatBytes(capacity, true) : null
            }, {
                label: I18n.tr("Used", "disk space in use"),
                value: space ? Math.round(space.percent) + "%" : null
            });
        }
        return stats;
    }

    // Each member's read plus write, or down plus up.
    rightStats: members.map(e => ({
                tile: true,
                label: e.name,
                value: isDisk ? (e.disk ? Format.formatRateSumOr(e.disk.readRate, e.disk.writeRate, "—") : null) : (e.net ? Format.formatRateSumOr(e.net.rxRate, e.net.txRate, "—") : null)
            }))
}
