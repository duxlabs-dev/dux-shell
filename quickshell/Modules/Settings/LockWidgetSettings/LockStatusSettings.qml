import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.DesktopWidgetSettings

DesktopWidgetInstanceSettings {
    id: root

    property var parentModal: null

    showAppearance: false

    SettingsToggleRow {
        text: I18n.tr("Background")
        checked: root.cfg.background ?? false
        onToggled: checked => root.updateConfig("background", checked)
    }

    SettingsToggleRow {
        visible: !root.greeterInstance
        text: I18n.tr("Show media player")
        checked: root.cfg.showMediaPlayer ?? true
        onToggled: checked => root.updateConfig("showMediaPlayer", checked)
    }

    SettingsSplitRow {
        title: I18n.tr("Weather")
        checked: root.cfg.showWeather ?? true
        onToggled: checked => root.updateConfig("showWeather", checked)
        onNavigated: keyboard => root.parentModal?.navigateTo("weather", keyboard)
    }
}
