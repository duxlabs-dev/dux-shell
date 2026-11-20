import QtQuick
import qs.Modules.ControlCenter.Details

OsdDetailSheet {
    required property var osd

    BrightnessDetail {
        anchors.fill: parent
        initialDeviceName: osd.device?.name ?? ""
        screenName: osd.screen?.name ?? ""
        screenModel: osd.screen?.model ?? ""
    }
}
