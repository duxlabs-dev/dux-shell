import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.DCommon.Common as DCommon
import qs.Modules.Settings.Widgets
import "../../Common/fcitx5Schema.js" as Fcitx5Schema

SettingsRow {
    id: root

    required property var row
    property var value
    readonly property var keyList: Fcitx5Schema.keyList(value)
    readonly property var fontParts: Fcitx5Schema.parseFont(value)
    property var fontFamilies: []
    readonly property var fontStyleValues: {
        const styles = ["", "Light", "Medium", "Bold", "Italic", "Bold Italic"];
        return styles.includes(fontParts.style) ? styles : [fontParts.style].concat(styles);
    }
    readonly property var fontStyleLabels: fontStyleValues.map(v => ({
                "": I18n.tr("Regular", "font style"),
                "Light": I18n.tr("Light", "font style"),
                "Medium": I18n.tr("Medium", "font style"),
                "Bold": I18n.tr("Bold", "font style"),
                "Italic": I18n.tr("Italic", "font style"),
                "Bold Italic": I18n.tr("Bold Italic", "font style")
            }[v] ?? v))

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

        DDropdown {
            id: fontDropdown
            anchors.verticalCenter: parent.verticalCenter
            visible: root.row.kind === "font"
            backgroundColor: SettingsMetrics.controlSurface
            enableFuzzySearch: true
            popupWidthOffset: SettingsMetrics.fontMenuExtraWidth
            options: root.fontFamilies
            currentValue: root.fontParts.family
            Accessible.name: root.title
            onValueChanged: value => {
                if (value !== root.fontParts.family)
                    root.valueEdited(root.row.path, Fcitx5Schema.buildFont(Object.assign({}, root.fontParts, {
                        "family": value
                    })));
            }
        }

        DDropdown {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.row.kind === "font"
            backgroundColor: SettingsMetrics.controlSurface
            options: root.fontStyleLabels
            optionValues: root.fontStyleValues
            currentValue: root.fontParts.style
            Accessible.name: I18n.tr("Style", "font style")
            onValueChanged: value => {
                if (value !== root.fontParts.style)
                    root.valueEdited(root.row.path, Fcitx5Schema.buildFont(Object.assign({}, root.fontParts, {
                        "style": value
                    })));
            }
        }

        DTextField {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.row.kind === "font"
            width: Theme.iconButtonSize * 1.5
            text: root.fontParts.size
            validator: sizeValidator
            Accessible.name: I18n.tr("Size", "font size")
            onEditingFinished: {
                if (text !== "" && text !== root.fontParts.size)
                    root.valueEdited(root.row.path, Fcitx5Schema.buildFont(Object.assign({}, root.fontParts, {
                        "size": text
                    })));
            }
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

    IntValidator {
        id: sizeValidator
        bottom: 1
        top: 999
    }

    Component.onCompleted: {
        if (row.kind !== "font")
            return;
        const families = DCommon.Fonts.selectableFamilies("");
        const current = fontParts.family;
        fontFamilies = current && !families.includes(current) ? [current].concat(families) : families;
    }
}
