import QtQuick
import qs.Common
import "../Common/GridLayout.js" as GridUtils

Item {
    id: root

    property bool editMode: false
    property var sourceItems: []
    property var slotLayout: ({
            "slots": [],
            "totalHeight": 0
        })
    property real minimumHeight: 0
    property real contentPadding: 0
    property real placeholderRadius: Theme.cornerRadiusXL
    property bool animationsEnabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
    property bool animateLayout: false
    // Slots take layout changes as they come, for a layout that an animation elsewhere already drives frame by frame.
    property bool holdLayout: false
    property int draggingSourceIndex: -1
    property var dragCell: null
    property var sizePreview: null
    property var pinnedCells: null
    property real heldHeight: 0
    property real pinnedHeight: 0
    property point dragScenePoint: Qt.point(0, 0)
    // Takes (sourceIndex, scenePoint, rect) with the dragged item's unsnapped rect; true while it hovers a target
    // outside the grid, which holds the grid still.
    property var dragsOutside: null
    property bool heldOutside: false
    // Takes (sourceIndex, scenePoint) and returns true when something outside the grid claims the dropped item.
    // The grid then stays mid-drag until that commit replaces the item.
    property var dropHandler: null
    // An item hovering from outside, placed first so the grid makes room for it.
    property var externalItem: null
    // A callback, not a signal: Qt 6.12 hands signal array parameters over as a V4Sequence that fails Array.isArray.
    property var commitHandler: null
    // The layout compacts upward, so a drop has to account for the hole the dragged item leaves.
    property bool gravity: false
    // Takes the items with the dragged one at its target and returns their packed cells, so a drop can tell
    // whether gravity would lift the dragged item back above where it was dropped.
    property var packer: null
    property real rowStep: 1
    readonly property alias tileModel: tiles
    readonly property bool interacting: draggingSourceIndex >= 0 || sizePreview !== null || externalItem !== null
    readonly property real layoutHeight: interacting ? Math.max(heldHeight, slotLayout.totalHeight) : slotLayout.totalHeight
    readonly property int interactingIndex: draggingSourceIndex >= 0 ? draggingSourceIndex : (sizePreview?.index ?? -1)
    readonly property var placementOrder: {
        const order = sourceItems.map((item, i) => i);
        if (externalItem)
            return [sourceItems.length].concat(order);
        if (interactingIndex < 0)
            return order;
        order.splice(interactingIndex, 1);
        order.unshift(interactingIndex);
        return order;
    }
    readonly property var pinnedItems: pinnedCells ? GridUtils.placedItems(sourceItems, pinnedCells) : sourceItems
    readonly property var layoutItems: {
        const items = externalItem ? pinnedItems.concat([externalItem]) : pinnedItems;
        const changes = sizePreview?.changes ?? dragCell;
        if (interactingIndex < 0 || !changes)
            return items;
        const changed = items.map((item, i) => i === interactingIndex ? Object.assign({}, item, changes) : item);
        return gravity && dragCell && draggingSourceIndex >= 0 ? GridUtils.dropInto(changed, pinnedCells, draggingSourceIndex, dragCell, packer, rowStep) : changed;
    }

    implicitHeight: Math.max(minimumHeight, layoutHeight) + contentPadding * 2
    height: implicitHeight

    function pin() {
        pinnedCells = slotLayout.slots.slice();
        heldHeight = slotLayout.totalHeight;
        pinnedHeight = heldHeight;
    }

    function cancelInteraction() {
        draggingSourceIndex = -1;
        dragCell = null;
        sizePreview = null;
        externalItem = null;
        heldOutside = false;
        pinnedCells = null;
        heldHeight = 0;
    }

    function committedItems() {
        return GridUtils.placedItems(layoutItems, slotLayout.slots);
    }

    function syncTiles() {
        animateLayout = false;
        cancelInteraction();
        const seen = {};
        const keys = sourceItems.map(item => {
            const base = JSON.stringify([item.id || "", item.instanceId || ""]);
            const count = seen[base] || 0;
            seen[base] = count + 1;
            return base + "#" + count;
        });
        for (let i = tiles.count - 1; i >= 0; i--) {
            if (keys.indexOf(tiles.get(i).key) < 0)
                tiles.remove(i);
        }
        for (let p = 0; p < keys.length; p++) {
            const json = JSON.stringify(sourceItems[p]);
            let current = -1;
            for (let j = p; j < tiles.count; j++) {
                if (tiles.get(j).key !== keys[p])
                    continue;
                current = j;
                break;
            }
            if (current < 0) {
                tiles.insert(p, {
                    "key": keys[p],
                    "json": json
                });
                continue;
            }
            if (current !== p)
                tiles.move(current, p, 1);
            if (tiles.get(p).json !== json)
                tiles.setProperty(p, "json", json);
        }
    }

    function beginDrag(sourceIndex) {
        if (!editMode || interacting || !sourceItems[sourceIndex])
            return;
        pin();
        draggingSourceIndex = sourceIndex;
    }

    function updateDragTarget(x, y) {
        const slot = draggingSourceIndex >= 0 ? slotLayout.slots[draggingSourceIndex] : null;
        if (!slot)
            return;
        heldOutside = dragsOutside?.(draggingSourceIndex, dragScenePoint, Qt.rect(x - contentPadding, y - contentPadding, slot.w, slot.h)) ?? false;
        if (heldOutside) {
            dragCell = null;
            return;
        }
        const cell = GridUtils.cellAt(slotLayout, x - contentPadding, y - contentPadding, slot.cols, slot.rows);
        if (dragCell && dragCell.col === cell.col && dragCell.row === cell.row)
            return;
        dragCell = cell;
    }

    function endDrag() {
        if (draggingSourceIndex < 0)
            return;
        if (dropHandler?.(draggingSourceIndex, dragScenePoint))
            return;
        const items = committedItems();
        const moved = pinnedCells.some((cell, i) => cell && (cell.col !== items[i].col || cell.row !== items[i].row));
        cancelInteraction();
        if (moved)
            commitHandler?.(items);
    }

    function previewExternal(item, x, y) {
        if (!editMode || draggingSourceIndex >= 0 || sizePreview)
            return;
        if (!pinnedCells)
            pin();
        const cell = GridUtils.cellAt(slotLayout, x - contentPadding, y - contentPadding, item.w, item.h);
        if (externalItem?.col === cell.col && externalItem?.row === cell.row)
            return;
        externalItem = Object.assign({}, item, cell);
    }

    function clearExternal() {
        if (externalItem)
            cancelInteraction();
    }

    function previewSize(index, changes) {
        if (!editMode || draggingSourceIndex >= 0 || !sourceItems[index])
            return;
        if (sizePreview?.index === index && JSON.stringify(sizePreview.changes) === JSON.stringify(changes))
            return;
        if (!pinnedCells)
            pin();
        sizePreview = {
            "index": index,
            "changes": changes
        };
    }

    function commitSize() {
        const preview = sizePreview;
        if (!preview)
            return;
        const item = sourceItems[preview.index];
        const changed = item && Object.keys(preview.changes).some(key => item[key] !== preview.changes[key]);
        const items = committedItems();
        if (changed)
            commitHandler?.(items);
        cancelInteraction();
    }

    function commitChange(index, changes) {
        previewSize(index, changes);
        commitSize();
    }

    onSourceItemsChanged: syncTiles()
    onSlotLayoutChanged: {
        if (interacting)
            heldHeight = Math.max(heldHeight, slotLayout.totalHeight);
    }
    Component.onCompleted: syncTiles()
    onEditModeChanged: {
        if (!editMode)
            cancelInteraction();
    }

    Timer {
        interval: 0
        running: root.width > 0 && !root.animateLayout
        onTriggered: root.animateLayout = true
    }

    ListModel {
        id: tiles
    }

    Rectangle {
        readonly property var slot: root.slotLayout.slots[root.draggingSourceIndex >= 0 ? root.draggingSourceIndex : root.externalItem ? root.sourceItems.length : -1] ?? null

        visible: slot !== null && !root.heldOutside
        x: slot ? slot.x + root.contentPadding : 0
        y: slot ? slot.y + root.contentPadding : 0
        width: slot ? slot.w : 0
        height: slot ? slot.h : 0
        radius: root.placeholderRadius
        color: Theme.withAlpha(Theme.primary, Theme.stateLayerDrag)

        Behavior on x {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
            }
        }

        Behavior on y {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
            }
        }
    }
}
