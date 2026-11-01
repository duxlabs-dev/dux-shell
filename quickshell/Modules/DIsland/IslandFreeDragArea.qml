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
    property point startOrigin
    property point lastPointer
    property bool tracking: false
    property bool movePending: false
    property bool flingPending: false
    property point releaseVelocity
    property var samples: []
    readonly property bool hostLifted: root.hostWindow.lifted

    onHostLiftedChanged: {
        if (root.hostLifted && root.flingPending)
            root.fling();
    }

    // Scene positions are surface-local; events just after the lift can still carry the pre-lift origin, so the reading that continues the stroke wins.
    function pointerPosition() {
        const p = root.centroid.scenePosition;
        const current = Qt.point(p.x + root.hostWindow.frameLeft, p.y + root.hostWindow.frameTop);
        if (!root.tracking)
            return current;
        const previous = Qt.point(p.x + root.startOrigin.x, p.y + root.startOrigin.y);
        const last = root.lastPointer;
        return Math.hypot(current.x - last.x, current.y - last.y) <= Math.hypot(previous.x - last.x, previous.y - last.y) ? current : previous;
    }

    function anchorFor(pointer) {
        return Qt.point(root.startAnchor.x + pointer.x - root.startPointer.x, root.startAnchor.y + pointer.y - root.startPointer.y);
    }

    function rememberPress() {
        root.startAnchor = Qt.point(root.surface.currentVisualX + root.surface.currentVisualWidth / 2, root.surface.currentVisualY + root.surface.currentVisualHeight / 2);
        root.startOrigin = Qt.point(root.hostWindow.frameLeft, root.hostWindow.frameTop);
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

    // Re-based at drag start: a press just after a settle can read the old origin, and a flying dot has moved since the press.
    function beginDrag() {
        root.flingPending = false;
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
        // Raised before dragging drops, so the lift holds through the fling.
        host.flinging = true;
        host.dragging = false;
        // A release before the lift lands waits for it, or the fling would spring out of the old buffer.
        if (host.lifted)
            root.fling();
        else
            root.flingPending = true;
    }

    function fling() {
        const host = root.hostWindow;
        root.flingPending = false;
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

    // One anchor write per frame however fast the mouse polls, and none before the lift lands.
    property FrameAnimation moveFrame: FrameAnimation {
        running: root.active && root.movePending && root.hostWindow.lifted
        onTriggered: root.applyMove()
    }
}
