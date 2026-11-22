import QtQuick
import qs.Common
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

    sheetSource: Qt.resolvedUrl("VolumeOsdSheet.qml")

    onIconClicked: AudioService.toggleMute()
    onLevelRequested: level => {
        SessionData.suppressOSDTemporarily();
        AudioService.setNodeVolume(AudioService.sink, level / 100);
    }

    Connections {
        target: root.audio

        function onVolumeChanged() {
            root.show();
        }

        function onMutedChanged() {
            root.show();
        }
    }

    readonly property var audioSink: AudioService.sink

    onAudioSinkChanged: {
        if (shouldBeVisible)
            show();
    }
}
