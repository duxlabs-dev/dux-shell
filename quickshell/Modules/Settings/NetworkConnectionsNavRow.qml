import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services

SettingsNavRow {
    id: navRow

    property var parentModal

    visible: NetworkService.connectionEditorSupported
    iconName: "network_manage"
    title: I18n.tr("Connections", "settings page listing saved network connection profiles")
    hint: I18n.tr("Saved configurations")
    onClicked: keyboard => navRow.parentModal?.navigateTo("network_connections", keyboard)
}
