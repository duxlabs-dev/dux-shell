import QtQuick
import qs.Common
import "../../Common/EditHistory.js" as EditHistory

QtObject {
    id: root

    property bool active: false
    property string pageId: ""
    property bool panel: false
    property var selection: null
    property bool popoverRequested: false
    readonly property bool canUndo: undoStack.length > 0
    readonly property var editKeys: ["dashCards", "dashOptions"]
    property string snapshot: ""
    property string undoBase: ""
    property var undoStack: []

    onActiveChanged: {
        begin();
        closePopover();
    }
    onPageIdChanged: closePopover()
    onPanelChanged: {
        if (!panel)
            closePopover();
    }
    Component.onCompleted: begin()

    function begin() {
        snapshot = active ? EditHistory.snapshot(SettingsData, editKeys) : "";
        undoBase = snapshot;
        undoStack = [];
    }

    function track() {
        if (!active)
            return;
        const state = EditHistory.snapshot(SettingsData, editKeys);
        if (state === undoBase)
            return;
        undoStack = EditHistory.push(undoStack, undoBase);
        undoBase = state;
    }

    function undo() {
        if (undoStack.length === 0)
            return;
        undoBase = undoStack[undoStack.length - 1];
        undoStack = undoStack.slice(0, -1);
        EditHistory.restore(SettingsData, undoBase, editKeys);
    }

    function discard() {
        EditHistory.restore(SettingsData, snapshot, editKeys);
    }

    function select(target) {
        if (active)
            selection = target;
    }

    function clearSelection() {
        selection = null;
    }

    function selectPage(entryId) {
        select({
            "kind": "page",
            "entryId": entryId,
            "key": entryId,
            "instanceId": ""
        });
    }

    function presentPageOptions(entryId, hasGrid) {
        if (hasGrid)
            selectPage(entryId);
        popoverRequested = true;
    }

    function togglePopover() {
        if (popoverRequested && selection === null) {
            closePopover();
            return;
        }
        selection = null;
        popoverRequested = true;
    }

    function closePopover() {
        popoverRequested = false;
        selection = null;
    }

    function isSelected(entryId, key, instanceId) {
        const s = selection;
        return !!s && s.entryId === entryId && s.key === key && (s.instanceId ?? "") === (instanceId ?? "");
    }

    // Deferred, so a reset that writes both keys lands as one undo step.
    property Connections settingsWatch: Connections {
        target: SettingsData
        enabled: root.active

        function onDashCardsChanged() {
            Qt.callLater(root.track);
        }

        function onDashOptionsChanged() {
            Qt.callLater(root.track);
        }
    }
}
