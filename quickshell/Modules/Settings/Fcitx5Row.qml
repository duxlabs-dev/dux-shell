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
    signal subOpened(string addon, string title)

    title: row.label
    subtitle: row.tooltip
    clickable: row.kind === "bool" || row.kind === "sub"
    showChevron: row.kind === "sub"
    onClicked: {
        if (row.kind === "sub")
            subOpened(row.addon, row.label);
        else
            valueEdited(row.path, Fcitx5Schema.boolString(!Fcitx5Schema.boolValue(value)));
    }

    readonly property var controls: ({
            "bool": toggle,
            "enum": dropdown,
            "font": fontControls,
            "int": textField,
            "string": textField,
            "strings": listField,
            "key": keyChips,
            "keys": keyChips
        })

    Loader {
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: root.controls[root.row.kind] ?? null
    }

    Component {
        id: toggle

        DToggle {
            hideText: true
            text: root.title
            activeFocusOnTab: false
            Accessible.ignored: true
            checked: Fcitx5Schema.boolValue(root.value)
            onToggled: value => root.valueEdited(root.row.path, Fcitx5Schema.boolString(value))
        }
    }

    Component {
        id: dropdown

        DDropdown {
            readonly property string syncedValue: String(root.value ?? "")

            onSyncedValueChanged: currentValue = syncedValue
            backgroundColor: SettingsMetrics.controlSurface
            options: Fcitx5Schema.toArray(root.row.choices?.labels)
            optionValues: Fcitx5Schema.toArray(root.row.choices?.values)
            width: Math.min(dropdownWidth, root.width - SettingsMetrics.rowPaddingH * 2)
            Accessible.name: root.title
            onValueChanged: value => {
                if (value !== String(root.value ?? ""))
                    root.valueEdited(root.row.path, value);
            }
        }
    }

    Component {
        id: fontControls

        Fcitx5FontControls {
            value: root.value
            title: root.title
            onFontEdited: font => root.valueEdited(root.row.path, font)
        }
    }

    Component {
        id: textField

        DTextField {
            width: root.row.kind === "int" ? SettingsMetrics.fieldWidthS : SettingsMetrics.fieldWidthM
            text: String(root.value ?? "")
            validator: root.row.kind === "int" ? intValidator : null
            Accessible.name: root.title
            onEditingFinished: {
                if (text !== String(root.value ?? ""))
                    root.valueEdited(root.row.path, text);
            }
        }
    }

    Component {
        id: listField

        DTextField {
            width: SettingsMetrics.fieldWidthL
            text: Fcitx5Schema.joinList(root.value)
            Accessible.name: root.title
            onEditingFinished: {
                if (text !== Fcitx5Schema.joinList(root.value))
                    root.valueEdited(root.row.path, Fcitx5Schema.splitList(text));
            }
        }
    }

    Component {
        id: keyChips

        Fcitx5KeyChips {
            maxWidth: Math.max(SettingsMetrics.fieldWidthL, root.width * 0.6)
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
