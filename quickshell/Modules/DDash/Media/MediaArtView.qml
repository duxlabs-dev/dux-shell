pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.DDash

Item {
    id: root

    required property var player
    property bool showLyrics: true
    property bool holdArt: false

    readonly property bool lyricsOpen: root.showLyrics && root.player.lyricsOpen && root.player.live
    readonly property bool lyricsReady: !LyricsService.controller.pending
    // The art stays up while lyrics first load, with the overlay's indicator on top. Once they have
    // shown, a reload on a track change keeps their place rather than flashing the art back in.
    property bool lyricsHeld: false
    readonly property bool lyricsShown: root.lyricsOpen && (lyricsReady || lyricsHeld)

    onLyricsOpenChanged: lyricsHeld = lyricsOpen && lyricsReady
    onLyricsReadyChanged: {
        if (lyricsReady && lyricsOpen)
            lyricsHeld = true;
    }
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None

    MediaArtSurface {
        id: surface
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        artStyle: root.player.options?.artStyle ?? MediaOptions.defaultArtStyle
        playing: !!root.player.presentation?.playing
        live: root.player.live
        suspended: root.lyricsShown
        visible: opacity > 0
        opacity: root.lyricsShown ? 0 : 1
        scale: root.lyricsShown ? DashMetrics.mediaArtLyricsScale : 1

        Behavior on opacity {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveEffects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        Behavior on scale {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }

        MediaArtwork {
            anchors.fill: parent
            cornerRadius: 0
            placeholderIconSize: DashMetrics.mediaArtPlaceholderIcon
            artUrl: root.holdArt ? "" : root.player.presentation?.artUrl ?? ""
        }
    }

    Loader {
        anchors.fill: parent
        active: root.lyricsOpen
        onLoaded: {
            if (root.player.ownsFocus())
                item.forceActiveFocus(Qt.PopupFocusReason);
        }

        sourceComponent: LyricsOverlay {
            player: root.player
            radius: 0
            backgroundColor: "transparent"
        }
    }
}
