import QtQuick
import qs.Common

QtObject {
    id: root

    property bool active: false
    property string pageId: ""
    property bool panel: false
    property var selection: null
    property bool popoverRequested: false
    readonly property bool canUndo: undoStack.length > 0
    readonly property int undoLimit: 50
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
        snapshot = active ? currentState() : "";
        undoBase = snapshot;
        undoStack = [];
    }

    function currentState() {
        const state = {};
        for (const key of editKeys)
            state[key] = SettingsData[key];
        return JSON.stringify(state);
    }

    function applyState(state) {
        const wanted = JSON.parse(state);
        for (const key of editKeys) {
            if (JSON.stringify(SettingsData[key]) !== JSON.stringify(wanted[key]))
                SettingsData.set(key, wanted[key]);
        }
    }

    function track() {
        if (!active)
            return;
        const state = currentState();
        if (state === undoBase)
            return;
        undoStack = undoStack.concat([undoBase]).slice(-undoLimit);
        undoBase = state;
    }

    function undo() {
        if (undoStack.length === 0)
            return;
        undoBase = undoStack[undoStack.length - 1];
        undoStack = undoStack.slice(0, -1);
        applyState(undoBase);
    }

    function discard() {
        if (snapshot !== "")
            applyState(snapshot);
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
