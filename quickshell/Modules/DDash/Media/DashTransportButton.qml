import QtQuick
import qs.Services
import qs.Widgets

// MediaAccentService stays out of the shared button so the bar and island never instantiate it.
MediaTransportButton {
    id: root

    required property var player

    usePresentation: true
    presentation: root.player.presentation
    focusRingColor: MediaAccentService.focusRing
}
