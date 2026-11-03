pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation

Row {
    id: root

    required property var player
    required property var presentation

    readonly property var focusTargets: [lyricsButton, volumeButton, devicesButton, playersButton]
    readonly property var panelButtons: [volumeButton, devicesButton, playersButton]

    height: Theme.buttonHeightS
    spacing: Theme.spacingXS

    Keys.onPressed: event => event.accepted = FocusNavigation.handleHorizontalKey(event, focusTargets, I18n.isRtl)

    DIconButton {
        id: lyricsButton
        focusRingColor: MediaAccentService.focusRing
        variant: "outlined"
        checkable: true
        checked: root.player.lyricsOpen
        containerColor: MediaAccentService.accentContainer
        contentColor: MediaAccentService.onAccentContainer
        iconName: "notes"
        visible: root.player.lyricsEnabled
        enabled: !!root.presentation
        tooltipText: I18n.tr("Lyrics", "Media player lyrics button")
        onClicked: root.player.toggleLyrics(lyricsButton)
    }

    GroupButton {
        id: volumeButton
        panelId: "volume"
        iconName: root.player.getVolumeIcon()
        enabled: root.player.volumeAvailable
        tooltipText: (root.player.usePlayerVolume ? I18n.tr("Media volume") : I18n.tr("Volume")) + ": " + Math.round(root.player.currentVolume * 100) + "%"

        MediaVolumeWheel {
            player: root.player
            button: volumeButton
        }
    }

    GroupButton {
        id: devicesButton
        panelId: "devices"
        tooltipText: I18n.tr("Devices", "Media player output device picker") + ": " + AudioService.displayName(AudioService.sink)
        iconName: AudioService.sinkIcon(AudioService.sink)

        MediaSinkMute {}
    }

    GroupButton {
        id: playersButton
        panelId: "players"
        tooltipText: I18n.tr("Players", "Media player selection")
        visible: (root.player.allPlayers?.length || 0) > 0
        iconName: "assistant_device"
    }

    component GroupButton: DIconButton {
        required property string panelId

        focusRingColor: MediaAccentService.focusRing

        readonly property bool active: root.player.panel === panelId

        variant: "outlined"
        checkable: true
        checked: active
        containerColor: MediaAccentService.accentContainer
        contentColor: MediaAccentService.onAccentContainer
        onClicked: root.player.togglePanel(panelId)
    }
}
