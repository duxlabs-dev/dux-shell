import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.DCommon.Common as DCommon
import qs.Modules.Settings.Widgets
import "../../Common/fcitx5Schema.js" as Fcitx5Schema

Row {
    id: root

    property var value
    property string title
    readonly property var parts: Fcitx5Schema.parseFont(value)
    property var families: []
    // DDropdown shows emptyText for "", so Regular needs a non-empty key.
    readonly property string regularKey: "Regular"
    readonly property string styleKey: parts.style === "" ? regularKey : parts.style
    readonly property var styleLabels: ({
            "Regular": I18n.tr("Regular", "font style"),
            "Light": I18n.tr("Light", "font style"),
            "Medium": I18n.tr("Medium", "font style"),
            "Bold": I18n.tr("Bold", "font style"),
            "Italic": I18n.tr("Italic", "font style"),
            "Bold Italic": I18n.tr("Bold Italic", "font style")
        })
    readonly property var styleValues: {
        const styles = Object.keys(styleLabels);
        return styles.includes(styleKey) ? styles : [styleKey].concat(styles);
    }

    signal fontEdited(string font)

    function editPart(part, text) {
        const next = part === "style" && text === regularKey ? "" : text;
        if (next === parts[part])
            return;
        const edited = Object.assign({}, parts);
        edited[part] = next;
        fontEdited(Fcitx5Schema.buildFont(edited));
    }

    spacing: Theme.spacingS

    DDropdown {
        anchors.verticalCenter: parent.verticalCenter
        backgroundColor: SettingsMetrics.controlSurface
        enableFuzzySearch: true
        popupWidthOffset: SettingsMetrics.fontMenuExtraWidth
        options: root.families
        currentValue: root.parts.family
        Accessible.name: root.title
        onValueChanged: value => root.editPart("family", value)
    }

    DDropdown {
        anchors.verticalCenter: parent.verticalCenter
        backgroundColor: SettingsMetrics.controlSurface
        options: root.styleValues.map(v => root.styleLabels[v] ?? v)
        optionValues: root.styleValues
        currentValue: root.styleKey
        Accessible.name: I18n.tr("Style", "font style")
        onValueChanged: value => root.editPart("style", value)
    }

    DTextField {
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.iconButtonSize * 1.5
        text: root.parts.size
        validator: sizeValidator
        Accessible.name: I18n.tr("Size", "font size")
        onEditingFinished: {
            if (text !== "")
                root.editPart("size", text);
        }
    }

    IntValidator {
        id: sizeValidator
        bottom: 1
        top: 999
    }

    Component.onCompleted: {
        const all = DCommon.Fonts.selectableFamilies("");
        const current = parts.family;
        families = current && !all.includes(current) ? [current].concat(all) : all;
    }
}
