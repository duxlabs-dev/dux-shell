import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.ControlCenter
import "../utils/widgets.js" as WidgetUtils
import "../../../Common/GridLayout.js" as GridUtils

DEditableGridSlot {
    id: root

    readonly property var widgetData: JSON.parse(json)
    readonly property var sizeSpec: WidgetUtils.sizeSpec(widgetData, grid.columns, grid.maximumRows)
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
            if (width !== current.w && sizeSpec.maxH > 1)
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
            visible: root.grid.editMode
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
