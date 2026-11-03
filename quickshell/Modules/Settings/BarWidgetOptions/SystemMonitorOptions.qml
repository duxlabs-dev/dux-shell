import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    Component.onCompleted: DgopService.ensureMeta()

    readonly property string type: page.widgetType
    readonly property var gpuLabels: (DgopService.availableGpus ?? []).map(gpu => (gpu.driver ? gpu.driver.toUpperCase() + " " : "") + (gpu.displayName ?? ""))
    readonly property var mountLabels: {
        const mounts = DgopService.diskMounts ?? [];
        if (mounts.length === 0)
            return ["/"];
        return mounts.map(mount => mount.mount);
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        settingKey: "barWidgetSystemMonitor"

        SettingsToggleRow {
            text: I18n.tr("Force padding")
            description: I18n.tr("Dynamic width")
            checked: root.page.value("minimumWidth") !== false
            onToggled: checked => root.page.set("minimumWidth", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Show swap")
            visible: root.type === "memUsage"
            checked: root.page.value("showSwap") === true
            onToggled: checked => root.page.set("showSwap", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Show in GB")
            visible: root.type === "memUsage"
            checked: root.page.value("showInGb") === true
            onToggled: checked => root.page.set("showInGb", checked)
        }

        SettingsDropdownRow {
            text: I18n.tr("GPU")
            visible: root.type === "gpuTemp"
            options: root.gpuLabels
            emptyText: I18n.tr("No GPU detected", "empty state when no graphics card is found")
            currentValue: root.gpuLabels[root.page.value("selectedGpuIndex")] ?? ""
            onValueChanged: value => {
                const index = root.gpuLabels.indexOf(value);
                if (index < 0)
                    return;
                root.page.set("selectedGpuIndex", index);
                root.page.set("pciId", DgopService.availableGpus[index]?.pciId ?? "");
            }
        }

        SettingsDropdownRow {
            resetStore: root.page
            resetKeys: ["mountPath"]
            text: I18n.tr("Mount", "noun, dropdown label for the disk mount point")
            visible: root.type === "diskUsage"
            options: root.mountLabels
            currentValue: root.page.value("mountPath") ?? "/"
            onValueChanged: value => root.page.set("mountPath", value)
        }

        SettingsToggleRow {
            text: I18n.tr("Show mount path")
            visible: root.type === "diskUsage"
            checked: root.page.value("showMountPath") === true
            onToggled: checked => root.page.set("showMountPath", checked)
        }

        SettingsDropdownRow {
            resetStore: root.page
            resetKeys: ["diskUsageMode"]
            readonly property var labels: [I18n.tr("Percentage"), I18n.tr("Total", "disk usage format option, total disk size"), I18n.tr("Remaining", "disk usage format option, free disk space"), I18n.tr("Remaining / Total")]

            text: I18n.tr("Disk usage format")
            visible: root.type === "diskUsage"
            options: labels
            currentValue: labels[root.page.value("diskUsageMode")] ?? labels[0]
            onValueChanged: value => {
                const index = labels.indexOf(value);
                if (index >= 0)
                    root.page.set("diskUsageMode", index);
            }
        }
    }
}
