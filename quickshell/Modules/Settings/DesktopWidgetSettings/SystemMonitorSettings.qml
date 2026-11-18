pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import "../../../Services/SysmonCatalog.js" as SysmonCatalog

DesktopWidgetInstanceSettings {
    id: root

    readonly property var config: SysmonCatalog.normalizeConfig(cfg, SysmonCatalog.defaultDesktopConfig())
    readonly property bool styled: config.layout === "tiles" || config.layout === "list"

    optionsTitle: I18n.tr("Layout", "noun, settings section title for arrangement options")
    backgroundOption: true

    SettingsButtonGroupRow {
        text: I18n.tr("Layout", "noun, settings section title for arrangement options")
        model: [I18n.tr("Tiles", "system monitor layout and background option"), I18n.tr("List", "noun, list view mode option"), I18n.tr("Bars", "system monitor layout option: bar meters, not the shell bars", true), I18n.tr("Graphs", "system monitor layout option")]
        values: ["tiles", "list", "bars", "graphs"]
        value: root.config.layout
        onValueSelected: value => root.updateConfig("layout", value)
    }

    SettingsButtonGroupRow {
        visible: root.styled
        text: I18n.tr("Style", "noun, visual style option label for a widget or the dock")
        model: [I18n.tr("Classic", "system monitor tile style option"), I18n.tr("Icon", "system monitor tile style option"), I18n.tr("Meter", "system monitor tile style option"), I18n.tr("Ring", "system monitor tile style option"), I18n.tr("Graph", "system monitor tile style option")]
        values: ["classic", "icon", "meter", "ring", "graph"]
        value: root.config.style
        onValueSelected: value => root.updateConfig("style", value)
    }

    SettingsButtonGroupRow {
        visible: root.config.layout === "bars"
        text: I18n.tr("Orientation", "system monitor bars: horizontal or vertical bars")
        model: [I18n.tr("Auto", "system monitor bars orientation: follow the widget shape"), I18n.tr("Horizontal", "system monitor bars orientation"), I18n.tr("Vertical", "system monitor bars orientation")]
        values: ["auto", "horizontal", "vertical"]
        value: root.config.barOrientation
        onValueSelected: value => root.updateConfig("barOrientation", value)
    }

    SettingsToggleRow {
        visible: root.config.layout === "bars"
        text: I18n.tr("Names", "system monitor bars: show device names")
        checked: root.config.barNames
        onToggled: checked => root.updateConfig("barNames", checked)
    }

    SettingsToggleRow {
        text: I18n.tr("Show header")
        checked: root.config.showHeader
        onToggled: checked => root.updateConfig("showHeader", checked)
    }

    SettingsTextFieldRow {
        visible: root.config.showHeader
        text: I18n.tr("Title", "noun, window title match field, also name field label")
        value: root.config.title
        alwaysFloatLabel: true
        placeholderText: SysmonCatalog.shortCpuName(DgopService.cpuModel) || DgopService.hostname
        maximumLength: SysmonCatalog.maxSuffix
        onEditingFinished: value => {
            if (value !== root.config.title)
                root.updateConfig("title", value);
        }
    }

    cards: [
        SettingsCard {
            title: I18n.tr("Metrics", "system monitor settings section title for the shown devices")

            SettingsMetricList {
                metrics: root.config.metrics
                allowGraph: root.styled && !(root.config.layout === "tiles" && root.config.style === "graph")
                onMetricsEdited: metrics => root.updateConfig("metrics", metrics)
            }

            SettingsButtonGroupRow {
                visible: root.config.layout === "graphs"
                text: I18n.tr("Legend", "system monitor chart legend placement")
                model: [I18n.tr("Off", "system monitor chart legend option"), I18n.tr("Inline", "system monitor chart legend option"), I18n.tr("List", "noun, list view mode option")]
                values: ["off", "inline", "list"]
                value: root.config.legend
                onValueSelected: value => root.updateConfig("legend", value)
            }

            SettingsButtonGroupRow {
                visible: root.config.layout !== "bars"
                text: I18n.tr("Graph time range")
                model: ["1m", "5m", "10m", "30m"]
                values: [60, 300, 600, 1800]
                value: root.config.graphInterval
                onValueSelected: value => root.updateConfig("graphInterval", value)
            }
        },
        SettingsCard {
            title: I18n.tr("Top processes")

            SettingsToggleRow {
                text: I18n.tr("Top processes")
                checked: root.config.showTopProcesses
                onToggled: checked => root.updateConfig("showTopProcesses", checked)
            }

            SettingsButtonGroupRow {
                visible: root.config.showTopProcesses
                text: I18n.tr("Process count")
                model: ["3", "5", "10"]
                values: [3, 5, 10]
                value: root.config.topProcessCount
                onValueSelected: value => root.updateConfig("topProcessCount", value)
            }

            SettingsButtonGroupRow {
                visible: root.config.showTopProcesses
                text: I18n.tr("Sort by")
                model: [I18n.tr("CPU", "processor label in system monitor"), I18n.tr("Memory", "system RAM label in system monitor")]
                values: ["cpu", "memory"]
                value: root.config.topProcessSortBy
                onValueSelected: value => root.updateConfig("topProcessSortBy", value)
            }
        }
    ]
}
