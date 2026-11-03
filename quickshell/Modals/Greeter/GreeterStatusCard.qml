import QtQuick
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: root

    property int count: 0
    property string label: ""
    property string iconName: ""
    property color iconColor: Theme.surfaceText
    property color bgColor: Theme.floatingWindowNestedSurface
    property bool selected: false

    signal clicked

    height: Math.round(Theme.fontSizeMedium * 5)
    radius: Theme.cornerRadius
    color: bgColor
    border.width: selected ? Theme.outlineWidthFocused : Theme.layerOutlineWidth
    border.color: selected ? iconColor : Theme.outlineMedium
    scale: mouseArea.pressed ? 0.97 : 1

    Behavior on scale {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.emphasizedEasing
        }
    }

    Behavior on border.width {
        NumberAnimation {
            duration: Theme.shortDuration
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingXS

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.spacingS

            DIcon {
                name: root.iconName
                size: Theme.iconSize - 4
                color: root.iconColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.count.toString()
                font.pixelSize: Theme.fontSizeXLarge
                font.weight: Theme.fontWeightMedium
                color: root.iconColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        StyledText {
            text: root.label
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
