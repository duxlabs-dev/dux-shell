import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services

SettingsCard {
    id: navCard

    property var parentModal

    visible: NetworkService.connectionEditorSupported

    SettingsNavRow {
        iconName: "network_manage"
        title: I18n.tr("All connections", "settings link to the list of every saved network connection")
        onClicked: keyboard => navCard.parentModal?.navigateTo("network_connections", keyboard)
    }
}
