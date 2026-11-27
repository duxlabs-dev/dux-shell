import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import "../../../Services/SysmonCatalog.js" as SysmonCatalog

Column {
    id: root

    property var page: null

    readonly property var choices: SysmonCatalog.barChoices
    readonly property var metrics: SysmonService.widgetMetrics(page?.entry)

    function apply(edited) {
        if (JSON.stringify(edited) === JSON.stringify(metrics))
            return;
        const updates = {
            "metrics": edited
        };
        if (page.entry?.selectedGpuIndex !== undefined) {
            updates.selectedGpuIndex = undefined;
            updates.pciId = undefined;
        }
        page.setMany(updates);
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        settingKey: "barWidgetSystemMonitor"
        title: I18n.tr("Entries", "system monitor bar widget: ordered list of shown devices")

        SettingsMetricList {
            metrics: root.metrics
            allowGraph: false
            allowDeviceOptions: true
            onMetricsEdited: metrics => root.apply(metrics)
        }

        SettingsButtonGroupRow {
            resetStore: root.page
            resetKeys: ["separator"]
            text: I18n.tr("Separator", "bar system monitor widget option: what is drawn between entries")
            visible: root.metrics.length >= 2
            model: [I18n.tr("Gap", "bar system monitor widget separator option"), I18n.tr("Line", "bar system monitor widget separator option"), I18n.tr("Dot", "bar system monitor widget separator option"), I18n.tr("Separate", "bar system monitor widget separator option: one pill per entry")]
            values: root.choices.separator
            value: root.page.value("separator")
            onValueSelected: v => root.page.set("separator", v)
        }
    }

    SettingsCard {
        settingKey: "barWidgetSystemMonitorAppearance"
        title: I18n.tr("Appearance", "settings section title for visual options")

        SettingsButtonGroupRow {
            resetStore: root.page
            resetKeys: ["style"]
            text: I18n.tr("Style", "noun, visual style option label for a widget or the dock")
            model: [I18n.tr("Icon", "system monitor tile style option"), I18n.tr("Meter", "system monitor tile style option"), I18n.tr("Ring", "system monitor tile style option"), I18n.tr("Graph", "system monitor tile style option")]
            values: root.choices.style
            value: root.page.value("style")
            onValueSelected: v => root.page.set("style", v)
        }

        SettingsButtonGroupRow {
            resetStore: root.page
            resetKeys: ["label"]
            text: I18n.tr("Label", "bar system monitor widget option: icon, name, both or none")
            model: [I18n.tr("Icon", "system monitor tile style option"), I18n.tr("Name", "bar system monitor widget label: the device name"), I18n.tr("Both", "bar system monitor widget label: icon and device name"), I18n.tr("None", "bar system monitor widget label: nothing")]
            values: root.choices.label
            value: root.page.value("label")
            onValueSelected: v => root.page.set("label", v)
        }

        SettingsColorPicker {
            resetStore: root.page
            resetKeys: ["colorMode", "customColor"]
            showDefault: true
            defaultColor: Theme.widgetIconColor
            colorMode: root.page.value("colorMode")
            customColor: root.page.value("customColor")
            onColorModeSelected: mode => root.page.set("colorMode", mode)
            onCustomColorSelected: color => root.page.set("customColor", color.toString())
        }

        SettingsButtonGroupRow {
            resetStore: root.page
            resetKeys: ["popout"]
            text: I18n.tr("Popout", "bar system monitor widget option: what opens when it is clicked")
            model: [I18n.tr("Compact", "bar system monitor widget popout option"), I18n.tr("Processes", "bar system monitor widget popout option"), I18n.tr("Device", "bar system monitor widget popout option"), I18n.tr("Overview", "bar system monitor widget popout option")]
            values: root.choices.popout
            value: root.page.value("popout")
            onValueSelected: v => root.page.set("popout", v)
        }
    }
}
