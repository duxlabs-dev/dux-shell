import QtQuick
import qs.Common
import qs.Services
import "../../Common/Format.js" as Format
import "../../Services/SysmonDevices.js" as SysmonDevices

DevicePane {
    id: root

    property string deviceName: ""

    readonly property var history: DgopService.deviceHistory[SysmonDevices.deviceKey("net", deviceName)] ?? ({})
    readonly property var rates: (DgopService.netRates ?? []).find(n => n.iface === deviceName) ?? null
    readonly property real axisMax: SysmonDevices.rateAxisMax(history.a, history.b, 102400)

    // NetworkManager's view, when it manages this interface; dgop's sysfs values fill the gaps.
    readonly property var ethernet: (NetworkService.ethernetDevices ?? []).find(d => d.name === deviceName) ?? null
    readonly property var wifi: (NetworkService.wifiDevices ?? []).find(d => d.name === deviceName) ?? null
    readonly property var netDevice: ethernet ?? wifi
    readonly property var wifiNetwork: wifi ? ((wifi.networks ?? []).find(n => n.connected) ?? null) : null

    readonly property var ipv4: rates?.ipv4 ?? []
    readonly property var ipv6: rates?.ipv6 ?? []
    readonly property string ipv6Main: SysmonDevices.stripPrefixLength(ipv6.find(a => !a.toLowerCase().startsWith("fe80")) ?? ipv6[0] ?? "")
    readonly property string linkSpeed: SysmonDevices.formatLinkSpeed(ethernet?.speed || rates?.speed || wifiNetwork?.rate || 0)

    function rate(v) {
        return v === null || v === undefined ? "—" : Format.formatRate(v, 1);
    }

    function total(v) {
        return v === null || v === undefined ? null : Format.formatBytes(v, true);
    }

    loaded: (history.a ?? []).length > 0
    title: deviceName
    subtitle: title !== deviceName ? deviceName : ""
    subtitle2: linkSpeed
    chartLabel: I18n.tr("Down", "network direction")
    chartValue: rate(rates?.rxRate)
    chartSecondaryLabel: I18n.tr("Up", "network direction")
    chartSecondaryValue: rate(rates?.txRate)
    values: history.a ?? []
    secondaryValues: history.b ?? []
    maximum: axisMax
    maximumText: Format.formatRate(axisMax, 1)

    leftStats: [
        {
            label: I18n.tr("SSID"),
            value: root.wifi?.ssid || null
        },
        {
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
            value: root.netDevice?.ip || SysmonDevices.stripPrefixLength(root.ipv4[0] ?? "") || null,
            tooltip: root.ipv4.join("\n")
        },
        {
            advanced: true,
            label: I18n.tr("IPv6", "network IPv6 address"),
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
            label: I18n.tr("Speed"),
            value: root.linkSpeed || null
        },
        {
            advanced: true,
            label: I18n.tr("Driver"),
            value: root.ethernet?.driver || root.rates?.driver || null
        },
        {
            advanced: true,
            label: I18n.tr("MTU", "network maximum transmission unit"),
            value: root.rates?.mtu > 0 ? String(root.rates.mtu) : null
        },
        {
            label: I18n.tr("Received since boot", "network data received since the system started"),
            value: root.total(root.rates?.rxTotal)
        },
        {
            label: I18n.tr("Sent since boot", "network data sent since the system started"),
            value: root.total(root.rates?.txTotal)
        }
    ]
}
