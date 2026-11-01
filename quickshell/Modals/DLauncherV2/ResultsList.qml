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
    property bool leadingSectionHeaderAtBottom: false
    property bool showEmptyState: true
    property var _visualModel: ({
            rows: [],
            indexMap: {},
            heights: [],
            height: 0
        })
    readonly property var _visualRows: _visualModel.rows
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

    function _rebuildVisualModel() {
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
                        item: items[i],
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
                var cellHeight = mode === "tile" ? cellWidth * LauncherMetrics.tileImageRatio : cellWidth + LauncherMetrics.tileLabelHeight;
                var gridSpace = root._fitSpace - sectionBand - LauncherMetrics.fadeLength;
                if (mode === "grid" && gridSpace > 0) {
                    // Never aim below what the icon and label need
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

    onGridColumnsChanged: rebuildTimer.restart()
    onWidthChanged: rebuildTimer.restart()
    on_FitSpaceChanged: _settleHeight()
    onResizingChanged: _settleHeight()

    // Only fitted grid cells depend on height
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
        mainListView.contentY = mainListView.originY;
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
            scrollBarTopMargin: (root.controller?.sections?.length > 0) ? LauncherMetrics.sectionBand : 0

            model: ScriptModel {
                values: root._visualRows
                objectProp: "_rowId"
            }

            currentIndex: root._flatIndexToRowMap[root.controller?.selectedFlatIndex] ?? -1
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

                readonly property string rowType: modelData?.type ?? ""

                z: 1
                width: mainListView.width
                height: modelData?.height ?? LauncherMetrics.rowHeight

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
                        topLeftRadius: delegateRoot.modelData?.firstInGroup ? Theme.groupedListOuterRadius : radius
                        topRightRadius: topLeftRadius
                        bottomLeftRadius: delegateRoot.modelData?.lastInGroup ? Theme.groupedListOuterRadius : radius
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
                        section: delegateRoot.modelData?.section ?? null
                        controller: root.controller
                        viewMode: {
                            var vt = root.controller?.viewModeVersion ?? 0;
                            void (vt);
                            return root.controller?.getSectionViewMode(delegateRoot.modelData?.sectionId ?? "") ?? "list";
                        }
                        canChangeViewMode: {
                            var vt = root.controller?.viewModeVersion ?? 0;
                            void (vt);
                            return root.controller?.canChangeSectionViewMode(delegateRoot.modelData?.sectionId ?? "") ?? false;
                        }
                        canCollapse: root.controller?.canCollapseSection(delegateRoot.modelData?.sectionId ?? "") ?? false
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
                        firstInGroup: delegateRoot.modelData?.firstInGroup ?? true
                        lastInGroup: delegateRoot.modelData?.lastInGroup ?? true
                        externalHighlight: true
                        item: delegateRoot.modelData?.item ?? null
                        isSelected: (delegateRoot.modelData?.flatIndex ?? -1) === root.controller?.selectedFlatIndex
                        controller: root.controller
                        flatIndex: delegateRoot.modelData?.flatIndex ?? -1

                        onClicked: {
                            if (root.controller && delegateRoot.modelData?.item) {
                                root.controller.executeItem(delegateRoot.modelData.item);
                            }
                        }

                        onRightClicked: (mouseX, mouseY) => {
                            root.itemRightClicked(delegateRoot.modelData?.flatIndex ?? -1, delegateRoot.modelData?.item ?? null, mouseX, mouseY);
                        }
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: delegateRoot.rowType === "grid_row"
                    visible: active
                    sourceComponent: Row {
                        Repeater {
                            model: delegateRoot.modelData?.items ?? []

                            Item {
                                id: gridCellDelegate
                                required property var modelData
                                required property int index

                                readonly property bool isTile: delegateRoot.modelData?.viewMode === "tile"
                                readonly property real cellWidth: Math.floor(delegateRoot.width / (delegateRoot.modelData?.cols ?? root.gridColumns))

                                width: cellWidth
                                height: delegateRoot.height

                                Rectangle {
                                    parent: mainListView.contentItem
                                    x: gridCellDelegate.x + LauncherMetrics.tileGap / 2
                                    y: delegateRoot.y + LauncherMetrics.tileGap / 2
                                    width: gridCellDelegate.width - LauncherMetrics.tileGap
                                    height: delegateRoot.height - LauncherMetrics.tileGap
                                    z: -1
                                    visible: delegateRoot.visible
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
                                            externalHighlight: true
                                            item: gridCellDelegate.modelData?.item ?? null
                                            isSelected: (gridCellDelegate.modelData?.flatIndex ?? -1) === root.controller?.selectedFlatIndex
                                            controller: root.controller
                                            flatIndex: gridCellDelegate.modelData?.flatIndex ?? -1

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
                                            externalHighlight: true
                                            item: gridCellDelegate.modelData?.item ?? null
                                            isSelected: (gridCellDelegate.modelData?.flatIndex ?? -1) === root.controller?.selectedFlatIndex
                                            controller: root.controller
                                            flatIndex: gridCellDelegate.modelData?.flatIndex ?? -1

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
