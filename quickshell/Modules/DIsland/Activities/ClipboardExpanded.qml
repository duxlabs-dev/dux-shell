pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modals.Clipboard
import qs.Modals.Common
import qs.Services

FocusScope {
    id: root

    required property var controller
    property var transientSurfaceTracker: null
    property var effectiveScreen: null
    property real alignedX: 0
    property real alignedY: 0

    clip: true

    function focusFace() {
        clipboardContent.searchField?.forceActiveFocus();
        return true;
    }

    function beginSession() {
        clipboardContent.resetState();
        if (ClipboardService.clipboardAvailable)
            ClipboardService.refresh();
        clipboardContent.searchField.text = "";
        root.focusFace();
    }

    QtObject {
        id: hostContract

        readonly property var effectiveScreen: root.effectiveScreen
        readonly property real alignedX: root.alignedX
        readonly property real alignedY: root.alignedY
    }

    Ref {
        service: ClipboardService
    }

    ConfirmModal {
        id: clearConfirmDialog

        confirmButtonText: I18n.tr("Clear All")
        confirmButtonColor: Theme.primary
        useOverlayLayer: true
        onShouldBeVisibleChanged: {
            root.controller.keyboardYielded = shouldBeVisible;
            if (shouldBeVisible) {
                selectedButton = 0;
                keyboardNavigation = true;
                return;
            }
            Qt.callLater(root.focusFace);
        }
    }

    ClipboardHistoryContent {
        id: clipboardContent

        anchors.fill: parent
        surfaceHost: hostContract
        transientSurfaceTracker: root.transientSurfaceTracker
        clearConfirmDialog: clearConfirmDialog
        onCloseRequested: root.controller.requestCollapse()
        onInstantCloseRequested: root.controller.requestCollapse()
    }

    Connections {
        target: root.controller

        function onSessionStarted(activityId) {
            if (activityId === "clipboard")
                Qt.callLater(root.beginSession);
        }
    }

    Component.onCompleted: root.controller.markVisualsReady("clipboard")
    Component.onDestruction: {
        root.controller.keyboardYielded = false;
        root.controller.setVisualsReady("clipboard", false);
    }
}
