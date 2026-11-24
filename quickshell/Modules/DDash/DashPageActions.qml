pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter.Widgets
import qs.Modules.DDash.Overview
import "utils/cards.js" as CardUtils
import "../../Common/EditHistory.js" as EditHistory

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
    property bool batching: false
    readonly property bool canUndo: undoStack.length > 0
    readonly property var editKeys: ["dashCards", "dashOptions"]

    signal optionsRequested
    signal finished

    implicitWidth: vertical ? Theme.navigationRailWidth : editControls.implicitWidth
    implicitHeight: editControls.implicitHeight

    onEditModeChanged: beginEdit()
    Component.onCompleted: beginEdit()

    function beginEdit() {
        editSnapshot = editMode ? EditHistory.snapshot(SettingsData, editKeys) : "";
        undoBase = editSnapshot;
        undoStack = [];
    }

    function trackEdit() {
        if (!editMode || batching)
            return;
        const state = EditHistory.snapshot(SettingsData, editKeys);
        if (state === undoBase)
            return;
        undoStack = EditHistory.push(undoStack, undoBase);
        undoBase = state;
    }

    // Keeps the intermediate states of a multi-write change out of the undo stack.
    function batchEdit(change) {
        batching = true;
        change();
        batching = false;
        trackEdit();
    }

    function undo() {
        if (undoStack.length === 0)
            return;
        undoBase = undoStack[undoStack.length - 1];
        undoStack = undoStack.slice(0, -1);
        batchEdit(() => EditHistory.restore(SettingsData, undoBase, editKeys));
    }

    function discard() {
        batchEdit(() => EditHistory.restore(SettingsData, editSnapshot, editKeys));
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
        batchEdit(() => {
            if (panelResizable)
                DashRegistry.resetPanelSize(entryId);
            if (entryId === DashRegistry.overviewId)
                CardUtils.resetToDefault();
            else
                tabItem?.resetWidgets?.();
        });
    }

    function clear() {
        if (entryId === DashRegistry.overviewId) {
            CardUtils.clearAll();
            return;
        }
        tabItem?.clearWidgets?.();
    }

    Connections {
        target: SettingsData
        enabled: root.editMode

        function onDashCardsChanged() {
            root.trackEdit();
        }

        function onDashOptionsChanged() {
            root.trackEdit();
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
