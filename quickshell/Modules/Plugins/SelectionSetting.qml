import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

Column {
    id: root

    required property string settingKey
    required property string label
    property string description: ""
    required property var options
    property string defaultValue: ""
    property string value: defaultValue

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

    readonly property var optionLabels: {
        const labels = [];
        for (let i = 0; i < options.length; i++) {
            labels.push(options[i].label || options[i]);
        }
        return labels;
    }

    readonly property var valueToLabel: {
        const map = {};
        for (let i = 0; i < options.length; i++) {
            const opt = options[i];
            if (typeof opt === 'object') {
                map[opt.value] = opt.label;
            } else {
                map[opt] = opt;
            }
        }
        return map;
    }

    readonly property var labelToValue: {
        const map = {};
        for (let i = 0; i < options.length; i++) {
            const opt = options[i];
            if (typeof opt === 'object') {
                map[opt.label] = opt.value;
            } else {
                map[opt] = opt;
            }
        }
        return map;
    }

    onValueChanged: {
        const settings = QmlUtils.findSettings(root.parent);
        if (settings) {
            settings.saveValue(settingKey, value);
        }
    }

    DDropdown {
        downKeyOpens: false
        width: parent.width
        text: root.label
        description: root.description
        currentValue: root.valueToLabel[root.value] || root.value
        options: root.optionLabels
        onValueChanged: newValue => {
            root.value = root.labelToValue[newValue] || newValue;
        }
    }
}
