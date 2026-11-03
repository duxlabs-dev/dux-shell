import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

Item {
    id: root

    readonly property string multimediaPackage: {
        const id = (SystemUpdateService.distribution || "").toLowerCase();
        if (id.includes("suse"))
            return "qt6-multimedia-imports";
        switch (id) {
        case "fedora":
        case "fedora-asahi-remix":
        case "nobara":
        case "bazzite":
        case "bluefin":
        case "ultramarine":
        case "evernight":
            return "qt6-qtmultimedia";
        case "debian":
        case "ubuntu":
        case "linuxmint":
        case "pop":
        case "elementary":
        case "zorin":
            return "qml6-module-qtmultimedia";
        case "arch":
        case "archarm":
        case "archcraft":
        case "cachyos":
        case "catos":
        case "endeavouros":
        case "manjaro":
        case "garuda":
        case "artix":
        case "obarun":
        case "xerolinux":
            return "qt6-multimedia";
        default:
            return I18n.tr("the Qt 6 Multimedia QML module");
        }
    }

    Component.onCompleted: {
        MultimediaService.ensureProbed();
        AudioService.refreshSoundThemes();
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            tab: "sounds"
            tags: ["sound", "audio", "notification", "volume"]
            settingKey: "systemSounds"
            visible: !MultimediaService.unavailable

            SettingsToggleRow {
                tab: "sounds"
                tags: ["sound", "enable", "system"]
                settingKey: "soundsEnabled"
                text: I18n.tr("System sounds")
                checked: SettingsData.soundsEnabled
                onToggled: checked => SettingsData.set("soundsEnabled", checked)
            }

            SettingsDropdownRow {
                readonly property string builtIn: I18n.tr("Built-in", "sound theme option, the sounds bundled with the shell")

                enabled: SettingsData.soundsEnabled
                visible: AudioService.soundThemeSupported
                tab: "sounds"
                tags: ["sound", "theme", "system", "gsettings", "select"]
                settingKey: "soundTheme"
                text: I18n.tr("Sound theme", "sounds settings dropdown label, which set of system sounds to use")
                options: {
                    const themes = AudioService.availableSoundThemes;
                    const current = AudioService.currentSoundTheme;
                    const unlisted = current && !themes.includes(current) ? [current] : [];
                    return [builtIn].concat(unlisted, themes);
                }
                currentValue: SettingsData.useSystemSoundTheme && AudioService.currentSoundTheme ? AudioService.currentSoundTheme : builtIn
                onValueChanged: value => AudioService.selectSoundTheme(value === builtIn ? "" : value)
            }

            SettingsToggleRow {
                enabled: SettingsData.soundsEnabled
                tab: "sounds"
                tags: ["sound", "login", "startup", "boot"]
                settingKey: "soundLogin"
                text: I18n.tr("Login", "noun, system sounds toggle, sound played on login")
                checked: SettingsData.soundLogin
                onToggled: checked => SettingsData.set("soundLogin", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.soundsEnabled
                tab: "sounds"
                tags: ["sound", "notification", "new"]
                settingKey: "soundNewNotification"
                text: I18n.tr("New notification")
                checked: SettingsData.soundNewNotification
                onToggled: checked => SettingsData.set("soundNewNotification", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.soundsEnabled
                tab: "sounds"
                tags: ["sound", "volume", "changed"]
                settingKey: "soundVolumeChanged"
                text: I18n.tr("Volume changed")
                checked: SettingsData.soundVolumeChanged
                onToggled: checked => SettingsData.set("soundVolumeChanged", checked)
            }

            SettingsToggleRow {
                enabled: (SettingsData.soundsEnabled) && (BatteryService.batteryAvailable)
                tab: "sounds"
                tags: ["sound", "power", "plugged", "cable", "charger"]
                settingKey: "soundPluggedIn"
                visible: BatteryService.batteryAvailable
                text: I18n.tr("Plugged in")
                checked: SettingsData.soundPluggedIn
                onToggled: checked => SettingsData.set("soundPluggedIn", checked)
            }

            SettingsToggleRow {
                enabled: SettingsData.soundsEnabled
                tab: "sounds"
                tags: ["sound", "media", "playback", "mute", "mpris", "music"]
                settingKey: "muteSoundsWhenMediaPlaying"
                text: I18n.tr("Mute during media playback")
                checked: SettingsData.muteSoundsWhenMediaPlaying
                onToggled: checked => SettingsData.set("muteSoundsWhenMediaPlaying", checked)
            }
        }

        SettingsNoteRow {
            paintBackground: false
            visible: MultimediaService.unavailable
            text: I18n.tr("System sounds are not available. Install %1 for sound support.", "sounds settings warning, %1 is a package name").arg(root.multimediaPackage)
        }
    }
}
