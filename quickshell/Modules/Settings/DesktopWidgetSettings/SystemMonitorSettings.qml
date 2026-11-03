pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

DesktopWidgetInstanceSettings {
    id: root

    readonly property var gpus: DgopService.availableGpus ?? []

    Component.onCompleted: DgopService.ensureMeta()
    readonly property var gpuLabels: gpus.map(gpu => (gpu.driver ? gpu.driver.toUpperCase() + " " : "") + (gpu.displayName ?? ""))

    SettingsToggleRow {
        text: I18n.tr("Show header")
        checked: root.cfg.showHeader ?? true
        onToggled: checked => root.updateConfig("showHeader", checked)
    }

    SettingsButtonGroupRow {
        readonly property var intervals: [60, 300, 600, 1800]
        text: I18n.tr("Graph time range")
        model: ["1m", "5m", "10m", "30m"]
        currentIndex: Math.max(0, intervals.indexOf(root.cfg.graphInterval ?? 60))
        checkEnabled: false
        onSelectionChanged: (index, selected) => {
            if (!selected)
                return;
            root.updateConfig("graphInterval", intervals[index]);
        }
    }

    SettingsToggleRow {
        text: I18n.tr("CPU")
        checked: root.cfg.showCpu ?? true
        onToggled: checked => root.updateConfig("showCpu", checked)
    }

    SettingsToggleRow {
        enabled: root.cfg.showCpu ?? true
        text: I18n.tr("CPU graph")
        checked: root.cfg.showCpuGraph ?? true
        onToggled: checked => root.updateConfig("showCpuGraph", checked)
    }

    SettingsToggleRow {
        enabled: root.cfg.showCpu ?? true
        text: I18n.tr("CPU temperature")
        checked: root.cfg.showCpuTemp ?? true
        onToggled: checked => root.updateConfig("showCpuTemp", checked)
    }

    SettingsToggleRow {
        text: I18n.tr("GPU temperature")
        checked: root.cfg.showGpuTemp ?? false
        onToggled: checked => root.updateConfig("showGpuTemp", checked)
    }

    SettingsDropdownRow {
        visible: root.cfg.showGpuTemp ?? false
        text: I18n.tr("GPU")
        options: root.gpuLabels
        emptyText: I18n.tr("No GPU detected", "empty state when no graphics card is found")
        currentValue: root.gpuLabels[root.gpus.findIndex(gpu => gpu.pciId === root.cfg.gpuPciId)] ?? ""
        onValueChanged: value => {
            const index = root.gpuLabels.indexOf(value);
            if (index < 0)
                return;
            root.updateConfig("gpuPciId", root.gpus[index].pciId);
        }
    }

    SettingsToggleRow {
        text: I18n.tr("Memory")
        checked: root.cfg.showMemory ?? true
        onToggled: checked => root.updateConfig("showMemory", checked)
    }

    SettingsToggleRow {
        enabled: root.cfg.showMemory ?? true
        text: I18n.tr("Memory graph")
        checked: root.cfg.showMemoryGraph ?? true
        onToggled: checked => root.updateConfig("showMemoryGraph", checked)
    }

    SettingsToggleRow {
        text: I18n.tr("Network")
        checked: root.cfg.showNetwork ?? true
        onToggled: checked => root.updateConfig("showNetwork", checked)
    }

    SettingsToggleRow {
        enabled: root.cfg.showNetwork ?? true
        text: I18n.tr("Network graph")
        checked: root.cfg.showNetworkGraph ?? true
        onToggled: checked => root.updateConfig("showNetworkGraph", checked)
    }

    SettingsToggleRow {
        text: I18n.tr("Disk")
        checked: root.cfg.showDisk ?? true
        onToggled: checked => root.updateConfig("showDisk", checked)
    }

    SettingsToggleRow {
        text: I18n.tr("Top processes")
        checked: root.cfg.showTopProcesses ?? false
        onToggled: checked => root.updateConfig("showTopProcesses", checked)
    }

    SettingsButtonGroupRow {
        readonly property var counts: [3, 5, 10]
        visible: root.cfg.showTopProcesses ?? false
        text: I18n.tr("Process count")
        model: counts.map(count => String(count))
        currentIndex: Math.max(0, counts.indexOf(root.cfg.topProcessCount ?? 3))
        checkEnabled: false
        onSelectionChanged: (index, selected) => {
            if (!selected)
                return;
            root.updateConfig("topProcessCount", counts[index]);
        }
    }

    SettingsButtonGroupRow {
        visible: root.cfg.showTopProcesses ?? false
        text: I18n.tr("Sort by")
        model: ["CPU", "MEM"]
        currentIndex: (root.cfg.topProcessSortBy ?? "cpu") === "cpu" ? 0 : 1
        checkEnabled: false
        onSelectionChanged: (index, selected) => {
            if (!selected)
                return;
            root.updateConfig("topProcessSortBy", index === 0 ? "cpu" : "memory");
        }
    }

    SettingsDropdownRow {
        text: I18n.tr("Layout")
        options: [I18n.tr("Auto"), I18n.tr("Grid"), I18n.tr("List")]
        currentValue: {
            switch (root.cfg.layoutMode ?? "auto") {
            case "grid":
                return I18n.tr("Grid");
            case "list":
                return I18n.tr("List");
            default:
                return I18n.tr("Auto");
            }
        }
        onValueChanged: value => {
            switch (value) {
            case I18n.tr("Grid"):
                root.updateConfig("layoutMode", "grid");
                return;
            case I18n.tr("List"):
                root.updateConfig("layoutMode", "list");
                return;
            default:
                root.updateConfig("layoutMode", "auto");
            }
        }
    }
}
