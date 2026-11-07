import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsRow {
    id: root

    property string text: ""
    property string description: ""
    property alias model: buttonGroup.model
    property alias currentIndex: buttonGroup.currentIndex
    property alias initialSelection: buttonGroup.initialSelection
    property alias currentSelection: buttonGroup.currentSelection
    property alias selectionMode: buttonGroup.selectionMode
    property alias buttonHeight: buttonGroup.buttonHeight
    property alias minButtonWidth: buttonGroup.minButtonWidth
    property alias buttonPadding: buttonGroup.buttonPadding
    property alias checkIconSize: buttonGroup.checkIconSize
    property alias textSize: buttonGroup.textSize
    property alias checkEnabled: buttonGroup.checkEnabled

    readonly property bool compact: width - buttonGroup.naturalWidth - SettingsMetrics.rowPaddingH * 2 - SettingsMetrics.rowContentSpacing < SettingsMetrics.buttonGroupCompactThreshold

    // `values` is index-aligned with `model`.
    property var values: []
    property var value: undefined
    property var fallbackValue: undefined

    signal selectionChanged(int index, bool selected)
    signal valueSelected(var value)

    function indexOfValue(value) {
        const index = values.indexOf(value);
        return index >= 0 ? index : Math.max(0, values.indexOf(fallbackValue));
    }

    title: text
    subtitle: description

    Item {
        id: trailingHost
        width: root.compact ? 0 : buttonGroup.width
        height: root.compact ? 0 : buttonGroup.height
        visible: !root.compact
        anchors.verticalCenter: parent.verticalCenter
    }

    body: Item {
        id: bodyHost
        width: parent.width
        height: buttonGroup.height
        visible: root.compact
    }

    DButtonGroup {
        id: buttonGroup
        arrowKeysSelect: false
        parent: root.compact ? bodyHost : trailingHost
        x: root.compact ? (parent.width - width) / 2 : 0
        selectionMode: "single"
        currentIndex: root.values.length > 0 ? root.indexOfValue(root.value) : 0
        enabled: root.enabled
        maximumWidth: root.compact ? root.width - SettingsMetrics.rowPaddingH * 2 : -1
        onSelectionChanged: (index, selected) => {
            root.selectionChanged(index, selected);
            if (selected && index < root.values.length)
                root.valueSelected(root.values[index]);
        }
    }
}
