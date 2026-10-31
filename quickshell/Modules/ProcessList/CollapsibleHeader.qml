import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

Item {
    id: root

    property string text: ""
    property bool collapsed: true

    signal toggled

    width: parent?.width ?? 0
    height: collapseButton.height + Theme.spacingXS * 2

    // Inside the bar's own bounds: a scrolling page clips anything that sticks out.
    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusS
        color: "transparent"

        StateLayer {
            onClicked: root.toggled()
        }
    }

    StyledText {
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    DActionButton {
        id: collapseButton
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter
        iconName: "expand_more"
        rotation: root.collapsed ? 0 : 180
        tooltipText: root.collapsed ? I18n.tr("Expand") : I18n.tr("Collapse")
        onClicked: root.toggled()
    }
}
