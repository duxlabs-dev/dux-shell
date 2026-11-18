pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null
    property string dialogKind: ""

    function pickPosition(kind, title) {
        dialogKind = kind;
        positionDialog.title = kind === "" ? I18n.tr("Position") : title;
        positionDialog.supportingText = kind === "" ? "" : I18n.tr("Position");
        positionDialog.show();
    }

    SettingsPositionDialog {
        id: positionDialog
        parent: root.parentModal?.dialogHostFor(root) ?? root
        selected: SettingsData.osdPositionFor(root.dialogKind)
        resettable: root.dialogKind === "" ? !SettingsData.isDefault(["osdPosition"]) : SettingsData.hasOsdPositionOverride(root.dialogKind)
        onPicked: position => SettingsData.setOsdPosition(root.dialogKind, position)
        onResetRequested: SettingsData.resetOsdPosition(root.dialogKind)
    }

    component EventTile: SettingsToggleRow {
        id: tile

        property string kind: ""
        readonly property bool overridden: SettingsData.hasOsdPositionOverride(kind)
        readonly property int position: SettingsData.osdPositionFor(kind)

        width: tiles.tileWidth
        iconBox: true
        iconColor: checked ? Theme.primary : Theme.surfaceVariantText
        topRadius: Theme.groupedListOuterRadius
        bottomRadius: Theme.groupedListOuterRadius
        dividerBefore: false
        checked: SettingsData[settingKey]
        onToggled: checked => SettingsData.set(settingKey, checked)

        supporting: DButton {
            text: ScreenPositions.label(tile.position)
            iconName: ScreenPositions.icon(tile.position)
            variant: "tonal"
            buttonHeight: Theme.buttonHeightXXS
            horizontalPadding: Theme.spacingS
            minimumWidth: 0
            backgroundColor: tile.overridden ? Theme.withAlpha(Theme.primary, Theme.tonalTintAlpha) : SettingsMetrics.controlColor
            textColor: tile.overridden ? Theme.primary : Theme.surfaceVariantText
            enabled: tile.checked
            Accessible.description: tile.text
            onClicked: root.pickPosition(tile.kind, tile.text)
        }
    }

    SettingsPage {
        id: mainColumn

        SettingsDeferred {
            SettingsCard {
                width: parent.width
                settingKey: "osd"

                SettingsRow {
                    settingKey: "osdPosition"
                    title: I18n.tr("Position")
                    subtitle: ScreenPositions.label(SettingsData.osdPosition)
                    clickable: true
                    onClicked: root.pickPosition("", "")

                    SettingsPreviewBox {
                        anchors.verticalCenter: parent.verticalCenter
                        symbol: ScreenPositions.icon(SettingsData.osdPosition)
                    }
                }

                SettingsToggleRow {
                    settingKey: "osdAlwaysShowValue"
                    text: I18n.tr("Always show percentage")
                    checked: SettingsData.osdAlwaysShowValue
                    onToggled: checked => SettingsData.set("osdAlwaysShowValue", checked)
                }
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Show for")
            settingKey: "osdEvents"

            Grid {
                id: tiles

                readonly property bool isSettingsRow: true
                readonly property bool transparentSlot: true
                readonly property real tileWidth: (width - columnSpacing * (columns - 1)) / columns

                columns: width >= SettingsMetrics.tileMinWidth * 2 + columnSpacing ? 2 : 1
                columnSpacing: SettingsMetrics.tileGap
                rowSpacing: SettingsMetrics.tileGap

                EventTile {
                    settingKey: "osdVolumeEnabled"
                    kind: "volume"
                    iconName: "volume_up"
                    text: I18n.tr("Volume")
                }

                EventTile {
                    settingKey: "osdMediaVolumeEnabled"
                    kind: "mediaVolume"
                    iconName: "music_note"
                    text: I18n.tr("Media volume")
                }

                EventTile {
                    settingKey: "osdMediaPlaybackEnabled"
                    kind: "mediaPlayback"
                    iconName: "play_arrow"
                    text: I18n.tr("Media playback")
                }

                EventTile {
                    settingKey: "osdBrightnessEnabled"
                    kind: "brightness"
                    iconName: "brightness_6"
                    text: I18n.tr("Brightness")
                }

                EventTile {
                    settingKey: "osdIdleInhibitorEnabled"
                    kind: "idleInhibitor"
                    iconName: "coffee"
                    text: I18n.tr("Idle inhibitor", "feature that keeps the session from going idle")
                }

                EventTile {
                    settingKey: "osdDoNotDisturbEnabled"
                    kind: "doNotDisturb"
                    iconName: "do_not_disturb_on"
                    text: I18n.tr("Do not disturb")
                }

                EventTile {
                    settingKey: "osdMicMuteEnabled"
                    kind: "mic"
                    iconName: "mic_off"
                    text: I18n.tr("Microphone mute")
                }

                EventTile {
                    settingKey: "osdMicVolumeEnabled"
                    kind: "mic"
                    iconName: "mic"
                    text: I18n.tr("Microphone volume")
                }

                EventTile {
                    settingKey: "osdCapsLockEnabled"
                    kind: "capsLock"
                    iconName: "keyboard_capslock"
                    text: I18n.tr("Caps lock")
                }

                EventTile {
                    settingKey: "osdNumLockEnabled"
                    kind: "numLock"
                    iconName: "dialpad"
                    text: I18n.tr("Num lock", "OSD toggle for the Num Lock indicator")
                }

                EventTile {
                    settingKey: "osdKeyboardLayoutEnabled"
                    kind: "keyboardLayout"
                    iconName: "keyboard"
                    visible: KeyboardLayoutService.available
                    text: I18n.tr("Keyboard layout")
                }

                EventTile {
                    settingKey: "osdInputMethodEnabled"
                    kind: "inputMethod"
                    iconName: "language"
                    visible: Fcitx5Service.available
                    text: I18n.tr("Input method", "OSD toggle for the IME (fcitx5) indicator")
                }

                EventTile {
                    settingKey: "osdTouchpadEnabled"
                    kind: "touchpad"
                    iconName: "touchpad_mouse"
                    visible: CompositorService.isNiri
                    text: I18n.tr("Touchpad")
                }

                EventTile {
                    settingKey: "osdAirplaneModeEnabled"
                    kind: "airplaneMode"
                    iconName: "airplanemode_active"
                    tags: ["airplane", "rfkill", "wifi", "bluetooth", "osd"]
                    text: I18n.tr("Airplane mode", "OSD toggle for airplane mode / rfkill indicator")
                }

                EventTile {
                    settingKey: "osdPowerProfileEnabled"
                    kind: "powerProfile"
                    iconName: "bolt"
                    text: I18n.tr("Power profile")
                }

                EventTile {
                    settingKey: "osdAudioOutputEnabled"
                    kind: "audioOutput"
                    iconName: "speaker"
                    text: I18n.tr("Audio output switch")
                }

                EventTile {
                    settingKey: "osdWorkspaceEnabled"
                    kind: "workspace"
                    iconName: "view_carousel"
                    text: I18n.tr("Workspace Switch", "toggle label for workspace change OSD")
                }
            }
        }
    }
}
