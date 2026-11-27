pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    readonly property bool breaksEnabled: SettingsData.wellbeingBreaksEnabled

    SettingsPage {
        SettingsCard {
            iconName: "notifications_paused"
            title: I18n.tr("Smart suppression", "settings card title, conditions that hold break reminders back")
            settingKey: "wellbeingBreakSuppression"
            tab: "wellbeing_alerts"
            tags: ["wellbeing", "break", "suppress", "postpone", "fullscreen", "meeting"]

            SettingsToggleRow {
                tab: "wellbeing_alerts"
                tags: ["wellbeing", "break", "suppress", "fullscreen", "game", "video"]
                settingKey: "wellbeingBreakSuppressFullscreen"
                enabled: root.breaksEnabled
                text: I18n.tr("Suppress in fullscreen", "break reminder setting")
                description: I18n.tr("Postpones breaks while an app is fullscreen", "break reminder setting description")
                checked: SettingsData.wellbeingBreakSuppressFullscreen
                onToggled: checked => SettingsData.set("wellbeingBreakSuppressFullscreen", checked)
            }

            SettingsToggleRow {
                tab: "wellbeing_alerts"
                tags: ["wellbeing", "break", "suppress", "meeting", "call", "microphone"]
                settingKey: "wellbeingBreakSuppressMeetings"
                enabled: root.breaksEnabled
                text: I18n.tr("Suppress during meetings", "break reminder setting")
                description: I18n.tr("Postpones breaks while the microphone is in use", "break reminder setting description")
                checked: SettingsData.wellbeingBreakSuppressMeetings
                onToggled: checked => SettingsData.set("wellbeingBreakSuppressMeetings", checked)
            }
        }

        SettingsDeferred {
            SettingsCard {
                iconName: "volume_up"
                title: I18n.tr("Audio & playback", "settings card title, sound and media behavior of break reminders")
                settingKey: "wellbeingBreakAudio"
                tab: "wellbeing_alerts"
                tags: ["wellbeing", "break", "sound", "music", "media", "pause"]

                SettingsToggleRow {
                    tab: "wellbeing_alerts"
                    tags: ["wellbeing", "break", "music", "media", "pause", "mpris"]
                    settingKey: "wellbeingBreakPauseMedia"
                    enabled: root.breaksEnabled
                    text: I18n.tr("Pause media during breaks", "break reminder setting")
                    description: I18n.tr("Pauses playing media when a break starts and resumes it after", "break reminder setting description")
                    checked: SettingsData.wellbeingBreakPauseMedia
                    onToggled: checked => SettingsData.set("wellbeingBreakPauseMedia", checked)
                }

                SettingsToggleRow {
                    tab: "wellbeing_alerts"
                    tags: ["wellbeing", "break", "sound", "alert", "chime"]
                    settingKey: "wellbeingBreakSound"
                    enabled: root.breaksEnabled && SettingsData.soundsEnabled
                    text: I18n.tr("Sound alerts", "break reminder setting")
                    description: I18n.tr("Plays a sound when a break starts or ends", "break reminder setting description")
                    checked: SettingsData.wellbeingBreakSound
                    onToggled: checked => SettingsData.set("wellbeingBreakSound", checked)
                }
            }
        }
    }
}
