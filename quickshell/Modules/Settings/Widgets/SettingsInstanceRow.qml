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
    property bool deleteEnabled: true

    property bool renameVisible: false
    property bool renameEnabled: true
    property bool defaultVisible: false
    property bool defaultEnabled: true

    signal toggled(bool checked)
    signal deleteRequested
    signal renameRequested
    signal defaultRequested

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

    DActionButton {
        visible: root.renameVisible
        enabled: root.renameEnabled
        iconName: "edit"
        tooltipText: I18n.tr("Rename")
        onClicked: root.renameRequested()
    }

    SettingsDeleteButton {
        id: deleteButton
        visible: root.deletable
        enabled: root.deleteEnabled
        onDeleteRequested: root.deleteRequested()
    }

    DActionButton {
        visible: root.defaultVisible
        enabled: root.defaultEnabled
        iconName: "check_circle"
        tooltipText: I18n.tr("Set as default", "button, makes this firewall zone the default one")
        onClicked: root.defaultRequested()
    }
}
