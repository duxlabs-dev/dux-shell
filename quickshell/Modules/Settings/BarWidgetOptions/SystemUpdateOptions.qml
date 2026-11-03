import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        settingKey: "barWidgetSystemUpdate"

        SettingsToggleRow {
            text: I18n.tr("Hide when no updates")
            checked: root.page.value("hideWhenIdle")
            onToggled: checked => root.page.set("hideWhenIdle", checked)
        }

        SettingsNavRow {
            iconName: "system_update_alt"
            title: I18n.tr("Software updates", "settings page, modal and bar widget title, DMS and system package updates")
            hint: I18n.tr("DMS and system updates", "settings sidebar hint for the software updates page")
            onClicked: keyboard => root.page.parentModal?.navigateTo("updater", keyboard)
        }
    }
}
