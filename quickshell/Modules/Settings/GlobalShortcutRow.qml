pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

SettingsRow {
    id: root

    required property var shortcut
    property string key: shortcut.triggers?.[0] ?? ""
    property var conflicts: []

    readonly property string preferredKey: shortcut.preferred?.[0] ?? ""

    signal editRequested

    title: shortcut.description || shortcut.id
    subtitle: conflicts.length > 0 ? I18n.tr("Conflicts with: %1", "keybind warning, %1 is a list of conflicting bind descriptions").arg(conflicts.map(bind => bind.desc).join(", ")) : ""
    subtitleColor: Theme.primary
    modified: key !== preferredKey
    resetByKeys: false

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

        DKeycap {
            text: root.key
            visible: root.key !== ""
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: I18n.tr("Disabled")
            visible: root.key === ""
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            anchors.verticalCenter: parent.verticalCenter
        }

        DActionButton {
            iconName: "edit"
            Accessible.name: I18n.tr("Edit")
            Accessible.description: root.title
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.editRequested()
        }
    }
}
