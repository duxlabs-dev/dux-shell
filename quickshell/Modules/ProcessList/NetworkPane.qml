import QtQuick
import qs.Common
import qs.Services
import "../../Common/Format.js" as Format
import "../../Services/SysmonDevices.js" as SysmonDevices

DevicePane {
    id: root

    property string deviceName: ""

    readonly property var historyA: DgopService.history(SysmonDevices.deviceKey("net", deviceName), "down")
    readonly property var historyB: DgopService.history(SysmonDevices.deviceKey("net", deviceName), "up")
    readonly property var rates: (DgopService.netRates ?? []).find(n => n.iface === deviceName) ?? null
    // The list is sampled but this interface isn't in it: down or removed, with its tab kept open.
    readonly property bool absent: (DgopService.netRates ?? []).length > 0 && rates === null
    readonly property real axisMax: SysmonDevices.rateAxisMax(historyA, historyB, 102400)

    // NetworkManager's view, when it manages this interface; dgop's sysfs values fill the gaps.
    readonly property var ethernet: (NetworkService.ethernetDevices ?? []).find(d => d.name === deviceName) ?? null
    readonly property var wifi: (NetworkService.wifiDevices ?? []).find(d => d.name === deviceName) ?? null
    readonly property var netDevice: ethernet ?? wifi
    readonly property var wifiNetwork: wifi ? ((wifi.networks ?? []).find(n => n.connected) ?? null) : null

    readonly property var ipv4: rates?.ipv4 ?? []
    readonly property var ipv6: rates?.ipv6 ?? []
    readonly property string ipv6Main: SysmonDevices.stripPrefixLength(ipv6.find(a => !a.toLowerCase().startsWith("fe80")) ?? ipv6[0] ?? "")
    readonly property string ip: netDevice?.ip || SysmonDevices.stripPrefixLength(ipv4[0] ?? "")
    readonly property string linkSpeed: SysmonDevices.formatLinkSpeed(ethernet?.speed || rates?.speed || wifiNetwork?.rate || 0)

    loaded: absent || historyA.length > 0
    idleText: absent ? I18n.tr("Disconnected", "system monitor: drive or interface no longer present") : ""
    idleIcon: "link_off"
    title: deviceName
    subtitle: title !== deviceName ? deviceName : ""
    subtitle2: linkSpeed
    chartLabel: I18n.tr("Down", "network direction")
    chartValue: Format.formatRateOr(rates?.rxRate, "—")
    chartSecondaryLabel: I18n.tr("Up", "network direction")
    chartSecondaryValue: Format.formatRateOr(rates?.txRate, "—")
    values: historyA
    secondaryValues: historyB
    maximum: axisMax
    maximumText: Format.formatRate(axisMax, 1)

    typeKey: "net"
    shortSubtitle: [subtitle, ip].filter(s => s).join(" · ")
    briefSubtitle: [subtitle, linkSpeed].filter(s => s).join(" · ")

    leftStats: [
        {
            label: "SSID",
            value: root.wifi?.ssid || null
        },
        {
            tile: true,
            label: I18n.tr("Signal"),
            value: root.wifi?.signal > 0 ? root.wifi.signal + "%" : null
        },
        {
            advanced: true,
            label: I18n.tr("Band"),
            value: SysmonDevices.wifiBand(root.wifiNetwork?.frequency ?? 0) || null
        },
        {
            label: I18n.tr("IP address"),
            value: root.ip || null,
            tooltip: root.ipv4.join("\n")
        },
        {
            advanced: true,
            label: "IPv6",
            value: root.ipv6Main || null,
            tooltip: root.ipv6.join("\n")
        },
        {
            advanced: true,
            label: I18n.tr("MAC address", "network hardware address"),
            value: root.netDevice?.hwAddress || null
        }
    ]

    rightStats: [
        {
            tile: true,
            label: I18n.tr("Speed"),
            value: root.linkSpeed || null
        },
        {
            advanced: true,
            tile: true,
            label: I18n.tr("Driver"),
            value: root.ethernet?.driver || root.rates?.driver || null
        },
        {
            advanced: true,
            tile: true,
            label: "MTU",
            value: root.rates?.mtu > 0 ? String(root.rates.mtu) : null
        },
        {
            label: I18n.tr("Received since boot", "network data received since the system started"),
            value: Format.formatBytesOr(root.rates?.rxTotal, null)
        },
        {
            label: I18n.tr("Sent since boot", "network data sent since the system started"),
            value: Format.formatBytesOr(root.rates?.txTotal, null)
        }
    ]
}
