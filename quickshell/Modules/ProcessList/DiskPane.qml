import QtQuick
import qs.Common
import qs.Services
import "../../Common/Format.js" as Format
import "../../Services/SysmonDevices.js" as SysmonDevices
import "Drives.js" as Drives

DevicePane {
    id: root

    property string deviceName: ""

    readonly property var history: DgopService.deviceHistory[SysmonDevices.deviceKey("disk", deviceName)] ?? ({})
    readonly property var rates: (DgopService.diskRates ?? []).find(d => d.device === deviceName) ?? null
    readonly property real axisMax: SysmonDevices.rateAxisMax(history.a, history.b, 1048576)

    readonly property var drive: Drives.driveFor(deviceName, DriveService.drives)

    DriveHealth {
        id: health
        level: Drives.healthLevel(root.drive)
    }

    function rate(v) {
        return v === null || v === undefined ? "—" : Format.formatRate(v, 1);
    }

    function total(v) {
        return v === null || v === undefined ? null : Format.formatBytes(v, true);
    }

    loaded: (history.a ?? []).length > 0
    title: drive?.model || deviceName
    titleTooltip: drive?.model ? deviceName : ""
    subtitle: Drives.driveSubtitle(drive)
    subtitle2: Drives.rootMostMount(drive)
    chartLabel: I18n.tr("Disk read", "disk read rate")
    chartValue: rate(rates?.readRate)
    chartSecondaryLabel: I18n.tr("Disk write", "disk write rate")
    chartSecondaryValue: rate(rates?.writeRate)
    values: history.a ?? []
    secondaryValues: history.b ?? []
    maximum: axisMax
    maximumText: Format.formatRate(axisMax, 1)

    leftStats: [
        {
            label: I18n.tr("Busy", "share of time a disk is busy"),
            value: root.rates?.busy != null ? Math.round(root.rates.busy) + "%" : root.rates ? "—" : null
        },
        {
            advanced: true,
            label: I18n.tr("Response time", "average time a disk takes per request"),
            value: root.rates?.responseTime != null ? root.rates.responseTime.toFixed(2) + " ms" : root.rates ? "—" : null
        },
        {
            label: I18n.tr("Capacity"),
            value: root.drive?.size > 0 ? Format.formatBytes(root.drive.size, true) : null
        }
    ]

    rightStats: [
        {
            label: I18n.tr("Temperature"),
            value: root.drive?.temperature != null ? SysmonDevices.formatTemp(root.drive.temperature) : null
        },
        {
            label: I18n.tr("Health"),
            value: health.text || null
        },
        {
            advanced: true,
            label: I18n.tr("Read total", "total data read"),
            value: root.total(root.rates?.readTotal)
        },
        {
            advanced: true,
            label: I18n.tr("Written total", "total data written"),
            value: root.total(root.rates?.writeTotal)
        }
    ]

    PartitionStrip {
        width: parent.width
        drive: root.drive
        mounts: DgopService.diskMounts ?? []
    }
}
