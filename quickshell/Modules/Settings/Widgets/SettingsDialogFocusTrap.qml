import QtQuick
import QtQuick.Window

Item {
    id: root

    property Item dialog: null
    property bool active: false
    readonly property Item windowFocusItem: root.Window.window?.activeFocusItem ?? null

    visible: false

    onWindowFocusItemChanged: {
        if (active)
            timer.restart();
    }

    function _trap() {
        const d = dialog;
        if (!active || !d || d.activeFocus)
            return;
        const first = d.nextItemInFocusChain(true);
        if (first && _isInside(first, d)) {
            first.forceActiveFocus(Qt.TabFocusReason);
            return;
        }
        d.forceActiveFocus();
    }

    function _isInside(item, ancestor) {
        for (let node = item; node; node = node.parent) {
            if (node === ancestor)
                return true;
        }
        return false;
    }

    Timer {
        id: timer
        interval: 0
        onTriggered: root._trap()
    }
}
