import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/fcitx5Schema.js" as Fcitx5Schema

SettingsRow {
    id: root

    required property var row
    property var value
    readonly property var keyList: Fcitx5Schema.keyList(value)

    signal valueEdited(var path, var value)

    title: row.label
    subtitle: row.tooltip
    resetKeys: []
    clickable: row.kind === "bool"
    onClicked: valueEdited(row.path, Fcitx5Schema.boolString(!Fcitx5Schema.boolValue(value)))

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

        DToggle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.row.kind === "bool"
            hideText: true
            text: root.title
            activeFocusOnTab: false
            Accessible.ignored: true
            checked: Fcitx5Schema.boolValue(root.value)
            onToggled: value => root.valueEdited(root.row.path, Fcitx5Schema.boolString(value))
        }

        DDropdown {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.row.kind === "enum"
            backgroundColor: SettingsMetrics.controlSurface
            options: Fcitx5Schema.toArray(root.row.choices?.labels)
            optionValues: Fcitx5Schema.toArray(root.row.choices?.values)
            currentValue: String(root.value ?? "")
            Accessible.name: root.title
            onValueChanged: value => root.valueEdited(root.row.path, value)
        }

        DTextField {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.row.kind === "int" || root.row.kind === "string"
            width: root.row.kind === "int" ? Theme.iconButtonSize * 2 : Theme.iconButtonSize * 5
            text: String(root.value ?? "")
            validator: root.row.kind === "int" ? intValidator : null
            Accessible.name: root.title
            onEditingFinished: {
                if (text !== String(root.value ?? ""))
                    root.valueEdited(root.row.path, text);
            }
        }

        Fcitx5KeyChips {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.row.kind === "key" || root.row.kind === "keys"
            maxWidth: Math.max(Theme.iconButtonSize * 6, root.width * 0.6)
            keys: root.keyList
            allowModifierless: root.row.modifierless
            allowModifierOnly: root.row.modifierOnly
            onKeysEdited: keys => root.valueEdited(root.row.path, root.row.kind === "keys" ? keys : (keys[keys.length - 1] ?? ""))
        }
    }

    IntValidator {
        id: intValidator
    }
}
