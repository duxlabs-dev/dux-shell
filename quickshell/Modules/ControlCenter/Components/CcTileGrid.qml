pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.ControlCenter
import "../utils/sections.js" as Sections
import "../utils/widgets.js" as WidgetUtils
import "../utils/pages.js" as Pages
import "../../../Common/GridLayout.js" as GridUtils

DEditableGrid {
    id: root

    property var model: null
    property int page: 0
    property bool live: true
    property string screenName: ""
    property int columns: CcMetrics.gridColumns
    property real availableHeight: CcMetrics.fallbackScreenHeight - CcMetrics.maxHeightInset
    readonly property int maximumRows: CcMetrics.rowCapFor(availableHeight, cellWidth - CcMetrics.gridGap)
    // The detail band opens under this tile's row and pushes the rows below it down. While a band is shown the
    // slots follow its animated height frame by frame instead of running their own motion, so one animation drives
    // both; the section is the band's own, which it keeps until it has fully collapsed.
    property string expandedSection: ""
    property real bandHeight: 0
    property real bandTargetHeight: 0
    property bool bandMoving: false
    readonly property int expandedIndex: indexForSection(expandedSection)
    readonly property real bandY: slotLayout.bandY ?? 0
    readonly property real baseHeight: baseLayout.totalHeight
    readonly property real targetHeight: GridUtils.insertBand(baseLayout, expandedIndex, expandedSection !== "" ? bandTargetHeight : 0).totalHeight

    signal expandClicked(var widgetData)
    signal removeWidget(int index)
    signal configRequested(int index, var widgetData, var anchor)
    signal colorPickerRequested
    signal lockRequested
    signal powerRequested
    signal settingsRequested
    signal editRequested
    signal accountsRequested
    signal closeRequested
    property bool tapToClose: false
    property var runningToplevels: []
    // A member drag inside a quick-tiles group never reaches the grid's own interaction state.
    property bool memberDragging: false
    property var swallowPoint: null

    readonly property real gridHeight: layoutHeight
    readonly property real cellWidth: (width + CcMetrics.gridGap) / columns
    readonly property bool dragging: draggingSourceIndex >= 0 || externalItem !== null
    readonly property CcTileSlot draggingSlot: tileRepeater.itemAt(draggingSourceIndex) as CcTileSlot
    // Carried to another page, the dragged tile is that page's to drop; this grid only keeps the pointer grab.
    property bool carried: false
    property string carryGroup: ""
    readonly property string hoverGroup: carryGroup !== "" ? carryGroup : heldOutside && !carried && draggingSourceIndex >= 0 ? (groupAt(dragScenePoint, draggingSourceIndex)?.groupId ?? "") : ""

    readonly property var savedWidgets: SettingsData.controlCenterWidgets || []
    readonly property var groupIds: WidgetUtils.groupIds(savedWidgets)
    readonly property var shownIndices: savedWidgets.reduce((indices, widget, i) => Pages.pageOf(widget) === page && !WidgetUtils.inGroup(widget, groupIds) && WidgetUtils.isShown(widget) && model?.componentForWidget(widget) ? indices.concat([i]) : indices, [])

    sourceItems: shownIndices.map(i => Object.assign({}, savedWidgets[i], sizeWithHiddenTwin(i)))
    readonly property var baseLayout: {
        const items = clamped(layoutItems);
        const layout = GridUtils.packCards(items, placementOrder, columns, width, CcMetrics.gridGap, cellWidth - CcMetrics.gridGap, I18n.isRtl, null, CcMetrics.gridStep, true);
        return GridUtils.shrinkRows(layout, items.map(item => WidgetUtils.isSmall(item, item.h)), CcMetrics.smallRowHeight);
    }
    // Whole pixels keep the rows crisp while they ride the band's animation.
    slotLayout: GridUtils.insertBand(baseLayout, expandedIndex, Math.round(bandHeight))
    holdLayout: bandMoving
    gravity: true
    rowStep: CcMetrics.gridStep
    packer: items => GridUtils.packCells(clamped(items), placementOrder, columns, null, CcMetrics.gridStep, true).cells
    placeholderRadius: draggingSlot?.small ? CcMetrics.pillRadius(draggingSlot.width, draggingSlot.height) : (draggingSlot?.tileItem?.bodyRadius ?? CcMetrics.pillRadius(width, CcMetrics.tileHeight))

    commitHandler: items => model.setLayout(withHidden(items))
    onEditModeChanged: {
        if (!editMode)
            memberDragging = false;
    }

    // A grouped member expands under its group's tile.
    function indexForSection(section) {
        if (section === "")
            return -1;
        const widget = Sections.widgetForSection(section);
        const target = widget?.group ? savedWidgets.find(other => other?.id === WidgetUtils.GROUP_ID && other.instanceId === widget.group) : widget;
        if (!target)
            return -1;
        return sourceItems.findIndex(item => item.id === target.id && (item.instanceId || "") === (target.instanceId || ""));
    }

    function clamped(items) {
        return items.map(widget => Object.assign({}, widget, WidgetUtils.clampSize(widget, columns, maximumRows)));
    }

    function sizeWithHiddenTwin(index) {
        const widget = savedWidgets[index];
        const size = WidgetUtils.clampSize(widget, Infinity);
        if (!WidgetUtils.isUnplaced(widget))
            return size;
        for (const neighbor of [index + 1, index - 1]) {
            const twin = savedWidgets[neighbor];
            if (!twin || Pages.pageOf(twin) !== page || WidgetUtils.isShown(twin) || !WidgetUtils.isUnplaced(twin))
                continue;
            const twinSize = WidgetUtils.clampSize(twin, Infinity);
            if (twinSize.w !== size.w || twinSize.h !== size.h)
                continue;
            size.w += twinSize.w;
            return size;
        }
        return size;
    }

    function groupAt(scenePoint, excludeIndex) {
        for (let i = 0; i < tileRepeater.count; i++) {
            const slot = tileRepeater.itemAt(i) as CcTileSlot;
            if (i === excludeIndex || slot?.widgetData.id !== WidgetUtils.GROUP_ID)
                continue;
            if (slot.contains(slot.mapFromItem(null, scenePoint.x, scenePoint.y)))
                return slot.tileItem;
        }
        return null;
    }

    function savedIndex(index) {
        return shownIndices[index] ?? -1;
    }

    function externalSpec(widgetId) {
        const widget = WidgetUtils.newWidget(widgetId, columns);
        return {
            "id": widgetId,
            "w": widget.w,
            "h": widget.h,
            "small": widget.small === true
        };
    }

    function externalGhostSize(widgetId) {
        const spec = externalSpec(widgetId);
        const rowUnit = cellWidth - CcMetrics.gridGap;
        const height = WidgetUtils.isSmall(spec, spec.h) ? CcMetrics.smallRowHeight : spec.h * rowUnit + (spec.h - 1) * CcMetrics.gridGap;
        return Qt.size(spec.w * cellWidth - CcMetrics.gridGap, height);
    }

    function hoverNew(widgetId, scenePoint) {
        const point = mapFromItem(null, scenePoint.x, scenePoint.y);
        if (!editMode || !contains(point)) {
            clearExternal();
            return false;
        }
        const spec = externalSpec(widgetId);
        previewExternal(spec, point.x - cellWidth * spec.w / 2, point.y - slotLayout.rowUnit * spec.h / 2);
        return true;
    }

    function dropNew(widgetId) {
        if (!externalItem || externalItem.id !== widgetId)
            return false;
        const placed = committedItems();
        const cell = placed.pop();
        const widgets = withHidden(placed);
        Qt.callLater(() => {
            model.addWidgetAt(widgetId, cell.col, cell.row, widgets, page);
            cancelInteraction();
        });
        return true;
    }

    function withHidden(items) {
        const widgets = savedWidgets.slice();
        shownIndices.forEach((saved, i) => widgets[saved] = items[i]);
        return widgets;
    }

    Repeater {
        id: tileRepeater

        model: root.tileModel

        CcTileSlot {
            grid: root
        }
    }
}
