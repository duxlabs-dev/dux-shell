import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

// A tinted note; health.legible keeps the icon readable on the tint in light themes.
Rectangle {
    id: root

    required property var health
    property alias text: noteLabel.text
    property alias iconName: noteIcon.name
    property color tone: Theme.error
    property string actionText: ""

    signal actionClicked

    height: Math.max(noteLabel.implicitHeight, actionButton.visible ? actionButton.height : 0) + Theme.spacingM * 2
    radius: Theme.cornerRadius
    color: Theme.blend(Theme.surfaceContainerHigh, tone, 0.16)

    DIcon {
        id: noteIcon
        x: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        size: Theme.iconSizeMedium
        color: root.health.legible(root.tone, root.color)
    }

    StyledText {
        id: noteLabel
        x: noteIcon.x + noteIcon.width + Theme.spacingS
        width: parent.width - x - Theme.spacingM - (actionButton.visible ? actionButton.width + Theme.spacingS : 0)
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        wrapMode: Text.WrapAnywhere
    }

    DButton {
        id: actionButton
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        visible: root.actionText !== ""
        enabled: !root.health.checking
        text: root.actionText
        onClicked: root.actionClicked()
    }
}
