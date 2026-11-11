import QtQuick
import Quickshell.Wayland
import qs.Common

DIdleSurface {
    id: root

    readonly property int hostCount: hostItem.children.length
    readonly property var activeHost: hostCount > 0 ? (hostItem.children[hostCount - 1].host ?? null) : null
    readonly property alias hostItem: hostItem

    kind: "osd"
    active: hostCount > 0
    maskItem: activeHost?.maskItem ?? null

    WlrLayershell.namespace: "dms:osd"
    WlrLayershell.layer: LayerShell.fromEnv("DMS_OSD_LAYER", WlrLayer.Overlay, {
        "allow": ["top", "overlay"],
        "invalidLayer": WlrLayer.Overlay,
        "label": "OSDs"
    })
    WlrLayershell.keyboardFocus: activeHost?.surfaceKeyboardFocus ?? WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: activeHost?.blurRegion ?? null



    Item {
        id: hostItem
        anchors.fill: parent
    }
}
