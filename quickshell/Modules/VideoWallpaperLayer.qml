import QtQuick
import QtMultimedia
import qs.Common
import qs.Services
import "../Common/WallpaperFormats.js" as WallpaperFormats

// Loaded by url so a missing QtMultimedia leaves the still frame underneath.
Item {
    id: root

    readonly property var log: Log.scoped("VideoWallpaperLayer")

    property string screenName: ""
    property string wantedSource: ""
    property string fillMode: ""
    // True once the still frame transition below is done, so the video plays out uncovered.
    property bool settled: false
    property bool shouldPlay: false

    // Switched only when settled.
    property string playingSource: ""
    readonly property bool current: playingSource !== "" && playingSource === wantedSource
    readonly property bool wantsPlay: shouldPlay && current
    readonly property bool shown: current && player.hasVideo && player.playbackState !== MediaPlayer.StoppedState
    readonly property bool rendering: player.playbackState === MediaPlayer.PlayingState || fadeAnimation.running

    function syncSource() {
        if (!settled || !WallpaperFormats.isVideo(wantedSource) || playingSource === wantedSource)
            return;
        playingSource = wantedSource;
    }

    function videoFillMode(mode) {
        switch (mode) {
        case "Stretch":
            return VideoOutput.Stretch;
        case "Fit":
        case "PreserveAspectFit":
            return VideoOutput.PreserveAspectFit;
        default:
            return VideoOutput.PreserveAspectCrop;
        }
    }

    opacity: shown ? 1 : 0
    onWantedSourceChanged: syncSource()
    onSettledChanged: syncSource()
    onWantsPlayChanged: wantsPlay ? player.play() : player.pause()
    Component.onCompleted: syncSource()

    Behavior on opacity {
        NumberAnimation {
            id: fadeAnimation
            duration: Theme.mediumDuration
            easing.type: Theme.standardEasing
        }
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: root.videoFillMode(root.fillMode)
    }

    MediaPlayer {
        id: player
        source: root.playingSource ? "file://" + root.playingSource.split('/').map(s => encodeURIComponent(s)).join('/') : ""
        videoOutput: videoOutput
        loops: WallpaperCyclingService.advancesOnVideoEnd(root.screenName) ? 1 : MediaPlayer.Infinite

        onSourceChanged: {
            if (root.wantsPlay)
                play();
        }
        onMediaStatusChanged: {
            if (mediaStatus !== MediaPlayer.EndOfMedia || !root.current)
                return;
            WallpaperCyclingService.handleVideoEnded(root.screenName);
            // Replays when cycling is off or picked the same file; a new pick replaces it.
            if (root.wantsPlay)
                play();
        }
        onErrorOccurred: (error, errorString) => root.log.warn("video wallpaper failed on", root.screenName + ":", errorString)
    }
}
