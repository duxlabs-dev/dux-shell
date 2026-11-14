pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modals.DLauncherV2.Components

Item {
    id: root

    property var controller: null
    property var keyForwardTargets: []
    property Item focusReturnTarget: null
    property int gridColumns: controller?.gridColumns ?? 4
    readonly property int iconColumns: controller?.iconColumns ?? 0
    property bool leadingSectionHeaderAtBottom: false
    property bool showEmptyState: true
    property var _visualModel: ({
            rows: [],
            indexMap: {},
            heights: [],
            height: 0
        })
    readonly property var _visualRows: _visualModel.rows
    readonly property bool _dmenuMode: controller?.searchMode === "dmenu"
    readonly property var _flatIndexToRowMap: _visualModel.indexMap
    readonly property var _cumulativeHeights: _visualModel.heights
    property int _lastSelectedFlatIndex: -1
    property bool _selectionMotionReady: false
    property var transientSurfaceTracker: null
    readonly property bool _bottomSectionHeaderActive: leadingSectionHeaderAtBottom && (controller?.sections?.length ?? 0) > 0

    readonly property real contentHeight: _visualModel.height
    readonly property int _densityLevel: Theme.densityLevel
    readonly property int pageRows: Math.max(1, Math.floor((height - LauncherMetrics.fadeLength) / (LauncherMetrics.rowHeight + LauncherMetrics.rowGap)))
    property real availableHeight: 0
    // Set while the host animates height, so fitted cells settle once instead of every frame
    required property bool resizing
    // Content-sized hosts follow fittedHeight, so their cells fit the budget rather than the current height
    readonly property real _fitSpace: availableHeight > 0 ? availableHeight : height
    readonly property real fittedHeight: {
        const rows = _visualModel.rows;
        const starts = _visualModel.heights;
        const inset = bottomSectionHeader.visible ? bottomSectionHeader.height + LauncherMetrics.resultsGap : 0;
        const viewport = availableHeight - inset;
        if (rows.length === 0 || _visualModel.height <= viewport + 1)
            return availableHeight;
        const limit = viewport - LauncherMetrics.fadeLength;
        let fitted = 0;
        for (let i = 0; i < rows.length; i++) {
            const bottom = starts[i] + rows[i].height;
            if (bottom > limit + 1)
                break;
            fitted = bottom;
        }
        return fitted > 0 ? Math.min(viewport, fitted + LauncherMetrics.fadeLength) + inset : availableHeight;
    }

    signal itemRightClicked(int index, var item, real mouseX, real mouseY)

    readonly property FolderPopup folderPopup: folderPopupLoader.item as FolderPopup
    property LauncherTile _dragTile: null
    property var _dragItem: null
    property int _pressIndex: -1
    property int _liftedIndex: -1
    property int _pressMemberIndex: -1
    property int _liftedMemberIndex: -1
    property int _dropTargetIndex: -1
    property point _pressScene: Qt.point(0, 0)
    property point _dragPoint: Qt.point(0, 0)
    property point _dragGrab: Qt.point(0, 0)
    property size _dragSize: Qt.size(0, 0)
    property bool _dragImageTile: false
    readonly property bool _pressActive: _pressIndex >= 0 || _pressMemberIndex >= 0
    readonly property bool _dragActive: _liftedIndex >= 0 || _liftedMemberIndex >= 0

    onVisibleChanged: {
        if (!visible)
            _resetDrag();
    }

    function _armDrag(tile, sceneX, sceneY, memberIndex = -1) {
        _resetDrag();
        const item = tile?.item;
        if (!item || controller?.searchQuery)
            return;
        const folderMove = item.type === "folder" && memberIndex < 0;
        if (item.type !== "app" && !folderMove)
            return;
        if (memberIndex < 0 && tile.flatIndex < 0)
            return;
        _dragTile = tile;
        _pressIndex = memberIndex < 0 ? tile.flatIndex : -1;
        _pressMemberIndex = memberIndex;
        _pressScene = Qt.point(sceneX, sceneY);
        _dragPoint = mapFromItem(null, sceneX, sceneY);
        liftTimer.restart();
    }

    function _lift() {
        const tile = _dragTile;
        if (!tile?.item || !visible) {
            _resetDrag();
            return;
        }
        const origin = tile.mapToItem(root, 0, 0);
        _dragItem = tile.item;
        _dragImageTile = tile.imageTile;
        _dragSize = Qt.size(tile.width, tile.height);
        _dragGrab = Qt.point(_dragPoint.x - origin.x, _dragPoint.y - origin.y);
        _liftedIndex = _pressIndex;
        _liftedMemberIndex = _pressMemberIndex;
        _updateDropTarget();
    }

    function _dragMove(sceneX, sceneY) {
        if (!_pressActive)
            return;
        if (!_dragActive && Math.hypot(sceneX - _pressScene.x, sceneY - _pressScene.y) >= (_dragTile?.dragThreshold ?? 0)) {
            _resetDrag();
            return;
        }
        _dragPoint = mapFromItem(null, sceneX, sceneY);
        if (!_dragActive)
            return;
        if (_liftedMemberIndex < 0) {
            _updateDropTarget();
            return;
        }
        const popup = root.folderPopup;
        if (popup)
            popup.memberDragOutside = !popup.surfaceContains(sceneX, sceneY);
    }

    function _dragRelease(sceneX, sceneY) {
        if (!_dragActive) {
            _resetDrag();
            return;
        }
        _dragPoint = mapFromItem(null, sceneX, sceneY);
        const source = _dragItem;
        if (_liftedMemberIndex >= 0) {
            _releaseFromFolder(source.id, sceneX, sceneY);
            return;
        }
        const hit = _hitTest(_dragPoint);
        const target = _dropTargetFor(hit);
        _resetDrag();
        // The drop destroys its releasing delegate; defer until the handler returns.
        if (target)
            Qt.callLater(root._dropOn, hit.entry, source);
    }

    function _releaseFromFolder(sourceId, sceneX, sceneY) {
        const popup = root.folderPopup;
        const folderId = controllerActiveFolderId;
        _resetDrag();
        if (!popup || !folderId)
            return;
        if (!popup.surfaceContains(sceneX, sceneY)) {
            Qt.callLater(root._dropOutOfFolder, sourceId);
            return;
        }
        const targetId = popup.members[popup.memberIndexAt(sceneX, sceneY)]?.id ?? "";
        if (targetId && targetId !== sourceId)
            Qt.callLater(root._reorderInFolder, folderId, sourceId, targetId);
    }

    function _resetDrag() {
        if (!_pressActive)
            return;
        liftTimer.stop();
        if (root.folderPopup)
            root.folderPopup.memberDragOutside = false;
        _liftedIndex = -1;
        _liftedMemberIndex = -1;
        _dropTargetIndex = -1;
        _pressIndex = -1;
        _pressMemberIndex = -1;
        _dragTile = null;
        _dragItem = null;
    }

    function _hitTest(point) {
        if (!listClip.contains(listClip.mapFromItem(root, point.x, point.y)))
            return null;
        const contentPoint = mainListView.contentItem.mapFromItem(root, point.x, point.y);
        const row = _visualRows[mainListView.indexAt(contentPoint.x, contentPoint.y)];
        if (row?.type !== "grid_row")
            return null;
        const cellWidth = Math.floor(mainListView.width / row.cols);
        const listX = mainListView.mapFromItem(root, point.x, point.y).x;
        const column = Math.floor((I18n.isRtl ? mainListView.width - listX : listX) / cellWidth);
        return {
            entry: row.items[column] ?? null,
            sectionId: row.sectionId
        };
    }

    function _dropTargetFor(hit) {
        const target = hit?.entry?.item;
        if (!target || target.id === _dragItem?.id)
            return null;
        if (_dragItem?.type === "folder")
            return hit.sectionId === "apps" ? target : null;
        if (target.type === "folder" || target.type === "app")
            return target;
        return null;
    }

    function _updateDropTarget() {
        if (_liftedMemberIndex >= 0)
            return;
        const hit = _hitTest(_dragPoint);
        _dropTargetIndex = _dropTargetFor(hit) ? hit.entry.flatIndex : -1;
    }

    function _dropOn(targetEntry, source) {
        const target = targetEntry.item;
        if (source.type === "folder") {
            controller?.moveLauncherFolder(source.data.folderId, targetEntry.flatIndex);
            return;
        }
        if (target.type === "folder") {
            SessionData.addAppToLauncherFolder(target.data.folderId, source.id);
            return;
        }
        controller?.createFolderWith([target.id, source.id]);
    }

    function _dropOutOfFolder(sourceId) {
        SessionData.removeAppFromLauncherFolder(sourceId);
    }

    // Uninstalled members make popup indices differ from stored app indices.
    function _reorderInFolder(folderId, sourceId, targetId) {
        const apps = SessionData.getLauncherFolder(folderId)?.apps ?? [];
        const from = apps.indexOf(sourceId);
        const to = apps.indexOf(targetId);
        if (from < 0 || to < 0)
            return;
        SessionData.moveAppInLauncherFolder(folderId, from, to);
    }

    Timer {
        id: liftTimer
        interval: LauncherMetrics.liftDelay
        onTriggered: root._lift()
    }

    readonly property int _dragScrollDirection: {
        if (_liftedIndex < 0)
            return 0;
        const y = _dragPoint.y - listClip.y;
        if (y < Theme.spacingXL)
            return -1;
        if (y > listClip.height - Theme.spacingXL)
            return 1;
        return 0;
    }

    Timer {
        id: dragScrollTimer
        interval: LauncherMetrics.dragScrollInterval
        repeat: true
        running: root._dragScrollDirection !== 0
        onTriggered: {
            const next = mainListView.contentY + root._dragScrollDirection * Theme.spacingL;
            mainListView.contentY = Math.max(mainListView.originY, Math.min(mainListView.maximumContentY, next));
            root._updateDropTarget();
        }
    }

    function _rebuildVisualModel() {
        root._resetDrag();
        root._selectionMotionReady = false;
        var sections = root.controller?.sections ?? [];
        var rows = [];
        var indexMap = {};
        var cumHeights = [];
        var cumY = 0;
        var hasGrid = false;
        const rowHeight = LauncherMetrics.rowHeight + LauncherMetrics.rowGap;
        const sectionBand = LauncherMetrics.sectionBand;
        const sectionGap = LauncherMetrics.resultsGap;

        for (var s = 0; s < sections.length; s++) {
            var section = sections[s];
            var sectionId = section.id;

            var isDmenuSection = sectionId === "dmenu" || sectionId.indexOf("dmenu:") === 0;
            var showsHeader = !isDmenuSection || (section.title && section.title.length > 0);
            if (showsHeader && (!root._bottomSectionHeaderActive || s > 0)) {
                if (rows.length > 0) {
                    cumHeights.push(cumY);
                    rows.push({
                        _rowId: "sp_" + sectionId,
                        type: "spacer",
                        height: sectionGap
                    });
                    cumY += sectionGap;
                }
                cumHeights.push(cumY);
                rows.push({
                    _rowId: "h_" + sectionId,
                    type: "header",
                    section: section,
                    sectionId: sectionId,
                    height: sectionBand
                });
                cumY += sectionBand;
            }

            if (section.collapsed)
                continue;

            var versionTrigger = root.controller?.viewModeVersion ?? 0;
            void (versionTrigger);
            var mode = root.controller?.getSectionViewMode(sectionId) ?? "list";
            var items = section.items ?? [];
            var flatStartIndex = section.flatStartIndex ?? 0;

            if (mode === "list") {
                for (var i = 0; i < items.length; i++) {
                    var flatIdx = flatStartIndex + i;
                    indexMap[flatIdx] = rows.length;
                    cumHeights.push(cumY);
                    var rowId = items[i].id;
                    if (items[i].type === "dmenu") {
                        var d = items[i].data;
                        rowId += ":" + (d.checked ? 1 : 0) + (d.active ? 1 : 0) + (d.urgent ? 1 : 0);
                    }
                    rows.push({
                        _rowId: rowId,
                        type: "list_item",
                        item: isDmenuSection ? Object.assign({}, items[i]) : items[i],
                        flatIndex: flatIdx,
                        sectionId: sectionId,
                        firstInGroup: i === 0,
                        lastInGroup: i === items.length - 1,
                        height: rowHeight
                    });
                    cumY += rowHeight;
                }
            } else {
                hasGrid = hasGrid || mode === "grid";
                var cols = root.controller?.getGridColumns(sectionId) ?? root.gridColumns;
                var cellWidth = Math.floor(root.width / cols);
                var cellHeight = mode === "tile" ? cellWidth * LauncherMetrics.tileImageRatio : mode === "icons" ? LauncherMetrics.iconsCellHeight : cellWidth + LauncherMetrics.tileLabelHeight;
                var gridSpace = root._fitSpace - sectionBand - LauncherMetrics.fadeLength;
                if (mode === "grid" && gridSpace > 0) {
                    var target = Math.max(cellHeight * LauncherMetrics.gridDensityScale, Math.min(cellHeight, LauncherMetrics.tileMinHeight));
                    cellHeight = gridSpace / Math.max(1, Math.round(gridSpace / target));
                }
                var numRows = Math.ceil(items.length / cols);

                for (var r = 0; r < numRows; r++) {
                    var rowItems = [];
                    for (var c = 0; c < cols; c++) {
                        var idx = r * cols + c;
                        if (idx >= items.length)
                            break;
                        var fi = flatStartIndex + idx;
                        indexMap[fi] = rows.length;
                        rowItems.push({
                            item: items[idx],
                            flatIndex: fi
                        });
                    }
                    cumHeights.push(cumY);
                    rows.push({
                        _rowId: "gr_" + sectionId + "_" + r,
                        type: "grid_row",
                        items: rowItems,
                        sectionId: sectionId,
                        viewMode: mode,
                        cols: cols,
                        height: cellHeight
                    });
                    cumY += cellHeight;
                }
            }
        }

        root._visualModel = {
            rows: rows,
            indexMap: indexMap,
            heights: cumHeights,
            height: cumY,
            hasGrid: hasGrid
        };
    }

    property string _pendingSectionId: ""

    Timer {
        id: rebuildTimer
        interval: 0
        onTriggered: {
            root._rebuildVisualModel();
            selectionTimer.restart();
        }
    }

    Timer {
        id: selectionTimer
        interval: 0
        onTriggered: {
            if (root._pendingSectionId) {
                root.revealExpandedSection(root._pendingSectionId);
                root._pendingSectionId = "";
                return;
            }
            if (root.controller?.keyboardNavigationActive)
                root.ensureVisible(root.controller.selectedFlatIndex);
        }
    }

    on_DragTileChanged: {
        if (!_dragTile && (_pressIndex >= 0 || _pressMemberIndex >= 0))
            _resetDrag();
    }
    onIconColumnsChanged: rebuildTimer.restart()
    onGridColumnsChanged: rebuildTimer.restart()
    onWidthChanged: rebuildTimer.restart()
    on_FitSpaceChanged: _settleHeight()
    onResizingChanged: _settleHeight()

    function _settleHeight() {
        if (resizing)
            return;
        if (_visualModel.hasGrid)
            rebuildTimer.restart();
        else
            selectionTimer.restart();
    }
    onLeadingSectionHeaderAtBottomChanged: rebuildTimer.restart()
    // ScriptModel keeps rows whose _rowId matches, so their stale heights must be dropped first
    on_DensityLevelChanged: {
        root._visualModel = {
            rows: [],
            indexMap: {},
            heights: [],
            height: 0
        };
        rebuildTimer.restart();
    }

    Connections {
        target: root.controller
        function onSectionsChanged() {
            rebuildTimer.restart();
        }
        function onViewModeVersionChanged() {
            rebuildTimer.restart();
        }
        function onSearchModeChanged() {
            root._resetDrag();
            root._visualModel = {
                rows: [],
                indexMap: {},
                heights: [],
                height: 0
            };
        }
        function onSectionExpanded(sectionId) {
            root._pendingSectionId = sectionId;
            rebuildTimer.restart();
        }
    }

    function resetScroll() {
        root._selectionMotionReady = false;
        root._lastSelectedFlatIndex = root.controller?.selectedFlatIndex ?? -1;
        mainListView.resetScroll();
    }

    function revealExpandedSection(sectionId) {
        for (var i = 0; i < _visualRows.length; i++) {
            if (_visualRows[i].sectionId === sectionId) {
                mainListView.positionViewAtIndex(i, ListView.Beginning);
                return;
            }
        }
    }

    function ensureVisible(index) {
        if (index < 0 || !controller?.flatModel || index >= controller.flatModel.length)
            return;
        var entry = controller.flatModel[index];
        if (!entry || entry.isHeader)
            return;
        var rowIndex = _flatIndexToRowMap[index];
        if (rowIndex === undefined)
            return;

        mainListView.revealIndex(rowIndex);
    }

    function getSelectedItemPosition() {
        var fallback = mapToItem(null, width / 2, height / 2);
        if (controllerActiveFolderId.length > 0)
            return root.folderPopup?.selectedCellScenePosition() ?? fallback;
        if (!controller?.flatModel || controller.selectedFlatIndex < 0)
            return fallback;

        var entry = controller.flatModel[controller.selectedFlatIndex];
        if (!entry || entry.isHeader)
            return fallback;

        var rowIndex = _flatIndexToRowMap[controller.selectedFlatIndex];
        if (rowIndex === undefined)
            return fallback;

        var rowY = (rowIndex < _cumulativeHeights.length) ? _cumulativeHeights[rowIndex] : 0;
        var row = _visualRows[rowIndex];
        if (!row)
            return fallback;

        var itemX = width / 2;
        var itemH = row.height;

        if (row.type === "grid_row") {
            var rowItems = row.items;
            for (var i = 0; i < rowItems.length; i++) {
                if (rowItems[i].flatIndex === controller.selectedFlatIndex) {
                    var cellWidth = Math.floor(width / row.cols);
                    itemX = (I18n.isRtl ? width - (i + 1) * cellWidth : i * cellWidth) + cellWidth / 2;
                    break;
                }
            }
        }

        var visualY = rowY - mainListView.contentY + mainListView.originY + itemH / 2;
        var clampedY = Math.max(LauncherMetrics.sectionBand, Math.min(height - LauncherMetrics.sectionBand, visualY));
        return mapToItem(null, itemX, clampedY);
    }

    readonly property int controllerSelectedFlatIndex: root.controller?.selectedFlatIndex ?? -1
    readonly property string controllerActiveFolderId: root.controller?.activeFolderId ?? ""
    property bool _folderPopupShown: false

    onControllerActiveFolderIdChanged: {
        if (controllerActiveFolderId.length > 0) {
            _folderPopupShown = true;
            return;
        }
        _resetDrag();
        if (!root.folderPopup?.close())
            _folderPopupShown = false;
    }

    function _hideFolderPopup() {
        if (controllerActiveFolderId.length === 0)
            _folderPopupShown = false;
    }

    Connections {
        target: root.controller
        ignoreUnknownSignals: true
        function onFolderOpened(folderId) {
            root.folderPopup?.open(folderId);
        }
    }

    function cellSceneRect(flatIndex, itemId) {
        const rowIndex = _flatIndexToRowMap[flatIndex];
        const row = _visualRows[rowIndex];
        const delegate = rowIndex === undefined ? null : mainListView.itemAtIndex(rowIndex);
        if (!row || !delegate)
            return null;
        let x = 0;
        let inset = 0;
        let width = mainListView.width;
        let height = row.height - LauncherMetrics.rowGap;
        if (row.type === "grid_row") {
            const column = row.items.findIndex(entry => entry.flatIndex === flatIndex);
            if (column < 0 || row.items[column].item?.id !== itemId)
                return null;
            const cellWidth = Math.floor(mainListView.width / row.cols);
            inset = LauncherMetrics.tileGap / 2;
            x = (I18n.isRtl ? mainListView.width - (column + 1) * cellWidth : column * cellWidth) + inset;
            width = cellWidth - LauncherMetrics.tileGap;
            height = row.height - LauncherMetrics.tileGap;
        } else if (row.type !== "list_item" || row.item?.id !== itemId) {
            return null;
        }
        const clipTop = delegate.mapToItem(listClip, x, inset).y;
        if (clipTop + height <= 0 || clipTop >= listClip.height)
            return null;
        const scene = delegate.mapToItem(null, x, inset);
        return {
            x: scene.x,
            y: scene.y,
            width: width,
            height: height
        };
    }

    onControllerSelectedFlatIndexChanged: {
        const previousRow = _visualModel.rows[_visualModel.indexMap[_lastSelectedFlatIndex]];
        const nextIndex = controllerSelectedFlatIndex;
        const nextRow = _visualModel.rows[_visualModel.indexMap[nextIndex]];
        _selectionMotionReady = previousRow !== undefined && nextRow !== undefined;
        _lastSelectedFlatIndex = nextIndex;
        if (controller?.keyboardNavigationActive) {
            selectionTimer.restart();
        }
    }

    Item {
        id: listClip
        anchors.fill: parent
        anchors.topMargin: stickyHeader.visible ? LauncherMetrics.sectionBand : 0
        anchors.bottomMargin: bottomSectionHeader.visible ? bottomSectionHeader.height + LauncherMetrics.resultsGap : 0
        clip: true

        DListView {
            id: mainListView
            y: -listClip.anchors.topMargin
            width: parent.width
            height: parent.height + listClip.anchors.topMargin
            fadeTopInset: listClip.anchors.topMargin
            fadeLength: LauncherMetrics.fadeLength
            clip: true
            interactive: !root._dragActive
            scrollBarTopMargin: (root.controller?.sections?.length > 0) ? LauncherMetrics.sectionBand : 0

            // Dmenu can contain thousands of rows; diffing their identities is quadratic.
            model: root._dmenuMode ? root._visualRows.length : rowModel

            ScriptModel {
                id: rowModel
                values: root._dmenuMode ? [] : root._visualRows
                objectProp: "_rowId"
            }

            // Keep the drag's mouse grab alive by retaining only its row.
            currentIndex: root._flatIndexToRowMap[root._liftedIndex >= 0 ? root._liftedIndex : root.controller?.selectedFlatIndex] ?? -1
            highlightFollowsCurrentItem: false
            highlight: LauncherHighlight {
                animate: root._selectionMotionReady
                readonly property var row: root._visualRows[mainListView.currentIndex]
                readonly property bool gridRow: row?.type === "grid_row"
                firstInGroup: gridRow || (row?.firstInGroup ?? true)
                lastInGroup: gridRow || (row?.lastInGroup ?? true)
                readonly property real cellWidth: gridRow ? Math.floor(mainListView.width / row.cols) : mainListView.width
                readonly property int column: gridRow ? row.items.findIndex(entry => entry.flatIndex === root.controller?.selectedFlatIndex) : 0
                x: gridRow ? (I18n.isRtl ? mainListView.width - (column + 1) * cellWidth : column * cellWidth) + LauncherMetrics.tileGap / 2 : 0
                y: (mainListView.currentItem?.y ?? 0) + (gridRow ? LauncherMetrics.tileGap / 2 : 0)
                width: cellWidth - (gridRow ? LauncherMetrics.tileGap : 0)
                height: Math.max(0, (row?.height ?? 0) - (gridRow ? LauncherMetrics.tileGap : LauncherMetrics.rowGap))
                visible: row?.type === "list_item" || gridRow && column >= 0
            }

            delegate: Item {
                id: delegateRoot
                required property var modelData
                required property int index

                readonly property var rowData: root._dmenuMode ? root._visualRows[index] : modelData
                readonly property string rowType: rowData?.type ?? ""

                z: 1
                // An integer model never arms DListView's orphan sweep, so hide released delegates here.
                visible: index >= 0
                width: mainListView.width
                height: rowData?.height ?? LauncherMetrics.rowHeight

                Component.onCompleted: mainListView.fadeIn(delegateRoot, index)

                Loader {
                    active: delegateRoot.rowType === "list_item"
                    sourceComponent: Rectangle {
                        parent: mainListView.contentItem
                        x: delegateRoot.x
                        y: delegateRoot.y
                        width: delegateRoot.width
                        height: delegateRoot.height - LauncherMetrics.rowGap
                        z: -1
                        visible: delegateRoot.visible
                        opacity: delegateRoot.opacity
                        color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
                        border.width: Theme.layerOutlineWidth
                        border.color: Theme.outlineMedium
                        radius: Theme.groupedListInnerRadius
                        topLeftRadius: delegateRoot.rowData?.firstInGroup ? Theme.groupedListOuterRadius : radius
                        topRightRadius: topLeftRadius
                        bottomLeftRadius: delegateRoot.rowData?.lastInGroup ? Theme.groupedListOuterRadius : radius
                        bottomRightRadius: bottomLeftRadius
                    }
                }

                Loader {
                    anchors.fill: parent
                    anchors.bottomMargin: LauncherMetrics.resultsGap
                    active: delegateRoot.rowType === "header"
                    visible: active
                    sourceComponent: SectionHeader {
                        focusReturnTarget: root.focusReturnTarget
                        section: delegateRoot.rowData?.section ?? null
                        controller: root.controller
                        viewMode: {
                            var vt = root.controller?.viewModeVersion ?? 0;
                            void (vt);
                            return root.controller?.getSectionViewMode(delegateRoot.rowData?.sectionId ?? "") ?? "list";
                        }
                        canChangeViewMode: {
                            var vt = root.controller?.viewModeVersion ?? 0;
                            void (vt);
                            return root.controller?.canChangeSectionViewMode(delegateRoot.rowData?.sectionId ?? "") ?? false;
                        }
                        canCollapse: root.controller?.canCollapseSection(delegateRoot.rowData?.sectionId ?? "") ?? false
                        transientSurfaceTracker: root.transientSurfaceTracker
                    }
                }

                Loader {
                    anchors.fill: parent
                    anchors.topMargin: 0
                    anchors.bottomMargin: LauncherMetrics.rowGap
                    active: delegateRoot.rowType === "list_item"
                    visible: active
                    sourceComponent: LauncherRow {
                        keyForwardTargets: root.keyForwardTargets
                        firstInGroup: delegateRoot.rowData?.firstInGroup ?? true
                        lastInGroup: delegateRoot.rowData?.lastInGroup ?? true
                        externalHighlight: true
                        item: delegateRoot.rowData?.item ?? null
                        isSelected: (delegateRoot.rowData?.flatIndex ?? -1) === root.controller?.selectedFlatIndex
                        controller: root.controller
                        flatIndex: delegateRoot.rowData?.flatIndex ?? -1

                        onClicked: {
                            if (root.controller && delegateRoot.rowData?.item) {
                                root.controller.executeItem(delegateRoot.rowData.item);
                            }
                        }

                        onRightClicked: (mouseX, mouseY) => {
                            root.itemRightClicked(delegateRoot.rowData?.flatIndex ?? -1, delegateRoot.rowData?.item ?? null, mouseX, mouseY);
                        }
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: delegateRoot.rowType === "grid_row"
                    visible: active
                    sourceComponent: Row {
                        Repeater {
                            model: delegateRoot.rowData?.items ?? []

                            Item {
                                id: gridCellDelegate
                                required property var modelData
                                required property int index

                                readonly property bool isTile: delegateRoot.rowData?.viewMode === "tile"
                                readonly property bool isBare: delegateRoot.rowData?.viewMode === "icons"
                                readonly property real cellWidth: Math.floor(delegateRoot.width / (delegateRoot.rowData?.cols ?? root.gridColumns))

                                width: cellWidth
                                height: delegateRoot.height

                                Rectangle {
                                    parent: mainListView.contentItem
                                    x: gridCellDelegate.x + LauncherMetrics.tileGap / 2
                                    y: delegateRoot.y + LauncherMetrics.tileGap / 2
                                    width: gridCellDelegate.width - LauncherMetrics.tileGap
                                    height: delegateRoot.height - LauncherMetrics.tileGap
                                    z: -1
                                    visible: delegateRoot.visible && !gridCellDelegate.isBare
                                    opacity: delegateRoot.opacity
                                    color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
                                    border.width: Theme.layerOutlineWidth
                                    border.color: Theme.outlineMedium
                                    radius: Theme.cornerRadiusL
                                }

                                Loader {
                                    width: parent.width - LauncherMetrics.tileGap
                                    height: parent.height - LauncherMetrics.tileGap
                                    anchors.centerIn: parent
                                    sourceComponent: gridCellDelegate.isTile ? tileCellComponent : gridCellComponent

                                    Component {
                                        id: gridCellComponent

                                        LauncherTile {
                                            id: gridTile
                                            externalHighlight: true
                                            bare: gridCellDelegate.isBare
                                            item: gridCellDelegate.modelData?.item ?? null
                                            isSelected: (gridCellDelegate.modelData?.flatIndex ?? -1) === root.controller?.selectedFlatIndex
                                            controller: root.controller
                                            flatIndex: gridCellDelegate.modelData?.flatIndex ?? -1
                                            dragSource: root._liftedIndex >= 0 && gridTile.flatIndex === root._liftedIndex
                                            receiving: root._dropTargetIndex >= 0 && gridTile.flatIndex === root._dropTargetIndex

                                            onDragPressed: (sceneX, sceneY) => root._armDrag(gridTile, sceneX, sceneY)
                                            onDragMoved: (sceneX, sceneY) => root._dragMove(sceneX, sceneY)
                                            onDragReleased: (sceneX, sceneY) => root._dragRelease(sceneX, sceneY)
                                            onDragCanceled: root._resetDrag()

                                            onClicked: {
                                                if (root.controller && gridCellDelegate.modelData?.item) {
                                                    root.controller.executeItem(gridCellDelegate.modelData.item);
                                                }
                                            }

                                            onRightClicked: (mouseX, mouseY) => {
                                                root.itemRightClicked(gridCellDelegate.modelData?.flatIndex ?? -1, gridCellDelegate.modelData?.item ?? null, mouseX, mouseY);
                                            }
                                        }
                                    }

                                    Component {
                                        id: tileCellComponent

                                        TileItem {
                                            id: imageTileItem
                                            externalHighlight: true
                                            item: gridCellDelegate.modelData?.item ?? null
                                            isSelected: (gridCellDelegate.modelData?.flatIndex ?? -1) === root.controller?.selectedFlatIndex
                                            controller: root.controller
                                            flatIndex: gridCellDelegate.modelData?.flatIndex ?? -1
                                            dragSource: root._liftedIndex >= 0 && imageTileItem.flatIndex === root._liftedIndex
                                            receiving: root._dropTargetIndex >= 0 && imageTileItem.flatIndex === root._dropTargetIndex

                                            onDragPressed: (sceneX, sceneY) => root._armDrag(imageTileItem, sceneX, sceneY)
                                            onDragMoved: (sceneX, sceneY) => root._dragMove(sceneX, sceneY)
                                            onDragReleased: (sceneX, sceneY) => root._dragRelease(sceneX, sceneY)
                                            onDragCanceled: root._resetDrag()

                                            onClicked: {
                                                if (root.controller && gridCellDelegate.modelData?.item) {
                                                    root.controller.executeItem(gridCellDelegate.modelData.item);
                                                }
                                            }

                                            onRightClicked: (mouseX, mouseY) => {
                                                root.itemRightClicked(gridCellDelegate.modelData?.flatIndex ?? -1, gridCellDelegate.modelData?.item ?? null, mouseX, mouseY);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: stickyHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: LauncherMetrics.sectionBand
        z: 101
        color: "transparent"
        visible: !root._bottomSectionHeaderActive && stickyHeaderSection !== null

        readonly property int versionTrigger: root.controller?.viewModeVersion ?? 0

        readonly property var stickyHeaderSection: {
            var scrollY = mainListView.contentY - mainListView.originY;
            if (scrollY <= 0)
                return null;

            var rows = root._visualModel.rows;
            var heights = root._visualModel.heights;
            if (rows.length === 0 || heights.length === 0)
                return null;

            var lo = 0;
            var hi = rows.length - 1;
            while (lo < hi) {
                var mid = (lo + hi + 1) >> 1;
                if (mid < heights.length && heights[mid] <= scrollY)
                    lo = mid;
                else
                    hi = mid - 1;
            }

            for (var i = lo; i >= 0; i--) {
                if (rows[i].type === "header")
                    return rows[i].section;
            }
            return null;
        }

        SectionHeader {
            focusReturnTarget: root.focusReturnTarget
            width: parent.width
            section: stickyHeader.stickyHeaderSection
            controller: root.controller
            viewMode: {
                void (stickyHeader.versionTrigger);
                return root.controller?.getSectionViewMode(stickyHeader.stickyHeaderSection?.id) ?? "list";
            }
            canChangeViewMode: {
                void (stickyHeader.versionTrigger);
                return root.controller?.canChangeSectionViewMode(stickyHeader.stickyHeaderSection?.id) ?? false;
            }
            canCollapse: {
                void (stickyHeader.versionTrigger);
                return root.controller?.canCollapseSection(stickyHeader.stickyHeaderSection?.id) ?? false;
            }
            transientSurfaceTracker: root.transientSurfaceTracker
        }
    }

    SectionHeader {
        id: bottomSectionHeader
        focusReturnTarget: root.focusReturnTarget
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 101
        visible: root._bottomSectionHeaderActive
        section: visible ? root.controller.sections[0] : null
        controller: root.controller
        viewMode: {
            var vt = root.controller?.viewModeVersion ?? 0;
            void (vt);
            return root.controller?.getSectionViewMode(section?.id ?? "") ?? "list";
        }
        canChangeViewMode: {
            var vt = root.controller?.viewModeVersion ?? 0;
            void (vt);
            return root.controller?.canChangeSectionViewMode(section?.id ?? "") ?? false;
        }
        canCollapse: root.controller?.canCollapseSection(section?.id ?? "") ?? false
        popupAbove: true
        transientSurfaceTracker: root.transientSurfaceTracker
    }

    Loader {
        id: folderPopupLoader
        anchors.fill: parent
        z: 102
        active: root._folderPopupShown
        sourceComponent: FolderPopup {
            controller: root.controller
            host: root
            focusReturnTarget: root.focusReturnTarget
            animationsEnabled: root.visible && (root.controller?.active ?? false)
            liftedMemberIndex: root._liftedMemberIndex
            dragActive: root._dragActive
            onDismissed: Qt.callLater(root._hideFolderPopup)
            onMemberRightClicked: (item, sceneX, sceneY) => root.itemRightClicked(-1, item, sceneX, sceneY)
            onMemberDragPressed: (tile, memberIndex, sceneX, sceneY) => root._armDrag(tile, sceneX, sceneY, memberIndex)
            onMemberDragMoved: (sceneX, sceneY) => root._dragMove(sceneX, sceneY)
            onMemberDragReleased: (sceneX, sceneY) => root._dragRelease(sceneX, sceneY)
            onMemberDragCanceled: root._resetDrag()
        }
    }

    Item {
        id: dragLayer
        anchors.fill: parent
        z: 102

        WheelHandler {
            enabled: root._pressActive
            onWheel: root._resetDrag()
        }

        Shortcut {
            sequence: "Escape"
            enabled: root._dragActive
            context: Qt.WindowShortcut
            onActivated: root._resetDrag()
        }

        Loader {
            active: root._dragActive
            x: root._dragPoint.x - root._dragGrab.x
            y: root._dragPoint.y - root._dragGrab.y
            width: root._dragSize.width
            height: root._dragSize.height
            sourceComponent: Item {
                NumberAnimation on scale {
                    from: 1
                    to: LauncherMetrics.dragLiftScale
                    duration: SettingsData.reduceMotion ? 0 : Theme.expressiveDurations.expressiveFastSpatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                }

                Loader {
                    anchors.fill: parent
                    active: Theme.elevationEnabled
                    sourceComponent: ElevationShadow {
                        level: Theme.elevationLevel3
                        targetColor: Theme.chipSurface
                        targetRadius: Theme.cornerRadiusL
                    }
                }

                Loader {
                    anchors.fill: parent
                    sourceComponent: root._dragImageTile ? ghostImageTile : ghostGridTile
                }

                Component {
                    id: ghostGridTile

                    LauncherTile {
                        enabled: false
                        item: root._dragItem
                        color: Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root))
                    }
                }

                Component {
                    id: ghostImageTile

                    TileItem {
                        enabled: false
                        item: root._dragItem
                        color: Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root))
                    }
                }
            }
        }
    }

    Item {
        anchors.centerIn: parent
        visible: root.showEmptyState && (!root.controller?.sections || root.controller.sections.length === 0) && !root.controller?.isFileSearching
        width: emptyColumn.implicitWidth
        height: emptyColumn.implicitHeight

        Column {
            id: emptyColumn
            spacing: Theme.spacingM

            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: getEmptyIcon()
                size: LauncherMetrics.gridIconSize
                color: Theme.outlineButton

                function getEmptyIcon() {
                    if (root.controller?.activePluginId)
                        return root.controller.getPluginMetadata(root.controller.activePluginId).icon;
                    var mode = root.controller?.searchMode ?? "all";
                    switch (mode) {
                    case "files":
                        var fileType = root.controller?.fileSearchType ?? "all";
                        switch (fileType) {
                        case "dir":
                            return "folder_open";
                        case "file":
                            return "insert_drive_file";
                        default:
                            return "folder_open";
                        }
                    case "plugins":
                        return "extension";
                    case "apps":
                        return "apps";
                    default:
                        return "search_off";
                    }
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: getEmptyText()
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.onSurfaceVariant
                horizontalAlignment: Text.AlignHCenter

                function getEmptyText() {
                    if (root.controller?.activePluginName)
                        return I18n.tr("No results found");
                    var mode = root.controller?.searchMode ?? "all";
                    var hasQuery = root.controller?.searchQuery?.length > 0;

                    switch (mode) {
                    case "files":
                        if (!DSearchService.dsearchAvailable)
                            return I18n.tr("File search requires %1\nInstall from %2", "launcher file search empty state, %1 is the dsearch binary, %2 is its repository").arg("dsearch").arg("github.com/duxlabs-dev/dux-search");
                        if (!hasQuery)
                            return I18n.tr("Type to search files");
                        if (root.controller.searchQuery.length < 2)
                            return I18n.tr("Type at least 2 characters");
                        var fileType = root.controller?.fileSearchType ?? "all";
                        switch (fileType) {
                        case "dir":
                            return I18n.tr("No folders found");
                        case "file":
                            return I18n.tr("No files found");
                        default:
                            return I18n.tr("No results found");
                        }
                    case "plugins":
                        return hasQuery ? I18n.tr("No plugin results") : I18n.tr("Browse or search plugins");
                    case "apps":
                        return I18n.tr("No apps found");
                    default:
                        return I18n.tr("No results found");
                    }
                }
            }
        }
    }
}
