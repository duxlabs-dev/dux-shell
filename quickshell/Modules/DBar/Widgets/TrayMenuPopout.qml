import QtQuick
import qs.Widgets

DPopout {
    required property SystemTrayBar tray
    readonly property bool openedByHover: tray.trayMenuOpenedByHover

    layerNamespace: "dms:tray-menu"
    screen: tray.parentScreen
    popupWidth: tray.trayMenuWidth
    popupHeight: tray.trayMenuHeight
    content: tray.trayMenuContent
    contentHandlesKeys: true
    onOpened: {
        contentLoader.item?.entryStack?.clear();
        contentLoader.item?.forceActiveFocus();
    }
}
