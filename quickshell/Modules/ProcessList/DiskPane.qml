import QtQuick
import qs.Common
import qs.Services
import "../../Common/Format.js" as Format
import "../../Services/SysmonDevices.js" as SysmonDevices
import "../../Services/Drives.js" as Drives

DevicePane {
    id: root

    property string deviceName: ""

    readonly property var historyA: DgopService.history(SysmonDevices.deviceKey("disk", deviceName), "read")
    readonly property var historyB: DgopService.history(SysmonDevices.deviceKey("disk", deviceName), "write")
    readonly property var rates: (DgopService.diskRates ?? []).find(d => d.device === deviceName) ?? null
    // The list is sampled but this drive isn't in it: unplugged, with its tab kept open.
    readonly property bool absent: (DgopService.diskRates ?? []).length > 0 && rates === null
    readonly property real axisMax: SysmonDevices.rateAxisMax(historyA, historyB, 1048576)

    readonly property var drive: Drives.driveFor(deviceName, DriveService.drives)
    readonly property var space: Drives.usedSpace(DriveService.drives, DgopService.diskMounts, deviceName, "")

    DriveHealth {
        id: health
        level: Drives.healthLevel(root.drive)
    }

    loaded: absent || historyA.length > 0
    idleText: absent ? I18n.tr("Disconnected", "system monitor: drive or interface no longer present") : ""
    idleIcon: "usb_off"
    title: drive?.model || deviceName
    titleTooltip: drive?.model ? deviceName : ""
    subtitle: Drives.driveSubtitle(drive)
    subtitle2: Drives.rootMostMount(drive)
    chartLabel: I18n.tr("Disk read", "disk read rate")
    chartValue: Format.formatRateOr(rates?.readRate, "—")
    chartSecondaryLabel: I18n.tr("Disk write", "disk write rate")
    chartSecondaryValue: Format.formatRateOr(rates?.writeRate, "—")
    values: historyA
    secondaryValues: historyB
    maximum: axisMax
    maximumText: Format.formatRate(axisMax, 1)

    typeKey: "disk"
    mainValue: space ? Math.round(space.percent) + "%" : "—"
    mainLabel: I18n.tr("Used", "disk space in use")
    mainFraction: space ? space.percent / 100 : -1
    mainDetail: space ? Format.formatBytes(space.used, true) + " / " + Format.formatBytes(space.total, true) : ""
    extraLabel: ""

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
            tile: true,
            label: I18n.tr("Capacity"),
            value: root.drive?.size > 0 ? Format.formatBytes(root.drive.size, true) : null
        }
    ]

    rightStats: [
        {
            tile: true,
            label: I18n.tr("Temperature"),
            value: root.drive?.temperature != null ? SysmonDevices.formatTemp(root.drive.temperature) : null
        },
        {
            tile: true,
            label: I18n.tr("Health"),
            value: health.text || null
        },
        {
            advanced: true,
            label: I18n.tr("Read total", "total data read"),
            value: Format.formatBytesOr(root.rates?.readTotal, null)
        },
        {
            advanced: true,
            label: I18n.tr("Written total", "total data written"),
            value: Format.formatBytesOr(root.rates?.writeTotal, null)
        }
    ]

    PartitionStrip {
        width: parent.width
        drive: root.drive
        mounts: DgopService.diskMounts ?? []
    }
}
