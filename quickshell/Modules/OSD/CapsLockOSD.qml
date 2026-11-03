import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

DOSD {
    id: root

    osdKind: "capsLock"

    osdWidth: Theme.osdHeight
    osdHeight: Theme.osdHeight
    autoHideInterval: 2000
    enableMouseInteraction: false

    property bool lastCapsLockState: false

    Connections {
        target: DMSService

        function onCapsLockStateChanged() {
            if (lastCapsLockState !== DMSService.capsLockState && SettingsData.osdCapsLockEnabled) {
                root.show();
            }
            lastCapsLockState = DMSService.capsLockState;
        }
    }

    Component.onCompleted: {
        lastCapsLockState = DMSService.capsLockState;
    }

    content: Item {
        OsdIcon {
            tonal: false
            anchors.centerIn: parent
            iconName: DMSService.capsLockState ? "shift_lock" : "shift_lock_off"
            iconColor: Theme.primary
        }
    }
}
