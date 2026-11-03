import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "ProcessColumns.js" as ProcessColumns

Rectangle {
    id: root

    color: "transparent"
    radius: Theme.cornerRadiusL
    clip: true

    property string searchText: ""
    property string expandedPid: ""
    property var contextMenu: null
    property var columns: ProcessColumns.DEFAULT_COLUMNS
    readonly property var processFilterTypes: CacheData.processFilterTypes
    readonly property bool onlineOnly: ProcessListMetrics.onlineOnly
    readonly property bool filtered: searchText.length > 0 || processFilterTypes.length === 1 || onlineOnly
    readonly property int processCount: filtered ? cachedProcesses.length : Math.max(DgopService.processCount, cachedProcesses.length)
    readonly property string processCountText: processCount === 1 ? I18n.tr("%1 process", "process count, singular, %1 is 1").arg(1) : I18n.tr("%1 processes", "process count, plural, %1 is a number").arg(processCount)
    readonly property real rowHeight: ProcessListMetrics.rowHeight
    property bool active: visible
    readonly property alias listView: processListView
    onSelectedIndexChanged: {
        if (keyboardNavigationActive)
            selectionScroll.schedule();
    }
    onActiveChanged: {
        if (!active)
            return;
        reconcileSort();
        updateProcesses();
    }
    onSearchTextChanged: refreshFilter()

    // The window lists every process; the popout shows dgop's top rows.
    property bool fullList: false
    readonly property bool needsFullProcessList: active && (fullList || searchText.length > 0 || onlineOnly || DgopService.dgopSort() === "")
    property bool holdsFullProcessList: false
    onNeedsFullProcessListChanged: {
        if (needsFullProcessList === holdsFullProcessList)
            return;
        holdsFullProcessList = needsFullProcessList;
        if (needsFullProcessList)
            DgopService.requestFullProcessList();
        else
            DgopService.releaseFullProcessList();
    }
    Component.onDestruction: {
        if (holdsFullProcessList)
            DgopService.releaseFullProcessList();
    }
    onColumnsChanged: reconcileSort()

    function reconcileSort() {
        const sort = DgopService.currentSort;
        if (sort !== "name" && sort !== "pid" && !columns.includes(sort))
            DgopService.setSortBy("cpu");
    }
    onProcessFilterTypesChanged: refreshFilter()
    onOnlineOnlyChanged: refreshFilter()

    property int selectedIndex: -1
    property bool keyboardNavigationActive: false
    property int forceRefreshCount: 0

    readonly property bool holdOrder: (contextMenu?.visible ?? false) || (contextMenu?.confirmationOpen ?? false) || expandedPid.length > 0
    // The order stays put for one more sample after a row or menu closes, so the list does not re-sort under the pointer.
    readonly property bool pauseUpdates: holdOrder || resumeHold.running
    readonly property bool shouldUpdate: !pauseUpdates || forceRefreshCount > 0

    onHoldOrderChanged: {
        if (!holdOrder)
            resumeHold.restart();
    }

    Timer {
        id: resumeHold
        interval: DgopService.updateInterval
    }
    property var cachedProcesses: []

    onFilteredProcessesChanged: {
        if (!shouldUpdate) {
            refreshValues();
            return;
        }
        updateProcesses();
        if (forceRefreshCount > 0)
            forceRefreshCount--;
    }

    onShouldUpdateChanged: {
        // Resuming waits for the next sample, so closing a row and the re-sort don't move the list at once.
        if (shouldUpdate && forceRefreshCount > 0)
            updateProcesses();
    }

    readonly property var filteredProcesses: {
        if (!active || !DgopService.allProcesses || DgopService.allProcesses.length === 0)
            return [];

        let procs = DgopService.allProcesses.slice();
        // App names only matter for searching and sorting by name; looking them up for every row each sample is wasted.
        if (searchText.length > 0 || DgopService.currentSort === "name")
            procs = procs.map(p => Object.assign({}, p, {
                    "appName": ProcessListMetrics.appEntry(p)?.name ?? ""
                }));

        if (processFilterTypes.length === 1)
            procs = procs.filter(p => processFilterTypes.includes(p.username === UserInfoService.username ? "user" : "system"));
        if (onlineOnly)
            procs = procs.filter(p => (p.connections ?? 0) > 0);

        if (searchText.length > 0) {
            const search = searchText.toLowerCase();
            procs = procs.filter(p => {
                const cmd = (p.command || "").toLowerCase();
                const app = (p.appName || "").toLowerCase();
                const fullCmd = (p.fullCommand || "").toLowerCase();
                const pid = p.pid.toString();
                return cmd.includes(search) || app.includes(search) || fullCmd.includes(search) || pid.includes(search);
            });
        }

        procs.sort(DgopService.processComparator());

        return procs;
    }

    readonly property real nameMinWidth: Theme.fontSizeSmall * 16
    readonly property var visibleColumns: root.columns.map(id => ProcessColumns.COLUMNS.find(c => c.id === id)).filter(c => c)
    // Wider than the card when many columns are on: the whole table then scrolls sideways, the name keeps its minimum.
    readonly property real tableWidth: Math.max(root.width, Theme.spacingL * 2 + root.leadWidth + root.nameMinWidth + visibleColumns.reduce((sum, c) => sum + root.columnWidth(c) + Theme.spacingXS * 2, 0))
    readonly property var visibleColumnIds: visibleColumns.map(c => c.id)
    readonly property real leadWidth: ProcessListMetrics.appIconSize + Theme.spacingS

    function columnWidth(c) {
        return Theme.fontSizeSmall * (c.width ?? 6);
    }

    component SortHeader: Item {
        id: sh

        property string sortKey: ""
        property string label: ""
        property bool alignLeft: false
        readonly property bool sorted: DgopService.currentSort === sortKey
        readonly property bool ascending: DgopService.sortAscending !== ["name", "pid"].includes(sortKey)

        implicitHeight: ProcessListMetrics.headerHeight
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.description: sorted ? (ascending ? I18n.tr("Ascending", "sort direction, smallest value first") : I18n.tr("Descending", "sort direction, largest value first")) : ""
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                DgopService.toggleSort(sortKey);
                event.accepted = true;
            }
        }

        FocusRing {
            radius: Theme.cornerRadiusXS + Theme.focusRingOffset
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: sh.alignLeft ? parent.left : undefined
            anchors.right: sh.alignLeft ? undefined : parent.right
            anchors.rightMargin: sh.alignLeft ? 0 : Theme.spacingXS
            width: Math.min(implicitWidth, sh.width)
            spacing: Theme.spacingXXS

            StyledText {
                width: Math.min(implicitWidth, sh.width - (arrow.visible ? arrow.width + parent.spacing : 0))
                text: sh.label
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: sh.sorted ? Theme.primary : Theme.surfaceVariantText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            DIcon {
                id: arrow
                visible: sh.sorted
                name: sh.ascending ? "arrow_upward" : "arrow_downward"
                size: Theme.fontSizeSmall
                color: Theme.primary
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: DgopService.toggleSort(sh.sortKey)
        }
    }

    DeferredAction {
        id: selectionScroll
        onTriggered: {
            root.ensureVisible();
            if (processListView.activeFocus)
                processListView.currentItem?.forceActiveFocus(Qt.TabFocusReason);
        }
    }

    function refreshFilter() {
        expandedPid = "";
        updateProcesses();
    }

    // While paused the order stays put (an open row must not move), but the values keep updating.
    function refreshValues() {
        if (!active)
            return;
        const fresh = new Map(filteredProcesses.map(p => [p.pid, p]));
        cachedProcesses = cachedProcesses.map(p => fresh.get(p.pid) ?? p);
    }

    function updateProcesses() {
        if (!active || DgopService.allProcesses.length === 0)
            return;
        const pid = cachedProcesses[selectedIndex]?.pid;
        cachedProcesses = filteredProcesses;
        selectedIndex = pid === undefined ? -1 : cachedProcesses.findIndex(p => p.pid === pid);
        if (selectedIndex < 0 && keyboardNavigationActive && cachedProcesses.length > 0)
            selectedIndex = 0;
    }

    function requestAction(index, action) {
        const process = cachedProcesses[index];
        if (!process || !contextMenu)
            return;
        selectedIndex = index;
        keyboardNavigationActive = true;
        contextMenu.parentFocusItem = processListView;
        contextMenu.processData = process;
        contextMenu.requestAction(action);
    }

    function selectNext() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = Math.min(selectedIndex + 1, cachedProcesses.length - 1);
        ensureVisible();
    }

    function selectPrevious() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        if (selectedIndex <= 0) {
            selectedIndex = -1;
            keyboardNavigationActive = false;
            return;
        }
        selectedIndex = selectedIndex - 1;
        ensureVisible();
    }

    function selectFirst() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = 0;
        ensureVisible();
    }

    function selectLast() {
        if (cachedProcesses.length === 0)
            return;
        keyboardNavigationActive = true;
        selectedIndex = cachedProcesses.length - 1;
        ensureVisible();
    }

    function toggleExpand() {
        if (selectedIndex < 0 || selectedIndex >= cachedProcesses.length)
            return;
        const process = cachedProcesses[selectedIndex];
        const pidStr = (process?.pid ?? -1).toString();
        expandedPid = (expandedPid === pidStr) ? "" : pidStr;
        if (expandedPid !== "")
            revealExpanded.restart();
    }

    // Once the strip has slid open, scroll it into view; a row near the bottom would otherwise open off screen.
    Timer {
        id: revealExpanded
        interval: Theme.expressiveDurations.expressiveDefaultSpatial
        onTriggered: {
            const index = root.cachedProcesses.findIndex(p => String(p.pid) === root.expandedPid);
            if (index >= 0)
                processListView.positionViewAtIndex(index, ListView.Contain);
        }
    }

    function openContextMenu() {
        if (selectedIndex < 0 || selectedIndex >= cachedProcesses.length)
            return;
        const delegate = processListView.itemAtIndex(selectedIndex);
        if (!delegate)
            return;
        const process = cachedProcesses[selectedIndex];
        if (!process || !contextMenu)
            return;
        contextMenu.processData = process;
        const itemPos = delegate.mapToItem(contextMenu.parent, delegate.width / 2, delegate.height / 2);
        contextMenu.parentFocusItem = processListView;
        contextMenu.show(itemPos.x, itemPos.y, true);
    }

    function reset() {
        selectedIndex = -1;
        keyboardNavigationActive = false;
        expandedPid = "";
    }

    function forceRefresh(count) {
        forceRefreshCount = count || 3;
    }

    function ensureVisible() {
        if (selectedIndex < 0)
            return;
        processListView.revealIndex(selectedIndex);
    }

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Down:
            selectNext();
            event.accepted = true;
            return;
        case Qt.Key_Up:
            selectPrevious();
            event.accepted = true;
            return;
        case Qt.Key_J:
            if (event.modifiers & Qt.ControlModifier) {
                selectNext();
                event.accepted = true;
            }
            return;
        case Qt.Key_K:
            if (event.modifiers & Qt.ControlModifier) {
                requestAction(selectedIndex, "quit");
                event.accepted = true;
            }
            return;
        case Qt.Key_Delete:
            if (!keyboardNavigationActive)
                return;
            requestAction(selectedIndex, "quit");
            event.accepted = true;
            return;
        case Qt.Key_Home:
            selectFirst();
            event.accepted = true;
            return;
        case Qt.Key_End:
            selectLast();
            event.accepted = true;
            return;
        case Qt.Key_Space:
            if (keyboardNavigationActive) {
                toggleExpand();
                event.accepted = true;
            }
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (keyboardNavigationActive) {
                toggleExpand();
                event.accepted = true;
            }
            return;
        case Qt.Key_Menu:
        case Qt.Key_F10:
            if (keyboardNavigationActive && selectedIndex >= 0) {
                openContextMenu();
                event.accepted = true;
            }
            return;
        }
    }

    Item {
        id: processKeys
        Keys.onPressed: event => root.handleKey(event)
    }

    Ref {
        service: DgopService
        modules: ["processes", "cpu", "memory", "system", "gpu"].concat(ProcessColumns.modulesFor(root.columns), root.onlineOnly || root.expandedPid !== "" ? ["process-net"] : [])
        active: root.active
    }

    Component.onCompleted: {
        reconcileSort();
        updateProcesses();
    }

    // The first details panel compiles its type, which stalled the first expand; build one hidden in the background.
    Loader {
        property bool warmed: false
        active: root.active && !warmed && DgopService.allProcesses.length > 0
        asynchronous: true
        visible: false
        sourceComponent: ProcessDetailStrip {
            process: null
        }
        onLoaded: warmed = true
    }

    // Column and direction change together on a header click; one refresh covers both.
    readonly property string sortOrder: DgopService.currentSort + (DgopService.sortAscending ? "+" : "-")

    onSortOrderChanged: Qt.callLater(refreshFilter)

    property real menuClosedAt: 0
    readonly property bool contextMenuOpen: contextMenu?.visible ?? false

    onContextMenuOpenChanged: {
        if (!contextMenuOpen)
            menuClosedAt = Date.now();
    }

    Connections {
        target: root.contextMenu
        function onProcessKilled() {
            root.expandedPid = "";
            root.forceRefresh(3);
        }
    }

    DFlickable {
        id: tableScroll
        anchors.fill: parent
        contentWidth: root.tableWidth
        contentHeight: height
        horizontal: true
        interactive: overflows
        clip: true

        readonly property bool overflows: contentWidth > width

        ColumnLayout {
            width: root.tableWidth
            height: tableScroll.height - (tableScroll.overflows ? Theme.scrollbarThickness + Theme.scrollbarGap : 0)
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spacingM
                implicitHeight: header.implicitHeight
                radius: Theme.cornerRadiusS
                color: Theme.surfaceContainerHigh

                RowLayout {
                    id: header
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingL
                    anchors.rightMargin: Theme.spacingL
                    spacing: Theme.spacingXS

                    Item {
                        Layout.minimumWidth: root.leadWidth
                    }

                    SortHeader {
                        id: nameHeader
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        sortKey: "name"
                        label: I18n.tr("Name")
                        alignLeft: true
                    }

                    Repeater {
                        model: root.visibleColumns

                        SortHeader {
                            required property var modelData
                            Layout.minimumWidth: root.columnWidth(modelData)
                            Layout.maximumWidth: Layout.minimumWidth
                            sortKey: modelData.id
                            label: ProcessListMetrics.columnLabel(modelData.id)
                        }
                    }
                }
            }

            DListView {
                id: processListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                reuseItems: true
                cacheBuffer: Math.round(height)
                activeFocusOnTab: true
                focus: true
                Keys.onPressed: event => root.handleKey(event)
                onActiveFocusChanged: {
                    if (activeFocus && root.selectedIndex < 0)
                        root.selectFirst();
                }
                spacing: Theme.groupedListGap
                currentIndex: root.selectedIndex
                add: null
                remove: null
                displaced: null
                move: null

                model: ScriptModel {
                    values: root.cachedProcesses
                    objectProp: "pid"
                }

                delegate: ProcessRow {
                    required property var modelData
                    required property int index
                    firstInGroup: index === 0
                    lastInGroup: index === processListView.count - 1
                    width: processListView.width
                    rowHeight: root.rowHeight
                    detailX: tableScroll.contentX
                    detailWidth: Math.min(width, tableScroll.width)
                    keyForwardTargets: [processKeys]
                    KeyNavigation.backtab: nameHeader
                    columns: root.visibleColumnIds
                    process: modelData
                    isExpanded: root.expandedPid === (modelData?.pid ?? -1).toString()
                    isSelected: root.keyboardNavigationActive && root.selectedIndex === index
                    onClicked: {
                        // A click that opens or dismisses the context menu is not meant for the row.
                        if (root.contextMenu?.visible || Date.now() - root.menuClosedAt < 400)
                            return;
                        processListView.forceActiveFocus(Qt.MouseFocusReason);
                        root.keyboardNavigationActive = true;
                        root.selectedIndex = index;
                        root.toggleExpand();
                    }
                    onActionRequested: action => root.requestAction(index, action)
                    onContextMenuRequested: (mouseX, mouseY) => {
                        if (!root.contextMenu)
                            return;
                        root.selectedIndex = index;
                        root.keyboardNavigationActive = true;
                        root.contextMenu.processData = modelData;
                        root.contextMenu.parentFocusItem = processListView;
                        const pos = mapToItem(root.contextMenu.parent, mouseX, mouseY);
                        root.contextMenu.show(pos.x, pos.y, false);
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    text: I18n.tr("No matching processes", "empty state in process list")
                    color: Theme.onSurfaceVariant
                    visible: processListView.count === 0 && !listSpinner.visible
                }

                DSpinner {
                    id: listSpinner
                    anchors.centerIn: parent
                    size: Theme.iconSize
                    visible: processListView.count === 0 && DgopService.allProcesses.length === 0
                }
            }
        }
    }
}
