pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.DDash
import qs.Modules.ControlCenter
import qs.Modules.DDash.Overview

FocusScope {
    id: root

    required property var controller
    required property string activityId
    required property Component tabComponent
    property string entryId: activityId
    property QtObject resizeGeometry: null
    readonly property DashEditSession editSession: root.controller.dashEditSession
    property bool contentStaged: false
    readonly property bool live: root.controller.expanded && root.controller.activeActivity === root.activityId
    readonly property bool editMode: live && editSession.active && editSession.pageId === entryId
    readonly property string dockSide: editMode ? root.controller.dashDockSideFor(entryId) : ""
    readonly property bool docked: dockSide !== ""
    readonly property real bodyWidth: docked ? Math.min(root.width, root.controller.dashboardWidthFor(activityId)) : root.width
    readonly property bool popoverMode: editMode && !docked && SettingsData.controlCenterEditLayout === "docked"
    readonly property real popoverTop: DashMetrics.islandEditHeaderInset + DashMetrics.editHeaderHeight + CcMetrics.sheetPadding
    // Independent of live, so a tab switch still reads the leaving page's value; a short body keeps the menus and sheets.
    readonly property bool panelFits: root.controller.dashDockSideFor(entryId) !== "" || (SettingsData.controlCenterEditLayout === "docked" && root.height - popoverTop - CcMetrics.sheetPadding >= CcMetrics.widgetPopoverMinHeight)
    readonly property bool panelMode: editMode && panelFits
    readonly property bool popoverShown: popoverMode && panelMode && (editSession.popoverRequested || editSession.selection !== null)
    readonly property DashEditPanel editPanel: panelLoader.item as DashEditPanel
    readonly property var tab: tabLoader.item
    readonly property real tabHeight: tab?.implicitHeight ?? 0
    readonly property real contentHeight: DashMetrics.panelHeightFor(entryId, tabHeight)
    readonly property bool tabsShown: root.controller.dashTabsShownFor(root.activityId)
    readonly property real tabBarHeight: tabBarLoader.item?.implicitHeight ?? Theme.navigationHeight
    readonly property real chromeHeight: DashMetrics.islandChromeHeight(tabsShown ? tabBarHeight : 0)
    readonly property bool tabBarShown: tabsShown && (!editMode || docked)
    readonly property bool handleHeader: !root.tabsShown && (!root.editMode || root.docked)
    readonly property real headerHeight: tabBarShown ? tabBarHeight : handleHeader ? DashMetrics.islandHandleHeight : DashMetrics.editHeaderHeight
    readonly property real pillOverhang: editMode ? DashMetrics.islandPillOverhang : 0
    readonly property int panelColumns: DashMetrics.panelColumnsFor(entryId)
    readonly property int contentRows: DashMetrics.rowsForHeight(tabHeight)
    readonly property int panelRows: Math.max(DashMetrics.panelFloorRowsFor(entryId), contentRows)

    signal windowRequested(string windowName)

    readonly property QtObject resizeHost: QtObject {
        readonly property real reserve: root.controller.dockReserveFor(root.activityId)
        readonly property real renderedAlignedX: (root.resizeGeometry?.renderedX ?? 0) + body.x
        readonly property real renderedAlignedY: root.resizeGeometry?.renderedY ?? 0

        function alignedXFor(width) {
            return (root.resizeGeometry?.screenXFor(width + reserve) ?? 0) + (root.dockSide === "left" ? reserve : 0);
        }
    }

    readonly property DPanelResizer panelResizer: DPanelResizer {
        popout: root.resizeHost
        stepWidth: DashMetrics.preferredColumnWidth + DashMetrics.gridGap
        widthFor: columns => Math.min(root.controller.dashboardAvailableWidth, DashMetrics.widthFor(SettingsData.showWeekNumber, undefined, columns))
        currentStep: () => root.panelColumns
        currentRows: () => root.panelRows
        minStep: Math.max(DashMetrics.minimumGridColumns, root.tab?.usedColumns ?? 0)
        maxStep: root.controller.dashboardColumnCap
        rowUnit: DashMetrics.gridRowUnit + DashMetrics.gridGap
        minRows: root.contentRows
        maxRows: Math.min(root.controller.dashboardRowBudget, DashMetrics.maximumGridRows)
        onPreview: (columns, rows) => DashMetrics.panelPreview = {
                "id": root.entryId,
                "columns": columns,
                "rows": rows
            }
        onCommitted: (columns, rows, columnsChanged, rowsChanged) => {
            const values = {};
            if (columnsChanged)
                values.panelColumns = columns;
            if (rowsChanged)
                values.panelRows = DashMetrics.panelRowsToStore(root.entryId, rows, root.contentRows);
            DashRegistry.setOptions(root.entryId, values);
            DashMetrics.panelPreview = null;
        }
        onCanceled: DashMetrics.panelPreview = null
    }

    readonly property bool panelResizing: panelResizer.resizing
    onPanelResizingChanged: root.controller.panelResizing = panelResizing

    clip: true
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    function setEditMode(on) {
        root.controller.setDashEditing(root.activityId, on);
    }

    // Edit room above the reported height; docked, the tab bar or handle replaces the edit header.
    function editRoom() {
        return Math.max(0, DashMetrics.islandEditChromeHeight + root.headerHeight - DashMetrics.editHeaderHeight - root.chromeHeight);
    }

    function syncEditing() {
        if (root.editMode) {
            if (root.controller.dashEditLayout === "") {
                const width = root.controller.dashboardWidthFor(root.activityId);
                root.controller.dashEditLayout = root.controller.pickDockSide(width, root.resizeGeometry?.screenXFor(width) ?? 0, root.controller.screen?.width ?? 0, root.controller.dashboardAvailableHeight - root.controller.controlCenterSheetInset);
            }
            root.controller.editDockSide = root.dockSide;
            root.controller.setEditing(root.activityId, true, root.editRoom());
            return;
        }
        if (root.controller.editingActivity === root.activityId)
            root.controller.editDockSide = "";
        root.controller.setEditing(root.activityId, false);
    }

    function focusFace() {
        headerActions.clearFocus();
        sheetHandle.focusTarget.focus = false;
        if (tabBarLoader.item)
            tabBarLoader.item.focus = false;
        tabLoader.focus = false;
        if (root.controller.dashNavigationFocused && tabBarLoader.item && (!root.editMode || root.docked)) {
            tabBarLoader.item.forceActiveFocus(Qt.OtherFocusReason);
            return true;
        }
        root.forceActiveFocus(Qt.OtherFocusReason);
        if (!root.editMode)
            root.tab?.restoreFocus?.();
        return true;
    }

    function reportHeight() {
        root.controller.setDashboardContentHeight(root.activityId, root.contentHeight + root.chromeHeight);
    }

    onContentHeightChanged: reportHeight()
    onChromeHeightChanged: reportHeight()
    onLiveChanged: {
        if (live)
            return;
        editSession.popoverRequested = false;
        headerActions.closeMenu();
        tabOptions.dismiss();
    }
    // A switched-to face stays disabled until its fade is halfway, so take focus then.
    onEnabledChanged: {
        if (enabled && live && root.controller.keyboardDismissRequested && !activeFocus)
            focusFace();
    }
    onDockedChanged: {
        // Ending the session clears the layout before editMode updates; re-syncing then would pick a new layout.
        if (editMode && editSession.active)
            syncEditing();
    }
    onEditModeChanged: {
        syncEditing();
        if (!editMode)
            panelResizer.cancel();
        Qt.callLater(() => {
            if (root.live)
                root.focusFace();
        });
    }

    Keys.onPressed: event => event.accepted = keyboard.handleKeyEvent(event)

    DashKeyboard {
        id: keyboard

        active: root.live
        editable: root.entryId !== ""
        editMode: root.editMode
        optionsShown: tabOptions.shown
        menuOpen: headerActions.menuOpen
        panelResizing: root.panelResizer.resizing
        canUndo: root.editSession.canUndo
        tabItem: root.tab
        contentScope: tabLoader
        contentTarget: root.tab?.focusTarget ?? null
        headerTargets: root.docked ? [tabBarLoader.item] : root.editMode ? headerActions.focusTargets : [tabBarLoader.item, sheetHandle.focusTarget]
        panelTargets: root.editPanel?.focusTargets ?? []
        panelDetailShown: (root.editPanel?.menuOpen ?? false) || root.popoverShown || (root.editPanel?.canGoBack ?? false)
        tabsShown: root.tabsShown
        onTabCycleRequested: direction => root.controller.cycleDashTab(direction, tabBarLoader.item?.activeFocus ?? false)
        onEditModeRequested: on => root.setEditMode(on)
        onPanelBackRequested: {
            if (root.editPanel?.menuOpen)
                root.editPanel.closeMenu();
            else if (root.popoverShown)
                root.editSession.closePopover();
            else
                root.editPanel?.back();
        }
        onDiscardRequested: headerActions.discard()
        onUndoRequested: root.editSession.undo()
        onLeaveRequested: root.focusFace()
        onOptionsDismissRequested: tabOptions.dismiss()
        onCloseRequested: root.controller.requestCollapse()
    }

    Item {
        id: body

        x: root.dockSide === "left" ? Math.max(0, root.width - width) : 0
        width: root.bodyWidth
        height: root.height

        Item {
            id: header
            enabled: !tabOptions.shown && !headerActions.menuOpen
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: root.editMode ? DashMetrics.islandEditHeaderInset : root.tabsShown ? DashMetrics.contentPadding : 0
                leftMargin: DashMetrics.contentPadding
                rightMargin: DashMetrics.contentPadding
            }
            height: root.headerHeight

            Loader {
                id: tabBarLoader
                anchors.fill: parent
                active: root.tabsShown
                visible: root.tabBarShown

                sourceComponent: DNavigationBar {
                    id: tabBar

                    editable: !root.editMode
                    evenlySpaced: SettingsData.dashTabsEvenlySpaced
                    currentIndex: root.controller.dashTabIds.indexOf(root.entryId)
                    nextFocusTarget: root.docked ? null : root.tab?.focusTarget ?? null
                    previousFocusTarget: root.docked ? null : root.tab?.focusTarget ?? null
                    model: root.controller.dashTabBarModel
                    onEditRequested: root.setEditMode(true)
                    onActivated: index => {
                        const id = root.controller.dashTabIds[index];
                        if (id === undefined || id === root.entryId)
                            return;
                        if (DashRegistry.isAction(id)) {
                            root.windowRequested(id);
                            return;
                        }
                        root.controller.requestDashTab(id, tabBar.activeFocus);
                    }
                }
            }

            DashSheetHandle {
                id: sheetHandle
                anchors.fill: parent
                visible: root.handleHeader
                editable: root.entryId !== "" && !root.editMode
                onEditRequested: root.setEditMode(true)
            }

            DashPageActions {
                id: headerActions
                session: root.editSession
                visible: root.editMode
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width, implicitWidth)
                height: parent.height
                availableWidth: parent.width
                transientSurfaceTracker: root.controller.transientSurfaces
                entryId: root.entryId
                tabItem: root.tab
                editMode: root.editMode
                panelResizable: true
                controlsShown: !root.docked
                addHandler: root.panelMode ? (anchor => root.editSession.togglePopover()) : null
                onOptionsRequested: {
                    if (root.panelMode)
                        root.editSession.presentPageOptions(root.entryId, !!root.tab?.editGrid);
                    else
                        tabOptions.presentFor(root.entryId);
                }
                onFinished: root.setEditMode(false)
            }
        }

        DFlickable {
            id: pages
            enabled: !tabOptions.shown && !headerActions.menuOpen
            showScrollBar: false
            anchors {
                top: header.bottom
                topMargin: root.editMode ? DashMetrics.contentPadding : root.tabsShown ? DashMetrics.contentGap : 0
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                leftMargin: DashMetrics.contentPadding
                rightMargin: DashMetrics.contentPadding
                bottomMargin: root.editMode ? DashMetrics.islandEditBottomInset : DashMetrics.contentPadding
            }
            contentHeight: tabLoader.y + tabLoader.height
            clip: contentHeight > height

            Loader {
                id: tabLoader
                y: root.pillOverhang
                width: pages.width
                height: Math.max(pages.height - y, root.tabHeight)
                active: root.contentStaged
                asynchronous: true
                visible: status === Loader.Ready
                sourceComponent: root.tabComponent
                onActiveFocusChanged: {
                    if (activeFocus)
                        root.controller.dashNavigationFocused = false;
                }
                onLoaded: {
                    root.reportHeight();
                    if (root.live)
                        root.focusFace();
                }
            }
        }

        Connections {
            target: root.tab
            ignoreUnknownSignals: true
            function onNavFocusRequested(backwards) {
                keyboard.focusHeader(backwards);
            }
        }

        DGridEditChrome {
            id: panelChrome

            anchors.fill: parent
            anchors.margins: PopoutMetrics.panelChromeInset - contentInset
            z: 2
            visible: root.editMode
            edgeResize: true
            removable: false
            cornerRadius: Math.max(0, Theme.windowRadius - PopoutMetrics.panelChromeInset)
            buttonSize: PopoutMetrics.chromeButtonSize
            iconSize: PopoutMetrics.chromeIconSize
            resizing: root.panelResizer.resizing
            atDefault: root.panelColumns === DashMetrics.defaultGridColumns && root.panelRows === DashMetrics.defaultPanelRows(root.entryId, root.contentRows)
            sizeText: root.panelColumns + "×" + root.panelRows
            onResizeStarted: (px, py, signX) => root.panelResizer.begin(px, py, signX)
            onResizeMoved: (px, py) => root.panelResizer.move(px, py)
            onResizeEnded: root.panelResizer.end()
            onResizeCanceled: root.panelResizer.cancel()
        }

        DSpinner {
            anchors.centerIn: pages
            size: DashMetrics.spinnerSize
            visible: !tabLoader.visible
        }

        DashOptionsSheet {
            id: tabOptions
            backdrop: pages
            tabScope: true
            onDismissed: root.focusFace()
        }
    }

    Loader {
        id: panelLoader

        readonly property real popoverWidth: Math.min(CcMetrics.dockedPanelWidth, body.width - CcMetrics.sheetPadding * 2)

        x: {
            if (!root.docked)
                return body.x + (I18n.isRtl ? body.width - width - CcMetrics.sheetPadding : CcMetrics.sheetPadding);
            const inner = CcMetrics.dockedPanelGap - CcMetrics.islandInset;
            return root.dockSide === "left" ? body.x - inner - width : body.x + body.width + inner;
        }
        y: root.docked ? CcMetrics.islandInset : root.popoverTop
        width: root.docked ? CcMetrics.dockedPanelWidth : popoverWidth
        height: root.docked ? root.height - CcMetrics.islandInset * 2 : root.height - root.popoverTop - CcMetrics.sheetPadding
        z: DashMetrics.overlayZ
        active: root.editMode && root.tab !== null && (root.docked || root.popoverShown)
        enabled: !tabOptions.shown && !headerActions.menuOpen

        sourceComponent: DashEditPanel {
            session: root.editSession
            tabItem: root.tab
            entryId: root.entryId
            pageActions: headerActions
            floating: !root.docked
            fadeOut: root.tab?.cardInteracting ?? false
            surfaceColor: root.docked ? Theme.withAlpha(CcMetrics.dialogColor, 1) : Theme.withAlpha(Theme.foregroundColor(Theme.cardSurface), 1)
            radius: root.docked ? Theme.windowRadius : Theme.cornerRadiusL
            transientSurfaceTracker: root.controller.transientSurfaces
            onCloseRequested: root.editSession.closePopover()
            onFinishRequested: root.setEditMode(false)
            onDiscardRequested: headerActions.discard()
        }
    }

    Binding {
        target: root.editSession
        property: "panel"
        value: root.panelFits
        when: root.editMode
        restoreMode: Binding.RestoreNone
    }

    Component.onDestruction: {
        if (panelResizing) {
            root.controller.panelResizing = false;
            DashMetrics.panelPreview = null;
        }
        if (root.editMode)
            root.controller.setDashEditing(root.activityId, false);
        if (root.controller.editingActivity === root.activityId)
            root.controller.editDockSide = "";
        root.controller.setEditing(root.activityId, false);
    }

    Component.onCompleted: {
        root.contentStaged = true;
        root.reportHeight();
        // A face created for a tab switch starts in edit mode without a change signal.
        if (root.editMode)
            root.syncEditing();
    }
}
