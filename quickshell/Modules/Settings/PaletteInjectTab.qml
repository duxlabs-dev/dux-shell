import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    Component.onCompleted: {
        if (!PaletteInjectService.loaded)
            PaletteInjectService.load();
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            width: parent.width
            iconName: "colorize"
            settingKey: "paletteInject"
            tags: ["palette", "matugen", "inject", "namespace", "command", "template", "color"]
            visible: Theme.matugenAvailable

            SettingsRow {
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        text: I18n.tr("Run an external command on each wallpaper change and merge its JSON palette into %1 under a namespace, so templates can use e.g. %2. The command receives the wallpaper as %3 and the mode as %4.", "injected palettes settings description, %1 is matugen, %2 a template placeholder, %3 and %4 placeholder and variable pairs").arg("matugen").arg("{{name.color0}}").arg("{image} / $DMS_WALLPAPER").arg("{mode} / $DMS_MODE")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        width: parent.width
                        bottomPadding: Theme.spacingS
                    }

                    StyledText {
                        visible: PaletteInjectService.palettes.length === 0
                        text: I18n.tr("No palettes configured. Use + to add one.", "injected palettes empty state")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    Repeater {
                        model: PaletteInjectService.palettes

                        delegate: Rectangle {
                            id: paletteItem
                            required property var modelData
                            required property int index

                            width: parent.width
                            height: paletteColumn.implicitHeight + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: SettingsMetrics.controlColor

                            Column {
                                id: paletteColumn
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                Row {
                                    width: parent.width
                                    spacing: Theme.spacingS

                                    StyledText {
                                        id: paletteLabel
                                        text: paletteItem.modelData.namespace ? paletteItem.modelData.namespace : I18n.tr("Palette %1", "palette heading, %1 is the palette number").arg(paletteItem.index + 1)
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Theme.fontWeightMedium
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Item {
                                        width: Math.max(0, parent.width - paletteLabel.implicitWidth - enableToggle.width - deleteBtn.width - Theme.spacingS * 2)
                                        height: 1
                                    }

                                    DToggle {
                                        id: enableToggle
                                        hideText: true
                                        checked: paletteItem.modelData.enabled !== false
                                        onToggled: checked => PaletteInjectService.updatePalette(paletteItem.index, "enabled", checked)
                                    }

                                    DActionButton {
                                        buttonSize: Theme.buttonHeightXXS
                                        iconName: "delete"
                                        iconColor: Theme.surfaceVariantText
                                        stateColor: Theme.error
                                        tooltipText: I18n.tr("Remove")
                                        anchors.verticalCenter: parent.verticalCenter
                                        onClicked: PaletteInjectService.removePalette(paletteItem.index)
                                    }
                                }

                                DTextField {
                                    outlined: true
                                    leftIconName: "label"
                                    labelText: I18n.tr("Name")
                                    placeholderText: I18n.tr("Palette name", "injected palette name field placeholder, also the matugen namespace")
                                    width: parent.width
                                    text: paletteItem.modelData.namespace || ""
                                    font.pixelSize: Theme.fontSizeSmall
                                    onEditingFinished: PaletteInjectService.updatePalette(paletteItem.index, "namespace", text)
                                }

                                DTextField {
                                    outlined: true
                                    leftIconName: "terminal"
                                    labelText: I18n.tr("Command")
                                    width: parent.width
                                    text: paletteItem.modelData.command || ""
                                    font.pixelSize: Theme.fontSizeSmall
                                    onEditingFinished: PaletteInjectService.updatePalette(paletteItem.index, "command", text)
                                }

                                DTextField {
                                    outlined: true
                                    leftIconName: "data_array"
                                    labelText: I18n.tr("Arguments", "injected palette command arguments field label")
                                    supportingText: I18n.tr("Space-separated; {image} and {mode} are substituted", "injected palette arguments field hint, {image} and {mode} stay as is")
                                    width: parent.width
                                    text: PaletteInjectService.argsText(paletteItem.modelData)
                                    font.pixelSize: Theme.fontSizeSmall
                                    onEditingFinished: PaletteInjectService.updatePalette(paletteItem.index, "args", PaletteInjectService.argsFromText(text))
                                }

                                DTextField {
                                    outlined: true
                                    leftIconName: "description"
                                    labelText: I18n.tr("JSON output path", "injected palette field label, file the command writes its palette to")
                                    supportingText: I18n.tr("File the command writes; leave empty to read stdout", "injected palette JSON output path hint")
                                    width: parent.width
                                    text: paletteItem.modelData.output_file || ""
                                    font.pixelSize: Theme.fontSizeSmall
                                    onEditingFinished: PaletteInjectService.updatePalette(paletteItem.index, "output_file", text)
                                }
                            }
                        }
                    }
                }
            }
        }

        SettingsFabBar {
            shown: Theme.matugenAvailable

            DFab {
                text: I18n.tr("Add palette", "injected palettes add button")
                iconName: "add"
                onClicked: PaletteInjectService.addPalette()
            }
        }
    }
}
