import QtQuick
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: root

    required property bool gridEnabled
    required property int gridSize

    width: helperRow.implicitWidth + Theme.spacingM * 2
    height: Theme.buttonHeightXS
    radius: Theme.cornerRadius
    color: Theme.hostSurface

    Row {
        id: helperRow
        anchors.centerIn: parent
        spacing: Theme.spacingM
        height: parent.height

        Row {
            spacing: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter

            DIcon {
                name: "grid_on"
                size: Theme.iconSizeSmall
                color: root.gridEnabled ? Theme.primary : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.gridEnabled ? I18n.tr("Grid: ON", "Widget grid snap status") : I18n.tr("Grid: OFF", "Widget grid snap status")
                font.pixelSize: Theme.fontSizeSmall
                font.family: Theme.fontFamily
                color: root.gridEnabled ? Theme.primary : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            DKeycap {
                text: "G"
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle {
            width: Theme.dividerWidth
            height: Theme.iconSizeSmall
            color: Theme.outline
            anchors.verticalCenter: parent.verticalCenter
        }

        Row {
            spacing: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter

            DKeycap {
                text: "Z"
                anchors.verticalCenter: parent.verticalCenter
            }

            NumericText {
                text: root.gridSize + "px"
                reserveText: "200px"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            DKeycap {
                text: "X"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
