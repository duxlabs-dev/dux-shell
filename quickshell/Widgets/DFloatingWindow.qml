pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

FloatingWindow {
    id: root

    readonly property bool isFloatingWindowSurface: true

    default property alias content: contentItem.data

    property color surfaceColor: Theme.floatingWindowSurface
    property bool contentVisible: true

    // A placeholder screen (no outputs left) is 0x0; a size derived from it is a zero geometry and the compositor drops the connection.
    function heightWithin(preferred, inset) {
        const available = (root.screen?.height ?? 0) - inset;
        return available > 0 ? Math.min(preferred, available) : preferred;
    }

    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: root.surfaceColor
        visible: root.contentVisible
    }

    // No surfaceColor gate: compositor window rules can make this window translucent.
    WindowBlur {
        targetWindow: root
        blurEnabled: root.contentVisible
        blurX: 0
        blurY: 0
        blurWidth: root.visible ? root.width : 0
        blurHeight: root.visible ? root.height : 0
    }

    Item {
        id: contentItem

        readonly property bool isFloatingWindowSurface: true
        property bool disablePopupTransparency: true

        anchors.fill: parent
        visible: root.contentVisible
    }
}
