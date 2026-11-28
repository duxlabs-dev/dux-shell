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

        SettingsDropdownRow {
            readonly property var workspaceFilters: ["all", "current", "other"]

            resetStore: root.page
            resetKeys: ["runningAppsCurrentWorkspace", "runningAppsOtherWorkspaces"]
            text: I18n.tr("Workspaces", "Running apps filter label: which workspaces to show apps from")
            options: [I18n.tr("All", "Running apps workspace filter: show apps from all workspaces"), I18n.tr("Current workspace", "Running apps filter: only show apps from the active workspace"), I18n.tr("Other workspaces", "Running apps workspace filter: only show apps from non-active workspaces")]
            currentValue: root.page.value("runningAppsCurrentWorkspace") ? options[1] : (root.page.value("runningAppsOtherWorkspaces") ? options[2] : options[0])
            onValueChanged: value => {
                const mode = workspaceFilters[options.indexOf(value)] ?? "all";
                root.page.set("runningAppsCurrentWorkspace", mode === "current");
                root.page.set("runningAppsOtherWorkspaces", mode === "other");
            }
        }

        SettingsToggleRow {
            text: I18n.tr("Current display", "Running apps filter: only show apps from the same monitor")
            checked: root.page.value("runningAppsCurrentMonitor")
            onToggled: checked => root.page.set("runningAppsCurrentMonitor", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Scroll wheel")
            checked: root.page.value("scrollEnabled")
            onToggled: checked => root.page.set("scrollEnabled", checked)
        }
    }
}
