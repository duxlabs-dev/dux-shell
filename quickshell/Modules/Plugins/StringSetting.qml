import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

Column {
    id: root

    required property string settingKey
    required property string label
    property string description: ""
    property string placeholder: ""
    property string defaultValue: ""
    property string value: defaultValue

    width: parent.width
    spacing: Theme.spacingS

    property bool isInitialized: false

    function loadValue() {
        const settings = QmlUtils.findSettings(root.parent);
        if (settings && settings.pluginService) {
            const loadedValue = settings.loadValue(settingKey, defaultValue);
            if (textField.activeFocus && isInitialized)
                return;
            value = loadedValue;
            textField.text = loadedValue;
            isInitialized = true;
        }
    }

    Component.onCompleted: {
        Qt.callLater(loadValue);
    }

    function commit() {
        if (!isInitialized)
            return;
        if (textField.text === value)
            return;
        value = textField.text;
        const settings = QmlUtils.findSettings(root.parent);
        if (settings)
            settings.saveValue(settingKey, value);
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

    DTextField {
        id: textField
        width: parent.width
        placeholderText: root.placeholder
        onEditingFinished: root.commit()
        onActiveFocusChanged: {
            if (!activeFocus)
                root.commit();
        }
    }
}
