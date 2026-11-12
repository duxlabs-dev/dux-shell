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

FocusScope {
    id: root

    required property var host

    property bool live: Window.window?.visible ?? false
    readonly property bool hostOpen: host.shouldBeVisible ?? false
    property bool audioRefHeld: false

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property string openSection: host.expandedSection ?? ""
    readonly property bool pageOpen: openSection !== ""
    readonly property int usedPageCount: Pages.pageCount(SettingsData.controlCenterWidgets || [], widget => widgetModel.isTileShown(widget))
    // Edit mode adds an empty page after the last used one to drop or add on.
    readonly property int pageCount: usedPageCount + (host.editMode ? 1 : 0)
    readonly property CcTileGrid widgetGrid: pager.currentItem as CcTileGrid
    readonly property list<Item> pageGrids: pager.items
    // The band stays with the page it opened on while it collapses, so switching page never moves it across.
    property int bandPage: 0
    readonly property CcTileGrid bandGrid: pageGrids[bandPage] as CcTileGrid
    // A tile held at a page edge moves to the neighbor page. Its own grid keeps the pointer grab, held still with the
    // tile drawn as a ghost under the pointer, while the page shown previews the tile and takes the drop.
    property CcTileGrid carrySource: null
    property point carryOffset
    // "group" or "trash" while either claims the carried tile, "" over the page.
    property string carryHover: ""
    property string carryGroupId: ""
    property bool carryDropped: false
    readonly property int carriedIndex: carrySource?.draggingSourceIndex ?? -1
    readonly property CcTileGrid dragGrid: carrySource ?? widgetGrid
    readonly property bool gridDragging: carrySource !== null || (widgetGrid?.dragging ?? false)
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
    readonly property Item dockedPanel: dockedPanelLoader.item
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
    function addableWidgets() {
        const existingIds = placedWidgetIds.split(",");
        const allWidgets = widgetModel.baseWidgetDefinitions.concat(widgetModel.getPluginWidgets());
        return allWidgets.filter(w => w.allowMultiple || !existingIds.includes(w.id));
    }
    // A spare row to drop below the last one, only where growth leaves the grid still.
    readonly property real dragRoom: gridDragging && (host.growsFromTop ?? true) && restingGridHeight + newRowUnit <= availableGridHeight ? newRowUnit : 0
    readonly property real newRowUnit: CcMetrics.gridGap + (widgetGrid?.slotLayout.rowUnit ?? 0)
    // Held during a drag so the trash never moves under the pointer.
    readonly property real heldGridHeight: gridDragging ? restingGridHeight + dragRoom : gridHeight
    // The popout sizes to where the band is going; the content inside follows the band frame by frame.
    readonly property real targetImplicitHeight: CcMetrics.sheetPadding * 2 + (gridDragging ? heldGridHeight : gridTargetHeight)
    readonly property bool contentOverflows: targetImplicitHeight > (host.availableHeight ?? Infinity)
    property Item detailReturnFocus: null
    // One string so Discard and undo can compare and restore the whole session state at once.
    readonly property string editState: JSON.stringify({
        "widgets": SettingsData.controlCenterWidgets || [],
        "columns": SettingsData.controlCenterColumns
    })
    property string editSnapshot: ""
    property string undoBase: ""
    property var undoStack: []
    readonly property int undoLimit: 50
    property bool undoBatching: false
    readonly property bool editIdle: carrySource === null && !(widgetGrid?.interacting ?? false) && !(widgetGrid?.memberDragging ?? false) && !panelResizing
    readonly property bool canUndo: host.editMode && undoStack.length > 0 && editIdle && !widgetSheetOpen && !pageOpen
    readonly property bool panelResizing: panelResizer.resizing
    readonly property bool swipeAllowed: editIdle && !widgetSheetOpen && !widgetPopoverOpen && detailBand.shownSection === ""
    readonly property real sheetContentWidth: host.sheetContentWidth ?? CcMetrics.sheetWidthFor(gridColumns)
    readonly property vector4d surfaceCornerRadii: host.surfaceCornerRadii ?? Qt.vector4d(Theme.windowRadius, Theme.windowRadius, Theme.windowRadius, Theme.windowRadius)
    // A dim can't follow a frame-attached body past its square corners; the covered content is faded out anyway.
    readonly property bool sheetsDim: !CcMetrics.hideCoveredContent || Math.min(surfaceCornerRadii.x, surfaceCornerRadii.y, surfaceCornerRadii.z, surfaceCornerRadii.w) > 0
    readonly property int gridColumnCap: host.gridColumnCap ?? CcMetrics.columnCapFor((host.triggerScreen?.width ?? CcMetrics.sheetWidthDefault + Theme.spacingL * 2) - Theme.spacingL * 2)
    readonly property int gridColumns: host.gridColumns ?? Math.min(CcMetrics.gridColumns, gridColumnCap)
    readonly property real availableGridHeight: (host.availableHeight ?? (host.triggerScreen?.height ?? CcMetrics.fallbackScreenHeight) - CcMetrics.maxHeightInset) - CcMetrics.sheetPadding * 2 - editRoom
    readonly property DPanelResizer panelResizer: DPanelResizer {
        popout: root.host
        stepWidth: CcMetrics.columnWidth + CcMetrics.gridGap
        widthFor: columns => CcMetrics.sheetWidthFor(columns) + root.sheetContentWidth - CcMetrics.sheetWidthFor(root.gridColumns)
        currentStep: () => root.gridColumns
        minStep: Math.min(CcMetrics.minimumColumns, root.gridColumnCap)
        maxStep: root.gridColumnCap
        onPreview: columns => CcMetrics.columnPreview = columns
        onCommitted: columns => {
            SettingsData.set("controlCenterColumns", columns);
            CcMetrics.columnPreview = 0;
        }
        onCanceled: CcMetrics.columnPreview = 0
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
        if (widgetData.id === "brightnessSlider") {
            openWidgetPage(widgetData);
            return;
        }
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
        if (JSON.stringify(SettingsData.controlCenterWidgets || []) !== JSON.stringify(wanted.widgets))
            SettingsData.set("controlCenterWidgets", wanted.widgets);
        if (SettingsData.controlCenterColumns !== wanted.columns)
            SettingsData.set("controlCenterColumns", wanted.columns);
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
    }
    onCarriedIndexChanged: {
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
        const widgets = SettingsData.controlCenterWidgets || [];
        const widget = Sections.widgetForSection(openSection);
        bandPage = Math.max(0, Math.min(widget ? Pages.pageOf(Pages.groupOf(widgets, widget) ?? widget) : pager.currentIndex, pager.count - 1));
        if (bandPage !== pager.currentIndex)
            pager.goTo(bandPage, animate && live);
    }

    onEditStateChanged: {
        addPin = null;
        if (!host.editMode || undoBatching || editState === undoBase)
            return;
        undoStack = undoStack.concat([undoBase]).slice(-undoLimit);
        undoBase = editState;
    }

    // Keeps the intermediate states of a multi-key write out of the undo stack.
    function batchEdit(change) {
        const before = editState;
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
        if (carryHover !== "" || !grid.contains(point))
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
        let cell = null;
        let base = null;
        if (target !== source && target.externalItem) {
            const placed = target.committedItems();
            cell = placed.pop();
            base = target.withHidden(placed);
        }
        carryDropped = target !== source;
        Qt.callLater(() => {
            if (groupId !== "")
                WidgetUtils.moveToGroup(savedIndex, groupId, before);
            else if (trashed)
                widgetModel.removeWidget(savedIndex);
            else if (target !== source)
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
        addPin = null;
        if (pin?.page === pager.currentIndex) {
            widgetModel.addWidget(widgetId, pin.col, pin.row, pin.page, pin.room);
            return;
        }
        widgetModel.addWidget(widgetId, undefined, undefined, pager.currentIndex);
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
        const cell = GridUtils.freeCellAt(grid.slotLayout, point.x, point.y, grid.height);
        if (!cell)
            return null;
        const origin = body.mapFromItem(grid, cell.x, cell.y);
        return {
            "page": pager.currentIndex,
            "col": cell.col,
            "row": cell.row,
            "room": GridUtils.freeRun(grid.slotLayout, cell.col, cell.row),
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
        anchors.margins: -contentInset
        anchors.topMargin: -contentInset - (editActions.visible && editActions.joined && root.stripAbove ? editActions.height : 0)
        anchors.bottomMargin: -contentInset - (editActions.visible && editActions.joined && !root.stripAbove ? editActions.height : 0)
        z: 1
        visible: root.host.editMode
        enabled: detailBand.shownSection === "" && !root.widgetSheetOpen
        edgeResize: root.panelResizing ? resizeSide < 0 : root.panelResizer.sideMovable(-1, root.gridColumns)
        cornerResize: root.panelResizing ? resizeSide > 0 : root.panelResizer.sideMovable(1, root.gridColumns)
        horizontalResize: true
        removable: false
        // Frame-attached corners are square, but the ring keeps the surface radius.
        cornerRadius: root.surfaceRadius
        buttonSize: Theme.iconSize
        iconSize: PopoutMetrics.chromeIconSize
        resizing: root.panelResizing
        atDefault: root.gridColumns === Math.min(CcMetrics.defaultColumns, root.gridColumnCap)
        sizeText: root.gridColumns + "×" + (root.widgetGrid?.slotLayout.rows ?? 0)
        onResizeStarted: (px, py, signX) => {
            resizeSide = signX;
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
        anchors.bottomMargin: root.chromeHeight
        clip: contentHeight > height
        contentWidth: width
        contentHeight: Math.max(height, mainColumn.y + mainColumn.implicitHeight + CcMetrics.sheetPadding)
        interactive: contentHeight > height

        Column {
            id: mainColumn

            width: root.sheetContentWidth - CcMetrics.sheetPadding * 2
            x: CcMetrics.sheetPadding
            y: CcMetrics.sheetPadding
            spacing: Theme.spacingS

            Item {
                id: body

                width: parent.width
                height: Math.max(root.gridHeight, root.heldGridHeight)
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
                        sourceComponent: Shape {
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                strokeColor: addHintItem.hovered ? Theme.primary : Theme.outlineVariant
                                strokeWidth: Theme.outlineWidthFocused
                                strokeStyle: ShapePath.DashLine
                                dashPattern: CcMetrics.addHintDashPattern
                                fillColor: "transparent"

                                PathRectangle {
                                    x: Theme.outlineWidthFocused / 2
                                    y: Theme.outlineWidthFocused / 2
                                    width: addHintItem.width - Theme.outlineWidthFocused
                                    height: addHintItem.height - Theme.outlineWidthFocused
                                    radius: Math.max(0, addHintItem.radius - Theme.outlineWidthFocused / 2)
                                }
                            }
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

                CcPager {
                    id: pager

                    width: parent.width
                    height: parent.height
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
                        if (!moving)
                            root.carrySettled();
                    }
                    delegate: CcTileGrid {
                        id: pageGrid

                        required property int index
                        readonly property bool holdsBand: index === root.bandPage

                        page: index
                        columns: root.gridColumns
                        availableHeight: root.availableGridHeight
                        // Covers the whole page, so an empty spot on a short or empty page still takes a drop.
                        minimumHeight: pager.height
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
                            if (!root.overTrash || root.widgetGrid !== pageGrid)
                                return null;
                            const target = root.docked ? root.dockedPanel : editActions;
                            return target ? pageGrid.mapFromItem(target, target.width / 2, target.height / 2) : null;
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

                    anchors.fill: pager
                    active: root.host.editMode
                    sourceComponent: CcPageEdge {
                        count: pager.count
                        currentIndex: pager.currentIndex
                        gutter: CcMetrics.sheetPadding
                        dragActive: root.gridDragWidget !== null
                        onCarryRequested: direction => root.carryTo(direction)
                    }
                }
            }
        }

        CcPageDots {
            id: pageDots

            x: mainColumn.x
            // Centered in the bottom padding, so the last row sits as close to the dots as the dots to the edge.
            y: mainColumn.y + body.height + (CcMetrics.sheetPadding - height) / 2
            width: mainColumn.width
            count: pager.count
            currentIndex: pager.currentIndex
            opacity: body.opacity
            enabled: root.editIdle
            onPageRequested: index => pager.goTo(index)
        }
    }

    CcEditActions {
        id: editActions

        x: 0
        y: root.editRoom > 0 ? Math.max(root.height - root.editRoom, CcMetrics.sheetPadding * 2 + root.heldGridHeight) + (root.editRoom - height) / 2 : (root.stripAbove ? -height : root.height)
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
        onAddWidgetRequested: root.openWidgetSheet()
        onUndoRequested: root.undoEdit()
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
        y: root.docked ? (insetTop ? barInset : 0) : CcMetrics.sheetPadding
        width: root.docked ? CcMetrics.dockedPanelWidth : popoverWidth
        height: root.docked ? root.height - barInset : root.height - CcMetrics.sheetPadding * 2
        z: CcMetrics.overlayZ
        active: root.docked || (root.widgetPopoverOpen && (root.host.editPopover ?? false))
        enabled: detailBand.shownSection === ""
        sourceComponent: CcDockedEditPanel {
            widgets: root.addableWidgets()
            grid: root.widgetGrid
            floating: !root.docked
            fadeOut: root.gridDragWidget !== null
            canUndo: root.canUndo
            removeTarget: root.docked && root.overTrash
            // Docked, it matches the body beside it, frame color and rounding included, and is opaque where the
            // blur cannot reach it; floating, it sits a tier above and hides the tiles under it.
            surfaceColor: {
                const base = root.docked ? (root.host.surfaceColor ?? CcMetrics.dialogColor) : Theme.foregroundColor(Theme.cardSurface);
                return root.docked && (root.host.surfaceBlurred ?? false) ? base : Theme.withAlpha(base, 1);
            }
            radius: root.docked ? root.surfaceRadius : Theme.cornerRadiusL
            transientSurfaceTracker: root.host.transientSurfaceTracker
            onCloseRequested: root.widgetPopoverOpen = false
            onAddRequested: widgetId => root.addWidget(widgetId)
            onUndoRequested: root.undoEdit()
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
            widgets: root.addableWidgets()
            onDismissRequested: opened = false
            onChosen: widgetId => {
                root.addWidget(widgetId);
                opened = false;
            }
        }
    }

    // Drawn from the carried tile itself, which stays in its own grid to keep the pointer grab.
    Loader {
        active: root.carrySource !== null
        z: CcMetrics.overlayZ
        sourceComponent: ShaderEffectSource {
            readonly property point scenePoint: root.carrySource?.dragScenePoint ?? Qt.point(0, 0)
            readonly property point local: root.mapFromItem(null, scenePoint.x, scenePoint.y)

            x: local.x - root.carryOffset.x
            y: local.y - root.carryOffset.y
            width: sourceItem?.width ?? 0
            height: sourceItem?.height ?? 0
            sourceItem: root.carrySource?.draggingSlot ?? null
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
