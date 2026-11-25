import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsRow {
    id: root

    property bool open: false
    property alias accessory: accessorySlot.data

    signal toggled

    clickable: true
    Accessible.name: title
    Accessible.checkable: true
    Accessible.checked: open
    Accessible.onToggleAction: toggled()
    onClicked: toggled()

    Row {
        id: accessorySlot
        spacing: Theme.spacingS
        visible: children.length > 0
        anchors.verticalCenter: parent.verticalCenter
    }

    DIcon {
        name: root.open ? "expand_less" : "expand_more"
        size: Theme.iconSize
        color: Theme.surfaceVariantText
        anchors.verticalCenter: parent.verticalCenter
    }
}
