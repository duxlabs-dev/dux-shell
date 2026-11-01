import QtQuick
import qs.Services
import qs.Widgets
import qs.Modules.DDash

DSeekbar {
    id: root

    required property var player

    height: DashMetrics.mediaSeekbarHeight
    activePlayer: root.player.activePlayer
    stableLength: root.player.presentation?.length ?? 0
    enabled: root.player.stableLength > 0
    accentColor: root.player.accent
    accentTrackColor: MediaAccentService.accentTrack
    accentSubtleColor: MediaAccentService.accentSubtle
    focusRingColor: MediaAccentService.focusRing
    isSeeking: root.player.isSeeking
    onIsSeekingChanged: root.player.isSeeking = isSeeking
}
