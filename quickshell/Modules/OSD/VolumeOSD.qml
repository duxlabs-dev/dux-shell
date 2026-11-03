import QtQuick
import qs.Common
import qs.Modules.ControlCenter.Details
import qs.Services

LevelOSD {
    id: root

    osdKind: "volume"

    readonly property var audio: AudioService.sink?.audio ?? null

    iconName: AudioService.sinkVolumeIconName
    insetIconName: "music_note"
    endIconName: AudioService.sinkIcon(AudioService.sink)
    endIconLabel: I18n.tr("Audio Output")
    iconInteractive: true
    iconLabel: audio?.muted ? I18n.tr("Unmute", "verb, button to unmute audio or a muted app") : I18n.tr("Mute")
    value: AudioService.sinkVolumePercent
    maximum: AudioService.sinkMaxVolume
    available: !!audio
    displayText: audio?.muted ? I18n.tr("Muted") : ""

    sheet: OsdDetailSheet {
        AudioOutputDetail {
            anchors.fill: parent
        }
    }

    onIconClicked: AudioService.toggleMute()
    onLevelRequested: level => {
        SessionData.suppressOSDTemporarily();
        audio.volume = level / 100;
    }

    Connections {
        target: root.audio

        function onVolumeChanged() {
            if (SettingsData.osdVolumeEnabled)
                root.show();
        }

        function onMutedChanged() {
            if (SettingsData.osdVolumeEnabled)
                root.show();
        }
    }

    readonly property var audioSink: AudioService.sink

    onAudioSinkChanged: {
        if (shouldBeVisible && SettingsData.osdVolumeEnabled)
            show();
    }
}
