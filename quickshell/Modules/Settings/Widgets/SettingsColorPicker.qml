pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

SettingsRow {
    id: root

    property string colorMode: "primary"
    property color customColor: "#ffffff"
    property string pickerTitle: I18n.tr("Choose color", "color picker title")
    property bool showDefault: false
    property color defaultColor: Theme.lockScreenContentColor

    signal colorModeSelected(string mode)
    signal customColorSelected(color selectedColor)

    title: I18n.tr("Color")

    body: Row {
        width: parent.width
        spacing: Theme.spacingS

        Repeater {
            id: swatches
            model: (root.showDefault ? [
                    {
                        id: "default",
                        label: I18n.tr("Default"),
                        color: root.defaultColor
                    }
                ] : []).concat([
                {
                    id: "primary",
                    label: I18n.tr("Primary"),
                    color: Theme.primary
                },
                {
                    id: "secondary",
                    label: I18n.tr("Secondary"),
                    color: Theme.secondary
                },
                {
                    id: "custom",
                    label: I18n.tr("Custom"),
                    color: root.customColor
                }
            ])

            Rectangle {
                required property var modelData
                required property int index

                width: (parent.width - Theme.spacingS * (swatches.count - 1)) / swatches.count
                height: Theme.listItemHeight + Theme.spacingXS
                radius: Theme.cornerRadius
                color: root.colorMode === modelData.id ? Theme.primarySelected : SettingsMetrics.controlColor
                border.color: root.colorMode === modelData.id ? Theme.primary : Theme.withAlpha(Theme.primary, 0)
                border.width: Theme.outlineWidthFocused

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    DColorSwatch {
                        width: Theme.iconSize
                        height: Theme.iconSize
                        swatchColor: modelData.color
                        anchors.horizontalCenter: parent.horizontalCenter

                        DIcon {
                            visible: modelData.id === "custom"
                            anchors.centerIn: parent
                            name: "colorize"
                            size: Theme.iconSizeSmall
                            color: Theme.background
                        }
                    }

                    StyledText {
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.id !== "custom") {
                            root.colorModeSelected(modelData.id);
                            return;
                        }
                        PopoutService.colorPickerModal.selectedColor = root.customColor;
                        PopoutService.colorPickerModal.pickerTitle = root.pickerTitle;
                        PopoutService.colorPickerModal.onColorSelectedCallback = function (selectedColor) {
                            root.customColorSelected(selectedColor);
                            root.colorModeSelected("custom");
                        };
                        PopoutService.colorPickerModal.show(true);
                    }
                }
            }
        }
    }
}
