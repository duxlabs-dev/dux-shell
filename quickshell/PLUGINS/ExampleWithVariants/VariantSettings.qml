import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "exampleVariants"

    onVariantsChanged: {
        variantsModel.clear();
        for (var i = 0; i < variants.length; i++) {
            variantsModel.append(variants[i]);
        }
    }

    StyledText {
        width: parent.width
        text: "Variant Manager"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Create multiple widget variants with different text, icons, and colors"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: addVariantColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.chipSurface

        Column {
            id: addVariantColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Add New Variant"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: (parent.width - Theme.spacingM * 2) / 3
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Name"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    DTextField {
                        id: nameField
                        width: parent.width
                        placeholderText: "Variant Name"
                    }
                }

                Column {
                    width: (parent.width - Theme.spacingM * 2) / 3
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Icon"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    DTextField {
                        id: iconField
                        width: parent.width
                        placeholderText: "star"
                    }
                }

                Column {
                    width: (parent.width - Theme.spacingM * 2) / 3
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Text"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    DTextField {
                        id: textField
                        width: parent.width
                        placeholderText: "Display Text"
                    }
                }
            }

            DButton {
                text: "Create Variant"
                iconName: "add"
                onClicked: {
                    if (!nameField.text) {
                        ToastService.showError("Please enter a variant name");
                        return;
                    }

                    var variantConfig = {
                        text: textField.text || nameField.text,
                        icon: iconField.text || "widgets"
                    };

                    createVariant(nameField.text, variantConfig);
                    ToastService.showInfo("Variant created: " + nameField.text);

                    nameField.text = "";
                    iconField.text = "";
                    textField.text = "";
                }
            }
        }
    }

    StyledRect {
        width: parent.width
        height: Math.max(200, variantsColumn.implicitHeight + Theme.spacingL * 2)
        radius: Theme.cornerRadius
        color: Theme.chipSurface

        Column {
            id: variantsColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Existing Variants"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            ListView {
                width: parent.width
                height: Math.max(100, contentHeight)
                clip: true
                spacing: Theme.spacingXS

                model: ListModel {
                    id: variantsModel
                }

                delegate: StyledRect {
                    required property var model
                    width: ListView.view.width
                    height: variantRow.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: variantMouseArea.containsMouse ? Theme.chipSurfaceNested : Theme.chipSurface

                    Row {
                        id: variantRow
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        Item {
                            width: Theme.iconSize
                            height: Theme.iconSize
                            anchors.verticalCenter: parent.verticalCenter

                            DIcon {
                                anchors.centerIn: parent
                                name: model.icon || "widgets"
                                size: Theme.iconSize
                                color: Theme.surfaceText
                                width: Theme.iconSize
                                height: Theme.iconSize
                                clip: true
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS
                            width: parent.width - Theme.iconSize - deleteButton.width - Theme.spacingM * 4

                            StyledText {
                                text: model.name || "Unnamed"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                width: parent.width
                                elide: Text.ElideRight
                            }

                            StyledText {
                                text: "Text: " + (model.text || "") + " | Icon: " + (model.icon || "")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                width: parent.width
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: deleteButton
                            Accessible.role: Accessible.Button
                            Accessible.name: I18n.tr("Delete")
                            width: 32
                            height: 32
                            radius: 16
                            color: deleteArea.containsMouse ? Theme.error : Theme.withAlpha(Theme.error, 0)
                            anchors.verticalCenter: parent.verticalCenter

                            DIcon {
                                anchors.centerIn: parent
                                name: "delete"
                                size: 16
                                color: deleteArea.containsMouse ? Theme.onError : Theme.surfaceVariantText
                            }

                            MouseArea {
                                id: deleteArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    removeVariant(model.id);
                                    ToastService.showInfo("Variant removed: " + model.name);
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: variantMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        propagateComposedEvents: true
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    text: "No variants created yet"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    visible: variantsModel.count === 0
                }
            }
        }
    }

    StyledRect {
        width: parent.width
        height: instructionsColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.hostSurface

        Column {
            id: instructionsColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                spacing: Theme.spacingM

                DIcon {
                    name: "info"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "How to Use Variants"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: "1. Create variants with different names, icons, and text\n2. Go to Bar Settings and click 'Add Widget'\n3. Each variant will appear as a separate widget option\n4. Add variants to your bar just like any other widget"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
            }
        }
    }
}
