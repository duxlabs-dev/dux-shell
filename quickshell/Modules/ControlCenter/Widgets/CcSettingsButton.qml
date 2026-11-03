import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Services
import qs.DCommon.Widgets

DActionButton {
    property string settingsTab: ""

    buttonSize: CcMetrics.headerActionSize
    iconSize: CcMetrics.headerActionIconSize
    iconName: "settings"
    iconColor: Theme.surfaceText
    Accessible.name: I18n.tr("Settings")
    onClicked: {
        PopoutService.closeControlCenter();
        PopoutService.openSettingsWithTab(settingsTab);
    }
}
