pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Desk
import qs.Modules.Settings.Niri.Shell

// Side pane of Animations: the picked animation on a large stage, its values, and Play to replay it.
Column {
    id: root

    property string title: ""
    property var anim: null
    property string effect: "open"
    property real slowdown: 1
    property bool animationsOn: true

    readonly property var values: [title, animationsOn ? I18n.tr("slowdown %1", "niri page motion pane; %1 is the slowdown factor like 1.0").arg(slowdown.toFixed(1)) : I18n.tr("animations off", "niri page motion pane")]

    width: parent?.width ?? 0
    spacing: Theme.spacingM

    NiriSideHead {
        icon: "animation"
        title: I18n.tr("Motion", "niri page side pane of animations")
    }

    ClippingRectangle {
        width: parent.width
        height: width * 9 / 16
        radius: Theme.cornerRadiusS
        color: "transparent"

        NiriWallpaper {
            anchors.fill: parent
        }

        AnimStage {
            id: stage
            anchors.fill: parent
            color: "transparent"
            anim: root.anim
            effect: root.effect
            slowdown: root.slowdown
            animationsOn: root.animationsOn
        }
    }

    Item {
        width: parent.width
        height: Math.max(chips.height, playButton.height)

        Flow {
            id: chips

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - playButton.width - Theme.spacingS
            spacing: Theme.spacingXS

            Repeater {
                model: root.values

                Rectangle {
                    id: chip

                    required property string modelData

                    width: Math.min(chipText.implicitWidth, chips.width - Theme.spacingS * 2) + Theme.spacingS * 2
                    height: chipText.implicitHeight + Theme.spacingXS * 2
                    radius: Theme.cornerRadiusS
                    color: "transparent"
                    border.width: Theme.outlineWidth
                    border.color: Theme.outlineVariant

                    StyledText {
                        id: chipText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, chips.width - Theme.spacingS * 2)
                        text: chip.modelData
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }
                }
            }
        }

        DButton {
            id: playButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            enabled: root.animationsOn
            iconName: "play_arrow"
            text: root.animationsOn ? I18n.tr("Play", "niri page motion pane: replay the picked animation") : I18n.tr("Off", "niri page motion pane: animations are off")
            onClicked: stage.play()
        }
    }
}
