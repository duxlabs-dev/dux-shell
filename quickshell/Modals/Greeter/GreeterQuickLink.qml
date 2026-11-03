import QtQuick
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: root

    property string iconName: ""
    property string title: ""
    property bool isExternal: false

    signal clicked

    height: Math.round(Theme.fontSizeMedium * 3.1)
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
        anchors.centerIn: parent
        spacing: Theme.spacingS

        DIcon {
            name: root.iconName
            size: Theme.iconSizeSmall + 2
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: root.title
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
            anchors.verticalCenter: parent.verticalCenter
        }

        DIcon {
            visible: root.isExternal
            name: "open_in_new"
            size: Theme.iconSizeSmall - 2
            color: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
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
