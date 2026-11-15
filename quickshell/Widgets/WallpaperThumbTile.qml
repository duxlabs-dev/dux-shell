import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Widgets

Item {
    id: root

    property string path: ""
    property bool selected: false
    property bool mismatched: false
    property real mismatchedOpacity: 1
    property string sizeText: ""
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None

    signal clicked

    width: GridView.view.cellWidth
    height: GridView.view.cellHeight

    Accessible.role: Accessible.Button
    Accessible.name: path.substring(path.lastIndexOf("/") + 1)
    Accessible.checkable: true
    Accessible.checked: selected
    Accessible.description: mismatched ? I18n.tr("Hidden", "wallpaper hidden because it doesn't fit the display") + (sizeText ? ", " + sizeText : "") : ""
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
                opacity: status !== Image.Ready ? 0 : root.mismatched ? root.mismatchedOpacity : 1

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

        Rectangle {
            visible: root.mismatched
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.spacingS
            width: hiddenIcon.width + Theme.spacingXS * 2
            height: width
            radius: Theme.cornerRadiusS
            color: Theme.surfaceContainer

            DIcon {
                id: hiddenIcon
                anchors.centerIn: parent
                name: "visibility_off"
                size: Theme.iconSizeSmall
                color: Theme.surfaceText
            }
        }

        Rectangle {
            visible: root.mismatched && root.sizeText !== ""
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: Theme.spacingS
            width: sizeLabel.implicitWidth + Theme.spacingS * 2
            height: sizeLabel.implicitHeight + Theme.spacingXS * 2
            radius: Theme.cornerRadiusS
            color: Theme.surfaceContainer

            StyledText {
                id: sizeLabel
                anchors.centerIn: parent
                text: root.sizeText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
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
