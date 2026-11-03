pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import "../../Common/Format.js" as Format

Item {
    id: root

    property var parentModal: null

    readonly property bool matugenSmartCapable: Theme.matugenAvailable && DMSService.matugenSmartSupported && Theme.currentTheme === Theme.dynamic
    readonly property var modes: matugenSmartCapable ? ["manual", "time", "location", "wallpaper"] : ["manual", "time", "location"]
    readonly property var modeLabels: [I18n.tr("Manual"), I18n.tr("Schedule", "noun, time based light and dark theme switching mode"), I18n.tr("Location", "noun, automatic mode based on geographic location, also weather location card"), I18n.tr("Wallpaper")].slice(0, modes.length)
    readonly property string mode: {
        if (SettingsData.matugenSmartMode)
            return "wallpaper";
        if (!SessionData.themeModeAutoEnabled)
            return "manual";
        return SessionData.themeModeAutoMode === "location" ? "location" : "time";
    }
    readonly property bool scheduled: mode === "time" || mode === "location"
    readonly property bool ownSchedule: scheduled && !SessionData.themeModeShareGammaSettings

    function setMode(value) {
        switch (value) {
        case "wallpaper":
            if (SessionData.themeModeAutoEnabled)
                SessionData.setThemeModeAutoEnabled(false);
            SettingsData.setMatugenSmartMode(true);
            return;
        case "time":
        case "location":
            if (SettingsData.matugenSmartMode)
                SettingsData.setMatugenSmartMode(false);
            SessionData.setThemeModeAutoMode(value);
            SessionData.setThemeModeAutoEnabled(true);
            return;
        }
        if (SettingsData.matugenSmartMode)
            SettingsData.setMatugenSmartMode(false);
        SessionData.setThemeModeAutoEnabled(false);
    }

    SettingsPage {
        SettingsCard {
            tab: "theme"
            tags: ["light", "dark", "mode", "appearance", "automatic", "schedule", "sunrise", "sunset", "matugen", "smart", "wallpaper", "brightness"]
            settingKey: "themeSchedule"

            SettingsToggleRow {
                tab: "theme"
                tags: ["light", "dark", "mode"]
                settingKey: "themeScheduleDarkMode"
                iconName: "dark_mode"
                text: I18n.tr("Dark mode")
                checked: !SessionData.isLightMode
                onToggled: toggled => {
                    if (toggled === !SessionData.isLightMode)
                        return;
                    Theme.screenTransition();
                    Theme.setLightMode(!toggled);
                }
            }

            SettingsButtonGroupRow {
                tab: "theme"
                tags: ["automatic", "schedule", "location", "sunrise", "sunset", "wallpaper", "matugen"]
                settingKey: "themeModeAutoEnabled"
                text: I18n.tr("Automatic control")
                model: root.modeLabels
                currentIndex: Math.max(0, root.modes.indexOf(root.mode))
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    root.setMode(root.modes[index]);
                }
            }

            SettingsToggleRow {
                tab: "theme"
                tags: ["gamma", "night", "share", "schedule"]
                settingKey: "themeModeShareGammaSettings"
                visible: root.scheduled
                text: I18n.tr("Share gamma control settings")
                description: SessionData.themeModeShareGammaSettings ? I18n.tr("Using shared settings from Gamma Control") : ""
                checked: SessionData.themeModeShareGammaSettings
                onToggled: checked => SessionData.setThemeModeShareGammaSettings(checked)
            }

            SettingsTimeRow {
                visible: root.ownSchedule && root.mode === "time"
                is24Hour: SettingsData.use24HourClock
                startTitle: I18n.tr("Dark mode starts")
                startHour: SessionData.themeModeStartHour
                startMinute: SessionData.themeModeStartMinute
                endTitle: I18n.tr("Light mode starts")
                endHour: SessionData.themeModeEndHour
                endMinute: SessionData.themeModeEndMinute
                onStartChanged: (hour, minute) => {
                    SessionData.setThemeModeStartHour(hour);
                    SessionData.setThemeModeStartMinute(minute);
                }
                onEndChanged: (hour, minute) => {
                    SessionData.setThemeModeEndHour(hour);
                    SessionData.setThemeModeEndMinute(minute);
                }
            }

            SettingsLocationSection {
                visible: root.ownSchedule && root.mode === "location"
            }

            SettingsRow {
                iconName: "schedule"
                title: I18n.tr("Next Transition")
                subtitle: Format.formatIsoTime(SessionData.themeModeNextTransition)
                visible: root.scheduled && SessionData.themeModeNextTransition !== ""
            }
        }
    }
}
