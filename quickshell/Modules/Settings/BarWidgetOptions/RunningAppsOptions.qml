import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        settingKey: "barWidgetRunningApps"

        SettingsToggleRow {
            text: I18n.tr("Compact mode")
            checked: root.page.value("runningAppsCompactMode")
            onToggled: checked => root.page.set("runningAppsCompactMode", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Group by app")
            checked: root.page.value("runningAppsGroupByApp")
            onToggled: checked => root.page.set("runningAppsGroupByApp", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Current workspace", "Running apps filter: only show apps from the active workspace")
            checked: root.page.value("runningAppsCurrentWorkspace")
            onToggled: checked => root.page.set("runningAppsCurrentWorkspace", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Current display", "Running apps filter: only show apps from the same monitor")
            checked: root.page.value("runningAppsCurrentMonitor")
            onToggled: checked => root.page.set("runningAppsCurrentMonitor", checked)
        }
    }
}
