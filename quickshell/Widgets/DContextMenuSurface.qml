import QtQuick
import Quickshell.Wayland
import qs.Common

DIdleSurface {
    id: root

    readonly property int hostCount: hostItem.children.length
    readonly property var activeHost: hostCount > 0 ? (hostItem.children[hostCount - 1].host ?? null) : null
    readonly property alias hostItem: hostItem

    kind: "context-menu"
    active: hostCount > 0
    maskItem: hostItem

    WlrLayershell.namespace: "dms:context-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: activeHost?.surfaceKeyboardFocus ?? WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: activeHost?.blurRegion ?? null



    Item {
        id: hostItem
        anchors.fill: parent
    }
}
