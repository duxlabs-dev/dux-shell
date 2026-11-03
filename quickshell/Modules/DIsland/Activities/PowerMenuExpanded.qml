pragma ComponentBehavior: Bound

import QtQuick
import qs.Modules.PowerMenu
import qs.Services

FocusScope {
    id: root

    required property var controller

    readonly property bool sheetActive: controller.expanded && controller.activeActivity === "powermenu"

    clip: true

    function focusFace() {
        powerContent.forceActiveFocus();
        return true;
    }

    function reportSize() {
        root.controller.setPowerMenuContentWidth(powerContent.desiredWidth);
        root.controller.setDestinationContentHeight("powermenu", powerContent.implicitHeight);
    }

    onSheetActiveChanged: {
        if (sheetActive)
            return;
        powerContent.cancelHold();
        powerContent.resetState();
    }

    PowerMenuContent {
        id: powerContent

        anchors.fill: parent
        focus: true
        onDesiredWidthChanged: root.reportSize()
        onImplicitHeightChanged: root.reportSize()
        onActiveFocusChanged: {
            if (!powerContent.activeFocus)
                powerContent.cancelHold();
        }
        onPowerActionRequested: action => {
            PopoutService.closeControlCenter();
            SessionService.executePowerAction(action);
        }
        onLockRequested: {
            PopoutService.closeControlCenter();
            IdleService.lockRequested();
        }
        onSwitchUserRequested: PopoutService.openSwitchUser()
        onCloseRequested: root.controller.requestCollapse()
    }

    Connections {
        target: root.controller

        function onSessionStarted(activityId) {
            if (activityId !== "powermenu")
                return;
            powerContent.cancelHold();
            powerContent.resetState();
            root.focusFace();
        }
    }

    Component.onCompleted: {
        root.reportSize();
        root.controller.markVisualsReady("powermenu");
    }
    Component.onDestruction: {
        powerContent.cancelHold();
        root.controller.setVisualsReady("powermenu", false);
    }
}
