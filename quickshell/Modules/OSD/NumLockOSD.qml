import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

DOSD {
    id: root

    osdKind: "numLock"

    osdWidth: Theme.osdHeight
    osdHeight: Theme.osdHeight
    autoHideInterval: 2000
    enableMouseInteraction: false

    readonly property bool currentNumLockState: DMSService.numLockState
    property bool lastNumLockState: false
    property bool stateInitialized: false

    onCurrentNumLockStateChanged: {
        if (stateInitialized && lastNumLockState !== currentNumLockState && SettingsData.osdNumLockEnabled)
            root.show();
        lastNumLockState = currentNumLockState;
    }

    Component.onCompleted: {
        lastNumLockState = currentNumLockState;
        stateInitialized = true;
    }

    content: Item {
        OsdIcon {
            tonal: false
            anchors.centerIn: parent
            iconName: "dialpad"
            iconColor: Theme.primary
        }
    }
}
