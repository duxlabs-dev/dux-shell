pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Row {
    id: faceRow

    property color ink: Theme.surfaceText
    property string icon: ""
    property string text: ""
    property real room: 0

    readonly property bool iconOnly: faceRow.text === ""
    readonly property real labelWidth: label.implicitWidth
    readonly property real iconRoom: Theme.iconSizeMedium + faceRow.spacing
    // Icon and label at full size: the button's own width when no row sizes it (the label's width follows the button's).
    readonly property real naturalWidth: faceRow.labelWidth + (faceRow.icon !== "" ? faceRow.iconRoom : 0)
    // Too narrow for icon and label: the label wins, the icon goes.
    readonly property bool cramped: !faceRow.iconOnly && faceRow.labelWidth + faceRow.iconRoom > faceRow.room
    readonly property bool truncated: label.truncated

    // Right to left, StyledButton's inherited LayoutMirroring flips the row (setting layoutDirection too undid it).
    spacing: Theme.spacingS

    DIcon {
        visible: faceRow.icon !== "" && !faceRow.cramped
        anchors.verticalCenter: parent.verticalCenter
        name: faceRow.icon
        size: Theme.iconSizeMedium
        color: faceRow.ink
    }

    StyledText {
        id: label

        visible: !faceRow.iconOnly
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0, faceRow.room - (faceRow.icon !== "" && !faceRow.cramped ? faceRow.iconRoom : 0)))
        text: faceRow.text
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: faceRow.ink
    }
}
