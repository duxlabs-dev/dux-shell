import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsRow {
    id: root

    property bool checked: false
    property bool navigable: true

    signal navigated(bool keyboard)
    signal toggled(bool checked)

    clickable: navigable
    onClicked: keyboard => navigated(keyboard)

    DIcon {
        name: "chevron_right"
        size: Theme.iconSize
        color: Theme.surfaceVariantText
        rotation: I18n.isRtl ? 180 : 0
        visible: root.navigable
        anchors.verticalCenter: parent.verticalCenter
    }

    SettingsDivider {
        vertical: true
        visible: root.navigable
    }

    Item {
        width: Theme.spacingS
        height: parent.height
        visible: root.navigable
    }

    DToggle {
        hideText: true
        text: root.title
        checked: root.checked
        enabled: root.enabled
        onToggled: value => root.toggled(value)
    }
}
