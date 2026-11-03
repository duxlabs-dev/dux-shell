import QtQuick
import qs.Common
import qs.DCommon.Widgets

DCard {
    id: root

    property string iconName: ""
    property string shape: "circle"
    property string hoverShape: "circle"
    property string accent: ""
    property string heading: ""
    property string description: ""

    readonly property var accentPair: Theme.accent(accent)
    readonly property bool engaged: hover.hovered || focusTarget.visualFocus
    readonly property var morphSpring: Theme.springPreset("default", Theme.expressiveDurations.expressiveDefaultSpatial)

    onEngagedChanged: morphMotion.retarget(engaged ? 1 : 0)

    clickable: true
    pad: Theme.spacingL
    restRadius: Theme.groupedListOuterRadius
    bodyRadius: focusTarget.pressed && Theme.shapeMorph ? Theme.cornerRadiusM : restRadius
    implicitHeight: body.implicitHeight + pad * 2
    Accessible.name: heading
    Accessible.description: description

    HoverHandler {
        id: hover
    }

    SpringMotion {
        id: morphMotion
        enabled: !Theme.springMotionDisabled
        stiffness: root.morphSpring.stiffness
        damping: root.morphSpring.damping
    }

    Column {
        id: body
        width: parent.width
        spacing: Theme.spacingM

        Item {
            width: parent.width
            height: Theme.buttonHeightM

            MorphShape {
                id: badge
                width: parent.height
                height: width
                fromShape: root.shape
                toShape: root.hoverShape
                progress: morphMotion.value
                color: root.accentPair?.container ?? Theme.primaryContainer
            }

            DIcon {
                anchors.centerIn: badge
                name: root.iconName
                size: Theme.iconSize
                color: root.accentPair?.onContainer ?? Theme.onPrimaryContainer
            }

            DIcon {
                anchors.right: parent.right
                anchors.top: parent.top
                name: "arrow_outward"
                size: Theme.iconSizeMedium
                color: root.engaged ? Theme.primary : Theme.surfaceVariantText
                rotation: I18n.isRtl ? -90 : 0
            }
        }

        StyledText {
            width: parent.width
            text: root.heading
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeightBold
            color: Theme.surfaceText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignLeft
        }

        StyledText {
            width: parent.width
            text: root.description
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignLeft
        }
    }
}
