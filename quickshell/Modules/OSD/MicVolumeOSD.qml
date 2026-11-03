import QtQuick
import qs.Common
import qs.Modules.ControlCenter.Details
import qs.Services

LevelOSD {
    id: root

    osdKind: "mic"

    readonly property var audio: AudioService.source?.audio ?? null
    readonly property bool muted: audio?.muted ?? false

    iconName: muted ? "mic_off" : "mic"
    insetIconName: "mic"
    endIconName: "graphic_eq"
    endIconLabel: I18n.tr("Audio Input")
    iconInteractive: true
    iconLabel: muted ? I18n.tr("Unmute") : I18n.tr("Mute")
    iconColor: muted ? Theme.onErrorContainer : Theme.onPrimary
    fillColor: muted ? Theme.error : Theme.primary
    value: AudioService.sourceVolumePercent
    available: !!audio
    displayText: muted ? I18n.tr("Muted") : ""

    sheet: OsdDetailSheet {
        AudioInputDetail {
            anchors.fill: parent
        }
    }

    onIconClicked: AudioService.toggleMicMute()
    onLevelRequested: level => {
        SessionData.suppressOSDTemporarily();
        audio.volume = level / 100;
    }

    Connections {
        target: root.audio

        function onMutedChanged() {
            if (SettingsData.osdMicMuteEnabled)
                root.show();
        }
    }

    // Plain volume changes stay silent: app AGC rewrites mic gain constantly.
    Connections {
        target: AudioService

        function onMicVolumeChanged() {
            if (SettingsData.osdMicVolumeEnabled)
                root.show();
        }

        function onSourceChanged() {
            if (root.shouldBeVisible && SettingsData.osdMicVolumeEnabled)
                root.show();
        }
    }
}
