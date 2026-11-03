import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import "../../Common/MuxBackends.js" as MuxBackends

Item {
    id: root

    readonly property var muxTypeOptions: Object.keys(MuxBackends.BACKENDS)

    SettingsPage {
        id: mainColumn

        SettingsCard {
            tab: "mux"
            tags: ["mux", "multiplexer", "tmux", "zellij", "herdr", "type"]
            title: I18n.tr("General")
            iconName: "terminal"

            SettingsDropdownRow {
                tab: "mux"
                tags: ["mux", "multiplexer", "tmux", "zellij", "herdr", "type", "backend"]
                settingKey: "muxType"
                text: I18n.tr("Type")
                options: root.muxTypeOptions
                currentValue: SettingsData.muxType
                onValueChanged: value => SettingsData.set("muxType", value)
            }
        }

        SettingsCard {
            tab: "mux"
            tags: ["mux", "terminal", "custom", "command", "script"]
            title: I18n.tr("Terminal")
            iconName: "desktop_windows"

            SettingsToggleRow {
                tab: "mux"
                tags: ["mux", "custom", "command", "override"]
                settingKey: "muxUseCustomCommand"
                text: I18n.tr("Use custom command")
                checked: SettingsData.muxUseCustomCommand
                onToggled: checked => SettingsData.set("muxUseCustomCommand", checked)
            }

            SettingsTextFieldRow {
                resetKeys: ["muxCustomCommand"]
                leftIconName: "terminal"
                text: I18n.tr("Custom command")
                visible: SettingsData.muxUseCustomCommand
                description: I18n.tr("The custom command used when attaching to sessions (receives the session name as the first argument)")
                value: SettingsData.muxCustomCommand
                onValueEdited: value => SettingsData.set("muxCustomCommand", value)
            }
        }

        SettingsCard {
            tab: "mux"
            tags: ["mux", "session", "filter", "exclude", "hide"]
            settingKey: "muxSessionFilter"
            title: I18n.tr("Session filter")
            iconName: "filter_list"

            SettingsTextFieldRow {
                resetKeys: ["muxSessionFilter"]
                leftIconName: "filter_list"
                text: I18n.tr("Pattern")
                description: I18n.tr("Comma-separated list of session names to hide. Wrap in slashes for regex (e.g., /^_.*/).")
                value: SettingsData.muxSessionFilter
                placeholderText: I18n.tr("e.g., scratch, /^tmp_.*/, build")
                onValueEdited: value => SettingsData.set("muxSessionFilter", value)
            }
        }
    }
}
