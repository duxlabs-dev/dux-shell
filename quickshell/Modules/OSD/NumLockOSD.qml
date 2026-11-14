import QtQuick
import qs.Common
import qs.Services

IconOSD {
    id: root

    osdKind: "numLock"
    iconName: "dialpad"
    iconColor: currentNumLockState ? Theme.primary : Theme.outline

    readonly property bool currentNumLockState: DMSService.numLockState
    property bool lastNumLockState: false
    property bool stateInitialized: false

    onCurrentNumLockStateChanged: {
        if (stateInitialized && DMSService.evdevStateInitialized && lastNumLockState !== currentNumLockState)
            root.show();
        lastNumLockState = currentNumLockState;
    }

    Component.onCompleted: {
        lastNumLockState = currentNumLockState;
        stateInitialized = true;
    }
}
