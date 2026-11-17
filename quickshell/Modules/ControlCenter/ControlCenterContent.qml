pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Services
import qs.Modules.ControlCenter.Components
import qs.Modules.ControlCenter.Models
import qs.Modules.ControlCenter.Details
import qs.DCommon.Widgets
import qs.Widgets
import "./utils/sections.js" as Sections
import "./utils/widgets.js" as WidgetUtils
import "./utils/pages.js" as Pages
import "../../Common/GridLayout.js" as GridUtils
import "../../Common/ControlCenterLayout.js" as PanelLayout

FocusScope {
    id: root

    component DashedOutline: Shape {
        id: outline

        property real radius: 0
        property color strokeColor: Theme.outlineVariant
        property color fillColor: "transparent"

        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: outline.strokeColor
            strokeWidth: Theme.outlineWidthFocused
            strokeStyle: ShapePath.DashLine
            dashPattern: CcMetrics.addHintDashPattern
            fillColor: outline.fillColor

            PathRectangle {
                x: Theme.outlineWidthFocused / 2
                y: Theme.outlineWidthFocused / 2
                width: outline.width - Theme.outlineWidthFocused
                height: outline.height - Theme.outlineWidthFocused
                radius: Math.max(0, outline.radius - Theme.outlineWidthFocused / 2)
            }
        }
    }

    required property var host

    property bool live: Window.window?.visible ?? false
    readonly property bool hostOpen: host.shouldBeVisible ?? false
    property bool audioRefHeld: false
    property bool ready: false

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property string openSection: host.expandedSection ?? ""
    readonly property bool pageOpen: openSection !== ""
    // Fixed rows paginate unsaved for this host's columns, so a narrower screen or a tile becoming available never hides tiles.
    // A height drag previews from its grab snapshot and saves only on release.
    readonly property var layoutWidgets: {
        const base = resizeBase?.vertical ? resizeBase.widgets : SettingsData.controlCenterWidgets || [];
        return fixedHeight ? rowLayout(base, gridColumns, fixedRows, (resizeBase?.vertical ?? false) && fixedRows > resizeBase.rows) : base;
    }
    readonly property int usedPageCount: Pages.pageCount(layoutWidgets, widget => widgetModel.isTileShown(widget))
    // Edit mode adds an empty page after the last used one to drop or add on.
    readonly property int pageCount: usedPageCount + (host.editMode ? 1 : 0)
    readonly property CcTileGrid widgetGrid: pager.currentItem as CcTileGrid
    readonly property list<Item> pageGrids: pager.items
    // The band stays with the page it opened on while it collapses, so switching page never moves it across.
    property int bandPage: 0
    readonly property CcTileGrid bandGrid: pageGrids[bandPage] as CcTileGrid
    // A tile held at a page edge carries to the neighbor page: its grid keeps the grab, the shown page takes the drop.
    property CcTileGrid carrySource: null
    property point carryOffset
    // "group" or "trash" while either claims the carried tile, "" over the page.
    property string carryHover: ""
    property string carryGroupId: ""
    property bool carryDropped: false
    readonly property int carriedIndex: carrySource?.draggingSourceIndex ?? -1
    readonly property CcTileGrid dragGrid: carrySource ?? widgetGrid
    readonly property bool libraryDragging: (dockedPanel?.dragWidgetId ?? "") !== ""
    readonly property bool gridDragging: libraryDragging || carrySource !== null || (widgetGrid?.dragging ?? false)
    // Every page is as tall as the tallest, so switching page never resizes the surface.
    readonly property real gridHeight: pageGrids.reduce((height, grid) => Math.max(height, (grid as CcTileGrid).gridHeight), 0)
    readonly property real gridTargetHeight: pageGrids.reduce((height, grid) => Math.max(height, (grid as CcTileGrid).targetHeight), 0)
    // A grid mid-drag counts at its height from before the drag, so a carry between pages never resizes the surface.
    readonly property real restingGridHeight: pageGrids.reduce((height, item) => {
        const grid = item as CcTileGrid;
        return Math.max(height, grid.interacting ? grid.pinnedHeight : grid.gridHeight);
    }, 0)
    // Reserved from the grid in both modes so the island growing into edit mode never reflows tiles.
    readonly property real editRoom: host.editRoom ?? 0
    readonly property real chromeHeight: (host.editRoomShown ?? false) ? editRoom : 0
    readonly property bool stripAbove: host.stripAbove ?? false
    readonly property bool docked: host.dockFits ?? false
    readonly property string dockSide: host.dockSide ?? ""
    readonly property CcDockedEditPanel dockedPanel: dockedPanelLoader.item as CcDockedEditPanel
    readonly property real surfaceRadius: Math.max(surfaceCornerRadii.x, surfaceCornerRadii.y, surfaceCornerRadii.z, surfaceCornerRadii.w)
    readonly property Item dockedBlurItem: docked && dockedPanel ? dockedPanelLoader : null
    readonly property bool widgetSheetOpen: widgetSheetLoader.item?.active ?? false
    readonly property real coveredAmount: Math.max(widgetSheetLoader.item?.progress ?? 0, codecSelectorLoader.item?.presence ?? 0, portSelectorLoader.item?.presence ?? 0)
    property bool widgetSheetRequested: false
    property bool widgetPopoverOpen: false
    property int toplevelRevision: 0
    readonly property var runningToplevels: {
        toplevelRevision;
        const all = CompositorService.sortedToplevels ?? [];
        const current = CompositorService.filterCurrentWorkspace(all, host.triggerScreen?.name) || [];
        return current.concat(all.filter(toplevel => !current.includes(toplevel)));
    }
    readonly property string placedWidgetIds: (SettingsData.controlCenterWidgets || []).map(w => w.id).sort().join(",")
    readonly property var gridDragWidget: dragGrid && dragGrid.draggingSourceIndex >= 0 ? (dragGrid.sourceItems[dragGrid.draggingSourceIndex] ?? null) : null
    // Off the grid, anything but a group is the trash.
    readonly property bool overTrash: gridDragWidget !== null && (carrySource ? carryHover === "trash" : widgetGrid.heldOutside && widgetGrid.hoverGroup === "")
    property var addPin: null
    readonly property bool addHintAllowed: host.editMode && editIdle && !pager.moving && !widgetSheetOpen && !widgetPopoverOpen && detailBand.shownSection === ""
    readonly property var addSpot: addHintAllowed && addHover.hovered ? spotAt(addHover.point.position) : null
    readonly property var addHint: addSpot ?? addPin

    // A function, so plugin widget components are only instantiated once a sheet or panel asks.
    function addableWidgets(fitSpot = false) {
        const existingIds = placedWidgetIds.split(",");
        const allWidgets = widgetModel.baseWidgetDefinitions.concat(widgetModel.getPluginWidgets());
        return allWidgets.filter(widget => {
            if (!widget.allowMultiple && existingIds.includes(widget.id))
                return false;
            return !fitSpot || canAddAtPin(widget.id);
        });
    }

    function canAddAtPin(widgetId) {
        if (!addPin || addPin.page !== pager.currentIndex)
            return true;
        const tile = WidgetUtils.defaultWidget(widgetId, gridColumns);
        return WidgetUtils.placedInRoom(tile, gridColumns, addPin.col, addPin.row, addPin.room) !== null;
    }
    // A spare row to drop below the last one, only where growth leaves the grid still.
    readonly property real dragRoom: !fixedHeight && gridDragging && (host.growsFromTop ?? true) && restingGridHeight + newRowUnit <= availableGridHeight ? newRowUnit : 0
    readonly property real newRowUnit: CcMetrics.gridGap + (widgetGrid?.slotLayout.rowUnit ?? 0)
    // Held during a drag so the trash never moves under the pointer.
    readonly property real heldGridHeight: gridDragging ? restingGridHeight + dragRoom : gridHeight
    // The popout sizes to where the band is going; the content inside follows the band frame by frame.
    readonly property real targetImplicitHeight: CcMetrics.gridVerticalPadding + (fixedHeight ? Math.max(fixedGridHeight, gridDragging ? heldGridHeight : gridTargetHeight) : gridDragging ? heldGridHeight : gridTargetHeight)
    readonly property bool contentOverflows: targetImplicitHeight > (host.availableHeight ?? Infinity)
    property Item detailReturnFocus: null
    // One string so Discard and undo can compare and restore the whole session state at once.
    readonly property string editState: JSON.stringify({
        "widgets": SettingsData.controlCenterWidgets || [],
        "columns": SettingsData.controlCenterColumns,
        "rows": SettingsData.controlCenterRows
    })
    property string editSnapshot: ""
    property string undoBase: ""
    property var undoStack: []
    readonly property int undoLimit: 50
    property bool undoBatching: false
    property int rowPreview: -1
    property var resizeBase: null
    property bool repaginating: false
    readonly property int panelRows: rowPreview >= 0 ? rowPreview : SettingsData.controlCenterRows
    readonly property bool fixedHeight: panelRows > 0
    readonly property int rowCap: CcMetrics.rowCapFor(availableGridHeight)
    readonly property int fixedRows: Math.max(CcMetrics.minimumRows, panelRows)
    readonly property var pageLayouts: pageGrids.map(item => (item as CcTileGrid).baseLayout)
    readonly property real fixedGridHeight: PanelLayout.heightForRows(pageLayouts, fixedRows, CcMetrics.gridRowUnit, CcMetrics.gridGap)
    readonly property int naturalRows: Math.max(CcMetrics.minimumRows, ...pageLayouts.map(layout => Math.ceil(layout.rows)))
    readonly property bool editIdle: !libraryDragging && carrySource === null && !(widgetGrid?.interacting ?? false) && !(widgetGrid?.memberDragging ?? false) && !panelResizing
    readonly property bool canUndo: host.editMode && undoStack.length > 0 && editIdle && !widgetSheetOpen && !pageOpen
    readonly property bool panelResizing: panelResizer.resizing
    readonly property bool swipeAllowed: editIdle && !widgetSheetOpen && !widgetPopoverOpen && detailBand.shownSection === ""
    readonly property real sheetContentWidth: host.sheetContentWidth ?? CcMetrics.sheetWidthFor(gridColumns)
    readonly property vector4d surfaceCornerRadii: host.surfaceCornerRadii ?? Qt.vector4d(Theme.windowRadius, Theme.windowRadius, Theme.windowRadius, Theme.windowRadius)
    // A dim can't follow a frame-attached body past its square corners; the covered content is faded out anyway.
    readonly property bool sheetsDim: !CcMetrics.hideCoveredContent || Math.min(surfaceCornerRadii.x, surfaceCornerRadii.y, surfaceCornerRadii.z, surfaceCornerRadii.w) > 0
    readonly property int gridColumnCap: host.gridColumnCap ?? CcMetrics.columnCapFor((host.triggerScreen?.width ?? CcMetrics.sheetWidthDefault + Theme.spacingL * 2) - Theme.spacingL * 2)
    readonly property int gridColumns: host.gridColumns ?? Math.min(CcMetrics.gridColumns, gridColumnCap)
    readonly property real availableGridHeight: (host.availableHeight ?? (host.triggerScreen?.height ?? CcMetrics.fallbackScreenHeight) - CcMetrics.maxHeightInset) - CcMetrics.gridVerticalPadding - editRoom
    readonly property real pageGridHeight: fixedHeight ? Math.min(availableGridHeight, fixedGridHeight) : availableGridHeight
    readonly property DPanelResizer panelResizer: DPanelResizer {
        popout: root.host
        pointerItem: panelChrome
        pointerInset: panelChrome.contentInset
        stepWidth: CcMetrics.columnWidth + CcMetrics.gridGap
        widthFor: columns => CcMetrics.sheetWidthFor(columns) + root.sheetContentWidth - CcMetrics.sheetWidthFor(root.gridColumns)
        currentStep: () => root.gridColumns
        currentRows: () => Math.min(root.rowCap, root.fixedHeight ? root.fixedRows : root.naturalRows)
        minStep: Math.min(CcMetrics.minimumColumns, root.gridColumnCap)
        maxStep: root.gridColumnCap
        rowEdgeFor: rows => {
            const gridHeight = PanelLayout.heightForRows(root.pageLayouts, rows, CcMetrics.gridRowUnit, CcMetrics.gridGap);
            // Logical edges stay distinct below the dock floor, so a smaller height can be chosen before Finish.
            const height = CcMetrics.gridVerticalPadding + gridHeight + root.chromeHeight;
            return root.host.resizeYFor(height) + ((root.host.growsFromTop ?? true) ? height : 0);
        }
        minRows: Math.min(root.rowCap, CcMetrics.minimumRows)
        maxRows: root.rowCap
        onPreview: (columns, rows) => {
            CcMetrics.columnPreview = columns;
            if (root.resizeBase?.vertical)
                root.rowPreview = rows;
        }
        onCommitted: (columns, rows, columnsChanged, rowsChanged) => {
            const base = root.resizeBase;
            root.batchEdit(() => {
                if (base.vertical && rowsChanged && rows > 0)
                    root.applyRowLayout(base.widgets, columns, rows, rows > base.rows);
                if (columnsChanged)
                    SettingsData.set("controlCenterColumns", columns);
                if (rowsChanged)
                    SettingsData.set("controlCenterRows", rows);
                CcMetrics.columnPreview = 0;
                root.rowPreview = -1;
                // Wider pages take back tiles a narrower layout spilled.
                root.enforceFixedHeight(columnsChanged && columns > base.columns);
            }, base.state);
            root.resizeBase = null;
        }
        onCanceled: {
            CcMetrics.columnPreview = 0;
            root.rowPreview = -1;
            root.resizeBase = null;
        }
    }

    implicitHeight: targetImplicitHeight
    focus: true

    function syncAudioRef(wanted) {
        if (wanted === audioRefHeld)
            return;
        audioRefHeld = wanted;
        if (wanted) {
            AudioService.addRef();
            return;
        }
        AudioService.removeRef();
    }

    onLiveChanged: syncAudioRef(live)
    onHostOpenChanged: {
        if (hostOpen)
            return;
        // an in-flight codec switch reports failure through the open selector
        if (!codecSelectorLoader.item?.isLoading)
            codecSelectorLoader.item?.dismiss();
        portSelectorLoader.item?.dismiss();
    }
    Component.onCompleted: {
        ready = true;
        WidgetUtils.ensureEditButton();
        syncAudioRef(live);
        pager.goTo(host.currentPage ?? 0, false);
        showSectionPage(false);
    }
    Component.onDestruction: syncAudioRef(false)
    onPlacedWidgetIdsChanged: WidgetUtils.ensureEditButton()

    function navigateTo(section) {
        if (section === host.expandedSection)
            return;
        if (!host.expandedSection && detailBand.shownSection === "")
            detailReturnFocus = root.Window.window?.activeFocusItem ?? null;
        host.expandedSection = section;
    }

    function goBack() {
        if (detailBand.dismissTransient())
            return;
        host.collapseAll();
    }

    // Only a popout the screen has capped scrolls; otherwise it grows around the band and any scroll would bounce.
    function revealDetail() {
        if (detailBand.section === "" || !contentOverflows)
            return;
        const top = mainColumn.y + body.y + detailBand.y;
        contentFlickable.revealRange(top, top + detailBand.height);
    }

    function openWidgetPage(widgetData) {
        const section = Sections.sectionFor(widgetData);
        if (host.expandedSection === section) {
            goBack();
            return;
        }
        navigateTo(section);
    }

    function showCodecSelector(device) {
        presentSheet(codecSelectorLoader, device);
    }

    function showPortSelector(node) {
        presentSheet(portSelectorLoader, node);
    }

    function presentSheet(loader, target) {
        loader.active = true;
        const sheet = loader.item;
        if (!sheet)
            return;
        sheet.show(target);
        if (!sheet.shown)
            loader.active = false;
    }

    function releaseSheet(loader) {
        if (loader.item?.shown)
            return;
        loader.active = false;
    }

    function openConfigOverlay(index, widgetData, anchor) {
        configOverlayLoader.active = true;
        const overlay = configOverlayLoader.item;
        if (!overlay)
            return;
        overlay.open(index, widgetData, anchor);
    }

    function releaseConfigOverlay() {
        if (configOverlayLoader.item?.visible)
            return;
        configOverlayLoader.active = false;
    }

    function applyEditState(state) {
        if (state === "")
            return;
        const wanted = JSON.parse(state);
        const batching = undoBatching;
        undoBatching = true;
        if (JSON.stringify(SettingsData.controlCenterWidgets || []) !== JSON.stringify(wanted.widgets))
            SettingsData.set("controlCenterWidgets", wanted.widgets);
        if (SettingsData.controlCenterColumns !== wanted.columns)
            SettingsData.set("controlCenterColumns", wanted.columns);
        if (SettingsData.controlCenterRows !== wanted.rows)
            SettingsData.set("controlCenterRows", wanted.rows);
        undoBatching = batching;
    }

    function rowLayout(widgets, columns, rows, pull = false) {
        const sized = widgets.map(widget => {
            if (!widgetModel.isTileShown(widget) || Pages.groupOf(widgets, widget))
                return widget;
            return Object.assign({}, widget, WidgetUtils.clampSize(widget, columns, rows));
        });
        return PanelLayout.paginate(sized, columns, rows, widget => widgetModel.isTileShown(widget), pull);
    }

    function applyRowLayout(widgets, columns, rows, pull = false) {
        const next = rowLayout(widgets, columns, rows, pull);
        if (JSON.stringify(next) !== JSON.stringify(SettingsData.controlCenterWidgets))
            SettingsData.set("controlCenterWidgets", next);
    }

    // An untouched layout stays a projection, so opening edit on a narrower host never rewrites its pages.
    function enforceFixedHeight(pull = false) {
        if (!ready || !hostOpen || !host.editMode || !fixedHeight || repaginating || !editIdle || editState === editSnapshot)
            return;
        repaginating = true;
        applyRowLayout(SettingsData.controlCenterWidgets || [], gridColumns, fixedRows, pull);
        repaginating = false;
    }

    function setFixedHeight(enabled) {
        batchEdit(() => {
            SettingsData.set("controlCenterRows", enabled ? Math.min(rowCap, naturalRows) : 0);
            enforceFixedHeight();
        });
    }

    // Restored before leaving, so the exit compacts the snapshot and never writes the discarded layout.
    function cancelEdit() {
        applyEditState(editSnapshot);
        host.editMode = false;
    }

    function undoEdit() {
        if (!canUndo)
            return;
        const previous = undoStack[undoStack.length - 1];
        undoStack = undoStack.slice(0, -1);
        undoBase = previous;
        undoBatching = true;
        applyEditState(previous);
        undoBatching = false;
    }

    onOpenSectionChanged: showSectionPage(true)
    onWidgetSheetOpenChanged: {
        if (!widgetSheetOpen)
            addPin = null;
    }
    onWidgetPopoverOpenChanged: {
        if (!widgetPopoverOpen)
            addPin = null;
    }
    // Any layout change can fill the marked spot.
    onEditIdleChanged: {
        if (!editIdle)
            addPin = null;
        else if (!repaginating)
            settleEdit.schedule();
    }
    onCarriedIndexChanged: {
        if (carriedIndex >= 0 || !carrySource)
            return;
        finishCarry.schedule();
    }

    DeferredAction {
        id: finishCarry
        onTriggered: root.releaseCarry()
    }

    function releaseCarry() {
        if (carriedIndex >= 0 || !carrySource)
            return;
        const source = carrySource;
        carrySource = null;
        carryHover = "";
        carryGroupId = "";
        if (widgetGrid !== source)
            widgetGrid?.clearExternal();
        if (!carryDropped)
            pager.goTo(source.page);
    }

    // A paged-away tile keeps keyboard focus, and with it its keys, so focus moves to the dots.
    function releaseHiddenFocus() {
        const pages = Array.from(pager.items);
        for (let item = Window.activeFocusItem; item; item = item.parent) {
            const page = pages.indexOf(item);
            if (page < 0)
                continue;
            if (page === pager.currentIndex)
                return;
            if (pageDots.visible) {
                pageDots.forceActiveFocus();
                return;
            }
            forceActiveFocus();
            return;
        }
    }

    // A band opened from outside the grid (IPC, the island) brings its tile's page first.
    function showSectionPage(animate) {
        if (openSection === "")
            return;
        // The grid shows the unsaved pagination, not the saved pages.
        const widgets = layoutWidgets;
        const widget = Sections.widgetForSection(openSection, widgets);
        bandPage = Math.max(0, Math.min(widget ? Pages.pageOf(Pages.groupOf(widgets, widget) ?? widget) : pager.currentIndex, pager.count - 1));
        if (bandPage !== pager.currentIndex)
            pager.goTo(bandPage, animate && live);
    }

    onEditStateChanged: {
        addPin = null;
        if (!repaginating && !undoBatching)
            settleEdit.schedule();
    }

    // Settings changes must finish syncing every grid before pagination can write again.
    DeferredAction {
        id: settleEdit
        enabled: root.ready && root.hostOpen && root.host.editMode
        onEnabledChanged: {
            if (enabled)
                schedule();
        }
        onTriggered: root.trackEditState()
    }

    function trackEditState() {
        if (!ready || !hostOpen || repaginating || !editIdle || resizeBase !== null || undoBatching)
            return;
        enforceFixedHeight();
        if (!host.editMode || editState === undoBase)
            return;
        undoStack = undoStack.concat([undoBase]).slice(-undoLimit);
        undoBase = editState;
    }

    onPageGridHeightChanged: {
        if (!repaginating && !undoBatching && resizeBase === null)
            settleEdit.schedule();
    }

    // Keeps the intermediate states of a multi-key write out of the undo stack.
    function batchEdit(change, before = editState) {
        undoBatching = true;
        change();
        undoBatching = false;
        if (editState === before)
            return;
        undoStack = undoStack.concat([before]).slice(-undoLimit);
        undoBase = editState;
    }

    function trashTakesGridDrag(scenePoint) {
        if (!WidgetUtils.isRemovable(gridDragWidget))
            return false;
        if (docked)
            return dockedPanel?.containsScenePoint(scenePoint) ?? false;
        return editActions.trashContains(scenePoint);
    }

    function groupTakesGridDrag(grid, scenePoint) {
        return WidgetUtils.canGroup(gridDragWidget) && grid.groupAt(scenePoint, grid.draggingSourceIndex) !== null;
    }

    function gridDragMoved(grid, scenePoint) {
        if (carrySource === grid) {
            carryMoved(scenePoint);
            return true;
        }
        const outside = groupTakesGridDrag(grid, scenePoint) || trashTakesGridDrag(scenePoint);
        (pageEdge.item as CcPageEdge)?.updateDrag(outside ? null : scenePoint);
        return outside;
    }

    function carryTo(direction) {
        if (libraryDragging) {
            widgetGrid?.clearExternal();
            pager.goTo(pager.currentIndex + direction);
            if (!pager.moving)
                dockedPanel?.updateDrag(dockedPanel.dragPoint);
            return;
        }
        const source = carrySource ?? widgetGrid;
        const slot = source?.draggingSlot;
        if (!slot)
            return;
        if (!carrySource) {
            carryOffset = slot.mapFromItem(null, source.dragScenePoint.x, source.dragScenePoint.y);
            carryDropped = false;
            carrySource = source;
            // Its other tiles go back to their cells at once, not on the next pointer move.
            source.heldOutside = true;
            source.dragCell = null;
        }
        if (widgetGrid !== carrySource)
            widgetGrid?.clearExternal();
        carryHover = "";
        carryGroupId = "";
        pager.goTo(pager.currentIndex + direction);
        if (!pager.moving)
            carrySettled();
    }

    // Skipped while the pages slide: a sliding grid maps the pointer to the wrong cell, so the settle replays it.
    function carryMoved(scenePoint) {
        const grid = widgetGrid;
        if (pager.moving || !grid || grid === carrySource)
            return;
        grid.dragScenePoint = scenePoint;
        const group = WidgetUtils.canGroup(gridDragWidget) ? grid.groupAt(scenePoint, -1) : null;
        carryGroupId = group?.groupId ?? "";
        carryHover = group ? "group" : trashTakesGridDrag(scenePoint) ? "trash" : "";
        const point = grid.mapFromItem(null, scenePoint.x, scenePoint.y);
        if (carryHover !== "" || !grid.acceptsDrop(scenePoint))
            grid.clearExternal();
        else
            grid.previewExternal(carrySource.sourceItems[carriedIndex], point.x - carryOffset.x, point.y - carryOffset.y);
        (pageEdge.item as CcPageEdge)?.updateDrag(carryHover === "" ? scenePoint : null);
    }

    function carrySettled() {
        const source = carrySource;
        if (!source)
            return;
        if (widgetGrid !== source) {
            carryMoved(source.dragScenePoint);
            return;
        }
        carrySource = null;
        carryHover = "";
        source.draggingSlot?.moveDrag(source.dragScenePoint);
    }

    function dropCarried(source, index) {
        const target = widgetGrid;
        const savedIndex = source.savedIndex(index);
        const page = pager.currentIndex;
        const group = carryHover === "group" ? target.groupAt(target.dragScenePoint, -1) : null;
        const groupId = group?.groupId ?? "";
        const before = group ? group.savedIndexAtSlot(group.incomingSlot) : -1;
        const trashed = carryHover === "trash";
        const placedOnPage = target !== source && target.externalItem !== null && target.acceptsDrop(source.dragScenePoint);
        let cell = null;
        let base = null;
        if (placedOnPage) {
            const placed = target.committedItems();
            cell = placed.pop();
            base = target.withHidden(placed);
        }
        carryDropped = placedOnPage || trashed || groupId !== "";
        Qt.callLater(() => {
            if (groupId !== "")
                WidgetUtils.moveToGroup(savedIndex, groupId, before);
            else if (trashed)
                widgetModel.removeWidget(savedIndex);
            else if (placedOnPage)
                widgetModel.moveToPage(savedIndex, page, base, cell);
            target.cancelInteraction();
            source.cancelInteraction();
        });
        return true;
    }

    // Drops commit a tick later: committing inside the release handler would destroy the dragged item mid-signal.
    function dropFromGrid(grid, index, scenePoint) {
        if (carrySource === grid)
            return dropCarried(grid, index);
        if (!grid.heldOutside)
            return false;
        const savedIndex = grid.savedIndex(index);
        const group = grid.hoverGroup !== "" ? grid.groupAt(scenePoint, index) : null;
        if (group) {
            const groupId = group.groupId;
            const before = group.savedIndexAtSlot(group.incomingSlot);
            Qt.callLater(() => {
                WidgetUtils.moveToGroup(savedIndex, groupId, before);
                grid.cancelInteraction();
            });
            return true;
        }
        Qt.callLater(() => {
            widgetModel.removeWidget(savedIndex);
            grid.cancelInteraction();
        });
        return true;
    }

    function addWidget(widgetId) {
        const pin = addPin;
        if (pin?.page === pager.currentIndex) {
            if (!widgetModel.addWidget(widgetId, pin.col, pin.row, pin.page, pin.room))
                return false;
        } else {
            widgetModel.addWidget(widgetId, undefined, undefined, pager.currentIndex);
        }
        addPin = null;
        return true;
    }

    // Edit chrome overhangs a tile's corners, so the spot stays hidden near them.
    function spotAt(position) {
        const grid = widgetGrid;
        if (!grid)
            return null;
        const point = grid.mapFromItem(body, position.x, position.y);
        const reach = CcMetrics.editChromeInset;
        const nearCorner = slot => slot && [slot.x, slot.x + slot.w].some(x => Math.abs(point.x - x) <= reach) && [slot.y, slot.y + slot.h].some(y => Math.abs(point.y - y) <= reach);
        if (grid.slotLayout.slots.some(nearCorner))
            return null;
        const cell = GridUtils.freeCellAt(grid.slotLayout, point.x, point.y, grid.height, grid.rowLimit);
        if (!cell)
            return null;
        const origin = body.mapFromItem(grid, cell.x, cell.y);
        return {
            "page": pager.currentIndex,
            "col": cell.col,
            "row": cell.row,
            "room": { "layout": grid.slotLayout, "rowLimit": grid.rowLimit },
            "x": origin.x,
            "y": origin.y,
            "w": cell.w,
            "h": cell.h
        };
    }

    function activateAddHint() {
        const spot = addSpot;
        if (addPin && (!spot || (spot.page === addPin.page && spot.col === addPin.col && spot.row === addPin.row))) {
            addPin = null;
            return;
        }
        if (!spot)
            return;
        addPin = spot;
        if (docked) {
            (dockedPanel as CcDockedEditPanel)?.focusSearch();
            return;
        }
        openWidgetSheet();
    }

    function tapAddHint(position) {
        const spot = addHint;
        if (!spot || position.x < spot.x || position.x >= spot.x + spot.w || position.y < spot.y || position.y >= spot.y + spot.h)
            return;
        activateAddHint();
    }

    function resetLayout() {
        batchEdit(() => widgetModel.resetToDefault());
        pager.goTo(0);
    }

    function clearLayout() {
        widgetModel.clearAll();
        pager.goTo(0);
    }

    function openWidgetSheet() {
        // The popover never grows the body, so a short one keeps the sheet.
        if ((host.editPopover ?? false) && height >= CcMetrics.widgetPopoverMinHeight + CcMetrics.sheetPadding * 2) {
            widgetPopoverOpen = !widgetPopoverOpen;
            return;
        }
        const sheet = widgetSheetLoader.item;
        if (!sheet) {
            widgetSheetRequested = true;
            return;
        }
        sheet.opened = true;
    }

    function closeWidgetSheet() {
        if (!widgetSheetLoader.item)
            return;
        widgetSheetLoader.item.opened = false;
    }

    function handleEscape() {
        if (codecSelectorLoader.item?.shown) {
            codecSelectorLoader.item.dismiss();
            return true;
        }
        if (portSelectorLoader.item?.shown) {
            portSelectorLoader.item.dismiss();
            return true;
        }
        if (widgetSheetLoader.item?.opened) {
            closeWidgetSheet();
            return true;
        }
        if (widgetPopoverOpen) {
            widgetPopoverOpen = false;
            return true;
        }
        if (configOverlayLoader.item?.visible) {
            configOverlayLoader.item.close();
            return true;
        }
        if (addPin) {
            addPin = null;
            return true;
        }
        if (pageOpen) {
            goBack();
            return true;
        }
        if (host.editMode) {
            host.editMode = false;
            return true;
        }
        host.close();
        return true;
    }

    Keys.onEscapePressed: event => {
        if (handleEscape())
            event.accepted = true;
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.host.shouldBeVisible
        context: Qt.WindowShortcut
        onActivated: root.handleEscape()
    }

    Shortcut {
        sequences: ["F2", "Ctrl+E"]
        enabled: root.host.shouldBeVisible && !root.host.editMode && !root.pageOpen
        context: Qt.WindowShortcut
        onActivated: root.host.editMode = true
    }

    Shortcut {
        sequences: ["Ctrl+Z"]
        enabled: root.host.shouldBeVisible && root.canUndo
        context: Qt.WindowShortcut
        onActivated: root.undoEdit()
    }

    Shortcut {
        sequence: "Ctrl+PgUp"
        enabled: root.host.shouldBeVisible && root.pageCount > 1 && root.swipeAllowed
        context: Qt.WindowShortcut
        onActivated: pager.goTo(pager.currentIndex - 1)
    }

    Shortcut {
        sequence: "Ctrl+PgDown"
        enabled: root.host.shouldBeVisible && root.pageCount > 1 && root.swipeAllowed
        context: Qt.WindowShortcut
        onActivated: pager.goTo(pager.currentIndex + 1)
    }

    readonly property bool editMode: host.editMode

    onEditModeChanged: {
        if (editMode) {
            host.collapseAll();
            editSnapshot = editState;
            undoBase = editState;
        } else {
            panelResizer.cancel();
            // Compacting renumbers the pages, so the page shown is kept.
            const used = Pages.usedPages(SettingsData.controlCenterWidgets || [], widget => widgetModel.isTileShown(widget));
            const page = Pages.nearestIndex(used, pager.currentIndex);
            if (page !== pager.currentIndex)
                pager.goTo(page, false);
            widgetModel.compactPages();
            editSnapshot = "";
            undoBase = "";
            widgetSheetRequested = false;
            widgetPopoverOpen = false;
            addPin = null;
        }
        undoStack = [];
        if (!activeFocus)
            forceActiveFocus();
    }

    DGridEditChrome {
        id: panelChrome

        property int resizeSide: 0

        anchors.fill: parent
        anchors.margins: (root.host.panelChromeInset ?? 0) - contentInset
        anchors.topMargin: (root.host.panelChromeInset ?? 0) - contentInset - (editActions.visible && editActions.joined && root.stripAbove ? editActions.height : 0)
        anchors.bottomMargin: (root.host.panelChromeInset ?? 0) - contentInset - (editActions.visible && editActions.joined && !root.stripAbove ? editActions.height : 0)
        z: 1
        visible: root.host.editMode
        enabled: detailBand.shownSection === "" && !root.widgetSheetOpen && !root.widgetPopoverOpen
        edgeResize: root.panelResizing ? resizeSide < 0 : root.panelResizer.sideMovable(-1, root.gridColumns)
        cornerResize: root.panelResizing ? resizeSide > 0 : root.panelResizer.sideMovable(1, root.gridColumns)
        horizontalResize: true
        verticalResize: root.fixedHeight
        verticalResizeAbove: !(root.host.growsFromTop ?? true)
        removable: false
        // Frame-attached corners are square, but the ring keeps the surface radius.
        cornerRadius: root.surfaceRadius
        buttonSize: Theme.iconSize
        iconSize: PopoutMetrics.chromeIconSize
        handleLength: Theme.buttonHeightM
        handleThickness: Theme.spacingS
        resizing: root.panelResizing
        atDefault: !root.fixedHeight && root.gridColumns === Math.min(CcMetrics.defaultColumns, root.gridColumnCap)
        sizeText: root.gridColumns + "×" + (root.fixedHeight ? root.fixedRows : root.widgetGrid?.slotLayout.rows ?? 0)
        onResizeStarted: (px, py, signX) => {
            resizeSide = signX;
            root.resizeBase = { "widgets": SettingsData.controlCenterWidgets, "rows": root.panelResizer.currentRows(), "columns": root.gridColumns, "vertical": signX === 0, "state": root.editState };
            root.panelResizer.begin(px, py, signX);
        }
        onResizeMoved: (px, py) => root.panelResizer.move(px, py)
        onResizeEnded: root.panelResizer.end()
        onResizeCanceled: root.panelResizer.cancel()
    }

    WidgetModel {
        id: widgetModel
        columns: root.gridColumns
        maximumRows: root.widgetGrid?.maximumRows ?? CcMetrics.rowCapFor(root.availableGridHeight)
        prepareLayout: widgets => root.fixedHeight ? root.rowLayout(widgets, root.gridColumns, root.fixedRows) : widgets
    }

    Rectangle {
        anchors.fill: parent
        topLeftRadius: root.surfaceCornerRadii.x
        topRightRadius: root.surfaceCornerRadii.y
        bottomRightRadius: root.surfaceCornerRadii.z
        bottomLeftRadius: root.surfaceCornerRadii.w
        color: Theme.withAlpha(Theme.backdropColor, Theme.scrimAlpha)
        opacity: root.host.powerMenuOpen ? 1 : 0
        visible: opacity > 0
        z: CcMetrics.overlayZ

        Behavior on opacity {
            enabled: CcMetrics.animationsEnabled
            NumberAnimation {
                duration: CcMetrics.fadeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }
    }

    DFlickable {
        id: contentFlickable

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.chromeHeight + CcMetrics.pageFooterHeight
        clip: contentHeight > height
        contentWidth: width
        contentHeight: Math.max(height, mainColumn.y + mainColumn.implicitHeight)
        interactive: contentHeight > height

        MouseArea {
            width: root.sheetContentWidth
            height: contentFlickable.contentHeight
            z: -1
            enabled: root.hostOpen && !root.host.editMode && !root.pageOpen && !root.widgetSheetOpen && !root.widgetPopoverOpen && !pager.moving && !root.host.powerMenuOpen
            acceptedButtons: Qt.RightButton
            onPressed: mouse => {
                mouse.accepted = !(root.widgetGrid?.containsTile(mapToItem(null, mouse.x, mouse.y)) ?? false);
            }
            onClicked: root.host.editMode = true
        }

        Column {
            id: mainColumn

            width: root.sheetContentWidth - CcMetrics.sheetPadding * 2
            x: CcMetrics.sheetPadding
            y: CcMetrics.sheetPadding
            spacing: Theme.spacingS

            Item {
                id: body

                width: parent.width
                height: Math.max(root.fixedHeight ? root.fixedGridHeight : 0, root.gridHeight, root.heldGridHeight)
                opacity: CcMetrics.hideCoveredContent ? 1 - root.coveredAmount : 1

                HoverHandler {
                    id: addHover
                    enabled: root.host.editMode
                }

                // Passive, so a swipe from the spot still pages.
                TapHandler {
                    id: addTap
                    enabled: root.addHint !== null
                    onTapped: eventPoint => root.tapAddHint(eventPoint.position)
                }

                // Under the pages: it only ever sits on an empty spot, and the tiles' edit chrome stays on top of it.
                Rectangle {
                    id: addHintItem

                    readonly property var spot: root.addHint
                    readonly property point pointer: addHover.point.position
                    readonly property bool hovered: spot !== null && addHover.hovered && pointer.x >= x && pointer.x < x + width && pointer.y >= y && pointer.y < y + height
                    readonly property bool pressed: hovered && addTap.pressed

                    x: spot?.x ?? 0
                    y: spot?.y ?? 0
                    width: spot?.w ?? 0
                    height: spot?.h ?? 0
                    radius: Math.min(Theme.cornerRadiusXL, Theme.fullRadius(width, height))
                    color: Theme.withAlpha(Theme.primary, pressed ? Theme.stateLayerPressed : hovered ? Theme.stateLayerHover : 0)
                    visible: spot !== null
                    activeFocusOnTab: visible
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("Add a widget here")
                    Accessible.onPressAction: root.activateAddHint()

                    Keys.onPressed: event => {
                        if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Space)
                            return;
                        root.activateAddHint();
                        event.accepted = true;
                    }

                    onHoveredChanged: {
                        if (hovered) {
                            (addHintTooltip.item as DTooltipHost)?.schedule();
                            return;
                        }
                        (addHintTooltip.item as DTooltipHost)?.dismiss();
                    }

                    Loader {
                        anchors.fill: parent
                        active: addHintItem.visible
                        sourceComponent: DashedOutline {
                            radius: addHintItem.radius
                            strokeColor: addHintItem.hovered ? Theme.primary : Theme.outlineVariant
                        }
                    }

                    DIcon {
                        anchors.centerIn: parent
                        name: "add"
                        size: Theme.iconSize
                        color: Theme.primary
                    }

                    FocusRing {}

                    Loader {
                        id: addHintTooltip

                        active: root.host.editMode
                        sourceComponent: DTooltipHost {
                            text: I18n.tr("Add a widget here")
                            target: addHintItem
                            side: "top"
                        }
                    }
                }

                // The edit floor holds the surface taller than the chosen rows; Finish shrinks it to this room's top.
                Item {
                    id: heldRoom

                    readonly property bool overflow: root.widgetGrid?.overflowPreview ?? false

                    y: body.height + CcMetrics.gridGap
                    width: body.width
                    height: pager.height - y - CcMetrics.gridGap
                    visible: root.host.editMode && root.fixedHeight && height >= Theme.spacingXL * 2 && !root.pageOpen && !root.widgetSheetOpen && !root.widgetPopoverOpen

                    Loader {
                        anchors.fill: parent
                        active: heldRoom.visible
                        sourceComponent: DashedOutline {
                            radius: Math.min(Theme.cornerRadiusXL, Theme.fullRadius(width, height))
                            fillColor: Theme.withAlpha(Theme.onSurface, Theme.stateLayerHover)
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        width: Math.max(0, parent.width - Theme.spacingXL * 2)
                        visible: (root.editIdle || root.panelResizing || root.libraryDragging || heldRoom.overflow) && !pager.moving && parent.height >= implicitHeight + Theme.spacingXL * 2
                        text: heldRoom.overflow ? I18n.tr("Overflow moves to the next page") : I18n.tr("Space reserved for editing\nFinish to apply the selected height.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }
                }

                CcPager {
                    id: pager

                    width: parent.width
                    height: Math.max(parent.height, contentFlickable.height - CcMetrics.sheetPadding)
                    count: root.pageCount
                    gutter: CcMetrics.sheetPadding
                    swipeEnabled: root.swipeAllowed
                    onCurrentIndexChanged: {
                        root.host.currentPage = currentIndex;
                        root.addPin = null;
                        root.releaseHiddenFocus();
                        if (root.pageOpen && currentIndex !== root.bandPage)
                            root.host.collapseAll();
                    }
                    onMovingChanged: {
                        if (moving)
                            return;
                        root.carrySettled();
                        if (root.libraryDragging)
                            root.dockedPanel?.updateDrag(root.dockedPanel.dragPoint);
                    }
                    delegate: CcTileGrid {
                        id: pageGrid

                        required property int index
                        readonly property bool holdsBand: index === root.bandPage

                        page: index
                        savedWidgets: root.layoutWidgets
                        overflowHost: overflowLayer
                        scrollOffset: contentFlickable.contentY
                        columns: root.gridColumns
                        availableHeight: root.pageGridHeight
                        rowLimit: root.fixedHeight ? root.fixedRows : 0
                        // Short and empty pages must accept drops across the available panel height.
                        minimumHeight: Math.max(pager.height, contentFlickable.height - CcMetrics.sheetPadding)
                        editMode: root.host.editMode
                        model: widgetModel
                        live: root.host.shouldBeVisible && pager.pageShown(index)
                        expandedSection: holdsBand ? detailBand.shownSection : ""
                        bandHeight: holdsBand ? detailBand.height : 0
                        bandTargetHeight: holdsBand ? detailBand.targetHeight : 0
                        bandMoving: holdsBand && detailBand.shownSection !== ""
                        screenName: root.host.triggerScreen?.name || ""
                        tapToClose: root.host.headerTogglesClose ?? false
                        runningToplevels: root.runningToplevels
                        swallowPoint: {
                            if (root.docked || !root.overTrash || root.widgetGrid !== pageGrid)
                                return null;
                            return pageGrid.mapFromItem(editActions, editActions.width / 2, editActions.height / 2);
                        }
                        carried: root.carrySource === pageGrid
                        carryGroup: root.carrySource !== null && root.widgetGrid === pageGrid ? root.carryGroupId : ""
                        dragsOutside: (index, scenePoint) => root.gridDragMoved(pageGrid, scenePoint)
                        dropHandler: (index, scenePoint) => root.dropFromGrid(pageGrid, index, scenePoint)
                        onExpandClicked: widgetData => root.openWidgetPage(widgetData)
                        onRemoveWidget: index => widgetModel.removeWidget(index)
                        onConfigRequested: (index, widgetData, anchor) => root.openConfigOverlay(index, widgetData, anchor)
                        onColorPickerRequested: root.host.openColorPicker()
                        onCloseRequested: root.host.close()
                        onSettingsRequested: root.host.openSettings()
                        onEditRequested: root.host.editMode = !root.host.editMode
                        onAccountsRequested: root.host.openAccounts()
                        onLockRequested: {
                            root.host.close();
                            root.host.lockRequested();
                        }
                        onPowerRequested: {
                            const loader = root.host.powerMenuModalLoader;
                            if (!loader)
                                return;
                            loader.active = true;
                            if (!loader.item)
                                return;
                            const bounds = Qt.rect(root.host.alignedX, root.host.alignedY, root.host.popupWidth, root.host.popupHeight);
                            loader.item.openFromControlCenter(bounds, root.host.screen);
                        }
                    }
                }

                StyledText {
                    parent: pager
                    readonly property real reserveTop: Math.min(pager.height, root.widgetGrid?.dropHeight ?? body.height)
                    // The held room labels the edit floor and overflow itself.
                    readonly property real reserveBottom: heldRoom.visible ? body.height : pager.height
                    x: Theme.spacingXL
                    y: reserveTop + (reserveBottom - reserveTop - height) / 2
                    width: Math.max(0, pager.width - Theme.spacingXL * 2)
                    visible: root.host.editMode && root.fixedHeight && (root.editIdle || root.libraryDragging || (root.widgetGrid?.overflowPreview ?? false)) && !(heldRoom.visible && heldRoom.overflow) && !pager.moving && !root.pageOpen && !root.widgetSheetOpen && !root.widgetPopoverOpen && reserveBottom - reserveTop >= implicitHeight + Theme.spacingXL * 2
                    text: (root.widgetGrid?.overflowPreview ?? false) ? I18n.tr("Overflow moves to the next page") : reserveTop < body.height ? I18n.tr("Space reserved for stable page height") : I18n.tr("Space reserved for editing\nFinish to apply the selected height.")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                CcDetailBand {
                    id: detailBand

                    x: pager.logical(root.bandPage - pager.position) * pager.stride
                    y: root.bandGrid?.bandY ?? 0
                    width: parent.width
                    section: root.host.expandedSection ?? ""
                    maximumHeight: root.availableGridHeight - (root.bandGrid?.baseHeight ?? 0)
                    coverage: Math.max(codecSelectorLoader.item?.presence ?? 0, portSelectorLoader.item?.presence ?? 0)
                    model: widgetModel
                    screenName: root.host.triggerScreen?.name || ""
                    screenModel: root.host.triggerScreen?.model || ""
                    transientSurfaceTracker: root.host.transientSurfaceTracker
                    runningToplevels: root.runningToplevels
                    onCodecSelectorRequested: device => root.showCodecSelector(device)
                    onPortSelectorRequested: node => root.showPortSelector(node)
                    onBackRequested: root.goBack()
                    onCollapseRequested: root.host.collapseAll()
                    onCloseRequested: root.host.close()
                    onHeightChanged: root.revealDetail()
                    onDismissed: {
                        const target = root.detailReturnFocus;
                        root.detailReturnFocus = null;
                        if (target?.visible && target.enabled) {
                            target.forceActiveFocus();
                            return;
                        }
                        root.forceActiveFocus();
                    }
                }

                Loader {
                    id: pageEdge

                    parent: root
                    x: mainColumn.x + body.x + pager.x
                    y: CcMetrics.sheetPadding
                    width: pager.width
                    height: Math.max(0, contentFlickable.height - CcMetrics.sheetPadding)
                    z: 2
                    active: root.host.editMode
                    sourceComponent: CcPageEdge {
                        count: pager.count
                        currentIndex: pager.currentIndex
                        gutter: CcMetrics.sheetPadding
                        dragActive: root.gridDragWidget !== null || root.libraryDragging
                        onCarryRequested: direction => root.carryTo(direction)
                    }
                }
            }
        }

        CcPageDots {
            id: pageDots

            parent: root
            // Under the chrome while it carries the height grip, so the grip's inner edge stays grabbable.
            z: panelChrome.z + (root.host.editMode && panelChrome.verticalResize ? -0.5 : 1)
            x: mainColumn.x
            y: contentFlickable.y + contentFlickable.height
            width: mainColumn.width
            count: pager.count
            currentIndex: pager.currentIndex
            // They share the bottom edge with the height handle, so they step aside while it drags.
            visible: count > 1 && !(root.panelResizing && (root.resizeBase?.vertical ?? false))
            opacity: body.opacity
            enabled: root.editIdle
            onPageRequested: index => pager.goTo(index)

            // The dots sit outside the pager, so a swipe over them pages too.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: undefined
                enabled: pager.swipeEnabled && pager.count > 1
                onWheel: event => pager.wheelBy(event)
            }
        }
    }

    CcEditActions {
        id: editActions

        x: 0
        y: root.editRoom > 0 ? Math.max(root.height - root.editRoom, CcMetrics.gridVerticalPadding + root.heldGridHeight) + (root.editRoom - height) / 2 : (root.stripAbove ? -height : root.height)
        width: root.sheetContentWidth
        height: implicitHeight
        // Below the edit rings so the trash fill never covers them.
        z: -1
        editMode: root.host.editMode && !root.docked
        enabled: detailBand.shownSection === "" && !root.widgetSheetOpen
        dragging: root.gridDragWidget !== null
        dragRemovable: WidgetUtils.isRemovable(root.gridDragWidget)
        overTrash: root.overTrash
        transientSurfaceTracker: root.host.transientSurfaceTracker
        joined: root.editRoom === 0
        above: root.stripAbove
        // Joined, the popout host paints the surface under the strip.
        backgroundColor: joined ? "transparent" : Theme.foregroundColor(Theme.cardSurface)
        cornerRadii: root.surfaceCornerRadii
        opacity: body.opacity
        canUndo: root.canUndo
        fixedHeight: root.fixedHeight
        onAddWidgetRequested: root.openWidgetSheet()
        onUndoRequested: root.undoEdit()
        onHeightModeRequested: fixed => root.setFixedHeight(fixed)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: undefined
            enabled: editActions.editMode && pager.swipeEnabled && pager.count > 1
            onWheel: event => pager.wheelBy(event)
        }
        onResetRequested: root.resetLayout()
        onClearRequested: root.clearLayout()
        onFinishRequested: root.host.editMode = false
        onCancelRequested: root.cancelEdit()
    }

    Loader {
        id: dockedPanelLoader

        readonly property real dockGap: root.host.dockGap ?? CcMetrics.dockedPanelGap
        // Keeps a connected body's bar edge to itself.
        readonly property real barInset: root.host.dockInset ?? 0
        readonly property bool insetTop: barInset > 0 && root.host.effectiveBarPosition === SettingsData.Position.Top
        readonly property real popoverWidth: Math.min(CcMetrics.dockedPanelWidth, root.width - CcMetrics.sheetPadding * 2)

        x: {
            if (!root.docked)
                return I18n.isRtl ? root.width - width - CcMetrics.sheetPadding : CcMetrics.sheetPadding;
            return root.dockSide === "left" ? -(width + dockGap) : root.width + dockGap;
        }
        y: {
            if (!root.docked)
                return CcMetrics.sheetPadding;
            if (root.host.dockAbove ?? false)
                return root.height - (insetTop ? 0 : barInset) - height;
            return insetTop ? barInset : 0;
        }
        width: root.docked ? CcMetrics.dockedPanelWidth : popoverWidth
        // A host that hangs the panel past a shorter body gives its floor; others grow the body to it.
        height: root.docked ? Math.max(root.height - barInset, root.host.dockPanelMinHeight ?? 0) : root.height - CcMetrics.sheetPadding * 2
        z: CcMetrics.overlayZ
        active: root.docked || (root.widgetPopoverOpen && (root.host.editPopover ?? false))
        enabled: detailBand.shownSection === ""
        sourceComponent: CcDockedEditPanel {
            widgets: root.addableWidgets()
            canAdd: widgetId => root.canAddAtPin(widgetId)
            grid: root.widgetGrid
            pageMoving: pager.moving
            prepareDrop: () => pager.goTo(pager.currentIndex, false)
            onDragUpdated: scenePoint => (pageEdge.item as CcPageEdge)?.updateDrag(root.dockedPanel.overPanel(scenePoint) || pager.moving ? null : scenePoint)
            floating: !root.docked
            fadeOut: root.gridDragWidget !== null
            canUndo: root.canUndo
            fixedHeight: root.fixedHeight
            removeTarget: root.docked && root.overTrash
            // Docked it matches the body, opaque where blur can't reach; floating it sits a tier up and hides the tiles.
            surfaceColor: {
                const base = root.docked ? (root.host.surfaceColor ?? CcMetrics.dialogColor) : Theme.foregroundColor(Theme.cardSurface);
                return root.docked && (root.host.surfaceBlurred ?? false) ? base : Theme.withAlpha(base, 1);
            }
            radius: root.docked ? root.surfaceRadius : Theme.cornerRadiusL
            transientSurfaceTracker: root.host.transientSurfaceTracker
            onCloseRequested: root.widgetPopoverOpen = false
            onAddRequested: widgetId => root.addWidget(widgetId)
            onUndoRequested: root.undoEdit()
            onHeightModeRequested: fixed => root.setFixedHeight(fixed)
            onResetRequested: root.resetLayout()
            onClearRequested: root.clearLayout()
            onFinishRequested: root.host.editMode = false
            onCancelRequested: root.cancelEdit()
        }
    }

    Loader {
        id: codecSelectorLoader

        anchors.fill: parent
        z: CcMetrics.overlayZ
        active: false
        sourceComponent: BluetoothCodecSelector {
            cornerRadii: root.surfaceCornerRadii
            dimsBackdrop: root.sheetsDim
            onDismissed: Qt.callLater(root.releaseSheet, codecSelectorLoader)
        }
    }

    Loader {
        id: portSelectorLoader

        anchors.fill: parent
        z: CcMetrics.overlayZ
        active: false
        sourceComponent: AudioPortSelector {
            cornerRadii: root.surfaceCornerRadii
            dimsBackdrop: root.sheetsDim
            onDismissed: Qt.callLater(root.releaseSheet, portSelectorLoader)
        }
    }

    Connections {
        target: CompositorService

        function onToplevelsChanged() {
            root.toplevelRevision++;
        }
    }

    Loader {
        id: widgetSheetLoader

        anchors.fill: parent
        anchors.topMargin: editActions.joined && root.stripAbove ? -editActions.height : 0
        anchors.bottomMargin: editActions.joined && !root.stripAbove ? -editActions.height : 0
        z: CcMetrics.overlayZ
        // With the popover, the sheet is only the fallback for a short surface, so it loads on request.
        active: root.host.editMode && !root.docked && (root.host.editLayoutDecided ?? true) && (!(root.host.editPopover ?? false) || root.widgetSheetRequested || (item?.active ?? false))
        asynchronous: true
        onLoaded: {
            if (!root.widgetSheetRequested)
                return;
            // Opened first: clearing the request alone would unload it again on the popover path.
            item.opened = true;
            root.widgetSheetRequested = false;
        }
        sourceComponent: CcWidgetSheet {
            scrimRadii: root.surfaceCornerRadii
            scrimVisible: root.sheetsDim
            surfaceColor: CcMetrics.dialogColor
            widgets: root.addableWidgets(true)
            onDismissRequested: opened = false
            onChosen: widgetId => {
                if (root.addWidget(widgetId))
                    opened = false;
            }
        }
    }

    // Spilling tiles paint above the dock's drag ghost and clip at the viewport, so they leave like a page swipe.
    Item {
        id: overflowLayer

        x: contentFlickable.x
        y: contentFlickable.y
        width: contentFlickable.width
        height: contentFlickable.height
        z: CcMetrics.overlayZ + 2
        clip: true
    }

    // The slot keeps the pointer grab; its preview escapes scrolling clips and paints above the dock.
    Loader {
        active: root.carrySource !== null || (root.docked && root.gridDragWidget !== null)
        z: CcMetrics.overlayZ + 1
        sourceComponent: ShaderEffectSource {
            readonly property real overflow: CcMetrics.editChromeInset
            readonly property point scenePoint: root.carrySource?.dragScenePoint ?? Qt.point(0, 0)
            readonly property point local: root.mapFromItem(null, scenePoint.x, scenePoint.y)

            readonly property point slotPoint: {
                if (!sourceItem)
                    return Qt.point(0, 0);
                contentFlickable.contentY;
                sourceItem.x;
                sourceItem.y;
                return root.mapFromItem(sourceItem, 0, 0);
            }

            x: (root.carrySource ? local.x - root.carryOffset.x : slotPoint.x) - overflow
            y: (root.carrySource ? local.y - root.carryOffset.y : slotPoint.y) - overflow
            width: (sourceItem?.width ?? 0) + overflow * 2
            height: (sourceItem?.height ?? 0) + overflow * 2
            sourceRect: Qt.rect(-overflow, -overflow, width, height)
            sourceItem: root.dragGrid?.draggingSlot ?? null
            hideSource: true
        }
    }

    Loader {
        id: configOverlayLoader

        active: false
        sourceComponent: WidgetConfigOverlay {
            transientSurfaceTracker: root.host.transientSurfaceTracker
            onVisibleChanged: {
                if (visible)
                    return;
                Qt.callLater(root.releaseConfigOverlay);
            }
        }
    }
}
