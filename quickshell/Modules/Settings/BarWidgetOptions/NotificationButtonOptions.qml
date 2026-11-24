import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        settingKey: "barWidgetNotificationButton"

        SettingsToggleRow {
            text: I18n.tr("Hide when no notifications", "notification center bar widget option, hides the widget while there are no notifications")
            checked: root.page.value("hideWhenEmpty") === true
            onToggled: checked => root.page.set("hideWhenEmpty", checked)
        }
    }
}
