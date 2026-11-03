pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.ControlCenter.Components
import qs.Modules.ControlCenter.Models
import qs.Modules.ControlCenter.Details
import qs.DCommon.Widgets
import qs.Widgets
import "./utils/sections.js" as Sections
import "./utils/widgets.js" as WidgetUtils

FocusScope {
    id: root

    required property var host

    property bool live: Window.window?.visible ?? false
    property bool audioRefHeld: false

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property bool pageOpen: (host.expandedSection ?? "") !== ""
    readonly property real gridHeight: widgetGrid.gridHeight
    readonly property real gridTargetHeight: widgetGrid.targetHeight
    // Reserved from the grid in both modes so the island growing into edit mode never reflows tiles.
    readonly property real editRoom: host.editRoom ?? 0
    readonly property real chromeHeight: (host.editRoomShown ?? false) ? editRoom : 0
    readonly property bool stripAbove: host.stripAbove ?? false
    readonly property bool widgetSheetOpen: widgetSheetLoader.item?.active ?? false
    readonly property real coveredAmount: Math.max(widgetSheetLoader.item?.progress ?? 0, codecSelectorLoader.item?.presence ?? 0, portSelectorLoader.item?.presence ?? 0)
    property bool widgetSheetRequested: false
    property int toplevelRevision: 0
    readonly property var runningToplevels: {
        toplevelRevision;
        const all = CompositorService.sortedToplevels ?? [];
        const current = CompositorService.filterCurrentWorkspace(all, host.triggerScreen?.name) || [];
        return current.concat(all.filter(toplevel => !current.includes(toplevel)));
    }
    readonly property string placedWidgetIds: (SettingsData.controlCenterWidgets || []).map(w => w.id).sort().join(",")
    readonly property var gridDragWidget: widgetGrid.draggingSourceIndex >= 0 ? (widgetGrid.sourceItems[widgetGrid.draggingSourceIndex] ?? null) : null
    // Off the grid, anything but a group is the trash.
    readonly property bool overTrash: gridDragWidget !== null && widgetGrid.heldOutside && widgetGrid.hoverGroup === ""
    // A spare row to drop below the last one, only where growth leaves the grid still.
    readonly property real dragRoom: widgetGrid.dragging && (host.growsFromTop ?? true) && widgetGrid.pinnedHeight + newRowUnit <= availableGridHeight ? newRowUnit : 0
    readonly property real newRowUnit: CcMetrics.gridGap + widgetGrid.slotLayout.rowUnit
    // Held during a drag so the trash never moves under the pointer.
    readonly property real heldGridHeight: widgetGrid.dragging ? widgetGrid.pinnedHeight + dragRoom : gridHeight
    // The popout sizes to where the band is going; the content inside follows the band frame by frame.
    readonly property real targetImplicitHeight: CcMetrics.sheetPadding * 2 + (widgetGrid.dragging ? heldGridHeight : gridTargetHeight)
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
    readonly property bool editIdle: !widgetGrid.interacting && !widgetGrid.memberDragging && !panelResizing
    readonly property bool canUndo: host.editMode && undoStack.length > 0 && editIdle && !widgetSheetOpen && !pageOpen
    readonly property bool panelResizing: panelResizer.resizing
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
    Component.onCompleted: {
        WidgetUtils.ensureEditButton();
        syncAudioRef(live);
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

    function cancelEdit() {
        const snapshot = editSnapshot;
        host.editMode = false;
        if (snapshot !== "")
            applyEditState(snapshot);
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

    onEditStateChanged: {
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
        return WidgetUtils.isRemovable(gridDragWidget) && editActions.trashContains(scenePoint);
    }

    function groupTakesGridDrag(scenePoint) {
        return WidgetUtils.canGroup(gridDragWidget) && widgetGrid.groupAt(scenePoint, widgetGrid.draggingSourceIndex) !== null;
    }

    // Drops commit a tick later: committing inside the release handler would destroy the dragged item mid-signal.
    function dropFromGrid(index, scenePoint) {
        if (!widgetGrid.heldOutside)
            return false;
        const savedIndex = widgetGrid.savedIndex(index);
        const group = widgetGrid.hoverGroup !== "" ? widgetGrid.groupAt(scenePoint, index) : null;
        if (group) {
            const groupId = group.groupId;
            const before = group.savedIndexAtSlot(group.incomingSlot);
            Qt.callLater(() => {
                WidgetUtils.moveToGroup(savedIndex, groupId, before);
                widgetGrid.cancelInteraction();
            });
            return true;
        }
        Qt.callLater(() => {
            widgetModel.removeWidget(savedIndex);
            widgetGrid.cancelInteraction();
        });
        return true;
    }

    function openWidgetSheet() {
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
        if (configOverlayLoader.item?.visible) {
            configOverlayLoader.item.close();
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

    readonly property bool editMode: host.editMode

    onEditModeChanged: {
        if (editMode) {
            host.collapseAll();
            editSnapshot = editState;
            undoBase = editState;
        } else {
            panelResizer.cancel();
            editSnapshot = "";
            undoBase = "";
            widgetSheetRequested = false;
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
        anchors.topMargin: -contentInset - (editActions.joined && root.stripAbove ? editActions.height : 0)
        anchors.bottomMargin: -contentInset - (editActions.joined && !root.stripAbove ? editActions.height : 0)
        z: 1
        visible: root.host.editMode
        enabled: detailBand.shownSection === "" && !root.widgetSheetOpen
        edgeResize: root.panelResizing ? resizeSide < 0 : root.panelResizer.sideMovable(-1, root.gridColumns)
        cornerResize: root.panelResizing ? resizeSide > 0 : root.panelResizer.sideMovable(1, root.gridColumns)
        horizontalResize: true
        removable: false
        // Frame-attached corners are square, but the ring keeps the surface radius.
        cornerRadius: Math.max(root.surfaceCornerRadii.x, root.surfaceCornerRadii.y, root.surfaceCornerRadii.z, root.surfaceCornerRadii.w)
        buttonSize: Theme.iconSize
        iconSize: PopoutMetrics.chromeIconSize
        resizing: root.panelResizing
        atDefault: root.gridColumns === Math.min(CcMetrics.defaultColumns, root.gridColumnCap)
        sizeText: root.gridColumns + "×" + widgetGrid.slotLayout.rows
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
        maximumRows: widgetGrid.maximumRows
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
        contentHeight: Math.max(height, mainColumn.implicitHeight + CcMetrics.sheetPadding)
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

                CcTileGrid {
                    id: widgetGrid
                    columns: root.gridColumns
                    availableHeight: root.availableGridHeight

                    width: parent.width
                    anchors.top: parent.top
                    editMode: root.host.editMode
                    model: widgetModel
                    live: root.host.shouldBeVisible
                    expandedSection: detailBand.shownSection
                    bandHeight: detailBand.height
                    bandTargetHeight: detailBand.targetHeight
                    bandMoving: detailBand.shownSection !== ""
                    screenName: root.host.triggerScreen?.name || ""
                    tapToClose: root.host.headerTogglesClose ?? false
                    runningToplevels: root.runningToplevels
                    swallowPoint: root.overTrash ? widgetGrid.mapFromItem(editActions, editActions.width / 2, editActions.height / 2) : null
                    dragsOutside: (index, scenePoint) => root.groupTakesGridDrag(scenePoint) || root.trashTakesGridDrag(scenePoint)
                    dropHandler: (index, scenePoint) => root.dropFromGrid(index, scenePoint)
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

                CcDetailBand {
                    id: detailBand

                    x: 0
                    y: widgetGrid.bandY
                    width: parent.width
                    section: root.host.expandedSection ?? ""
                    maximumHeight: root.availableGridHeight - widgetGrid.baseHeight
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
            }
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
        editMode: root.host.editMode
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
        onResetRequested: root.batchEdit(() => widgetModel.resetToDefault())
        onClearRequested: widgetModel.clearAll()
        onFinishRequested: root.host.editMode = false
        onCancelRequested: root.cancelEdit()
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
        active: root.host.editMode
        asynchronous: true
        onLoaded: {
            if (!root.widgetSheetRequested)
                return;
            root.widgetSheetRequested = false;
            item.opened = true;
        }
        sourceComponent: CcWidgetSheet {
            scrimRadii: root.surfaceCornerRadii
            scrimVisible: root.sheetsDim
            surfaceColor: CcMetrics.dialogColor
            widgets: {
                const existingIds = root.placedWidgetIds.split(",");
                const allWidgets = widgetModel.baseWidgetDefinitions.concat(widgetModel.getPluginWidgets());
                return allWidgets.filter(w => w.allowMultiple || !existingIds.includes(w.id));
            }
            onDismissRequested: opened = false
            onChosen: widgetId => {
                widgetModel.addWidget(widgetId);
                opened = false;
            }
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
