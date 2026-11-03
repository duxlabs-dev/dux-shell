import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        settingKey: "barWidgetClock"

        SettingsToggleRow {
            text: I18n.tr("Compact mode")
            checked: root.page.value("clockCompactMode")
            onToggled: checked => root.page.set("clockCompactMode", checked)
        }

        SettingsButtonGroupRow {
            resetStore: root.page
            resetKeys: ["clockDateOrder"]
            text: I18n.tr("Order", "noun, clock widget option for time and date order")
            enabled: !root.page.value("clockCompactMode")
            model: [I18n.tr("Time first"), I18n.tr("Date first")]
            currentIndex: root.page.value("clockDateOrder") === "dateFirst" ? 1 : 0
            onSelectionChanged: (index, selected) => {
                if (!selected)
                    return;
                root.page.set("clockDateOrder", index === 1 ? "dateFirst" : "timeFirst");
            }
        }

        SettingsToggleRow {
            text: I18n.tr("Notification badge", "clock widget option: unread notification count next to the time")
            checked: root.page.value("clockNotificationBadge")
            onToggled: checked => root.page.set("clockNotificationBadge", checked)
        }

        SettingsDropdownRow {
            readonly property var actions: ["dash", "settings", "command", "none"]

            resetStore: root.page
            resetKeys: ["clockClickAction"]
            text: I18n.tr("Click action", "clock widget option: what clicking the clock opens")
            options: [I18n.tr("Dashboard"), I18n.tr("Time & weather"), I18n.tr("Custom command"), I18n.tr("None", "bar click action")]
            currentValue: options[actions.indexOf(root.page.value("clockClickAction"))] ?? options[0]
            onValueChanged: value => root.page.set("clockClickAction", actions[options.indexOf(value)] ?? "dash")
        }

        SettingsTextFieldRow {
            resetStore: root.page
            resetKeys: ["clockClickCommand"]
            text: I18n.tr("Custom command")
            visible: root.page.value("clockClickAction") === "command"
            placeholderText: "gnome-clocks"
            value: root.page.value("clockClickCommand")
            onEditingFinished: value => root.page.set("clockClickCommand", value.trim())
        }

        SettingsNavRow {
            iconName: "schedule"
            title: I18n.tr("Time & weather")
            hint: I18n.tr("Clock format, calendar, weather location")
            onClicked: keyboard => root.page.parentModal?.navigateTo("time_weather", keyboard)
        }
    }
}
