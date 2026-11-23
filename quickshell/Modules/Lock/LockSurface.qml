pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Modules.ScreenCorners

FocusScope {
    id: root

    required property WlSessionLock lock
    required property var pam
    required property string sharedPasswordBuffer
    required property string screenName
    required property bool lockUiVisible
    property bool inputRevealed: false
    property bool fadeCompletionReported: false
    signal inputRevealRequested(bool revealed)
    signal lockUiFadeFinished()

    required property bool isLocked

    signal passwordChanged(string newPassword)
    signal unlockRequested

    function completeLockUiFadeIfNeeded() {
        if (IdleService.lockTransitionPhase !== "fadingLockUi")
            return;
        if (root.lockUiVisible !== false)
            return;
        if (lockContent.uiOpacity !== 0)
            return;
        if (fadeCompletionReported)
            return;
        fadeCompletionReported = true;
        root.lockUiFadeFinished();
    }

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
        uiOpacity: (root.lockUiVisible && !videoScreensaver.active) ? 1 : 0
        onUnlockRequested: root.unlockRequested()
        onPasswordEdited: text => root.passwordChanged(text)

        Behavior on uiOpacity {
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                // Video screensaver can hold opacity at zero, so completion must not depend on animation start.
                onRunningChanged: {
                    if (!running)
                        completeLockUiFadeIfNeeded()
                }
            }
        }
    }

    VideoScreensaver {
        id: videoScreensaver
        anchors.fill: parent
        screenName: root.screenName
        onDismissed: Qt.callLater(() => lockContent.focusPasswordField())
    }

    Loader {
        anchors.fill: parent
        active: SettingsData.screenCornersEnabled
        sourceComponent: ScreenCornerShape {}
    }

    onLockUiVisibleChanged: {
        if (lockUiVisible) {
            fadeCompletionReported = false;
            return;
        }
        Qt.callLater(completeLockUiFadeIfNeeded)
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
