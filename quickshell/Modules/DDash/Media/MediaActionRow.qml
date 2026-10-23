pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation

RowLayout {
    id: root

    required property var player

    readonly property var focusTargets: [lyricsButton, volumeSlider, outputButton]
    readonly property var panelButtons: [outputButton]

    spacing: Theme.spacingM
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Keys.onPressed: event => event.accepted = FocusNavigation.handleHorizontalKey(event, focusTargets, I18n.isRtl)

    DIconButton {
        id: lyricsButton

        visible: root.player.lyricsEnabled
        enabled: !!root.player.presentation
        width: buttonSize
        variant: "tonal"
        iconName: "lyrics"
        checkable: true
        checked: root.player.lyricsOpen
        containerColor: checked ? MediaAccentService.accentContainer : Theme.surfaceContainerHighest
        contentColor: checked ? MediaAccentService.onAccentContainer : Theme.onSurfaceVariant
        tooltipText: I18n.tr("Lyrics", "Media player lyrics button")
        onClicked: root.player.toggleLyrics(lyricsButton)
    }

    MediaVolumeSlider {
        id: volumeSlider

        Layout.fillWidth: true
        size: "s"
        volume: root.player.currentVolume
        muted: root.player.usePlayerVolume ? volume === 0 : AudioService.sinkSilent
        maximumVolume: root.player.maxVolumePercent
        enabled: root.player.volumeAvailable
        onVolumeChangedByUser: volume => root.player.setVolume(volume)
        onMuteRequested: root.player.toggleMute()
    }

    DIconButton {
        id: outputButton

        readonly property string panelId: "devices"

        width: buttonSize
        variant: "tonal"
        iconName: AudioService.sinkIcon(AudioService.sink)
        containerColor: MediaAccentService.accentSecondaryContainer
        contentColor: MediaAccentService.onAccentSecondaryContainer
        tooltipText: I18n.tr("Devices", "Media player output device picker") + ": " + AudioService.displayName(AudioService.sink)
        onClicked: root.player.togglePanel(panelId, outputButton)
    }
}
