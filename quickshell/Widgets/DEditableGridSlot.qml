import QtQuick
import qs.Common

Item {
    id: root

    required property int index
    required property string json
    required property var grid

    readonly property var slot: grid.slotLayout.slots[index] ?? null
    readonly property bool dragging: grid.draggingSourceIndex === index
    readonly property bool resizing: grid.sizePreview?.index === index
    property var resizeOrigin: null
    property var dragOrigin: null
    property Item passthrough: null
    property int restCursor: Qt.OpenHandCursor
    property bool raised: dragging || resizing
    readonly property bool interactionEnabled: resizeOrigin !== null || dragOrigin !== null || !grid.interacting

    signal resizeRequested(real requestedWidth, real requestedHeight)
    signal pressAndHold
    signal clicked

    function moveDrag(scenePosition) {
        if (!dragOrigin || !dragging)
            return;
        grid.dragScenePoint = scenePosition;
        const point = grid.mapFromItem(null, scenePosition.x, scenePosition.y);
        x = dragOrigin.x + point.x - dragOrigin.px;
        y = dragOrigin.y + point.y - dragOrigin.py;
        grid.updateDragTarget(x, y);
    }

    function beginResize(px, py) {
        if (!slot || grid.interacting)
            return;
        const point = mapToItem(null, px, py);
        resizeOrigin = {
            "x": point.x,
            "y": point.y,
            "w": slot.w,
            "h": slot.h
        };
        resizeRequested(slot.w, slot.h);
    }

    function resizeTo(px, py) {
        if (!resizeOrigin || !grid.editMode)
            return;
        const point = mapToItem(null, px, py);
        const dx = (point.x - resizeOrigin.x) * (I18n.isRtl ? -1 : 1);
        resizeRequested(resizeOrigin.w + dx, resizeOrigin.h + point.y - resizeOrigin.y);
    }

    function finishResize() {
        if (!resizeOrigin)
            return;
        grid.commitSize();
        resizeOrigin = null;
    }

    function cancelResize() {
        if (!resizeOrigin)
            return;
        grid.cancelInteraction();
        resizeOrigin = null;
    }

    onResizingChanged: {
        if (!resizing)
            resizeOrigin = null;
    }

    onDraggingChanged: {
        if (!dragging)
            dragOrigin = null;
    }

    visible: slot !== null
    width: slot ? slot.w : 0
    height: slot ? slot.h : 0
    z: raised ? 2 : hoverTracker.hovered ? 1 : 0

    QtObject {
        id: passthroughMask

        function contains(point: point): bool {
            if (point.x < 0 || point.y < 0 || point.x >= root.width || point.y >= root.height)
                return false;
            const target = root.passthrough;
            if (!target?.visible)
                return true;
            return !target.contains(root.mapToItem(target, point.x, point.y));
        }
    }

    Binding {
        target: root
        property: "x"
        value: root.slot ? root.slot.x + root.grid.contentPadding : 0
        when: !root.dragging
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root
        property: "y"
        value: root.slot ? root.slot.y + root.grid.contentPadding : 0
        when: !root.dragging
        restoreMode: Binding.RestoreNone
    }

    Behavior on width {
        enabled: !root.dragging && root.resizeOrigin === null && root.grid.animationsEnabled && root.grid.animateLayout && !root.grid.holdLayout
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    Behavior on height {
        enabled: !root.dragging && root.resizeOrigin === null && root.grid.animationsEnabled && root.grid.animateLayout && !root.grid.holdLayout
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    Behavior on x {
        enabled: !root.dragging && root.resizeOrigin === null && root.grid.animationsEnabled && root.grid.animateLayout && !root.grid.holdLayout
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveDefaultSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
        }
    }

    Behavior on y {
        enabled: !root.dragging && root.resizeOrigin === null && root.grid.animationsEnabled && root.grid.animateLayout && !root.grid.holdLayout
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveDefaultSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
        }
    }

    // Edit chrome overhangs the gap; the hovered slot paints over its neighbours so its badges stay whole.
    HoverHandler {
        id: hoverTracker
        enabled: root.grid.editMode
    }

    MouseArea {
        id: dragArea

        anchors.fill: parent
        z: 1
        visible: root.grid.editMode
        enabled: visible && (root.dragOrigin !== null || !root.grid.interacting)
        hoverEnabled: enabled
        acceptedButtons: Qt.LeftButton
        cursorShape: root.dragging ? Qt.ClosedHandCursor : root.restCursor
        containmentMask: root.passthrough ? passthroughMask : null
        onPressAndHold: root.pressAndHold()
        onClicked: root.clicked()
        onWheel: wheel => wheel.accepted = true
    }

    DragHandler {
        target: null
        enabled: root.grid.editMode && (root.dragOrigin !== null || !root.grid.interacting)
        cursorShape: Qt.ClosedHandCursor

        onGrabChanged: (transition, point) => {
            switch (transition) {
            case PointerDevice.GrabExclusive:
                const origin = root.grid.mapFromItem(null, point.scenePressPosition.x, point.scenePressPosition.y);
                root.dragOrigin = {
                    "x": root.x,
                    "y": root.y,
                    "px": origin.x,
                    "py": origin.y
                };
                root.grid.beginDrag(root.index);
                root.moveDrag(point.scenePosition);
                return;
            case PointerDevice.UngrabExclusive:
                if (!root.dragging) {
                    root.dragOrigin = null;
                    return;
                }
                if (!root.grid.editMode) {
                    root.grid.cancelInteraction();
                    return;
                }
                root.grid.endDrag();
                root.dragOrigin = null;
                return;
            case PointerDevice.CancelGrabExclusive:
                if (root.dragging)
                    root.grid.cancelInteraction();
                root.dragOrigin = null;
                return;
            }
        }

        onCentroidChanged: {
            if (active)
                root.moveDrag(centroid.scenePosition);
        }
    }
}
