import QtQuick
import qs.Common

// Dims everything outside rect (in content units, scaled by unitScale) and outlines it.
Item {
    id: root

    property var rect: null
    property real unitScale: 1
    property color dimColor: Theme.withAlpha(Theme.background, 0.6)

    readonly property real rx: (rect?.x ?? 0) * unitScale
    readonly property real ry: (rect?.y ?? 0) * unitScale
    readonly property real rw: (rect?.width ?? 0) * unitScale
    readonly property real rh: (rect?.height ?? 0) * unitScale

    Rectangle {
        width: parent.width
        height: root.ry
        color: root.dimColor
    }
    Rectangle {
        y: root.ry + root.rh
        width: parent.width
        height: parent.height - y
        color: root.dimColor
    }
    Rectangle {
        y: root.ry
        width: root.rx
        height: root.rh
        color: root.dimColor
    }
    Rectangle {
        x: root.rx + root.rw
        y: root.ry
        width: parent.width - x
        height: root.rh
        color: root.dimColor
    }
    Rectangle {
        x: root.rx
        y: root.ry
        width: root.rw
        height: root.rh
        visible: root.rect !== null
        color: "transparent"
        border.color: Theme.primary
        border.width: Theme.outlineWidthFocused
    }
}
