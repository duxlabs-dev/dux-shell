import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.ControlCenter
import "../utils/widgets.js" as WidgetUtils
import "../../../Common/GridLayout.js" as GridUtils

DEditableGridSlot {
    id: root

    readonly property var widgetData: JSON.parse(json)
    readonly property real resizeRows: grid.rowLimit > 0 ? grid.rowLimit - (grid.pinnedCells?.[index]?.row ?? slot?.row ?? 0) : grid.maximumRows
    readonly property var sizeSpec: WidgetUtils.sizeSpec(widgetData, grid.columns, resizeRows)
    readonly property real cols: slot?.cols ?? 1
    readonly property real rows: slot?.rows ?? 1
    readonly property bool compact: cols <= 2 && rows === 1
    readonly property bool small: WidgetUtils.isSmall(grid.layoutItems[index] ?? widgetData, rows)
    readonly property var tileItem: tileLoader.item
    // Edit chrome hugs a small tile's pill, not its slot.
    readonly property real bodyInset: tileItem?.bodyInset ?? 0
    // Small tiles resize from a virtual half row so growing them passes through full size first.
    property real biasH: 0
    readonly property real smallSpanLimit: (1 + CcMetrics.smallRowFraction) / 2

    readonly property bool overflowing: grid.interacting && grid.slotLayout.slots[index] === null && grid.slotLayout.commitSlots?.[index] != null
    property real overflowProgress: overflowing ? 1 : 0
    readonly property var shownSlot: grid.slotLayout.slots[index] ?? null
    property var lastShownSlot: null
    readonly property real overflowTravel: I18n.isRtl ? -(x + width) : grid.width - x

    onShownSlotChanged: {
        if (shownSlot)
            lastShownSlot = shownSlot;
    }

    // Not the grab snapshot: a tile already pushed down a row would jump back up.
    retainedSlot: overflowing ? lastShownSlot : null
    opacity: 1 - overflowProgress
    enabled: !overflowing
    visible: slot !== null && (!overflowing || overflowProgress < 1)

    Behavior on overflowProgress {
        enabled: CcMetrics.animationsEnabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveDefaultSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.emphasizedAccel
        }
    }

    readonly property bool swallowed: dragging && grid.swallowPoint !== null
    property real swallowProgress: swallowed ? 1 : 0
    // Outlives the grid's point so the release animation can still use it.
    property var swallowAnchor: null

    onSwallowedChanged: {
        if (swallowed)
            swallowAnchor = grid.swallowPoint;
    }

    Behavior on swallowProgress {
        enabled: CcMetrics.animationsEnabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.standard
        }
    }

    transform: [
        Translate {
            x: root.overflowProgress > 0 ? root.overflowProgress * root.overflowTravel : 0
        },
        Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            xScale: 1 - root.swallowProgress * (1 - CcMetrics.trashSwallowScale)
            yScale: xScale
        },
        // Gated so resting tiles don't track every layout animation.
        Translate {
            x: root.swallowProgress > 0 ? root.swallowProgress * ((root.swallowAnchor?.x ?? 0) - root.x - root.width / 2) : 0
            y: root.swallowProgress > 0 ? root.swallowProgress * ((root.swallowAnchor?.y ?? 0) - root.y - root.height / 2) : 0
        }
    ]

    passthrough: tileItem?.passthrough ?? null
    restCursor: widgetData.id === WidgetUtils.EDIT_ID ? Qt.PointingHandCursor : Qt.OpenHandCursor
    // Matches the chrome's hitOverflow, so reaching for a button never hides it.
    hoverMargin: CcMetrics.gridGap / 2
    readonly property bool editing: grid.editMode
    // The origins lead the grid's interacting, so the grip never hides under its own press.
    readonly property bool chromeShown: resizeOrigin !== null || dragOrigin !== null || dragging || resizing || activeFocus || (hovered && !grid.interacting)

    activeFocusOnTab: editing
    onEditingChanged: {
        if (!editing)
            focus = false;
    }
    raised: dragging || resizing || (tileItem?.memberDragging ?? false)

    function reanchor(small) {
        const shift = ((small ? CcMetrics.smallRowFraction : 1) - smallSpanLimit) * grid.cellWidth;
        biasH += shift;
    }

    function spanOf(requested, bias = 0) {
        return (requested + bias + CcMetrics.gridGap) / grid.cellWidth;
    }

    onClicked: {
        if (widgetData.id === WidgetUtils.EDIT_ID)
            root.grid.editRequested();
    }

    onPressAndHold: {
        if (!WidgetUtils.hasOptions(widgetData.id))
            return;
        root.grid.configRequested(root.grid.savedIndex(root.index), root.widgetData, chromeBounds);
    }

    onResizeRequested: (requestedWidth, requestedHeight) => {
        const step = sizeSpec.step;
        const canShrink = WidgetUtils.canShrink(widgetData.id);
        if (canShrink && root.small !== (spanOf(requestedHeight, biasH) < smallSpanLimit))
            reanchor(!root.small);
        const spanW = spanOf(requestedWidth);
        const spanH = spanOf(requestedHeight, biasH);
        let width = GridUtils.dimension(Math.round(spanW / step) * step, sizeSpec.minW, sizeSpec.maxW, sizeSpec.w, step);
        let height = GridUtils.dimension(Math.round(spanH / step) * step, sizeSpec.minH, sizeSpec.maxH, sizeSpec.h, step);
        const current = WidgetUtils.clampSize(widgetData, grid.columns, grid.maximumRows);
        if (WidgetUtils.isSliderWidget(widgetData.id) && width < 2 && height < 2) {
            if (width !== current.w && sizeSpec.maxH >= 2)
                height = 2;
            else
                width = Math.min(2, sizeSpec.maxW);
        }
        const changes = {};
        if (width !== current.w)
            changes.w = width;
        if (height !== current.h)
            changes.h = height;
        const small = canShrink && height === 1 && spanH < smallSpanLimit;
        if (small !== (widgetData.small === true))
            changes.small = small;
        grid.previewSize(index, changes);
    }

    // Touch never hovers, so a tap focuses the tile to show its chrome.
    TapHandler {
        enabled: root.editing
        acceptedDevices: PointerDevice.TouchScreen
        onTapped: root.forceActiveFocus()
    }

    CcTileLoader {
        id: tileLoader
        anchors.fill: parent
        grid: root.grid
        widgetData: root.widgetData
        savedIndex: root.grid.savedIndex(root.index)
        columns: root.cols
        rows: root.rows
        compact: root.compact
        small: root.small
    }

    // A same-column insertion otherwise covers the outgoing pill with the dock's drag preview.
    Loader {
        parent: root.grid.overflowHost
        active: parent !== null && root.overflowing && root.overflowProgress < 1

        sourceComponent: ShaderEffectSource {
            readonly property point slotPoint: {
                root.x;
                root.y;
                root.overflowProgress;
                root.grid.x;
                root.grid.y;
                root.grid.scrollOffset;
                return root.grid.overflowHost.mapFromItem(root, 0, 0);
            }

            x: slotPoint.x
            y: slotPoint.y
            width: root.width
            height: root.height
            opacity: root.opacity
            sourceItem: tileLoader
            hideSource: true
        }
    }

    Item {
        id: chromeBounds

        anchors.fill: parent
        anchors.margins: -CcMetrics.editChromeInset
        anchors.topMargin: -CcMetrics.editChromeInset + root.bodyInset
        anchors.bottomMargin: -CcMetrics.editChromeInset + root.bodyInset
    }

    Loader {
        id: editChromeLoader

        anchors.fill: chromeBounds
        z: 2
        active: root.grid.editMode || root.resizing

        sourceComponent: CcEditChrome {
            id: chrome
            visible: root.editing && (root.chromeShown || chrome.keyboardFocused)
            enabled: root.interactionEnabled
            widgetData: root.widgetData
            passthrough: root.passthrough
            dragging: root.dragging
            resizing: root.resizing
            cornerRadius: root.small ? CcMetrics.pillRadius(root.width, root.height - root.bodyInset * 2) : (root.tileItem?.bodyRadius ?? CcMetrics.pillRadius(root.width, root.height))
            sizeText: root.cols + "×" + (root.small ? CcMetrics.smallRowFraction : root.rows)
            onResizeStarted: (px, py) => {
                root.biasH = root.small ? CcMetrics.smallRowFraction * root.grid.cellWidth - CcMetrics.gridGap - root.height : 0;
                root.beginResize(px, py);
            }
            onResizeMoved: (px, py) => root.resizeTo(px, py)
            onResizeEnded: root.finishResize()
            onResizeCanceled: root.cancelResize()
            onRemoveRequested: root.grid.removeWidget(root.grid.savedIndex(root.index))
            onConfigRequested: anchor => root.grid.configRequested(root.grid.savedIndex(root.index), root.widgetData, anchor)
        }
    }
}
