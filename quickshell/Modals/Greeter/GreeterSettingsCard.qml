import QtQuick
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: root

    property string iconName: ""
    property string title: ""
    property string description: ""

    signal clicked

    readonly property real iconContainerSize: Math.round(Theme.iconSize * 1.5)

    height: Math.round(Theme.fontSizeMedium * 4.5)
    radius: Theme.cornerRadius
    color: Theme.floatingWindowNestedSurface
    border.width: Theme.layerOutlineWidth
    border.color: Theme.outlineMedium

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Theme.primary
        opacity: mouseArea.containsMouse ? 0.12 : 0
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingM

        Rectangle {
            width: root.iconContainerSize
            height: root.iconContainerSize
            radius: Math.round(root.iconContainerSize * 0.28)
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter

            DIcon {
                anchors.centerIn: parent
                name: root.iconName
                size: Theme.iconSize - 4
                color: Theme.primaryText
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXXS
            width: parent.width - root.iconContainerSize - Theme.spacingM

            StyledText {
                text: root.title
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            StyledText {
                text: root.description
                font.pixelSize: Theme.fontSizeXSmall
                color: Theme.surfaceVariantText
                width: parent.width
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
