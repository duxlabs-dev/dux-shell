pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.DDash
import qs.Modules.DDash.Overview

FocusScope {
    id: root

    required property var controller
    required property string activityId
    required property Component tabComponent
    property string entryId: activityId
    property QtObject resizeGeometry: null
    property bool editMode: false
    property bool contentStaged: false
    readonly property bool live: root.controller.expanded && root.controller.activeActivity === root.activityId
    readonly property var tab: tabLoader.item
    readonly property real tabHeight: tab?.implicitHeight ?? 0
    readonly property real contentHeight: DashMetrics.panelHeightFor(entryId, tabHeight)
    readonly property bool tabsShown: root.controller.dashTabsShownFor(root.activityId)
    readonly property real chromeHeight: DashMetrics.islandChromeHeight(tabsShown ? (tabBarLoader.item?.implicitHeight ?? Theme.navigationHeight) : 0)
    readonly property bool handleHeader: !root.editMode && !root.tabsShown
    readonly property real pillOverhang: editMode ? DashMetrics.islandPillOverhang : 0
    readonly property int panelColumns: DashMetrics.panelColumnsFor(entryId)
    readonly property int contentRows: DashMetrics.rowsForHeight(tabHeight)
    readonly property int panelRows: Math.max(DashMetrics.panelFloorRowsFor(entryId), contentRows)

    signal windowRequested(string windowName)

    readonly property QtObject resizeHost: QtObject {
        readonly property real renderedAlignedX: root.resizeGeometry?.renderedX ?? 0
        readonly property real renderedAlignedY: root.resizeGeometry?.renderedY ?? 0

        function alignedXFor(width) {
            return root.resizeGeometry?.screenXFor(width) ?? 0;
        }
    }

    readonly property DPanelResizer panelResizer: DPanelResizer {
        popout: root.resizeHost
        stepWidth: DashMetrics.preferredColumnWidth + DashMetrics.gridGap
        widthFor: columns => Math.min(root.controller.dashboardAvailableWidth, DashMetrics.widthFor(SettingsData.showWeekNumber, undefined, columns))
        currentStep: () => root.panelColumns
        currentRows: () => root.panelRows
        minStep: DashMetrics.minimumGridColumns
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

    clip: true
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    function focusFace() {
        pageActions.clearFocus();
        sheetHandle.focusTarget.focus = false;
        if (tabBarLoader.item)
            tabBarLoader.item.focus = false;
        tabLoader.focus = false;
        if (root.controller.dashNavigationFocused && tabBarLoader.item && !root.editMode) {
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
        editMode = false;
        pageActions.closeMenu();
        tabOptions.dismiss();
    }
    // A switched-to face stays disabled until its fade is halfway, so take focus then.
    onEnabledChanged: {
        if (enabled && live && root.controller.keyboardDismissRequested && !activeFocus)
            focusFace();
    }
    onEditModeChanged: {
        root.controller.setEditing(root.activityId, editMode, Math.max(0, DashMetrics.islandEditChromeHeight - root.chromeHeight));
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
        menuOpen: pageActions.menuOpen
        tabItem: root.tab
        contentScope: tabLoader
        contentTarget: root.tab?.focusTarget ?? null
        headerTargets: root.editMode ? pageActions.focusTargets : [tabBarLoader.item, sheetHandle.focusTarget]
        tabsShown: root.tabsShown
        onTabCycleRequested: direction => root.controller.cycleDashTab(direction, tabBarLoader.item?.activeFocus ?? false)
        onEditModeRequested: on => root.editMode = on
        onLeaveRequested: root.focusFace()
        onOptionsDismissRequested: tabOptions.dismiss()
        onCloseRequested: root.controller.requestCollapse()
    }

    Item {
        id: header
        enabled: !tabOptions.shown && !pageActions.menuOpen
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: root.editMode ? DashMetrics.islandEditHeaderInset : root.tabsShown ? DashMetrics.contentPadding : 0
            leftMargin: DashMetrics.contentPadding
            rightMargin: DashMetrics.contentPadding
        }
        height: root.editMode ? DashMetrics.editHeaderHeight : root.tabsShown ? (tabBarLoader.item?.implicitHeight ?? Theme.navigationHeight) : DashMetrics.islandHandleHeight

        Loader {
            id: tabBarLoader
            anchors.fill: parent
            active: root.tabsShown
            visible: !root.editMode

            sourceComponent: DNavigationBar {
                id: tabBar

                editable: true
                evenlySpaced: SettingsData.dashTabsEvenlySpaced
                currentIndex: root.controller.dashTabIds.indexOf(root.entryId)
                nextFocusTarget: root.tab?.focusTarget ?? null
                previousFocusTarget: root.tab?.focusTarget ?? null
                model: root.controller.dashTabBarModel
                onEditRequested: root.editMode = true
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
            editable: root.entryId !== ""
            onEditRequested: root.editMode = true
        }

        DashPageActions {
            id: pageActions
            visible: root.editMode
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width, implicitWidth)
            height: parent.height
            transientSurfaceTracker: root.controller.transientSurfaces
            entryId: root.entryId
            tabItem: root.tab
            editMode: root.editMode
            panelResizable: true
            onOptionsRequested: tabOptions.presentFor(root.entryId)
            onFinished: root.editMode = false
        }
    }

    DFlickable {
        id: pages
        enabled: !tabOptions.shown && !pageActions.menuOpen
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

    Component.onDestruction: root.controller.setEditing(root.activityId, false)

    Component.onCompleted: {
        root.contentStaged = true;
        root.reportHeight();
    }
}
