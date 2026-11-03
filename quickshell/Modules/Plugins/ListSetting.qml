import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

Column {
    id: root

    required property string settingKey
    required property string label
    property string description: ""
    property var defaultValue: []
    property var items: defaultValue
    property Component delegate: null
    property alias inputs: inputSlot.data
    property bool isLoading: false
    property bool _loaded: false

    width: parent.width
    spacing: Theme.spacingM

    Component.onCompleted: loadValue()

    function loadValue() {
        const settings = QmlUtils.findSettings(root.parent);
        if (settings) {
            isLoading = true;
            items = settings.loadValue(settingKey, defaultValue);
            isLoading = false;
        }
        _loaded = true;
    }

    onItemsChanged: {
        if (isLoading || !_loaded)
            return;
        const settings = QmlUtils.findSettings(root.parent);
        if (settings)
            settings.saveValue(settingKey, items);
    }

    function addItem(item) {
        items = items.concat([item]);
    }

    function removeItem(index) {
        const newItems = items.slice();
        newItems.splice(index, 1);
        items = newItems;
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

    Column {
        id: inputSlot
        width: parent.width
        spacing: Theme.spacingM
        visible: children.length > 0
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        Repeater {
            model: root.items
            delegate: root.delegate ? root.delegate : defaultDelegate
        }

        StyledText {
            text: I18n.tr("No items added yet")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            visible: root.items.length === 0
        }
    }

    Component {
        id: defaultDelegate
        StyledRect {
            width: parent.width
            height: 40
            radius: Theme.cornerRadius
            color: Theme.chipSurface
            border.width: 0

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                text: modelData
                color: Theme.surfaceText
            }

            ListSettingRemoveButton {
                onClicked: root.removeItem(index)
            }
        }
    }
}
