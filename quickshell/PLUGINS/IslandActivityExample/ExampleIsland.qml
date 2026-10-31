import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DIsland.Kit

IslandActivityComponent {
    id: root

    readonly property string label: root.activityData.label ?? ""
    readonly property bool still: Theme.currentAnimationBaseDuration <= 0 || SettingsData.reduceMotion
    // The alert's grains: how many, how many times they fall, and how far (px).
    readonly property int grains: 12
    readonly property int grainPasses: 3
    readonly property real grainDrop: 120

    compactLength: 200
    expandedWidth: 420
    expandedHeight: 150

    compactContent: Item {
        Row {
            anchors.centerIn: parent
            spacing: Theme.spacingS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.kind === "glance" ? "bluetooth" : "timer"
                size: Theme.iconSizeSmall
                color: root.kind === "alert" ? Theme.primary : Theme.surfaceText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    expandedContent: Column {
        padding: Theme.spacingL
        spacing: Theme.spacingM

        StyledText {
            text: root.label
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeightMedium
        }

        IslandButton {
            role: "primary"
            text: I18n.tr("Dismiss", "island example plugin: dismiss button")
            onClicked: root.dismiss()
        }
    }

    // Grains falling from the island's lower edge a few times, then still: no image once they are done. They follow DMS's
    // animation speed; reduced motion shows them fallen at once. The layer never takes clicks.
    overflowContent: Item {
        Repeater {
            model: root.kind === "alert" ? root.grains : 0

            Rectangle {
                id: grain

                required property int index
                property real fall: root.still ? 1 : 0

                width: Theme.spacingXS
                height: width
                radius: width / 2
                color: Theme.primary
                x: root.islandRect.x + root.islandRect.width * (grain.index + 1) / (root.grains + 1)
                y: root.islandRect.y + root.islandRect.height + grain.fall * root.grainDrop
                opacity: 1 - grain.fall

                NumberAnimation on fall {
                    running: !root.still && !root.interrupted
                    from: 0
                    to: 1
                    // 900 ms at DMS's default speed (250 ms), each grain 70 ms slower than the one before.
                    duration: Theme.currentAnimationBaseDuration * (3.6 + grain.index * 0.28)
                    loops: root.grainPasses
                }
            }
        }
    }
}
