import QtQuick
import qs.Common

// GridView highlight for WallpaperThumbTile; z puts it above the delegates (z 1).
Item {
    z: 2

    Rectangle {
        anchors.fill: parent
        anchors.margins: Theme.spacingXS - Theme.focusRingOffset / 2
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRingColor
        radius: Theme.cornerRadiusM + Theme.focusRingOffset / 2
    }
}
