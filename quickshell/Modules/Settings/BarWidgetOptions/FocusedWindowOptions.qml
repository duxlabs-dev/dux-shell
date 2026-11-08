import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        settingKey: "barWidgetFocusedWindow"

        SettingsToggleRow {
            text: I18n.tr("Compact mode")
            checked: root.page.value("focusedWindowCompactMode")
            onToggled: checked => root.page.set("focusedWindowCompactMode", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Show icon")
            checked: root.page.value("focusedWindowShowIcon")
            onToggled: checked => root.page.set("focusedWindowShowIcon", checked)
        }

        SettingsButtonGroupRow {
            resetStore: root.page
            resetKeys: ["focusedWindowSize"]
            text: I18n.tr("Size")
            model: [I18n.tr("Small", "bar widget size option"), I18n.tr("Medium", "bar widget size option"), I18n.tr("Large", "bar widget size option"), I18n.tr("Largest", "bar widget size option")]
            currentIndex: Math.max(0, Math.min(3, root.page.value("focusedWindowSize")))
            onSelectionChanged: (index, selected) => {
                if (selected)
                    root.page.set("focusedWindowSize", index);
            }
        }
    }
}
