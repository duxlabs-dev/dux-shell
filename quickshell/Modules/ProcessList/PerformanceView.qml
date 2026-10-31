import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import "../../Services/SysmonDevices.js" as Devices
import "../../Common/Format.js" as Format
import "Drives.js" as Drives

Item {
    id: root

    readonly property bool isFloatingWindowSurface: true

    property string currentKey: "cpu"
    property bool showHidden: false

    readonly property var netKindOrder: ["ethernet", "wifi", "vpn", "other", "virtual", "loopback"]
    readonly property var netKindNames: ({
            ethernet: I18n.tr("Ethernet"),
            wifi: I18n.tr("Wi-Fi"),
            vpn: I18n.tr("VPN")
        })

    function history(key) {
        return DgopService.deviceHistory[key] ?? ({});
    }

    // Bar widgets keep cpu/memory history while this page is closed; use it so the chart starts full.
    function longer(a, b) {
        return (a ?? []).length >= (b ?? []).length ? (a ?? []) : b;
    }

    function rate(value) {
        return value === null || value === undefined ? "—" : Format.formatRate(value, 1);
    }

    function pairTotal(a, b) {
        return a === null || a === undefined || b === null || b === undefined ? "—" : Format.formatRate(a + b, 1);
    }

    readonly property var nets: {
        const kindRank = kind => {
            const i = netKindOrder.indexOf(kind);
            return i < 0 ? netKindOrder.length : i;
        };
        return (DgopService.netRates ?? []).map(n => ({
                    net: n,
                    kind: Devices.interfaceKind(n.iface, n.linkType)
                })).sort((a, b) => kindRank(a.kind) - kindRank(b.kind) || Devices.naturalCompare(a.net.iface, b.net.iface));
    }
    readonly property int hiddenCount: nets.filter(n => Devices.isHiddenByDefault(n.kind)).length

    readonly property var railModel: {
        const processor = I18n.tr("Processor", "system monitor device group: CPU and memory");
        const items = [
            {
                key: "cpu",
                group: processor,
                icon: "memory",
                name: I18n.tr("CPU", "processor label in system monitor"),
                value: DgopService.cpuSampleCount === 0 ? "—" : DgopService.cpuUsage.toFixed(0) + "%",
                values: longer(history("cpu").a, DgopService.cpuHistory),
                maximum: 100
            },
            {
                key: "memory",
                group: processor,
                icon: "developer_board",
                name: I18n.tr("Memory", "system RAM label in system monitor"),
                value: DgopService.memoryInfo === null ? "—" : Format.formatBytes(DgopService.usedMemoryKB * 1024, true) + " / " + Format.formatBytes(DgopService.totalMemoryKB * 1024, true),
                values: longer(history("memory").a, DgopService.memoryHistory),
                maximum: 100
            }
        ];

        for (const g of DgopService.availableGpus ?? []) {
            const key = Devices.deviceKey("gpu", Devices.gpuSlot(g));
            const suspended = g.state === "suspended";
            const off = !Devices.gpuMonitored(DgopService.gpuPciIds, g.pciId, g.busId);
            items.push({
                key: key,
                group: I18n.tr("Graphics"),
                icon: "gpu",
                name: g.fullName,
                value: off ? I18n.tr("Monitoring off", "GPU monitoring is turned off in settings") : suspended ? I18n.tr("Idle", "adjective, printer state", true) : (g.usage != null ? Math.round(g.usage) + "%" : "—"),
                values: suspended || off ? [] : (history(key).a ?? []),
                maximum: 100
            });
        }

        const disks = (DgopService.diskRates ?? []).filter(d => Devices.isWholeDisk(d.device)).slice().sort((a, b) => Devices.naturalCompare(a.device, b.device));
        for (const d of disks) {
            const key = Devices.deviceKey("disk", d.device);
            items.push({
                key: key,
                group: I18n.tr("Storage", "system monitor device group: disks"),
                icon: Drives.driveIcon(Drives.driveFor(d.device, DriveService.drives)),
                name: Drives.driveFor(d.device, DriveService.drives)?.model || d.device,
                value: pairTotal(d.readRate, d.writeRate),
                valueTooltip: I18n.tr("Disk read", "disk read rate") + ": " + rate(d.readRate) + "\n" + I18n.tr("Disk write", "disk write rate") + ": " + rate(d.writeRate),
                values: history(key).a ?? [],
                secondaryValues: history(key).b ?? []
            });
        }

        const shown = nets.filter(n => root.showHidden || !Devices.isHiddenByDefault(n.kind));
        for (const {
            net,
            kind
        } of shown) {
            const key = Devices.deviceKey("net", net.iface);
            const sameKind = shown.filter(n => n.kind === kind).length;
            items.push({
                key: key,
                group: I18n.tr("Network"),
                hidden: Devices.isHiddenByDefault(kind),
                icon: kind === "wifi" ? "wifi" : kind === "vpn" ? "vpn_key" : "lan",
                name: sameKind === 1 && netKindNames[kind] ? netKindNames[kind] : net.iface,
                value: pairTotal(net.rxRate, net.txRate),
                valueTooltip: I18n.tr("Down", "network direction") + ": " + rate(net.rxRate) + "\n" + I18n.tr("Up", "network direction") + ": " + rate(net.txRate),
                values: history(key).a ?? [],
                secondaryValues: history(key).b ?? []
            });
        }
        return items;
    }

    // Per-thread usage history for the CPU pane; it fills while the window is open, whichever page is shown.
    property var threadHistory: []

    Connections {
        target: DgopService
        function onPerCoreCpuUsageChanged() {
            const usage = DgopService.perCoreCpuUsage;
            root.threadHistory = usage.map((u, i) => Format.addToHistory(root.threadHistory[i] || [], u, DgopService.historySize));
        }
    }

    readonly property var activeEntry: railModel.find(e => e.key === currentKey) ?? railModel[0]
    readonly property string activeKey: activeEntry.key

    Ref {
        service: DgopService
        modules: ["cpu", "memory", "system", "disk-rate", "net-rate", "diskmounts", "gpu", "memory-modules"]
        active: root.visible
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.spacingXL

        DeviceRail {
            Layout.preferredWidth: Theme.navigationRailWidth * 3
            Layout.fillHeight: true
            model: root.railModel
            currentKey: root.activeKey
            historyLength: DgopService.historySize
            hiddenCount: root.hiddenCount
            showHidden: root.showHidden
            onSelected: key => root.currentKey = key
            onShowHiddenToggled: root.showHidden = !root.showHidden
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: SettingsMetrics.paneRadius
            color: SettingsMetrics.paneColor
            border.width: Theme.layerOutlineWidth
            border.color: Theme.outlineMedium
            clip: true

            Loader {
                id: pane
                anchors.fill: parent
                anchors.margins: SettingsMetrics.panePadding
                sourceComponent: {
                    const prefix = root.activeKey.split(":")[0];
                    return prefix === "disk" ? diskPane : prefix === "net" ? netPane : prefix === "memory" ? memoryPane : prefix === "gpu" ? gpuPane : cpuPane;
                }
            }
        }
    }

    Component {
        id: cpuPane
        CpuPane {
            values: root.railModel[0].values
            threadHistory: root.threadHistory
        }
    }

    Component {
        id: memoryPane
        MemoryPane {
            values: root.railModel[1].values
        }
    }

    Component {
        id: diskPane
        DiskPane {
            deviceName: root.activeKey.slice(root.activeKey.indexOf(":") + 1)
        }
    }

    Component {
        id: gpuPane
        GpuPane {
            slot: root.activeKey.slice(root.activeKey.indexOf(":") + 1)
        }
    }

    Component {
        id: netPane
        NetworkPane {
            deviceName: root.activeKey.slice(root.activeKey.indexOf(":") + 1)
            title: root.activeEntry.name
        }
    }
}
