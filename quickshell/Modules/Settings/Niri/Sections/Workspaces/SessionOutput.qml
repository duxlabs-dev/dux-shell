pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Rectangle {
    id: root

    property string output: ""
    // [{workspace, idx, apps}] from session.js layout()
    property var rows: []
    property var choices: []

    signal added(string appId, string workspace)
    signal removed(string appId)

    implicitHeight: column.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadiusM
    color: Theme.surfaceContainer
    border.width: Theme.outlineWidth
    border.color: Theme.outlineVariant

    Column {
        id: column

        x: Theme.spacingM
        y: Theme.spacingM
        width: parent.width - Theme.spacingM * 2
        spacing: Theme.spacingS

        Row {
            spacing: Theme.spacingS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "monitor"
                size: Theme.iconSizeSmall
                color: Theme.surfaceText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.output || I18n.tr("Any screen", "niri page session")
                font.weight: Theme.fontWeightBold
                color: Theme.surfaceText
            }
        }

        Repeater {
            model: root.rows

            Column {
                id: wsRow

                required property var modelData

                width: column.width
                spacing: Theme.spacingXS

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outlineVariant
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    Rectangle {
                        visible: wsRow.modelData.idx > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(height, idxText.implicitWidth + Theme.spacingS)
                        height: idxText.implicitHeight + Theme.spacingXXS * 2
                        radius: Theme.cornerRadiusS
                        color: Theme.surfaceContainerHighest

                        StyledText {
                            id: idxText
                            anchors.centerIn: parent
                            text: wsRow.modelData.idx
                            font.pixelSize: Theme.fontSizeSmall
                            font.family: Theme.monoFontFamily
                            color: Theme.surfaceText
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x
                        text: wsRow.modelData.workspace || I18n.tr("Any workspace", "niri page session")
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: wsRow.modelData.workspace ? Theme.surfaceText : Theme.surfaceVariantText
                    }
                }

                Flow {
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: wsRow.modelData.apps

                        Rectangle {
                            id: chip

                            required property var modelData

                            width: Math.min(Theme.spacingS + label.implicitWidth + removeButton.width, wsRow.width)
                            height: Theme.buttonHeightXS
                            radius: Theme.cornerRadiusS
                            color: Theme.surfaceContainerHigh

                            StyledText {
                                id: label
                                x: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                width: chip.width - x - removeButton.width
                                text: chip.modelData.command?.join(" ") ?? chip.modelData.appId
                                elide: Text.ElideRight
                                font.family: Theme.monoFontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                            }

                            DActionButton {
                                id: removeButton
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                buttonSize: Theme.buttonHeightXS
                                iconName: "close"
                                iconSize: Theme.iconSizeSmall
                                tooltipText: I18n.tr("Remove", "niri page session")
                                Accessible.name: I18n.tr("Remove %1", "niri page session, %1 is a program").arg(chip.modelData.appId)
                                onClicked: root.removed(chip.modelData.appId)
                            }
                        }
                    }

                    DDropdown {
                        visible: root.choices.length > 0
                        compactMode: true
                        dropdownWidth: Theme.iconButtonSize * 3
                        width: dropdownWidth
                        backgroundColor: SettingsMetrics.controlSurface
                        options: root.choices
                        emptyText: I18n.tr("Add…", "niri page session: add a program to a workspace")
                        Accessible.name: I18n.tr("Add a program", "niri page session")
                        onValueChanged: value => {
                            currentValue = "";
                            root.added(value, wsRow.modelData.workspace);
                        }
                    }
                }
            }
        }
    }
}
