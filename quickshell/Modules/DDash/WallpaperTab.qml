import Qt.labs.folderlistmodel
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Modals.FileBrowser
import qs.DCommon.FileBrowser as FB
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.ControlCenter.Widgets
import qs.Modules.DDash
import "../../DCommon/Common/FocusNavigation.js" as FocusNavigation
import "../../Common/WallpaperFormats.js" as WallpaperFormats

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    implicitWidth: DashMetrics.contentWidthFor(SettingsData.showWeekNumber, DashMetrics.panelColumnsFor(entryId))
    implicitHeight: DashMetrics.tabMinHeight

    property string wallpaperDir: ""
    readonly property string searchQuery: wallpaperSearchField.text
    property var filteredWallpaperPaths: []
    property int currentPage: 0
    property string entryId: "wallpaper"
    readonly property var options: DashRegistry.resolvedOptions(entryId)
    readonly property bool carousel: options.layout === "carousel"
    readonly property int columns: Math.max(DashMetrics.wallpaperColumnsMin, Math.min(DashMetrics.wallpaperColumnsMax, Number(options.columns) || DashMetrics.wallpaperColumnsMin))
    readonly property int rows: Math.max(DashMetrics.wallpaperRowsMin, Math.min(DashMetrics.wallpaperRowsMax, Number(options.rows) || DashMetrics.wallpaperRowsMin))
    readonly property int itemsPerPage: columns * rows
    readonly property int flatIndex: currentPage * itemsPerPage + gridIndex
    readonly property int wallpaperCount: filteredWallpaperPaths.length
    property int totalPages: Math.max(1, Math.ceil(wallpaperCount / itemsPerPage))
    property bool active: false
    property bool searchExpanded: false
    readonly property Item focusTarget: wallpaperView
    readonly property var focusTargets: [wallpaperView, previousPageButton, pageButton, nextPageButton, sortButton, folderButton, searchExpanded ? wallpaperSearchField : searchToggleButton, collapseSearchButton]
    readonly property Item previousFocusTarget: searchExpanded ? collapseSearchButton : searchToggleButton
    readonly property bool blocksTabNavigation: sortMenu.menuVisible || pageJumpPopup.visible || !!wallpaperBrowserLoader.item?.shouldBeVisible
    property int gridIndex: 0
    property Item keyForwardTarget: null
    property var parentPopout: null
    property var transientSurfaceTracker: null
    property bool enableAnimation: false
    property string selectedFileName: ""
    property var targetScreen: null
    property string targetScreenName: targetScreen ? targetScreen.name : ""
    readonly property var wallpaperBrowserSettings: FB.FileBrowserSettings.load("wallpaper")
    readonly property string sortKey: wallpaperBrowserSettings.sortKey
    readonly property bool sortDescending: wallpaperBrowserSettings.sortDesc
    readonly property var sortKeys: ["name", "size", "mtime", "type"]
    readonly property var sortOptions: [I18n.tr("Name"), I18n.tr("Size"), I18n.tr("Modified"), I18n.tr("Type")]
    property int gridRevision: 0
    property int pagerCachePages: 1

    function cycleFocus(backwards) {
        return FocusNavigation.moveFocus(focusTargets, backwards);
    }

    function refreshAfterSort() {
        // Defer until FolderListModel finishes reordering.
        Qt.callLater(() => {
            rebuildWallpaperList(true);
        });
    }

    function cleanFilePath(path) {
        return path ? path.toString().replace(/^file:\/\//, '') : "";
    }

    function wallpaperPathAt(index) {
        if (index < 0 || index >= wallpaperCount)
            return "";
        return filteredWallpaperPaths[index] || "";
    }

    function pageItemCount(page) {
        return Math.max(0, Math.min(itemsPerPage, wallpaperCount - page * itemsPerPage));
    }

    function searchTerms() {
        const query = searchQuery.trim().toLowerCase();
        return query ? query.split(/\s+/).filter(t => t.length > 0) : [];
    }

    function matchesTerms(terms, fileName, filePath) {
        if (terms.length === 0)
            return true;

        const haystack = (fileName + " " + filePath).toLowerCase();
        for (let i = 0; i < terms.length; i++) {
            if (haystack.indexOf(terms[i]) === -1)
                return false;
        }
        return true;
    }

    function rebuildWallpaperList(preferCurrentWallpaper) {
        const paths = [];
        if (wallpaperFolderModel.status === FolderListModel.Ready) {
            const terms = searchTerms();
            const rowCount = wallpaperFolderModel.count;
            for (let i = 0; i < rowCount; i++) {
                const filePath = cleanFilePath(wallpaperFolderModel.get(i, "filePath"));
                if (!filePath)
                    continue;
                if (terms.length > 0) {
                    const fileName = wallpaperFolderModel.get(i, "fileName") || filePath.substring(filePath.lastIndexOf('/') + 1);
                    if (!matchesTerms(terms, fileName, filePath))
                        continue;
                }
                paths.push(filePath);
            }
        }

        const selectCurrent = preferCurrentWallpaper && visible && active;
        if (selectCurrent) {
            enableAnimation = false;
            const currentWallpaper = getCurrentWallpaper();
            let matched = false;
            if (currentWallpaper) {
                for (let i = 0; i < paths.length; i++) {
                    if (paths[i] === currentWallpaper) {
                        currentPage = Math.floor(i / itemsPerPage);
                        gridIndex = i % itemsPerPage;
                        matched = true;
                        break;
                    }
                }
            }
            if (!matched) {
                currentPage = 0;
                gridIndex = 0;
            }
        } else {
            const nextTotal = Math.max(1, Math.ceil(paths.length / itemsPerPage));
            if (currentPage >= nextTotal)
                currentPage = Math.max(0, nextTotal - 1);
            const visibleCount = Math.max(0, Math.min(itemsPerPage, paths.length - currentPage * itemsPerPage));
            gridIndex = visibleCount > 0 ? Math.min(gridIndex, visibleCount - 1) : 0;
        }

        filteredWallpaperPaths = paths;
        gridRevision++;
        updateSelectedFileName();
        if (selectCurrent) {
            Qt.callLater(() => {
                enableAnimation = true;
            });
        }
    }

    function openFolderBrowser() {
        wallpaperBrowserLoader.active = true;
        wallpaperBrowserLoader.item.open();
    }

    function focusSearch() {
        searchExpanded = true;
        Qt.callLater(() => {
            wallpaperSearchField.forceActiveFocus();
            wallpaperSearchField.selectAll();
        });
    }

    function clearSearch() {
        wallpaperSearchField.clear();
    }

    function collapseSearch() {
        clearSearch();
        searchExpanded = false;
        if (keyForwardTarget)
            keyForwardTarget.forceActiveFocus();
    }

    onSortKeyChanged: refreshAfterSort()
    onSortDescendingChanged: refreshAfterSort()
    onSearchQueryChanged: {
        currentPage = 0;
        gridIndex = 0;
        searchDebounce.restart();
    }

    function setSort(key, descending) {
        FB.FileBrowserSettings.save("wallpaper", {
            "sortKey": key,
            "sortDesc": descending
        });
    }

    function getCurrentWallpaper() {
        if (SessionData.perMonitorWallpaper && targetScreenName)
            return SessionData.getMonitorWallpaper(targetScreenName);
        return SessionData.wallpaperPath;
    }

    function setCurrentWallpaper(path) {
        if (SessionData.perMonitorWallpaper && targetScreenName) {
            SessionData.setMonitorWallpaper(targetScreenName, path);
            SessionData.setMonitorCyclingFolderPath(targetScreenName, "");
            return;
        }
        SessionData.setWallpaper(path);
        SessionData.wallpaperCyclingFolderPath = "";
        SessionData.saveSettings();
    }

    onCurrentPageChanged: updateSelectedFileName()

    onTotalPagesChanged: {
        if (currentPage >= totalPages)
            currentPage = Math.max(0, totalPages - 1);
    }

    onGridIndexChanged: updateSelectedFileName()

    onItemsPerPageChanged: reselectCurrent()

    function selectFlat(index) {
        if (index < 0 || index >= wallpaperCount)
            return;
        currentPage = Math.floor(index / itemsPerPage);
        gridIndex = index % itemsPerPage;
    }

    onVisibleChanged: {
        if (visible && active)
            setInitialSelection();
    }

    Component.onCompleted: loadWallpaperDirectory()

    onActiveChanged: {
        if (active && visible)
            setInitialSelection();
    }

    function goToNextCell(visibleCount) {
        if (gridIndex + 1 < visibleCount) {
            gridIndex++;
        } else if (currentPage < totalPages - 1) {
            gridIndex = 0;
            currentPage++;
        } else if (totalPages > 1) {
            gridIndex = 0;
            currentPage = 0;
        }
    }

    function goToPrevCell() {
        if (gridIndex > 0) {
            gridIndex--;
        } else if (currentPage > 0) {
            currentPage--;
            gridIndex = pageItemCount(currentPage) - 1;
        } else if (totalPages > 1) {
            currentPage = totalPages - 1;
            gridIndex = pageItemCount(currentPage) - 1;
        }
    }

    function closeOverlays() {
        if (sortMenu.menuVisible || pageJumpPopup.visible) {
            sortMenu.closeDropdownMenu();
            pageJumpPopup.visible = false;
            return true;
        }
        return false;
    }

    function openSortMenu() {
        const index = Math.max(0, sortKeys.indexOf(sortKey));
        sortMenu.currentValue = sortOptions[index];
        sortMenu.openDropdownMenu();
    }

    function chooseSort(value) {
        const index = sortMenu.options.indexOf(value);
        if (index < 0)
            return;
        if (index < sortKeys.length) {
            setSort(sortKeys[index], sortDescending);
            return;
        }
        setSort(sortKey, index === sortKeys.length + 1);
    }

    function handleKeyEvent(event) {
        if (event.key === Qt.Key_Escape) {
            if (closeOverlays())
                return true;
            if (searchQuery !== "") {
                clearSearch();
                return true;
            }
            if (searchExpanded) {
                collapseSearch();
                return true;
            }
            return false;
        }

        if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
            closeOverlays();
            focusSearch();
            return true;
        }
        const currentCol = gridIndex % columns;
        const visibleCount = pageItemCount(currentPage);

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (gridIndex >= 0 && gridIndex < visibleCount) {
                const filePath = wallpaperPathAt(currentPage * itemsPerPage + gridIndex);
                if (filePath)
                    setCurrentWallpaper(filePath);
            }
            return true;
        }

        if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
            if (I18n.isRtl)
                goToPrevCell();
            else
                goToNextCell(visibleCount);
            return true;
        }

        if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
            if (I18n.isRtl)
                goToNextCell(visibleCount);
            else
                goToPrevCell();
            return true;
        }

        if (root.carousel && (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.key === Qt.Key_PageDown)) {
            goToNextCell(visibleCount);
            return true;
        }

        if (root.carousel && (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.key === Qt.Key_PageUp)) {
            goToPrevCell();
            return true;
        }

        if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            if (gridIndex + columns < visibleCount) {
                gridIndex += columns;
            } else if (currentPage < totalPages - 1) {
                gridIndex = currentCol;
                currentPage++;
            } else if (totalPages > 1) {
                gridIndex = currentCol;
                currentPage = 0;
            }
            return true;
        }

        if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            if (gridIndex >= columns) {
                gridIndex -= columns;
            } else if (currentPage > 0) {
                currentPage--;
                const prevPageCount = pageItemCount(currentPage);
                const prevPageRows = Math.ceil(prevPageCount / columns);
                gridIndex = Math.min((prevPageRows - 1) * columns + currentCol, prevPageCount - 1);
            } else if (totalPages > 1) {
                currentPage = totalPages - 1;
                const lastPageCount = pageItemCount(currentPage);
                const lastPageRows = Math.ceil(lastPageCount / columns);
                gridIndex = Math.min((lastPageRows - 1) * columns + currentCol, lastPageCount - 1);
            }
            return true;
        }

        if (event.key === Qt.Key_PageUp && totalPages > 1) {
            gridIndex = 0;
            currentPage = (currentPage - 1 + totalPages) % totalPages;
            return true;
        }

        if (event.key === Qt.Key_PageDown && totalPages > 1) {
            gridIndex = 0;
            currentPage = (currentPage + 1) % totalPages;
            return true;
        }

        if (event.key === Qt.Key_Home && event.modifiers & Qt.ControlModifier) {
            gridIndex = 0;
            currentPage = 0;
            return true;
        }

        if (event.key === Qt.Key_End && event.modifiers & Qt.ControlModifier) {
            currentPage = totalPages - 1;
            gridIndex = Math.max(0, pageItemCount(currentPage) - 1);
            return true;
        }

        return false;
    }

    function setInitialSelection() {
        const currentWallpaper = getCurrentWallpaper();
        let index = -1;
        if (currentWallpaper && wallpaperCount > 0)
            index = filteredWallpaperPaths.indexOf(currentWallpaper);
        const page = index >= 0 ? Math.floor(index / itemsPerPage) : currentPage;
        const cell = index >= 0 ? index % itemsPerPage : 0;
        updateSelectedFileName();
        if (page === currentPage && cell === gridIndex) {
            enableAnimation = true;
            return;
        }
        enableAnimation = false;
        currentPage = page;
        gridIndex = cell;
        Qt.callLater(() => {
            enableAnimation = true;
        });
    }

    function loadWallpaperDirectory() {
        const currentWallpaper = getCurrentWallpaper();

        if (!currentWallpaper || currentWallpaper.startsWith("#")) {
            wallpaperDir = wallpaperBrowserSettings.lastPath;
            return;
        }

        wallpaperDir = currentWallpaper.substring(0, currentWallpaper.lastIndexOf('/'));
    }

    function updateSelectedFileName() {
        const filePath = wallpaperCount > 0 ? wallpaperPathAt(currentPage * itemsPerPage + gridIndex) : "";
        selectedFileName = filePath ? filePath.substring(filePath.lastIndexOf('/') + 1) : "";
    }

    function reselectCurrent() {
        loadWallpaperDirectory();
        if (visible && active)
            setInitialSelection();
    }

    readonly property string sessionWallpaperPath: SessionData.wallpaperPath
    readonly property var sessionMonitorWallpapers: SessionData.monitorWallpapers
    readonly property bool sessionPerMonitorWallpaper: SessionData.perMonitorWallpaper

    onSessionWallpaperPathChanged: reselectCurrent()
    onSessionMonitorWallpapersChanged: reselectCurrent()
    onSessionPerMonitorWallpaperChanged: reselectCurrent()

    onTargetScreenNameChanged: reselectCurrent()

    Timer {
        id: searchDebounce

        interval: DashMetrics.searchDebounce
        repeat: false
        onTriggered: root.rebuildWallpaperList(false)
    }

    FolderListModel {
        id: wallpaperFolderModel

        onCountChanged: {
            if (status === FolderListModel.Ready)
                root.rebuildWallpaperList(true);
        }
        onStatusChanged: root.rebuildWallpaperList(status === FolderListModel.Ready)

        showDirsFirst: false
        showDotAndDotDot: false
        showHidden: false
        caseSensitive: false
        nameFilters: WallpaperFormats.nameFilters(true)
        showFiles: true
        showDirs: false
        sortField: {
            switch (root.sortKey) {
            case "size":
                return FolderListModel.Size;
            case "mtime":
                return FolderListModel.Time;
            case "type":
                return FolderListModel.Type;
            default:
                return FolderListModel.Name;
            }
        }
        sortReversed: root.sortDescending
        folder: wallpaperDir ? "file://" + wallpaperDir.split('/').map(s => encodeURIComponent(s)).join('/') : ""
    }

    Item {
        id: searchKeyHandler

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                event.accepted = false;
                if (root.keyForwardTarget)
                    root.keyForwardTarget.Keys.pressed(event);
                return;
            }

            const ctrlHomeOrEnd = (event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Home || event.key === Qt.Key_End);
            const gridNavigationKey = event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Escape || ctrlHomeOrEnd;
            if (!gridNavigationKey)
                return;

            event.accepted = root.handleKeyEvent(event);
            if (!event.accepted && root.keyForwardTarget)
                root.keyForwardTarget.Keys.pressed(event);
        }
    }

    Loader {
        id: wallpaperBrowserLoader

        active: false

        sourceComponent: FileBrowserSurfaceModal {
            browserTitle: I18n.tr("Select Wallpaper Directory", "wallpaper directory file browser title")
            bucket: "wallpaper"
            startPath: root.getCurrentWallpaper()
            filters: WallpaperFormats.nameFilters(true)
            parentPopout: root.parentPopout
            onAccepted: paths => {
                root.setCurrentWallpaper(paths[0]);
                root.wallpaperDir = paths[0].substring(0, paths[0].lastIndexOf('/'));
            }
        }
    }

    Column {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        Item {
            id: wallpaperView
            width: parent.width
            height: parent.height - DashMetrics.wallpaperFooterHeight

            Loader {
                anchors.fill: parent
                active: root.carousel
                visible: active

                sourceComponent: WallpaperCarousel {
                    paths: root.filteredWallpaperPaths
                    currentIndex: root.flatIndex
                    currentWallpaper: root.getCurrentWallpaper()
                    animate: root.enableAnimation
                    onIndexRequested: index => root.selectFlat(index)
                    onActivated: path => root.setCurrentWallpaper(path)
                }
            }

            // Dank* wrappers reset contentY on model change and take the wheel; the pager needs snap-one-item paging.
            ListView {
                id: pager
                anchors.centerIn: parent
                width: parent.width - Theme.spacingS
                height: parent.height - Theme.spacingS
                orientation: ListView.Vertical
                snapMode: ListView.SnapOneItem
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: 0
                preferredHighlightEnd: height
                highlightMoveDuration: root.enableAnimation && DashMetrics.animationsEnabled ? DashMetrics.transitionDuration : 0
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                enabled: root.active
                interactive: root.active
                keyNavigationEnabled: false
                activeFocusOnTab: false
                focus: false
                cacheBuffer: Math.max(0, height * root.pagerCachePages)
                reuseItems: false
                visible: !root.carousel
                model: !root.carousel && height > 1 ? root.totalPages : 0

                onCountChanged: {
                    if (count > 0 && currentIndex !== root.currentPage)
                        currentIndex = root.currentPage;
                }

                onCurrentIndexChanged: {
                    if (!moving)
                        return;
                    if (currentIndex >= 0 && currentIndex !== root.currentPage)
                        root.currentPage = currentIndex;
                }

                Component.onCompleted: currentIndex = root.currentPage

                readonly property int rootCurrentPage: root.currentPage

                onRootCurrentPageChanged: {
                    if (currentIndex !== rootCurrentPage)
                        currentIndex = rootCurrentPage;
                }

                delegate: GridView {
                    id: pageGrid

                    property int pageIndex: index

                    width: pager.width
                    height: Math.max(1, pager.height)
                    cellWidth: Math.max(1, Math.floor(width / root.columns))
                    cellHeight: Math.max(1, Math.floor(height / root.rows))
                    interactive: false
                    keyNavigationEnabled: false
                    activeFocusOnTab: false
                    focus: false
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: root.enableAnimation && DashMetrics.animationsEnabled ? DashMetrics.fadeDuration : 0
                    currentIndex: root.currentPage === pageIndex ? root.gridIndex : -1

                    highlight: Item {
                        z: DashMetrics.overlayZ
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingXS - Theme.focusRingOffset / 2
                            color: "transparent"
                            border.width: Theme.focusRingWidth
                            border.color: Theme.focusRingColor
                            radius: DashMetrics.wallpaperThumbRadius + Theme.focusRingOffset / 2
                        }
                    }

                    reuseItems: true
                    model: ScriptModel {
                        values: {
                            root.gridRevision; // dependency only
                            const startIndex = pageGrid.pageIndex * root.itemsPerPage;
                            const endIndex = Math.min(startIndex + root.itemsPerPage, root.wallpaperCount);
                            return root.filteredWallpaperPaths.slice(startIndex, endIndex);
                        }
                    }

                    onCountChanged: {
                        if (root.currentPage !== pageIndex || count === 0)
                            return;
                        if (root.gridIndex >= count)
                            root.gridIndex = count - 1;
                    }

                    delegate: Item {
                        width: pageGrid.cellWidth
                        height: pageGrid.cellHeight

                        property string wallpaperPath: modelData || ""
                        property bool isSelected: root.getCurrentWallpaper() === modelData

                        Rectangle {
                            id: wallpaperCard
                            anchors.fill: parent
                            anchors.margins: Theme.spacingXS
                            color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
                            border.width: Theme.layerOutlineWidth
                            border.color: Theme.outlineMedium
                            radius: DashMetrics.wallpaperThumbRadius

                            ClippingRectangle {
                                anchors.fill: parent
                                radius: wallpaperCard.radius
                                color: "transparent"

                                CachingImage {
                                    anchors.fill: parent
                                    imagePath: VideoWallpaperService.imageFor(modelData || "")
                                    maxCacheSize: DashMetrics.wallpaperThumbCache
                                    animate: false
                                    opacity: status === Image.Ready ? 1 : 0

                                    Behavior on opacity {
                                        enabled: DashMetrics.animationsEnabled
                                        NumberAnimation {
                                            duration: DashMetrics.fadeDuration
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: Theme.withAlpha(Theme.primary, isSelected ? Theme.stateLayerFocus : 0)
                                border.width: isSelected ? Theme.outlineWidthFocused : 0
                                border.color: Theme.primary

                                Behavior on color {
                                    enabled: DashMetrics.animationsEnabled
                                    ColorAnimation {
                                        duration: DashMetrics.fadeDuration
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                                    }
                                }
                            }

                            StateLayer {
                                anchors.fill: parent
                                cornerRadius: parent.radius
                                stateColor: Theme.primary
                                onClicked: {
                                    root.gridIndex = index;
                                    if (modelData)
                                        root.setCurrentWallpaper(modelData);
                                }
                            }
                        }
                    }
                }
            }

            DSpinner {
                anchors.centerIn: parent
                size: DashMetrics.spinnerSize
                visible: wallpaperFolderModel.status === FolderListModel.Loading && wallpaperFolderModel.count === 0
            }

            CcEmptyState {
                anchors.centerIn: parent
                visible: wallpaperFolderModel.status === FolderListModel.Ready && root.wallpaperCount === 0
                iconName: root.searchQuery.trim() !== "" ? "search_off" : "wallpaper"
                title: root.searchQuery.trim() !== "" ? I18n.tr("No results found") : I18n.tr("No wallpapers")

                DButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Choose wallpaper folder")
                    visible: root.searchQuery.trim() === ""
                    onClicked: root.openFolderBrowser()
                }
            }
        }

        Column {
            width: parent.width
            height: DashMetrics.wallpaperFooterHeight

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                width: controlsRow.width + actionButtons.width + spacing
                height: DashMetrics.wallpaperControlSize
                spacing: Theme.spacingS

                Row {
                    id: controlsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    FooterButton {
                        id: previousPageButton
                        iconName: "skip_previous"
                        enabled: root.totalPages > 1
                        Accessible.name: I18n.tr("Previous page")
                        onClicked: root.currentPage = (root.currentPage - 1 + root.totalPages) % root.totalPages
                    }

                    DButton {
                        id: pageButton
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.wallpaperCount > 0 ? (root.wallpaperCount === 1 ? I18n.tr("%1 wallpaper  •  %2 / %3", "singular, %1 is 1, %2 current page, %3 total pages").arg(root.wallpaperCount).arg(root.currentPage + 1).arg(root.totalPages) : I18n.tr("%1 wallpapers  •  %2 / %3", "plural, %1 is a count, %2 current page, %3 total pages").arg(root.wallpaperCount).arg(root.currentPage + 1).arg(root.totalPages)) : I18n.tr("No wallpapers")
                        buttonHeight: DashMetrics.wallpaperControlSize
                        horizontalPadding: Theme.spacingS
                        backgroundColor: "transparent"
                        textColor: Theme.onSurfaceVariant
                        onClicked: {
                            if (root.totalPages <= 1)
                                return;
                            sortMenu.closeDropdownMenu();
                            pageJumpPopup.visible = !pageJumpPopup.visible;
                        }
                    }

                    FooterButton {
                        id: nextPageButton
                        iconName: "skip_next"
                        enabled: root.totalPages > 1
                        Accessible.name: I18n.tr("Next page")
                        onClicked: root.currentPage = (root.currentPage + 1) % root.totalPages
                    }
                }

                Row {
                    id: actionButtons

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    FooterButton {
                        id: sortButton
                        iconName: "filter_list"
                        enabled: wallpaperFolderModel.count > 0
                        tooltipText: I18n.tr("Sort wallpapers")
                        Accessible.description: [root.sortOptions[Math.max(0, root.sortKeys.indexOf(root.sortKey))], root.sortDescending ? I18n.tr("Descending") : I18n.tr("Ascending")].join(" · ")
                        onClicked: {
                            pageJumpPopup.visible = false;
                            if (sortMenu.menuVisible) {
                                sortMenu.closeDropdownMenu();
                                return;
                            }
                            root.openSortMenu();
                        }
                        Keys.onDownPressed: event => {
                            root.openSortMenu();
                            event.accepted = true;
                        }

                        DDropdown {
                            id: sortMenu

                            showTrigger: false
                            popupAnchorItem: sortButton
                            focusReturnTarget: sortButton
                            transientSurfaceTracker: root.transientSurfaceTracker
                            openUpwards: true
                            alignPopupRight: !I18n.isRtl
                            popupWidth: Math.min(root.width, Theme.smallBreakpoint / 2)
                            options: root.sortOptions.concat([I18n.tr("Ascending"), I18n.tr("Descending")])
                            optionIcons: ["sort_by_alpha", "straighten", "history", "category", root.sortDescending ? "arrow_upward" : "check", root.sortDescending ? "check" : "arrow_downward"]
                            onValueChanged: value => root.chooseSort(value)
                        }
                    }

                    FooterButton {
                        id: folderButton
                        iconName: "folder_open"
                        tooltipText: I18n.tr("Choose wallpaper folder")
                        onClicked: root.openFolderBrowser()
                    }

                    Item {
                        id: searchControl

                        anchors.verticalCenter: parent.verticalCenter
                        width: root.searchExpanded ? DashMetrics.wallpaperSearchWidth : DashMetrics.wallpaperControlSize
                        height: DashMetrics.wallpaperControlSize
                        clip: true

                        Behavior on width {
                            enabled: DashMetrics.animationsEnabled
                            NumberAnimation {
                                duration: DashMetrics.transitionDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.standard
                            }
                        }

                        FooterButton {
                            id: searchToggleButton

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "search"
                            visible: !root.searchExpanded
                            Accessible.name: I18n.tr("Search", "search field placeholder") + "…"
                            onClicked: root.focusSearch()
                        }

                        DSearchField {
                            id: wallpaperSearchField

                            anchors.fill: parent
                            topPadding: Theme.spacingXS
                            bottomPadding: Theme.spacingXS
                            leftIconSize: Theme.iconSizeSmall
                            showClearButton: false
                            rightAccessoryWidth: (root.searchQuery !== "" ? DashMetrics.wallpaperSmallButtonSize + Theme.spacingXXS : 0) + DashMetrics.wallpaperSmallButtonSize + Theme.spacingXXS
                            placeholderText: I18n.tr("Search", "search field placeholder") + "…"
                            keyForwardTargets: [searchKeyHandler]
                            visible: root.searchExpanded
                        }

                        SearchButton {
                            anchors.right: collapseSearchButton.left
                            iconName: "backspace"
                            visible: root.searchExpanded && root.searchQuery !== ""
                            Accessible.name: I18n.tr("Clear", "verb, button clearing a search, image, job list or notification")
                            onClicked: root.clearSearch()
                        }

                        SearchButton {
                            id: collapseSearchButton

                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingXXS
                            iconName: "close"
                            visible: root.searchExpanded
                            Accessible.name: I18n.tr("Close")
                            onClicked: root.collapseSearch()
                        }
                    }
                }
            }

            StyledText {
                width: parent.width
                height: DashMetrics.wallpaperFilenameHeight
                text: root.selectedFileName
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.onSurfaceVariant
                visible: root.selectedFileName !== "" && root.options.filename !== false
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    function jumpToPage(value) {
        const n = parseInt(value);
        if (!isNaN(n))
            currentPage = Math.max(0, Math.min(totalPages - 1, n - 1));
        pageJumpPopup.visible = false;
    }

    MouseArea {
        anchors.fill: parent
        z: DashMetrics.overlayZ - 1
        visible: pageJumpPopup.visible
        enabled: visible
        onClicked: root.closeOverlays()
    }

    BackdropBlur {
        visible: pageJumpPopup.visible
        z: DashMetrics.overlayZ
        width: pageJumpPopup.width
        height: pageJumpPopup.height
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: DashMetrics.wallpaperOverlayBottomMargin
        radius: Theme.cornerRadiusM
        sourceItem: contentColumn
    }

    StyledRect {
        id: pageJumpPopup
        width: DashMetrics.pageJumpWidth
        height: jumpColumn.height + Theme.spacingM * 2
        color: Theme.nestedSurface
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
        radius: Theme.cornerRadiusM
        visible: false
        z: DashMetrics.overlayZ + 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: DashMetrics.wallpaperOverlayBottomMargin

        onVisibleChanged: {
            if (!visible)
                return;
            pageJumpField.text = (root.currentPage + 1).toString();
            pageJumpField.forceActiveFocus();
            pageJumpField.selectAll();
        }

        Column {
            id: jumpColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingXS

            StyledText {
                text: I18n.tr("Jump to page (1 - %1)", "wallpaper page jump prompt, %1 is the last page number").arg(root.totalPages)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.onSurfaceVariant
            }

            DTextField {
                id: pageJumpField
                width: parent.width
                placeholderText: "1 - " + root.totalPages
                maximumLength: 6
                topPadding: Theme.spacingS
                bottomPadding: Theme.spacingS
                validator: IntValidator {
                    bottom: 1
                    top: root.totalPages
                }
                onAccepted: root.jumpToPage(text)
            }
        }
    }

    component FooterButton: DActionButton {
        anchors.verticalCenter: parent.verticalCenter
        iconSize: DashMetrics.wallpaperControlIconSize
        buttonSize: DashMetrics.wallpaperControlSize
        tooltipSide: "top"
    }

    component SearchButton: DActionButton {
        anchors.verticalCenter: parent.verticalCenter
        z: 2
        iconSize: Theme.iconSizeSmall
        buttonSize: DashMetrics.wallpaperSmallButtonSize
        tooltipSide: "top"
    }
}
