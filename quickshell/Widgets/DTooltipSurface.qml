import QtQuick
import Quickshell.Wayland
import qs.Common

DIdleSurface {
    id: root

    readonly property alias hostItem: hostItem

    kind: "tooltip"
    active: hostItem.children.length > 0

    WlrLayershell.namespace: "dms:tooltip"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None



    Item {
        id: hostItem
        anchors.fill: parent
    }
}
