import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

Column {
    id: root

    required property string settingKey
    required property string label
    property string description: ""
    property color defaultValue: Theme.primary
    property color value: defaultValue

    width: parent.width
    spacing: Theme.spacingS

    property bool isInitialized: false

    function loadValue() {
        const settings = QmlUtils.findSettings(root.parent);
        if (!settings || !settings.pluginService)
            return;
        const loadedValue = settings.loadValue(settingKey, defaultValue);
        // pre-fix saves persisted the QColor as {}, which throws when assigned to a color property
        value = typeof loadedValue === "string" ? loadedValue : defaultValue;
        isInitialized = true;
    }

    Component.onCompleted: {
        Qt.callLater(loadValue);
    }

    onValueChanged: {
        if (!isInitialized)
            return;
        const settings = QmlUtils.findSettings(root.parent);
        if (settings) {
            settings.saveValue(settingKey, value.toString());
        }
    }

    StyledText {
        text: root.label
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        text: root.description
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        width: parent.width
        wrapMode: Text.WordWrap
        visible: root.description !== ""
    }

    Row {
        width: parent.width
        spacing: Theme.spacingS

        Rectangle {
            width: 100
            height: 36
            radius: Theme.cornerRadius
            color: root.value
            border.color: Theme.outlineStrong
            border.width: 2

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (PopoutService && PopoutService.colorPickerModal) {
                        PopoutService.colorPickerModal.selectedColor = root.value;
                        PopoutService.colorPickerModal.pickerTitle = root.label;
                        PopoutService.colorPickerModal.onColorSelectedCallback = function (selectedColor) {
                            root.value = selectedColor;
                        };
                        PopoutService.colorPickerModal.show();
                    }
                }
            }
        }

        StyledText {
            text: root.value.toString()
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
