import QtQuick
import qs.Common
import qs.Modules.DDash

Item {
    z: DashMetrics.overlayZ

    Rectangle {
        anchors.fill: parent
        anchors.margins: Theme.spacingXS - Theme.focusRingOffset / 2
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRingColor
        radius: DashMetrics.wallpaperThumbRadius + Theme.focusRingOffset / 2
    }
}
