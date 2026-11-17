pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    property int supportedActions: Qt.CopyAction
    property int generation: 0
    property var _grabResult: null
    property var _activeHost: null
    readonly property bool dragging: Drag.active

    signal dragStarted
    signal dragFinished(int action)

    Drag.dragType: Drag.None
    Drag.supportedActions: root.supportedActions

    Component.onDestruction: cancel()

    function _resetDragState(clearPassthrough) {
        Drag.active = false;
        _grabResult = null;
        Drag.mimeData = ({});
        Drag.imageSource = "";
        if (clearPassthrough && _activeHost && _activeHost.dragPassthrough !== undefined)
            _activeHost.dragPassthrough = false;
        _activeHost = null;
    }

    function cancel() {
        generation++;
        _resetDragState(true);
    }

    function launch(host, ghostItem, mimeData, hotSpot, onFinished) {
        if (!ghostItem || !mimeData || Object.keys(mimeData).length === 0) {
            if (typeof onFinished === "function")
                onFinished(Qt.IgnoreAction);
            return false;
        }

        const currentGen = ++generation;
        _activeHost = host ?? null;

        const started = ghostItem.grabToImage(result => {
            if (currentGen !== root.generation || !result) {
                if (currentGen === root.generation && typeof onFinished === "function")
                    onFinished(Qt.IgnoreAction);
                return;
            }

            root._grabResult = result;
            root.Drag.mimeData = mimeData;
            root.Drag.imageSource = result.url;
            if (hotSpot !== undefined && hotSpot !== null)
                root.Drag.hotSpot = hotSpot;

            if (host && host.dragPassthrough !== undefined)
                host.dragPassthrough = true;

            // Wait one tick so Wayland commits the empty input mask and opacity 0 before startDrag() blocks.
            Qt.callLater(() => {
                if (currentGen !== root.generation) {
                    root._resetDragState(true);
                    return;
                }

                root.Drag.active = true;
                root.dragStarted();
                const action = root.Drag.startDrag(root.supportedActions);
                root.dragFinished(action);
                const keepHidden = (typeof onFinished === "function") && (onFinished(action) === true);
                root._resetDragState(!keepHidden);
            });
        });

        if (!started) {
            _activeHost = null;
            if (typeof onFinished === "function")
                onFinished(Qt.IgnoreAction);
            return false;
        }
        return true;
    }
}
