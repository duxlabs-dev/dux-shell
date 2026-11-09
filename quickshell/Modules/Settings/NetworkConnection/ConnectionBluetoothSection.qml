import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

SettingsCard {
    id: root

    required property var editor

    readonly property int rev: editor.revision
    readonly property var bt: {
        rev;
        return editor.draft?.bluetooth ?? {};
    }
    readonly property bool valid: true

    title: I18n.tr("Bluetooth")

    SettingsRow {
        title: I18n.tr("Device")
        subtitle: String(root.bt.bdaddr ?? "")
    }

    SettingsRow {
        title: I18n.tr("Type")
        subtitle: String(root.bt.type ?? "").toUpperCase()
    }
}
