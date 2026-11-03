import QtQuick
import qs.Common
import qs.DCommon.Widgets

ListSetting {
    id: root

    property var fields: []

    delegate: rowDelegate

    inputs: [
        Flow {
            width: parent.width
            spacing: Theme.spacingS

            Repeater {
                model: root.fields

                StyledText {
                    text: modelData.label
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                    width: modelData.width || 200
                }
            }
        },
        Flow {
            id: inputRow
            width: parent.width
            spacing: Theme.spacingS

            property var inputFields: []

            Repeater {
                model: root.fields

                DTextField {
                    width: modelData.width || 200
                    placeholderText: modelData.placeholder || ""

                    Component.onCompleted: inputRow.inputFields.push(this)

                    Keys.onReturnPressed: addButton.clicked()
                }
            }

            DButton {
                id: addButton
                width: 50
                height: 36
                text: I18n.tr("Add")

                onClicked: {
                    let newItem = {};
                    let hasValue = false;

                    for (let i = 0; i < root.fields.length; i++) {
                        const field = root.fields[i];
                        const value = inputRow.inputFields[i].text.trim();
                        if (value !== "")
                            hasValue = true;
                        if (field.required && value === "")
                            return;
                        newItem[field.id] = value || (field.default || "");
                    }

                    if (!hasValue)
                        return;
                    root.addItem(newItem);
                    for (let i = 0; i < inputRow.inputFields.length; i++)
                        inputRow.inputFields[i].text = "";
                    if (inputRow.inputFields.length > 0)
                        inputRow.inputFields[0].forceActiveFocus();
                }
            }
        },
        StyledText {
            text: I18n.tr("Current Items")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
            visible: root.items.length > 0
        }
    ]

    Component {
        id: rowDelegate

        StyledRect {
            width: parent.width
            height: 40
            radius: Theme.cornerRadius
            color: Theme.chipSurface
            border.width: 0

            required property int index
            required property var modelData

            Row {
                id: itemRow
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingM

                property var itemData: parent.modelData

                Repeater {
                    model: root.fields

                    StyledText {
                        required property int index
                        required property var modelData

                        text: {
                            const field = modelData;
                            const item = itemRow.itemData;
                            if (!field || !field.id || !item)
                                return "";
                            return item[field.id] || "";
                        }
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        width: modelData ? (modelData.width || 200) : 200
                        elide: Text.ElideRight
                    }
                }
            }

            ListSettingRemoveButton {
                onClicked: root.removeItem(index)
            }
        }
    }
}
