pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    property BoardCard board: null

    readonly property var named: board?.named ?? []
    readonly property string anyScreen: I18n.tr("Any screen")

    width: parent?.width ?? 0
    spacing: Theme.spacingXS

    StyledText {
        width: parent.width
        visible: root.named.length === 0
        topPadding: Theme.spacingS
        text: I18n.tr("No named workspaces. niri uses numbered ones.")
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
    }

    Repeater {
        model: root.named.length

        Item {
            id: row

            required property int index
            readonly property var ws: root.named[index] ?? ({
                    "name": "",
                    "output": ""
                })
            readonly property var lane: root.board.lanes.find(l => l.name === ws.name)

            width: root.width
            height: Theme.listItemHeight

            Row {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: Theme.spacingS

                // Round index pill, same shape as the lane headers.
                Rectangle {
                    id: idxPill

                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.iconSizeSmall + Theme.spacingXS
                    height: width
                    radius: width / 2
                    color: Theme.surfaceContainerHigh

                    StyledText {
                        anchors.centerIn: parent
                        text: String(row.index + 1)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceText
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - screenIcon.width - screen.width - actions.width - Theme.spacingS * 3

                    StyledText {
                        width: parent.width
                        text: row.ws.name
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: !row.lane ? I18n.tr("Not open") : row.lane.windows.length === 1 ? I18n.tr("%1 window", "niri page named workspaces; singular, %1 is 1").arg(1) : I18n.tr("%1 windows").arg(row.lane.windows.length)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                // The screen shows its icon on every row, like the board bands above.
                DIcon {
                    id: screenIcon

                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!row.ws.output
                    // eDP is the panel: same guess as the board bands.
                    name: row.ws.output.startsWith("eDP") ? "laptop" : "desktop_windows"
                    size: Theme.iconSizeSmall
                    color: Theme.surfaceVariantText
                }

                DDropdown {
                    id: screen
                    anchors.verticalCenter: parent.verticalCenter
                    compactMode: true
                    dropdownWidth: Theme.iconButtonSize * 3
                    width: dropdownWidth
                    backgroundColor: SettingsMetrics.controlSurface
                    options: [root.anyScreen].concat(root.board.outputNames)
                    currentValue: row.ws.output || root.anyScreen
                    Accessible.name: I18n.tr("Screen for %1").arg(row.ws.name)
                    onValueChanged: value => root.board.setNamedOutput(row.ws.name, value === root.anyScreen ? "" : value)
                }

                Row {
                    id: actions
                    anchors.verticalCenter: parent.verticalCenter

                    DActionButton {
                        enabled: row.index > 0
                        opacity: enabled ? 1 : SettingsMetrics.disabledOpacity
                        iconName: "arrow_upward"
                        tooltipText: I18n.tr("Move %1 up").arg(row.ws.name)
                        onClicked: root.board.moveNamedUp(row.index)
                    }

                    DActionButton {
                        iconName: "delete"
                        tooltipText: I18n.tr("Remove workspace %1").arg(row.ws.name)
                        onClicked: root.board.removeNamed(row.ws.name)
                    }
                }
            }
        }
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS

        DTextField {
            id: newName
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - addButton.width - Theme.spacingS
            placeholderText: I18n.tr("Name")
            maximumLength: 64
            Accessible.name: I18n.tr("New workspace name")
            onAccepted: addButton.clicked()
        }

        DButton {
            id: addButton
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Add")
            iconName: "add"
            onClicked: {
                if (root.board.addNamed(newName.text))
                    newName.text = "";
            }
        }
    }
}
