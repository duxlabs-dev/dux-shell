import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property string positionScope: ""
    readonly property var positionScopes: [
        {
            "value": "",
            "label": I18n.tr("Default"),
            "shown": true
        },
        {
            "value": "volume",
            "label": I18n.tr("Volume"),
            "shown": SettingsData.osdVolumeEnabled
        },
        {
            "value": "mediaVolume",
            "label": I18n.tr("Media volume"),
            "shown": SettingsData.osdMediaVolumeEnabled
        },
        {
            "value": "mediaPlayback",
            "label": I18n.tr("Media playback"),
            "shown": SettingsData.osdMediaPlaybackEnabled
        },
        {
            "value": "brightness",
            "label": I18n.tr("Brightness"),
            "shown": SettingsData.osdBrightnessEnabled
        },
        {
            "value": "idleInhibitor",
            "label": I18n.tr("Idle inhibitor", "feature that keeps the session from going idle"),
            "shown": SettingsData.osdIdleInhibitorEnabled
        },
        {
            "value": "mic",
            "label": I18n.tr("Microphone"),
            "shown": SettingsData.osdMicMuteEnabled || SettingsData.osdMicVolumeEnabled
        },
        {
            "value": "capsLock",
            "label": I18n.tr("Caps lock"),
            "shown": SettingsData.osdCapsLockEnabled
        },
        {
            "value": "numLock",
            "label": I18n.tr("Num lock", "OSD toggle for the Num Lock indicator"),
            "shown": SettingsData.osdNumLockEnabled
        },
        {
            "value": "keyboardLayout",
            "label": I18n.tr("Keyboard layout"),
            "shown": SettingsData.osdKeyboardLayoutEnabled && KeyboardLayoutService.available
        },
        {
            "value": "touchpad",
            "label": I18n.tr("Touchpad"),
            "shown": SettingsData.osdTouchpadEnabled && CompositorService.isNiri
        },
        {
            "value": "powerProfile",
            "label": I18n.tr("Power profile"),
            "shown": SettingsData.osdPowerProfileEnabled
        },
        {
            "value": "audioOutput",
            "label": I18n.tr("Audio output switch"),
            "shown": SettingsData.osdAudioOutputEnabled
        },
        {
            "value": "workspace",
            "label": I18n.tr("Workspace Switch", "toggle label for workspace change OSD"),
            "shown": SettingsData.osdWorkspaceEnabled
        }
    ].filter(scope => scope.shown).map(scope => ({
                "value": scope.value,
                "label": scope.label,
                "icon": SettingsData.hasOsdPositionOverride(scope.value) ? "pin_drop" : "",
                "tooltip": SettingsData.hasOsdPositionOverride(scope.value) ? I18n.tr("Custom") : ""
            }))

    onPositionScopesChanged: {
        if (!positionScopes.some(scope => scope.value === positionScope))
            positionScope = "";
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            width: parent.width
            settingKey: "osd"

            SettingsRow {
                id: positionRow

                readonly property bool overridden: root.positionScope !== "" && SettingsData.hasOsdPositionOverride(root.positionScope)

                settingKey: "osdPosition"
                title: I18n.tr("Position")
                subtitle: {
                    const label = positionPicker.labelFor(SettingsData.osdPositionFor(root.positionScope));
                    return root.positionScope !== "" && !overridden ? I18n.tr("Default") + " · " + label : label;
                }
                modified: root.positionScope === "" ? !SettingsData.isDefault(["osdPosition"]) : overridden
                resetByKeys: false
                onResetRequested: SettingsData.resetOsdPosition(root.positionScope)

                body: [
                    DFilterChips {
                        model: root.positionScopes
                        Binding on currentIndex {
                            value: Math.max(0, root.positionScopes.findIndex(scope => scope.value === root.positionScope))
                            restoreMode: Binding.RestoreNone
                        }
                        showCounts: false
                        onSelectionChanged: index => root.positionScope = root.positionScopes[index].value
                    },
                    SettingsScreenPositionPicker {
                        id: positionPicker
                        selected: SettingsData.osdPositionFor(root.positionScope)
                        onPicked: position => SettingsData.setOsdPosition(root.positionScope, position)
                    }
                ]
            }

            SettingsToggleRow {
                settingKey: "osdAlwaysShowValue"
                text: I18n.tr("Always show percentage")
                checked: SettingsData.osdAlwaysShowValue
                onToggled: checked => SettingsData.set("osdAlwaysShowValue", checked)
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Show for")
            settingKey: "osdEvents"

            SettingsToggleRow {
                settingKey: "osdVolumeEnabled"
                text: I18n.tr("Volume")
                checked: SettingsData.osdVolumeEnabled
                onToggled: checked => SettingsData.set("osdVolumeEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdMediaVolumeEnabled"
                text: I18n.tr("Media volume")
                checked: SettingsData.osdMediaVolumeEnabled
                onToggled: checked => SettingsData.set("osdMediaVolumeEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdMediaPlaybackEnabled"
                text: I18n.tr("Media playback")
                checked: SettingsData.osdMediaPlaybackEnabled
                onToggled: checked => SettingsData.set("osdMediaPlaybackEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdBrightnessEnabled"
                text: I18n.tr("Brightness")
                checked: SettingsData.osdBrightnessEnabled
                onToggled: checked => SettingsData.set("osdBrightnessEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdIdleInhibitorEnabled"
                text: I18n.tr("Idle inhibitor", "feature that keeps the session from going idle")
                checked: SettingsData.osdIdleInhibitorEnabled
                onToggled: checked => SettingsData.set("osdIdleInhibitorEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdMicMuteEnabled"
                text: I18n.tr("Microphone mute")
                checked: SettingsData.osdMicMuteEnabled
                onToggled: checked => SettingsData.set("osdMicMuteEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdMicVolumeEnabled"
                text: I18n.tr("Microphone volume")
                checked: SettingsData.osdMicVolumeEnabled
                onToggled: checked => SettingsData.set("osdMicVolumeEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdCapsLockEnabled"
                text: I18n.tr("Caps lock")
                checked: SettingsData.osdCapsLockEnabled
                onToggled: checked => SettingsData.set("osdCapsLockEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdNumLockEnabled"
                text: I18n.tr("Num lock", "OSD toggle for the Num Lock indicator")
                checked: SettingsData.osdNumLockEnabled
                onToggled: checked => SettingsData.set("osdNumLockEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdKeyboardLayoutEnabled"
                visible: KeyboardLayoutService.available
                text: I18n.tr("Keyboard layout")
                checked: SettingsData.osdKeyboardLayoutEnabled
                onToggled: checked => SettingsData.set("osdKeyboardLayoutEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdTouchpadEnabled"
                visible: CompositorService.isNiri
                text: I18n.tr("Touchpad")
                checked: SettingsData.osdTouchpadEnabled
                onToggled: checked => SettingsData.set("osdTouchpadEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdPowerProfileEnabled"
                text: I18n.tr("Power profile")
                checked: SettingsData.osdPowerProfileEnabled
                onToggled: checked => SettingsData.set("osdPowerProfileEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdAudioOutputEnabled"
                text: I18n.tr("Audio output switch")
                checked: SettingsData.osdAudioOutputEnabled
                onToggled: checked => SettingsData.set("osdAudioOutputEnabled", checked)
            }

            SettingsToggleRow {
                settingKey: "osdWorkspaceEnabled"
                text: I18n.tr("Workspace Switch", "toggle label for workspace change OSD")
                checked: SettingsData.osdWorkspaceEnabled
                onToggled: checked => SettingsData.set("osdWorkspaceEnabled", checked)
            }
        }
    }
}
