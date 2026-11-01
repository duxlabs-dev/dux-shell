pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modals.DLauncherV2

FocusScope {
    id: root

    required property var controller
    required property var launcherController
    property var transientSurfaceTracker: null
    property var effectiveScreen: null
    property real screenWidth: effectiveScreen?.width ?? 1920
    property real screenHeight: effectiveScreen?.height ?? 1080
    property real alignedX: 0
    property real alignedY: 0

    clip: true

    function focusFace() {
        launcherContent.searchField.forceActiveFocus();
        return true;
    }

    function initializeSession() {
        const pendingQuery = root.controller.launcherPendingQuery;
        const targetQuery = pendingQuery || (SettingsData.rememberLastQuery ? (SessionData.launcherLastQuery || "") : "");
        const targetMode = root.controller.launcherPendingMode || SessionData.getLauncherRestoreMode();
        // Used once: the face stays loaded between opens.
        root.controller.launcherPendingQuery = "";
        root.controller.launcherPendingMode = "";

        launcherContent.closeTransientUi?.();
        launcherContent.suspendSearchUpdates = true;
        launcherContent.searchField.text = targetQuery;
        launcherContent.suspendSearchUpdates = false;
        launcherController.openSession(targetQuery, !!pendingQuery, targetMode, true);

        launcherContent.resetScroll();
        root.focusFace();
        if (!pendingQuery) {
            launcherContent.searchField.selectAll();
            return;
        }
        launcherContent.searchField.cursorPosition = targetQuery.length;
    }

    QtObject {
        id: hostContract

        readonly property bool spotlightOpen: root.controller.launcherSessionActive
        readonly property bool isClosing: false
        readonly property bool contentVisible: true
        readonly property var effectiveScreen: root.effectiveScreen
        readonly property real screenWidth: root.screenWidth
        readonly property real screenHeight: root.screenHeight
        readonly property real alignedX: root.alignedX
        readonly property real alignedY: root.alignedY

        function hide() {
            root.controller.requestCollapse();
        }
    }

    SpotlightLauncherContent {
        id: launcherContent

        anchors.fill: parent
        anchors.margins: Theme.spacingM
        parentModal: hostContract
        resultsInset: 0
        controllerOverride: root.launcherController
        transientSurfaceTracker: root.transientSurfaceTracker
        showResultsWithoutQuery: true
        resizeAnimated: false
        maxResultsHeight: Math.max(120, root.controller.launcherMaxHeight - Theme.spacingM * 2 - launcherContent.searchAreaHeight - launcherContent.actionPanelHeight)

        onImplicitHeightChanged: root.controller.setDestinationContentHeight("launcher", implicitHeight + Theme.spacingM * 2)
    }

    onActiveFocusChanged: root.controller.launcherInputFocused = activeFocus

    Connections {
        target: root.controller

        // Synchronous so the results are ready before the first morph frame.
        function onSessionStarted(activityId) {
            if (activityId === "launcher")
                root.initializeSession();
        }
    }

    Component.onCompleted: root.controller.markVisualsReady("launcher")
    Component.onDestruction: root.controller.launcherInputFocused = false
}
