import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Modules.DDash
import qs.Widgets

Item {
    id: root

    property string path: ""
    property bool isSelected: false

    signal clicked

    width: GridView.view.cellWidth
    height: GridView.view.cellHeight

    Rectangle {
        id: thumbCard

        anchors.fill: parent
        anchors.margins: Theme.spacingXS
        color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
        radius: DashMetrics.wallpaperThumbRadius

        ClippingRectangle {
            anchors.fill: parent
            radius: thumbCard.radius
            color: "transparent"

            CachingImage {
                anchors.fill: parent
                imagePath: VideoWallpaperService.imageFor(root.path)
                maxCacheSize: DashMetrics.wallpaperThumbCache
                animate: false
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    enabled: DashMetrics.animationsEnabled
                    NumberAnimation {
                        duration: DashMetrics.fadeDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.withAlpha(Theme.primary, root.isSelected ? Theme.stateLayerFocus : 0)
            border.width: root.isSelected ? Theme.outlineWidthFocused : 0
            border.color: Theme.primary

            Behavior on color {
                enabled: DashMetrics.animationsEnabled
                ColorAnimation {
                    duration: DashMetrics.fadeDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                }
            }
        }

        StateLayer {
            anchors.fill: parent
            cornerRadius: parent.radius
            stateColor: Theme.primary
            onClicked: root.clicked()
        }
    }
}
