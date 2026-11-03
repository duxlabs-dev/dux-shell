import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsRow {
    id: root

    property bool selected: false
    property string summary: ""
    property bool checked: false
    property bool toggleVisible: true
    property bool toggleEnabled: true
    property bool deletable: true

    signal toggled(bool checked)
    signal deleteRequested

    clickable: true
    iconName: selected ? "radio_button_checked" : "radio_button_unchecked"
    iconColor: selected ? Theme.primary : Theme.surfaceVariantText
    subtitle: deleteButton.confirming ? I18n.tr("Confirm Delete") : summary
    subtitleColor: deleteButton.confirming ? Theme.error : Theme.surfaceVariantText

    DToggle {
        visible: root.toggleVisible
        hideText: true
        text: root.title
        activeFocusOnTab: false
        checked: root.checked
        enabled: root.toggleEnabled
        onToggled: value => root.toggled(value)
    }

    SettingsDeleteButton {
        id: deleteButton
        visible: root.deletable
        onDeleteRequested: root.deleteRequested()
    }
}
