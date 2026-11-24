import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Modules.Network

DModal {
    id: root
    visible: false
    layerNamespace: "dms:wifi-qrcode"

    property bool disablePopupTransparency: true
    modalWidth: 420
    modalHeight: Math.min(dialog.implicitHeight, screenHeight - Theme.spacingXL * 2)
    directContent: dialog
    onBackgroundClicked: hide()
    onDialogClosed: dialog.cleanup()
    onOpened: Qt.callLater(() => dialog.forceActiveFocus())

    function show(ssid) {
        dialog.load(ssid);
    }

    function hide() {
        close();
    }

    WifiQRCodeDialog {
        id: dialog
        onReady: root.open()
        onRejected: root.hide()
    }
}
