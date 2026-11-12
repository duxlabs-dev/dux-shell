pragma ComponentBehavior: Bound

import QtQuick
import qs.Common

Item {
    id: root

    required property bool dismissEnabled
    required property bool dismissSuspended
    required property bool surfaceVisible

    property int graceInterval: 150
    property bool bodyHovered: false
    // A closed transient surface leaves bodyHovered stale; sway sends no enter until the pointer moves.
    property bool pointerUnknown: false
    property real globalOffsetX: 0
    property real globalOffsetY: 0

    signal dismissRequested

    function cancelPending() {
        graceTimer.stop();
        pointerUnknown = false;
        hoverTracker.cancelPending();
    }

    function updateBodyHover(over) {
        bodyHovered = over;
        if (over) {
            pointerUnknown = false;
            graceTimer.stop();
        } else if (dismissEnabled && !dismissSuspended && surfaceVisible) {
            graceTimer.restart();
        }
    }

    function updateCursor(sceneX, sceneY) {
        PopoutManager.updateHoverCursor(sceneX + globalOffsetX, sceneY + globalOffsetY);
    }

    function notePointerMoved() {
        if (pointerUnknown)
            Qt.callLater(root.resolveUnknownPointer);
    }

    function resolveUnknownPointer() {
        if (!pointerUnknown || bodyHovered)
            return;
        pointerUnknown = false;
        if (dismissEnabled && !dismissSuspended && surfaceVisible)
            graceTimer.restart();
    }

    onDismissEnabledChanged: {
        if (!dismissEnabled)
            cancelPending();
    }
    onDismissSuspendedChanged: {
        graceTimer.stop();
        pointerUnknown = !dismissSuspended && dismissEnabled && surfaceVisible && !bodyHovered;
    }
    onSurfaceVisibleChanged: {
        if (!surfaceVisible)
            cancelPending();
    }

    Timer {
        id: graceTimer
        interval: root.graceInterval
        repeat: false
        onTriggered: {
            if (!root.dismissEnabled || root.dismissSuspended || !root.surfaceVisible || root.bodyHovered)
                return;
            if (PopoutManager.cursorOverBar(PopoutManager.hoverCursorGlobalX, PopoutManager.hoverCursorGlobalY))
                return;
            root.dismissRequested();
        }
    }

    HoverDismissTracker {
        id: hoverTracker
        enabled: root.dismissEnabled && !root.dismissSuspended && root.surfaceVisible
        shouldDismiss: function () {
            return !root.bodyHovered && !PopoutManager.cursorOverBar(PopoutManager.hoverCursorGlobalX, PopoutManager.hoverCursorGlobalY);
        }
        onDismissRequested: root.dismissRequested()
        onHoveredChanged: {
            if (hovered)
                root.notePointerMoved();
        }
        onHoverMoved: (gx, gy) => {
            root.updateCursor(gx, gy);
            root.notePointerMoved();
        }
    }
}
