import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "../DCommon/Common/Contrast.js" as Contrast

Item {
    id: root

    property string iconName: ""
    property real size: Theme.iconSize
    property color color: Theme.surfaceText
    property string badgeName: ""
    // A charging badge takes the icon's color, a low one the error color.
    property color badgeColor: root.badgeName === "bolt" ? root.color : Theme.error
    property color badgeInk: root.badgeName === "bolt" ? Contrast.readableOn(root.badgeColor, [Theme.surface, Theme.surfaceText]) : Theme.onError
    // Badge sizes are for a Theme.iconSize icon and scale with it.
    readonly property real badgeScale: root.size / Theme.iconSize
    property real badgeSize: Math.round((Theme.spacingM - Theme.dividerWidth) * root.badgeScale)
    property real badgeGlyph: Math.round((Theme.spacingS + Theme.dividerWidth) * root.badgeScale)
    property real badgeOverhang: Math.round(Theme.spacingXS * root.badgeScale)
    // Ring in the background color that separates the badge from the icon.
    property real cutWidth: 0
    property color cutColor: "transparent"

    implicitWidth: root.size + (root.badgeName !== "" ? root.badgeOverhang : 0)
    implicitHeight: root.size

    DIcon {
        anchors.left: parent.left
        name: root.iconName
        size: root.size
        color: root.color
    }

    Rectangle {
        visible: root.badgeName !== ""
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -Theme.spacingXXS
        width: root.badgeSize + root.cutWidth * 2
        height: width
        radius: width / 2
        color: root.badgeColor
        border.width: root.cutWidth
        border.color: root.cutColor

        DIcon {
            anchors.centerIn: parent
            name: root.badgeName
            size: root.badgeGlyph
            filled: true
            color: root.badgeInk
        }
    }
}
