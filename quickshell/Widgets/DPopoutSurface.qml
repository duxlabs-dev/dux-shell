import QtQuick
import Quickshell.Wayland
import qs.Common

DIdleSurface {
    id: root

    readonly property int hostCount: hostItem.children.length
    readonly property var activeHost: hostCount > 0 ? (hostItem.children[hostCount - 1].host ?? null) : null
    readonly property alias hostItem: hostItem

    kind: "popout"
    active: hostCount > 0
    maskItem: activeHost?.maskItem ?? null

    WlrLayershell.namespace: "dms:popout"
    WlrLayershell.layer: activeHost?.effectivePopoutLayer ?? WlrLayer.Top
    WlrLayershell.keyboardFocus: activeHost?.surfaceKeyboardFocus ?? WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: activeHost?.blurRegion ?? null

    Item {
        id: hostItem
        anchors.fill: parent
    }
}
