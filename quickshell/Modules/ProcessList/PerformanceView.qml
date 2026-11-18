import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import "../../Services/SysmonDevices.js" as Devices
import "../../Common/Format.js" as Format

Item {
    id: root

    readonly property bool isFloatingWindowSurface: true

    property string currentKey: "cpu"
    property bool showHidden: false

    function scrollToTop() {
        if (pane.item)
            pane.item.contentY = 0;
    }

    function rate(value) {
        return value === null || value === undefined ? "—" : Format.formatRate(value, 1);
    }

    function pairTotal(a, b) {
        return a === null || a === undefined || b === null || b === undefined ? "—" : Format.formatRate(a + b, 1);
    }

    readonly property var allDevices: SysmonService.devices({
        showHidden: true
    })
    readonly property int hiddenCount: allDevices.filter(e => e.hidden).length

    readonly property var railModel: allDevices.filter(e => root.showHidden || !e.hidden).map(e => {
        switch (e.type) {
        case "cpu":
            return Object.assign({}, e, {
                value: DgopService.cpuSampleCount === 0 ? "—" : DgopService.cpuUsage.toFixed(0) + "%",
                values: DgopService.history("cpu", "usage"),
                maximum: 100
            });
        case "memory":
            return Object.assign({}, e, {
                value: DgopService.memoryInfo === null ? "—" : Format.formatBytes(DgopService.usedMemoryKB * 1024, true) + " / " + Format.formatBytes(DgopService.totalMemoryKB * 1024, true),
                values: DgopService.history("memory", "used"),
                maximum: 100
            });
        case "gpu":
            {
                const g = e.gpu;
                const suspended = g.state === "suspended";
                const off = !Devices.gpuMonitored(DgopService.gpuPciIds, g.pciId, g.busId);
                return Object.assign({}, e, {
                    value: off ? I18n.tr("Monitoring off", "GPU monitoring is turned off in settings") : suspended ? I18n.tr("Idle", "adjective, printer state", true) : (g.usage != null ? Math.round(g.usage) + "%" : "—"),
                    values: suspended || off ? [] : DgopService.history(e.key, "usage"),
                    maximum: 100
                });
            }
        case "disk":
            return Object.assign({}, e, {
                value: pairTotal(e.disk.readRate, e.disk.writeRate),
                valueTooltip: SysmonService.valueLabel("disk", "read") + ": " + rate(e.disk.readRate) + "\n" + SysmonService.valueLabel("disk", "write") + ": " + rate(e.disk.writeRate),
                values: DgopService.history(e.key, "read"),
                secondaryValues: DgopService.history(e.key, "write")
            });
        default:
            return Object.assign({}, e, {
                value: pairTotal(e.net.rxRate, e.net.txRate),
                valueTooltip: SysmonService.valueLabel("net", "down") + ": " + rate(e.net.rxRate) + "\n" + SysmonService.valueLabel("net", "up") + ": " + rate(e.net.txRate),
                values: DgopService.history(e.key, "down"),
                secondaryValues: DgopService.history(e.key, "up")
            });
        }
    })

    readonly property var activeEntry: railModel.find(e => e.key === currentKey) ?? railModel[0]
    readonly property string activeKey: activeEntry.key
    onActiveKeyChanged: scrollToTop()

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
