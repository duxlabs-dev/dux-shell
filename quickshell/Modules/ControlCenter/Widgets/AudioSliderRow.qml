import QtQuick
import qs.Common
import qs.Services

CcSliderRow {
    id: root

    property var node: AudioService.sink
    property bool isInput: false
    property real maxVolume: 100
    property bool playFeedback: false

    readonly property var audio: node?.audio ?? null
    readonly property real volumePercent: audio ? Math.round(AudioService.getNodeVolume(node) * 100) : 0
    readonly property bool audible: !!audio && !audio.muted && AudioService.getNodeVolume(node) > 0

    iconName: {
        if (!isInput)
            return AudioService.volumeIconName(node);
        return audible ? "mic" : "mic_off";
    }
    sliderLabel: isInput ? I18n.tr("Input Volume") : I18n.tr("Volume")
    iconLabel: audio?.muted ? I18n.tr("Unmute") : I18n.tr("Mute")
    sliderEnabled: audio !== null
    minimum: 0
    maximum: maxVolume
    valueOverride: volumePercent
    wheelStep: AudioService.wheelVolumeStep

    onIconClicked: {
        if (!audio)
            return;
        SessionData.suppressOSDTemporarily();
        audio.muted = !audio.muted;
    }

    onSliderValueChanged: newValue => {
        if (!audio)
            return;
        SessionData.suppressOSDTemporarily();
        AudioService.setNodeVolume(node, newValue / 100);
        if (newValue > 0 && audio.muted)
            audio.muted = false;
        if (playFeedback)
            AudioService.playVolumeChangeSoundIfEnabled();
    }

    Binding {
        target: root.slider
        property: "value"
        value: Math.min(root.maxVolume, root.volumePercent)
        restoreMode: Binding.RestoreNone
        when: !root.isDragging
    }
}
