pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

// Category chips above the keyboard: icon, name, count; picking one lights its keys
Flow {
    id: root

    required property KeyboardCard board

    spacing: Theme.spacingXS

    Repeater {
        model: root.board.categories

        Rectangle {
            id: chip

            required property string modelData
            readonly property bool on: root.board.pickedCategory === modelData

            width: chipRow.width + Theme.spacingS * 2
            height: Theme.buttonHeightS
            radius: height / 2
            color: root.board.tintOf(modelData)
            border.width: on ? Theme.outlineWidthFocused : 0
            // The icon colour, not the raw category line: it keeps 3:1 on the card in light themes
            border.color: root.board.iconOf(modelData)
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.checkable: true
            Accessible.checked: on
            Accessible.name: I18n.tr("%1, %2 shortcuts").arg(modelData).arg(root.board.counts[modelData] ?? 0)
            Keys.onReturnPressed: root.board.pickCategory(modelData)
            Keys.onEnterPressed: root.board.pickCategory(modelData)
            Keys.onSpacePressed: root.board.pickCategory(modelData)

            Row {
                id: chipRow

                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.board.icons[chip.modelData] ?? "keyboard_command_key"
                    size: Theme.iconSizeSmall
                    color: root.board.iconOf(chip.modelData)
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.modelData
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: chip.on ? Font.Bold : Font.Medium
                    color: Theme.surfaceText
                }
            }

            FocusRing {}

            // Half the gap on each side: 44 px of hit area without overlapping the next chip
            MouseArea {
                anchors.fill: parent
                anchors.margins: -root.spacing / 2
                cursorShape: Qt.PointingHandCursor
                onClicked: root.board.pickCategory(chip.modelData)
            }
        }
    }
}
