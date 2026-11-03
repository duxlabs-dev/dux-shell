import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsRow {
    id: root

    property string text: ""
    property string description: ""
    property color descriptionColor: Theme.surfaceVariantText
    property bool checked: false
    property bool toggling: false
    property alias accessory: accessorySlot.data

    signal toggled(bool checked)

    title: text
    subtitle: description
    subtitleColor: descriptionColor
    clickable: true
    resetKeys: []
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onToggleAction: root.clicked(true)
    onClicked: {
        if (!enabled || toggling)
            return;
        toggled(!checked);
    }

    Row {
        id: accessorySlot
        spacing: Theme.spacingS
        visible: children.length > 0
        anchors.verticalCenter: parent.verticalCenter
    }

    DToggle {
        anchors.verticalCenter: parent.verticalCenter
        hideText: true
        text: root.text
        description: root.description
        activeFocusOnTab: false
        Accessible.ignored: true
        checked: root.checked
        enabled: root.enabled
        toggling: root.toggling
        onToggled: value => root.toggled(value)
    }
}
