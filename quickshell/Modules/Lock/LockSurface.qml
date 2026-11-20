pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Modules.ScreenCorners

FocusScope {
    id: root

    required property WlSessionLock lock
    required property var pam
    required property string sharedPasswordBuffer
    required property string screenName
    property bool inputRevealed: false
    signal inputRevealRequested(bool revealed)

    required property bool isLocked

    signal passwordChanged(string newPassword)
    signal unlockRequested

    HoverHandler {
        enabled: root.pam.awaitingActivityRetry
        onPointChanged: root.pam.retryFprintOnActivity()
    }

    PointHandler {
        onActiveChanged: {
            if (active)
                root.pam.retryFprintOnActivity();
        }
    }

    Keys.onPressed: event => {
        root.pam.retryFprintOnActivity();
        if (videoScreensaver.active && videoScreensaver.inputEnabled) {
            videoScreensaver.dismiss();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
    }

    LockScreenContent {
        id: lockContent

        anchors.fill: parent
        demoMode: false
        sessionLock: root.lock
        pam: root.pam
        passwordBuffer: root.sharedPasswordBuffer
        inputRevealed: root.inputRevealed
        onInputRevealRequested: revealed => root.inputRevealRequested(revealed)
        screenName: root.screenName
        enabled: !videoScreensaver.active
        focus: !videoScreensaver.active
        opacity: videoScreensaver.active ? 0 : 1
        onUnlockRequested: root.unlockRequested()
        onPasswordEdited: text => root.passwordChanged(text)

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }
    }

    VideoScreensaver {
        id: videoScreensaver
        anchors.fill: parent
        screenName: root.screenName
        onDismissed: Qt.callLater(() => lockContent.focusPasswordField())
    }

    RoundCorner {
        corner: "topLeft"
        visible: SettingsData.screenCornerMode !== "off"
        anchors { left: root.left; top: root.top }
    }
    RoundCorner {
        corner: "topRight"
        visible: SettingsData.screenCornerMode !== "off"
        anchors { right: root.right; top: root.top }
    }
    RoundCorner {
        corner: "bottomLeft"
        visible: SettingsData.screenCornerMode !== "off"
        anchors { left: root.left; bottom: root.bottom }
    }
    RoundCorner {
        corner: "bottomRight"
        visible: SettingsData.screenCornerMode !== "off"
        anchors { right: root.right; bottom: root.bottom }
    }

    Component.onCompleted: forceActiveFocus()

    onIsLockedChanged: {
        if (isLocked) {
            forceActiveFocus();
            lockContent.resetLockState();
            if (SettingsData.lockScreenVideoEnabled) {
                videoScreensaver.start();
            }
            return;
        }
        lockContent.unlocking = false;
    }
}
