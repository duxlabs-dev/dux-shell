pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

// Under the keyboard: the modifier layer, the hold-Super hint, the layout with its link to Input
Flow {
    id: root

    required property KeyboardCard board

    function openInput() {
        SettingsUiState.niriSection = "input";
    }

    // 44 px: the smallest hit area the page allows for a control
    readonly property real hitHeight: Theme.buttonHeightS + Theme.spacingXS

    spacing: Theme.spacingS

    DButtonGroup {
        id: layerGroup

        arrowKeysSelect: false
        buttonHeight: root.hitHeight
        model: root.board.layers.map((l, i) => ({
                    "text": i === 0 ? l : l.slice(root.board.modKey.length),
                    "icon": "",
                    "tooltip": ""
                }))
        currentIndex: root.board.layers.indexOf(root.board.shownLayer)
        Accessible.name: I18n.tr("Modifier layer")
        onSelectionChanged: (index, selected) => {
            if (selected)
                root.board.chosenLayer = root.board.layers[index];
        }
    }

    Row {
        height: root.hitHeight
        spacing: Theme.spacingXS

        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "visibility"
            size: Theme.iconSizeSmall
            color: root.board.holding ? Theme.primary : Theme.surfaceVariantText
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.board.holding ? I18n.tr("%1 held · release to go back").arg(root.board.heldLayer) : I18n.tr("Hold %1 to see every key", "niri keyboard hint, %1 = configured mod key").arg(root.board.modKey)
            font.pixelSize: Theme.fontSizeSmall
            font.weight: root.board.holding ? Font.DemiBold : Font.Normal
            color: root.board.holding ? Theme.surfaceText : Theme.surfaceVariantText
            Accessible.role: Accessible.StatusBar
        }
    }

    Rectangle {
        width: layoutRow.width + Theme.spacingS * 2
        height: root.hitHeight
        radius: height / 2
        color: SettingsMetrics.controlColor
        activeFocusOnTab: true
        Accessible.role: Accessible.Link
        Accessible.name: I18n.tr("Layout %1, from niri. Change it in Input").arg(root.board.layoutName || root.board.layoutId)
        Keys.onReturnPressed: root.openInput()
        Keys.onEnterPressed: root.openInput()
        Keys.onSpacePressed: root.openInput()

        Row {
            id: layoutRow

            anchors.centerIn: parent
            spacing: Theme.spacingXS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "language"
                size: Theme.iconSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("%1 · from niri").arg(root.board.layoutId)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
        }

        FocusRing {}

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openInput()
        }
    }
}
