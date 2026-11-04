import QtQuick
import qs.Common

// A place the side column (desk or section pane) can sit in, with its separator line on one edge.
Item {
    id: root

    // "top", "bottom" or "left"
    property string line: "bottom"

    Rectangle {
        y: root.line === "bottom" ? root.height - height : 0
        width: root.line === "left" ? Theme.outlineWidth : root.width
        height: root.line === "left" ? root.height : Theme.outlineWidth
        color: Theme.outlineVariant
    }
}
