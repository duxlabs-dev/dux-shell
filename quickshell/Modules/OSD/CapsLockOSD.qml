import QtQuick
import qs.Common
import qs.Services

IconOSD {
    id: root

    osdKind: "capsLock"
    iconName: DMSService.capsLockState ? "shift_lock" : "shift_lock_off"

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
}
