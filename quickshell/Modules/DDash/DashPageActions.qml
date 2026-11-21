pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter.Widgets
import qs.Modules.DDash.Overview
import "utils/cards.js" as CardUtils

Item {
    id: root

    required property string entryId
    property var transientSurfaceTracker: null
    property var tabItem: null
    property bool vertical: false
    property bool editMode: false
    property bool panelResizable: false
    property real availableWidth: Infinity
    readonly property bool hasWidgets: entryId === DashRegistry.overviewId || typeof tabItem?.clearWidgets === "function"
    readonly property bool menuOpen: customMenu.open
    readonly property bool hasCustomActions: customMenu.visibleItems.length > 0
    readonly property var focusTargets: editControls.focusTargets
    property string editSnapshot: ""
    property string undoBase: ""
    property var undoStack: []
    readonly property bool canUndo: undoStack.length > 0
    readonly property int undoLimit: 50
    readonly property var editKeys: ["dashCards", "dashOptions"]

    signal optionsRequested
    signal finished

    implicitWidth: vertical ? Theme.navigationRailWidth : editControls.implicitWidth
    implicitHeight: editControls.implicitHeight

    onEditModeChanged: beginEdit()
    Component.onCompleted: beginEdit()

    function beginEdit() {
        editSnapshot = editMode ? currentState() : "";
        undoBase = editSnapshot;
        undoStack = [];
    }

    function trackEdit() {
        if (!editMode)
            return;
        const state = currentState();
        if (state === undoBase)
            return;
        undoStack = undoStack.concat([undoBase]).slice(-undoLimit);
        undoBase = state;
    }

    function applyState(state) {
        const wanted = JSON.parse(state);
        for (const key of editKeys) {
            if (JSON.stringify(SettingsData[key]) !== JSON.stringify(wanted[key]))
                SettingsData.set(key, wanted[key]);
        }
    }

    function undo() {
        if (undoStack.length === 0)
            return;
        undoBase = undoStack[undoStack.length - 1];
        undoStack = undoStack.slice(0, -1);
        applyState(undoBase);
    }

    function currentState() {
        const state = {};
        for (const key of editKeys)
            state[key] = SettingsData[key];
        return JSON.stringify(state);
    }

    function discard() {
        if (editSnapshot !== "")
            applyState(editSnapshot);
        finished();
    }

    function closeMenu() {
        editControls.cancelConfirmation();
        customMenu.close();
    }

    function clearFocus() {
        editControls.clearFocus();
    }

    function reset() {
        if (panelResizable)
            DashRegistry.resetPanelSize(entryId);
        if (entryId === DashRegistry.overviewId) {
            CardUtils.resetToDefault();
            return;
        }
        tabItem?.resetWidgets?.();
    }

    function clear() {
        if (entryId === DashRegistry.overviewId) {
            CardUtils.clearAll();
            return;
        }
        tabItem?.clearWidgets?.();
    }

    // Deferred, so a reset that writes both keys lands as one undo step.
    Connections {
        target: SettingsData
        enabled: root.editMode

        function onDashCardsChanged() {
            Qt.callLater(root.trackEdit);
        }

        function onDashOptionsChanged() {
            Qt.callLater(root.trackEdit);
        }
    }

    CcMenu {
        id: customMenu
        transientSurfaceTracker: root.transientSurfaceTracker
        items: root.tabItem?.menuActions ?? []
    }

    DashEditControls {
        id: editControls
        anchors.centerIn: parent
        width: root.width
        height: root.height
        visible: root.editMode
        vertical: root.vertical
        availableWidth: root.availableWidth
        canAdd: (root.tabItem?.addable?.length ?? 0) > 0
        hasWidgets: root.hasWidgets
        hasOptions: DashRegistry.hasOptions(root.entryId, true)
        hasCustomActions: root.hasCustomActions
        onActionsRequested: anchor => customMenu.openAt(anchor)
        onAddRequested: anchor => root.tabItem?.openAddMenu(anchor)
        onOptionsRequested: root.optionsRequested()
        onResetRequested: root.reset()
        onClearRequested: root.clear()
        onDiscardRequested: root.discard()
        onFinished: root.finished()
    }
}
