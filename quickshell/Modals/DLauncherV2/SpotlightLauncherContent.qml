pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modals.DLauncherV2.Components
import "../../Common/LauncherKeybinds.js" as LauncherKeybinds

FocusScope {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var parentModal: null
    property alias searchField: searchInput
    property var controllerOverride: null
    readonly property var controller: controllerOverride ?? searchController
    readonly property alias activeContextMenu: contextMenu
    property var transientSurfaceTracker: null
    property bool showResultsWithoutQuery: false
    property bool suspendSearchUpdates: false
    property real maxResultsHeight: 0
    // Off for hosts that animate their own size, where this would only slide the bottom fade.
    property bool resizeAnimated: true
    property real resultsInset: LauncherMetrics.spotlightInset

    property bool editMode: false
    property var editingApp: null
    property string editAppId: ""

    readonly property bool _hasQuery: root.showResultsWithoutQuery || searchInput.text.length > 0 || root.controller.searchMode === "dmenu"
    readonly property real _searchBarH: LauncherMetrics.pillHeight
    readonly property real _searchAreaH: _searchBarH
    readonly property alias searchAreaHeight: root._searchAreaH
    readonly property real actionPanelHeight: actionPanel.height
    readonly property real _statusH: Theme.listItemTwoLineHeight + Theme.spacingXL
    readonly property bool _firstSectionShowsHeader: !!(root.controller.sections?.[0]?.title?.length > 0)
    readonly property real _resultsTopGap: _firstSectionShowsHeader ? LauncherMetrics.resultsGap : root.resultsInset
    readonly property real _rowsHeightBudget: _resultsTopGap + ((root.controller.searchMode === "dmenu" && root.controller.dmenuLines > 0) ? (root.controller.dmenuLines * (LauncherMetrics.rowHeight + LauncherMetrics.rowGap) + (_firstSectionShowsHeader ? LauncherMetrics.sectionBand : 0) + LauncherMetrics.fadeLength) : LauncherMetrics.maxResultsHeight)
    readonly property real _maxResultsH: root.maxResultsHeight > 0 ? root.maxResultsHeight : Math.max(0, Math.min(_rowsHeightBudget + resultsList.bottomInset, (parentModal?.screenHeight ?? Theme.mediumBreakpoint) - (parentModal?.modalY ?? 0) - LauncherMetrics.pillHeight - actionPanel.height - Theme.spacingL))
    readonly property real _resultsContentH: resultsList.contentHeight > 0 ? _resultsTopGap + resultsList.contentHeight + resultsList.bottomInset : _statusH
    readonly property real _resultsH: _hasQuery ? Math.min(_resultsContentH, _resultsTopGap + resultsList.fittedHeight + resultsList.bottomInset) : 0
    readonly property int _resizeDuration: Theme.expressiveDurations.expressiveFastSpatial
    readonly property real _frameClipRadius: Math.max(0, (parentModal?.frameBottomRadius ?? 0) - resultsInset)
    readonly property real _editAvailableH: maxResultsHeight > 0 ? maxResultsHeight + _searchAreaH : Math.max(LauncherMetrics.maxResultsHeight, (parentModal?.screenHeight ?? Theme.mediumBreakpoint) - (parentModal?.modalY ?? 0) - Theme.spacingL)
    readonly property real _editH: Math.min(editLoader.implicitHeight, _editAvailableH)

    implicitHeight: editMode ? _editH + Theme.spacingM * 2 : _searchAreaH + mesgRow.height + resultsContainer.height + actionPanel.height

    property bool _animateResize: false

    Component.onCompleted: resizeAnimEnableTimer.restart()

    Timer {
        id: resizeAnimEnableTimer
        interval: Theme.expressiveDurations.expressiveEffects
        onTriggered: root._animateResize = true
    }

    function resetScroll() {
        resultsList.resetScroll();
    }

    function resetSearch() {
        if (root.controller.searchMode === "dmenu") {
            root.controller.setSearchQuery("");
            return;
        }
        root.controller.reset();
        if (root.showResultsWithoutQuery)
            root.controller.performSearch();
    }

    function closeTransientUi() {
        transientSurfaceTracker?.closeAll?.();
        actionPanel.hide();
        root._clearEditState();
        root.enabled = true;
    }

    function _clearEditState() {
        editMode = false;
        editingApp = null;
        editAppId = "";
    }

    function openEditMode(app) {
        if (!app)
            return;
        editingApp = app;
        editAppId = app.id || app.execString || app.exec || "";
        editMode = true;
    }

    function closeEditMode() {
        root._clearEditState();
        Qt.callLater(root._focusSearch);
    }

    function _focusSearch() {
        searchInput.forceActiveFocus();
        searchInput.cursorPosition = searchInput.text.length;
    }

    function _showContextMenu(item, sceneX, sceneY, fromKeyboard) {
        if (!item || !contextMenu.hasContextMenuActions(item))
            return;
        const localPos = root.mapFromItem(null, sceneX, sceneY);
        contextMenu.show(localPos.x, localPos.y, item, fromKeyboard);
    }

    function _handleKey(event) {
        if (root.editMode) {
            if (event.key === Qt.Key_Escape) {
                root.closeEditMode();
                event.accepted = true;
            }
            return;
        }

        const hasCtrl = event.modifiers & Qt.ControlModifier;

        if (root.controller.searchMode === "dmenu") {
            const kbN = root.controller.matchDmenuKeybind(event);
            if (kbN > 0) {
                root.controller.acceptDmenuViaKeybind(kbN);
                event.accepted = true;
                return;
            }
        }

        const launcherAction = LauncherKeybinds.actionForEvent(event, SettingsData.launcherKeybinds);
        if (launcherAction) {
            actionPanel.hide();
            if (launcherAction.mode)
                root.controller.setMode(launcherAction.mode);
            else
                _cycleCategory(launcherAction.id === "previousMode");
            event.accepted = true;
            return;
        }

        switch (event.key) {
        case Qt.Key_Escape:
            if (actionPanel.expanded) {
                actionPanel.hide();
                event.accepted = true;
                return;
            }
            if (root.controller.clearPluginFilter()) {
                event.accepted = true;
                return;
            }
            if (root.parentModal?.attemptUserCancel)
                root.parentModal.attemptUserCancel();
            else
                root.parentModal?.hide();
            event.accepted = true;
            return;
        case Qt.Key_Backspace:
            if (searchInput.text.length === 0) {
                if (root.controller.clearPluginFilter()) {
                    event.accepted = true;
                    return;
                }
                if (root.controller.autoSwitchedToFiles) {
                    root.controller.restorePreviousMode();
                    event.accepted = true;
                    return;
                }
            }
            event.accepted = false;
            return;
        case Qt.Key_Down:
            root.controller.selectNext();
            event.accepted = true;
            return;
        case Qt.Key_Up:
            root.controller.selectPrevious();
            event.accepted = true;
            return;
        case Qt.Key_Right:
        case Qt.Key_Left:
            if (root.controller.getCurrentSectionViewMode() === "list")
                break;
            if ((event.key === Qt.Key_Right) !== I18n.isRtl)
                root.controller.selectRight();
            else
                root.controller.selectLeft();
            event.accepted = true;
            return;
        case Qt.Key_H:
        case Qt.Key_L:
            if (!hasCtrl || root.controller.getCurrentSectionViewMode() === "list")
                break;
            if ((event.key === Qt.Key_L) !== I18n.isRtl)
                root.controller.selectRight();
            else
                root.controller.selectLeft();
            event.accepted = true;
            return;
        case Qt.Key_PageDown:
            root.controller.selectPageDown(resultsList.pageRows);
            event.accepted = true;
            return;
        case Qt.Key_PageUp:
            root.controller.selectPageUp(resultsList.pageRows);
            event.accepted = true;
            return;
        case Qt.Key_J:
            if (hasCtrl) {
                root.controller.selectNext();
                event.accepted = true;
                return;
            }
            break;
        case Qt.Key_K:
            if (hasCtrl) {
                root.controller.selectPrevious();
                event.accepted = true;
                return;
            }
            break;
        case Qt.Key_N:
        case Qt.Key_P:
            if (!hasCtrl)
                break;
            if (event.key === Qt.Key_N)
                root.controller.selectNextSection();
            else
                root.controller.selectPreviousSection();
            event.accepted = true;
            return;
        case Qt.Key_Tab:
            if (!hasCtrl && actionPanel.hasActions) {
                actionPanel.expanded ? actionPanel.cycleAction() : actionPanel.show();
            }
            event.accepted = true;
            return;
        case Qt.Key_Backtab:
            if (!hasCtrl && actionPanel.hasActions) {
                actionPanel.expanded ? actionPanel.cycleAction(true) : actionPanel.show();
            }
            event.accepted = true;
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (event.modifiers & Qt.ShiftModifier) {
                if (root.controller.searchMode === "dmenu" && root.controller.dmenuMultiSelect)
                    root.controller.toggleDmenuMultiSelectHighlighted();
                else
                    root.controller.pasteSelected();
            } else if (actionPanel.expanded && actionPanel.selectedActionIndex > 0) {
                actionPanel.executeSelectedAction();
            } else {
                root.controller.executeSelected(!!(event.modifiers & Qt.ControlModifier));
            }
            event.accepted = true;
            return;
        case Qt.Key_Menu:
        case Qt.Key_F10:
            if (contextMenu.hasContextMenuActions(root.controller.selectedItem)) {
                const scenePos = resultsList.getSelectedItemPosition();
                _showContextMenu(root.controller.selectedItem, scenePos.x, scenePos.y, true);
                event.accepted = true;
                return;
            }
            break;
        }

        event.accepted = false;
    }

    Controller {
        id: searchController
        active: !root.controllerOverride && (root.parentModal ? (root.parentModal.spotlightOpen || root.parentModal.isClosing) : true)
        viewModeContext: "spotlight"
        forceLinearNavigation: false
    }

    LauncherContextMenu {
        id: contextMenu
        parent: root
        controller: root.controller
        searchField: searchInput
        parentHandler: root
        transientSurfaceTracker: root.transientSurfaceTracker

        onEditAppRequested: app => root.openEditMode(app)
    }

    Connections {
        target: root.parentModal
        ignoreUnknownSignals: true

        function onSpotlightOpenChanged() {
            if (!root.parentModal?.spotlightOpen)
                root.closeTransientUi();
        }

        function onContentVisibleChanged() {
            if (!root.parentModal?.contentVisible) {
                root.closeTransientUi();
                return;
            }
            root._animateResize = false;
            resizeAnimEnableTimer.restart();
        }
    }

    Connections {
        target: root.controller

        function onSelectedItemChanged() {
            if (actionPanel.expanded)
                actionPanel.hide();
        }

        function onItemExecuted() {
            root.parentModal?.hide();
            CompositorService.closeNiriOverviewOnWindowFocus();
        }
        function onModeChanged(mode, userInitiated) {
            if (!userInitiated || !SettingsData.rememberLastMode)
                return;
            SessionData.setLauncherLastMode(mode);
        }
        function onSearchQueryRequested(query) {
            searchInput.text = query;
            root._focusSearch();
        }
    }

    Item {
        id: searchBarItem
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root._searchAreaH
        visible: !root.editMode

        LauncherSearchField {
            id: searchInput
            readonly property bool _isDmenu: root.controller.searchMode === "dmenu"
            pluginName: _isDmenu ? root.controller.dmenuPrompt : root.controller.activePluginName
            pluginIcon: _isDmenu ? root.controller.dmenuIcon : (root.controller.activePluginId ? root.controller.getPluginMetadata(root.controller.activePluginId).icon : "")
            pluginIconVisible: _isDmenu ? !!root.controller.dmenuIcon : true
            anchors.fill: parent
            mode: root.controller.searchMode
            showModes: SettingsData.spotlightBarShowModeChips || root._hasQuery
            flat: true
            onModeSelected: mode => root._selectMode(mode)
            placeholderText: _isDmenu ? root.controller.dmenuPlaceholder : I18n.tr("Spotlight Search")
            echoMode: (_isDmenu && root.controller.dmenuPassword) ? TextInput.Password : TextInput.Normal
            hidePlaceholderOnFocus: false
            ignoreUpDownKeys: true
            ignoreTabKeys: true
            keyForwardTargets: [searchKeyHandler]

            onTextChanged: {
                if (root.suspendSearchUpdates)
                    return;
                actionPanel.hide();
                if (text.length > 0) {
                    root.controller.setSearchQuery(text);
                    return;
                }
                root.resetSearch();
            }

            Item {
                id: searchKeyHandler
                Keys.onPressed: event => root._handleKey(event)
            }
        }
    }

    Item {
        id: mesgRow
        readonly property bool _visible: root.controller.searchMode === "dmenu" && root.controller.dmenuMesg.length > 0
        anchors.top: searchBarItem.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.resultsInset
        anchors.rightMargin: root.resultsInset
        height: _visible ? mesgText.implicitHeight + Theme.spacingS * 2 : 0
        visible: _visible && !root.editMode

        StyledText {
            id: mesgText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Theme.spacingS
            text: root.controller.dmenuMesg
            wrapMode: Text.WordWrap
            color: Theme.onSurfaceVariant
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    Rectangle {
        anchors.top: mesgRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.outlineWidth
        z: 1
        color: Theme.outlineVariant
        visible: !root.editMode && root._hasQuery && !(Theme.focusRingWidth > 0 && searchInput.getActiveFocus())
    }

    ClippingRectangle {
        id: resultsContainer
        anchors.top: mesgRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.resultsInset
        anchors.rightMargin: root.resultsInset
        color: "transparent"
        bottomLeftRadius: actionPanel.height > 0 ? 0 : root._frameClipRadius
        bottomRightRadius: bottomLeftRadius
        height: root._resultsH
        visible: !root.editMode

        Behavior on height {
            enabled: root.resizeAnimated && root._animateResize
            NumberAnimation {
                duration: root._resizeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.standard
            }
        }

        ResultsList {
            id: resultsList
            focusReturnTarget: searchInput
            keyForwardTargets: [searchKeyHandler]
            readonly property real bottomInset: Theme.spacingS
            availableHeight: Math.max(0, root._maxResultsH - root._resultsTopGap - bottomInset)
            resizing: actionPanel.animating
            anchors.fill: parent
            anchors.topMargin: root._resultsTopGap
            controller: root.controller
            showEmptyState: root._hasQuery
            transientSurfaceTracker: root.transientSurfaceTracker

            onItemRightClicked: (index, item, sceneX, sceneY) => {
                root._showContextMenu(item, sceneX, sceneY, false);
            }
        }
    }

    ActionPanel {
        id: actionPanel
        anchors.top: resultsContainer.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        selectedItem: root.controller.selectedItem
        controller: root.controller
        visible: !root.editMode
    }

    Loader {
        id: editLoader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingM
        height: root.editMode ? root._editH : 0
        active: root.editMode
        visible: active
        focus: root.editMode

        sourceComponent: AppEditView {
            focus: true
            editingApp: root.editingApp
            editAppId: root.editAppId
            onCloseRequested: root.closeEditMode()
        }

        onLoaded: item.loadOverride()
    }

    function _cycleCategory(reverse) {
        const modes = searchInput.modes;
        const idx = (searchInput.modeIndex + (reverse ? modes.length - 1 : 1)) % modes.length;
        _selectMode(modes[idx].mode);
    }

    function _selectMode(mode) {
        root.controller.setMode(mode, false);
        if (root._hasQuery)
            root.controller.setSearchQuery(searchInput.text);
        root._focusSearch();
    }
}
