import QtQuick
import qs.Widgets

DPopout {
    required property SystemTrayBar tray

    layerNamespace: "dms:tray-overflow"
    screen: tray.parentScreen
    popupWidth: tray.overflowRawWidth
    popupHeight: tray.overflowRawHeight
    content: tray.overflowContent
}
