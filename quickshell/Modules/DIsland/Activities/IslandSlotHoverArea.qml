pragma ComponentBehavior: Bound

import QtQuick

MouseArea {
    id: root

    required property var controller
    property bool hoverCounted: false

    function syncHover() {
        const wanted = root.enabled && root.visible && root.containsMouse;
        if (wanted === root.hoverCounted)
            return;
        root.hoverCounted = wanted;
        if (wanted) {
            root.controller.slotHoverEntered();
            return;
        }
        root.controller.slotHoverExited();
    }

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onContainsMouseChanged: syncHover()
    onEnabledChanged: syncHover()
    onVisibleChanged: syncHover()
    Component.onDestruction: {
        if (hoverCounted)
            controller.slotHoverExited();
    }
}
