pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Desk
import "../../../../../Common/niri/sections/corners.js" as Corners

// A screen outline with one button per corner; each opens the action menu.
Item {
    id: root

    required property var card
    readonly property real buttonSize: Theme.minimumTouchTargetSize
    readonly property real pad: buttonSize / 2 - Theme.spacingS

    width: Math.min(parent.width, buttonSize * 7)
    height: (width - pad * 2) * 9 / 16 + pad * 2
    Accessible.role: Accessible.Grouping
    Accessible.name: I18n.tr("Hot corners. Each corner runs one action")

    ClippingRectangle {
        anchors.fill: screenRect
        radius: screenRect.radius
        color: "transparent"

        NiriWallpaper {
            anchors.fill: parent
        }
    }

    Rectangle {
        id: screenRect
        anchors.fill: parent
        anchors.margins: root.pad
        radius: Theme.cornerRadiusM
        color: "transparent"
        border.width: Theme.outlineWidthFocused
        border.color: Theme.outline
    }

    Repeater {
        model: Corners.corners

        delegate: Rectangle {
            id: cornerButton

            required property string modelData
            readonly property bool atLeft: modelData.endsWith("left")
            readonly property bool atTop: modelData.startsWith("top")
            readonly property string action: root.card.current[modelData] ?? "none"
            readonly property bool on: action !== "none"
            readonly property bool open: root.card.openCorner === modelData

            x: (atLeft ? screenRect.x + Theme.spacingS : screenRect.x + screenRect.width - Theme.spacingS) - width / 2
            y: (atTop ? screenRect.y + Theme.spacingS : screenRect.y + screenRect.height - Theme.spacingS) - height / 2
            width: root.buttonSize
            height: width
            radius: width / 2
            color: on ? Theme.primary : Theme.surfaceContainerHigh
            border.width: open ? Theme.outlineWidthFocused * 2 : Theme.outlineWidthFocused
            border.color: on ? Theme.primary : (area.containsMouse || open ? Theme.surfaceText : Theme.outline)
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: root.card.cornerInfo[modelData].text + ": " + root.card.actionOf(action).text
            Keys.onReturnPressed: root.card.openMenu(cornerButton, modelData)
            Keys.onSpacePressed: root.card.openMenu(cornerButton, modelData)

            // Apart from the button, so it shows on a lit (primary) corner too.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -Theme.outlineWidthFocused * 2
                visible: cornerButton.activeFocus
                radius: width / 2
                color: "transparent"
                border.width: Theme.outlineWidthFocused
                border.color: Theme.primary
            }

            DIcon {
                anchors.centerIn: parent
                name: cornerButton.on ? root.card.actionOf(cornerButton.action).icon : root.card.cornerInfo[cornerButton.modelData].icon
                size: Theme.iconSizeMedium
                color: cornerButton.on ? Theme.primaryText : Theme.surfaceVariantText
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.card.openMenu(cornerButton, cornerButton.modelData)
            }
        }
    }
}
