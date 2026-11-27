import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common

PanelWindow {
    id: root

    required property string edge
    property real exclusionSize: 0
    property string layerNamespace: "dms:bar-exclusion"

    visible: exclusionSize > 0
    color: "transparent"
    mask: Region {}
    implicitWidth: 1
    implicitHeight: 1
    exclusiveZone: exclusionSize

    WlrLayershell.namespace: layerNamespace
    WlrLayershell.layer: WlrLayer.Top

    anchors {
        top: root.edge !== "bottom"
        bottom: root.edge !== "top"
        left: root.edge !== "right"
        right: root.edge !== "left"
    }
    margins.top: SurfaceRecovery.marginNudge(anchors.top)
    margins.bottom: SurfaceRecovery.marginNudge(anchors.bottom)
    margins.left: SurfaceRecovery.marginNudge(anchors.left)
    margins.right: SurfaceRecovery.marginNudge(anchors.right)

    Component.onCompleted: SurfaceRecovery.track(root)
    Component.onDestruction: SurfaceRecovery.untrack(root)
}
