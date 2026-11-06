pragma ComponentBehavior: Bound

import QtQuick

DragHandler {
    id: root

    required property var hostWindow
    required property var surface

    readonly property real maxFlingSpeed: 4000
    readonly property real flingProjection: 0.09
    // Single events are too noisy on high-rate mice, so the fling reads the stroke's last stretch.
    readonly property int velocityWindow: 60
    property point startAnchor
    property point startPointer
    property point lastPointer
    property bool tracking: false
    property bool movePending: false
    property point releaseVelocity
    property var samples: []

    function pointerPosition() {
        const p = root.centroid.scenePosition;
        return Qt.point(p.x, p.y);
    }

    function anchorFor(pointer) {
        return Qt.point(root.startAnchor.x + pointer.x - root.startPointer.x, root.startAnchor.y + pointer.y - root.startPointer.y);
    }

    function rememberPress() {
        root.startAnchor = Qt.point(root.surface.currentVisualX + root.surface.currentVisualWidth / 2, root.surface.currentVisualY + root.surface.currentVisualHeight / 2);
        root.startPointer = root.pointerPosition();
        root.lastPointer = root.startPointer;
        root.samples = [];
        root.tracking = true;
    }

    function recordPointer() {
        const now = Date.now();
        root.lastPointer = root.pointerPosition();
        while (root.samples.length > 1 && now - root.samples[0].time > root.velocityWindow)
            root.samples.shift();
        root.samples.push({
            "time": now,
            "x": root.lastPointer.x,
            "y": root.lastPointer.y
        });
        root.movePending = true;
    }

    function flingVelocity() {
        const now = Date.now();
        const recent = root.samples.filter(sample => now - sample.time <= root.velocityWindow);
        if (recent.length < 2)
            return Qt.point(0, 0);
        const first = recent[0];
        const last = recent[recent.length - 1];
        const seconds = (last.time - first.time) / 1000;
        if (seconds < 0.008)
            return Qt.point(0, 0);
        const clamp = value => Math.max(-root.maxFlingSpeed, Math.min(root.maxFlingSpeed, value));
        return Qt.point(clamp((last.x - first.x) / seconds), clamp((last.y - first.y) / seconds));
    }

    // Re-based at drag start: a flying dot has moved since the press.
    function beginDrag() {
        root.tracking = false;
        root.rememberPress();
        root.hostWindow.dragging = true;
        root.hostWindow.wake();
        root.recordPointer();
    }

    function applyMove() {
        root.movePending = false;
        root.hostWindow.anchor = root.anchorFor(root.lastPointer);
    }

    function finishDrag() {
        const host = root.hostWindow;
        root.releaseVelocity = root.flingVelocity();
        root.movePending = false;
        root.tracking = false;
        // Raised before dragging drops, so the anchor stays held through the fling.
        host.flinging = true;
        host.dragging = false;
        root.fling();
    }

    function fling() {
        const host = root.hostWindow;
        // An expand requested mid-drag disables this handler; the sheet must not open with the release velocity.
        if (root.surface.controller.expanded) {
            host.flinging = false;
            host.wake();
            return;
        }
        const velocity = root.releaseVelocity;
        const anchor = root.anchorFor(root.lastPointer);
        root.surface.flingSeed = {
            "offsetAlong": root.surface.isVertical ? velocity.y : velocity.x,
            "offsetCross": root.surface.isVertical ? velocity.x : velocity.y
        };
        host.anchor = Qt.point(host.clampAnchorX(anchor.x + velocity.x * root.flingProjection), host.clampAnchorY(anchor.y + velocity.y * root.flingProjection));
        // An unchanged anchor never reaches applyTarget, so the seed is spent here.
        if (root.surface.flingSeed)
            root.surface.applyTarget();
        host.flinging = root.surface.motionRunning;
        host.wake();
    }

    parent: root.surface
    target: null
    acceptedButtons: Qt.LeftButton
    cursorShape: active ? Qt.ClosedHandCursor : Qt.ArrowCursor
    onActiveChanged: {
        if (active)
            root.beginDrag();
        else
            root.finishDrag();
    }
    onCentroidChanged: {
        if (!(root.centroid.pressedButtons & Qt.LeftButton)) {
            root.tracking = false;
            return;
        }
        if (!root.tracking)
            root.rememberPress();
        if (active)
            root.recordPointer();
    }

    // One anchor write per frame however fast the mouse polls, and none before the surface spans the output.
    property FrameAnimation moveFrame: FrameAnimation {
        running: root.active && root.movePending && root.hostWindow.outputSized
        onTriggered: root.applyMove()
    }
}
