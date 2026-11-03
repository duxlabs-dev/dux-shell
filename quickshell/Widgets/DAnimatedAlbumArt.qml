import QtQuick
import QtMultimedia
import Quickshell.Widgets
import qs.Services

// Loaded by url so a missing QtMultimedia degrades to the static art underneath.
ClippingRectangle {
    id: root

    radius: width / 2
    color: "transparent"
    contentInsideBorder: true
    border.color: MediaAccentService.accent
    border.width: 2
    // Reveal only while frames are flowing; the static art beneath covers load, stall and error.
    opacity: video.hasVideo && video.playbackState === MediaPlayer.PlayingState && video.error === MediaPlayer.NoError ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: 300
            easing.type: Easing.InOutQuad
        }
    }

    Video {
        id: video
        anchors.fill: parent
        source: AppleMusicArtService.animatedArtUrl
        fillMode: VideoOutput.PreserveAspectCrop
        loops: MediaPlayer.Infinite
        muted: true
        onSourceChanged: {
            if (source != "")
                play();
        }
        Component.onCompleted: {
            if (source != "")
                play();
        }
    }
}
