pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Io
import Quickshell.Widgets
import qs.Common
import "../../../../Common/niri/vendor.js" as Vendor

Item {
    id: root

    property real size: Theme.iconSize
    property color color: Theme.surfaceText
    property string sysVendor: ""
    readonly property string vendorKind: Vendor.vendorKind(sysVendor)

    width: size
    height: size

    FileView {
        path: "/sys/class/dmi/id/sys_vendor"
        printErrors: false
        onLoaded: root.sysVendor = text()
    }

    IconImage {
        anchors.fill: parent
        smooth: true
        mipmap: true
        asynchronous: true
        source: "file://" + Theme.shellDir + "/" + Vendor.logoFor(root.vendorKind)
        // The framework gear is drawn black: brightness lifts it to white so colorization reaches the full color.
        layer.enabled: root.vendorKind === "framework"
        layer.effect: MultiEffect {
            brightness: 1
            saturation: 0
            colorization: 1
            colorizationColor: root.color
        }
    }
}
