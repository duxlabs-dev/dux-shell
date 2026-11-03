import QtQuick
import qs.Common
import qs.Modules.PowerMenu
import qs.Widgets

DPopout {
    id: root

    signal powerActionRequested(string action)
    signal lockRequested
    signal switchUserRequested

    layerNamespace: "dms:power-menu"
    popupWidth: contentLoader.item?.desiredWidth ?? 400
    popupHeight: contentLoader.item ? contentLoader.item.implicitHeight : 300
    triggerWidth: 40
    positioning: ""
    shouldBeVisible: false

    onBackgroundClicked: {
        contentLoader.item?.cancelHold();
        close();
    }

    onOpened: Qt.callLater(() => {
        contentLoader.item?.resetState();
        contentLoader.item?.forceActiveFocus();
    })

    onPopoutClosed: contentLoader.item?.cancelHold()

    content: Component {
        PowerMenuContent {
            anchors.fill: parent
            focus: true
            onPowerActionRequested: action => root.powerActionRequested(action)
            onLockRequested: root.lockRequested()
            onSwitchUserRequested: root.switchUserRequested()
            onCloseRequested: root.close()
        }
    }
}
