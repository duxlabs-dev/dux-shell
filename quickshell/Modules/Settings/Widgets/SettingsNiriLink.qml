import QtQuick
import qs.Common
import qs.Services

// Stands where settings the niri page now owns used to be, so each lives in one place only.
SettingsNavRow {
    property string section: "windows"

    visible: CompositorService.isNiri
    iconName: "view_column"
    title: I18n.tr("Set in niri", "link row to the niri settings page, where these settings now live")
    onClicked: {
        SettingsUiState.niriSection = section;
        PopoutService.openSettingsWithTab("niri");
    }
}
