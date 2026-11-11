import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property string path: ""
    property bool selected: false
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None

    signal clicked

    width: GridView.view.cellWidth
    height: GridView.view.cellHeight

    Accessible.role: Accessible.Button
    Accessible.name: path.substring(path.lastIndexOf("/") + 1)
    Accessible.checkable: true
    Accessible.checked: selected
    Accessible.onPressAction: root.clicked()

    Rectangle {
        id: thumbCard

        anchors.fill: parent
        anchors.margins: Theme.spacingXS
        color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
        radius: Theme.cornerRadiusM

        ClippingRectangle {
            anchors.fill: parent
            radius: thumbCard.radius
            color: "transparent"

            CachingImage {
                anchors.fill: parent
                imagePath: VideoWallpaperService.imageFor(root.path)
                maxCacheSize: 256
                animate: false
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    enabled: root.animationsEnabled
                    NumberAnimation {
                        duration: Theme.expressiveDurations.expressiveEffects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.withAlpha(Theme.primary, root.selected ? Theme.stateLayerFocus : 0)
            border.width: root.selected ? Theme.outlineWidthFocused : 0
            border.color: Theme.primary

            Behavior on color {
                enabled: root.animationsEnabled
                ColorAnimation {
                    duration: Theme.expressiveDurations.expressiveEffects
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
