import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

Column {
    id: root

    required property string settingKey
    required property string label
    property string description: ""
    property int defaultValue: 0
    property int value: defaultValue
    property int minimum: 0
    property int maximum: 100
    property string startIcon: ""
    property string endIcon: ""
    property alias leftIcon: root.startIcon // ! TODO deprecate me after 1.7 release
    property alias rightIcon: root.endIcon // ! TODO deprecate me after 1.7 release
    property bool iconsClickable: false
    property string unit: ""

    width: parent.width
    spacing: Theme.spacingS

    function loadValue() {
        const settings = QmlUtils.findSettings(root.parent);
        if (settings && settings.pluginService) {
            value = settings.loadValue(settingKey, defaultValue);
        }
    }

    Component.onCompleted: {
        loadValue();
    }

    onValueChanged: {
        const settings = QmlUtils.findSettings(root.parent);
        if (settings) {
            settings.saveValue(settingKey, value);
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

    DSlider {
        upDownKeysStep: false
        width: parent.width
        value: root.value
        minimum: root.minimum
        maximum: root.maximum
        startIcon: root.startIcon
        endIcon: root.endIcon
        iconsClickable: root.iconsClickable
        unit: root.unit
        wheelEnabled: false
        onSliderValueChanged: newValue => {
            root.value = newValue;
        }
    }
}
