import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        settingKey: "barWidgetNetworkMonitor"

        SettingsToggleRow {
            text: I18n.tr("Hide when idle", "network speed widget option, hides the widget while traffic is low")
            description: I18n.tr("While download and upload are both under 1 KB/s", "network speed widget option description for hide when idle")
            checked: root.page.value("hideWhenIdle") === true
            onToggled: checked => root.page.set("hideWhenIdle", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Compact mode")
            description: I18n.tr("Whole numbers, at most three digits", "network speed widget option, shows 1 MB/s instead of 1023.4 KB/s")
            checked: root.page.value("compactMode") === true
            onToggled: checked => root.page.set("compactMode", checked)
        }
    }
}
