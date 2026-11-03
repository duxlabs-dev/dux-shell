import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.DesktopWidgetSettings

DesktopWidgetInstanceSettings {
    id: root

    showAppearance: false

    SettingsToggleRow {
        text: I18n.tr("Show date")
        checked: root.instanceData?.enabled !== false
        onToggled: checked => SettingsData.updateDesktopWidgetInstance(root.instanceId, {
                enabled: checked
            })
    }

    SettingsDropdownRow {
        text: I18n.tr("Date format", "lock screen date widget dropdown")
        options: [I18n.tr("Short", "date format option"), I18n.tr("Long", "date format option")]
        currentValue: (root.cfg.format ?? "long") === "short" ? I18n.tr("Short", "date format option") : I18n.tr("Long", "date format option")
        enabled: SettingsData.lockDateFormat === ""
        onValueChanged: value => root.updateConfig("format", value === I18n.tr("Short", "date format option") ? "short" : "long")
    }

    SettingsColorPicker {
        showDefault: true
        colorMode: root.cfg.colorMode ?? "default"
        customColor: root.cfg.customColor ?? "#ffffff"
        onColorModeSelected: mode => root.updateConfig("colorMode", mode)
        onCustomColorSelected: selectedColor => root.updateConfig("customColor", selectedColor.toString())
    }
}
