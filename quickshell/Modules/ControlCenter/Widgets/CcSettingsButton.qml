import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Services
import qs.DCommon.Widgets

DActionButton {
    property string settingsTab: ""
    property var parentPopout: null

    buttonSize: CcMetrics.headerActionSize
    iconSize: CcMetrics.headerActionIconSize
    iconName: "settings"
    iconColor: Theme.surfaceText
    Accessible.name: I18n.tr("Settings")
    onClicked: {
        if (parentPopout)
            parentPopout.close();
        else
            PopoutService.closeControlCenter();
        PopoutService.openSettingsWithTab(settingsTab);
    }
}
