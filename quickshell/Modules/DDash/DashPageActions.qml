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
    readonly property bool hasWidgets: entryId === DashRegistry.overviewId || typeof tabItem?.clearWidgets === "function"
    readonly property bool menuOpen: customMenu.open
    readonly property bool hasCustomActions: customMenu.visibleItems.length > 0
    readonly property var focusTargets: editControls.focusTargets

    signal optionsRequested
    signal finished

    implicitWidth: vertical ? Theme.navigationRailWidth : editControls.implicitWidth
    implicitHeight: editControls.implicitHeight

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
        canAdd: (root.tabItem?.addable?.length ?? 0) > 0
        hasWidgets: root.hasWidgets
        hasOptions: DashRegistry.hasOptions(root.entryId, true)
        hasCustomActions: root.hasCustomActions
        onActionsRequested: anchor => customMenu.openAt(anchor)
        onAddRequested: anchor => root.tabItem?.openAddMenu(anchor)
        onOptionsRequested: root.optionsRequested()
        onResetRequested: root.reset()
        onClearRequested: root.clear()
        onFinished: root.finished()
    }
}
