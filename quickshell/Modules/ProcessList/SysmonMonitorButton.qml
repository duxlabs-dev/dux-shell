import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

DButton {
    // "processes", "disk" or a device key
    property string target: "processes"

    text: I18n.tr("System Monitor", "button that opens the system monitor window")
    iconName: "open_in_new"
    variant: "text"
    onClicked: {
        PopoutService.showProcessListModal(target);
        PopoutService.processListPopout?.close();
    }
}
