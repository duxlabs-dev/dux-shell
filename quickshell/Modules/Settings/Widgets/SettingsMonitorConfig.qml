pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import "../../../Services/SysmonCatalog.js" as SysmonCatalog

Column {
    id: root

    required property var config
    property bool processes: false
    property color slotColor: SettingsMetrics.rowColor
    // Tighter buttons without check marks, for narrow hosts such as the dash options sheet.
    property bool dense: false
    readonly property bool styled: config.layout === "tiles"
    readonly property string styleKey: styled ? "style" : config.layout === "bars" ? "barStyle" : config.layout === "list" ? "listStyle" : ""
    readonly property var styleChoices: ({
            "style": {
                "labels": [I18n.tr("Icon", "system monitor tile style option"), I18n.tr("Meter", "system monitor tile style option"), I18n.tr("Ring", "system monitor tile style option"), I18n.tr("Graph", "system monitor tile style option")],
                "values": ["icon", "meter", "ring", "graph"]
            },
            "barStyle": {
                "labels": [I18n.tr("Brackets", "system monitor bars style option"), I18n.tr("Tiles", "system monitor layout and style option")],
                "values": ["brackets", "tiles"]
            },
            "listStyle": {
                "labels": [I18n.tr("Rows", "system monitor list style option"), I18n.tr("Tiles", "system monitor layout and style option")],
                "values": ["rows", "tiles"]
            }
        })

    signal configEdited(string key, var value)

    component ConfigButtons: SettingsButtonGroupRow {
        id: buttons

        property bool dense: false

        checkEnabled: !dense

        Binding on buttonPadding {
            when: buttons.dense
            value: Theme.spacingXS
        }
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        title: I18n.tr("Layout", "noun, settings section title for arrangement options")
        slotColor: root.slotColor

        ConfigButtons {
            dense: root.dense
            text: I18n.tr("Layout", "noun, settings section title for arrangement options")
            model: values.map(id => SysmonService.layoutName(id))
            values: ["tiles", "list", "bars", "graphs"]
            value: root.config.layout
            onValueSelected: value => root.configEdited("layout", value)
        }

        ConfigButtons {
            dense: root.dense
            visible: root.styleKey !== ""
            text: I18n.tr("Style", "noun, visual style option label for a widget or the dock")
            model: root.styleChoices[root.styleKey]?.labels ?? []
            values: root.styleChoices[root.styleKey]?.values ?? []
            value: root.config[root.styleKey] ?? ""
            onValueSelected: value => root.configEdited(root.styleKey, value)
        }

        ConfigButtons {
            dense: root.dense
            visible: root.config.layout === "bars"
            text: I18n.tr("Orientation", "system monitor bars: horizontal or vertical bars")
            model: [I18n.tr("Auto", "system monitor bars orientation: follow the widget shape"), I18n.tr("Horizontal", "system monitor bars orientation"), I18n.tr("Vertical", "system monitor bars orientation")]
            values: ["auto", "horizontal", "vertical"]
            value: root.config.barOrientation
            onValueSelected: value => root.configEdited("barOrientation", value)
        }

        SettingsToggleRow {
            visible: root.config.layout === "bars"
            text: I18n.tr("Names", "system monitor bars: show device names")
            checked: root.config.barNames
            onToggled: checked => root.configEdited("barNames", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Show header", "system monitor widget option")
            checked: root.config.showHeader
            onToggled: checked => root.configEdited("showHeader", checked)
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
                    root.configEdited("title", value);
            }
        }
    }

    SettingsCard {
        title: I18n.tr("Metrics", "system monitor settings section title for the shown devices")
        slotColor: root.slotColor

        SettingsMetricList {
            metrics: root.config.metrics
            allowGraph: (root.config.layout === "list" && root.config.listStyle === "rows") || (root.styled && root.config.style !== "graph")
            onMetricsEdited: metrics => root.configEdited("metrics", metrics)
        }

        ConfigButtons {
            dense: root.dense
            visible: root.config.layout === "graphs"
            text: I18n.tr("Legend", "system monitor chart legend placement")
            model: [I18n.tr("Off", "system monitor chart legend option"), I18n.tr("Inline", "system monitor chart legend option"), I18n.tr("List", "noun, list view mode option")]
            values: ["off", "inline", "list"]
            value: root.config.legend
            onValueSelected: value => root.configEdited("legend", value)
        }

        ConfigButtons {
            dense: root.dense
            visible: root.config.layout !== "bars"
            text: I18n.tr("Graph time range", "system monitor widget option")
            model: ["1m", "5m", "10m", "30m"]
            values: [60, 300, 600, 1800]
            value: root.config.graphInterval
            onValueSelected: value => root.configEdited("graphInterval", value)
        }
    }

    SettingsCard {
        title: I18n.tr("Top processes", "system monitor widget option")
        visible: root.processes
        slotColor: root.slotColor

        SettingsToggleRow {
            text: I18n.tr("Top processes", "system monitor widget option")
            checked: root.config.showTopProcesses
            onToggled: checked => root.configEdited("showTopProcesses", checked)
        }

        ConfigButtons {
            dense: root.dense
            visible: root.config.showTopProcesses
            text: I18n.tr("Process count", "system monitor widget option")
            model: ["3", "5", "10"]
            values: [3, 5, 10]
            value: root.config.topProcessCount
            onValueSelected: value => root.configEdited("topProcessCount", value)
        }

        ConfigButtons {
            dense: root.dense
            visible: root.config.showTopProcesses
            text: I18n.tr("Sort by", "system monitor widget option")
            model: [I18n.tr("CPU", "processor label in system monitor"), I18n.tr("Memory", "system RAM label in system monitor")]
            values: ["cpu", "memory"]
            value: root.config.topProcessSortBy
            onValueSelected: value => root.configEdited("topProcessSortBy", value)
        }
    }
}
