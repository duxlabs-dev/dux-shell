pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// Full-screen, click-through layer a plugin activity draws past the island's clip into.
PanelWindow {
    id: root

    required property Component content
    required property int layer
    property bool shown: true

    visible: root.shown
    color: "transparent"
    exclusiveZone: -1

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.namespace: "dms:dankisland:overflow"
    WlrLayershell.layer: root.layer
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {}

    Loader {
        anchors.fill: parent
        sourceComponent: root.content
    }
}
