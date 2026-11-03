import QtQuick
import Quickshell.Services.Mpris
import qs.Services
import qs.Modules.DDash

QtObject {
    id: root

    required property var player
    property var current: null
    readonly property bool settling: settle.running
    readonly property var incoming: {
        const source = player.activePlayer;
        if (!source)
            return null;
        return {
            key: source.dbusName,
            identity: source.identity,
            title: MprisController.stableTitle,
            artist: MprisController.stableArtist,
            album: MprisController.stableAlbum,
            artUrl: TrackArtService.resolvedArtUrl || source.trackArtUrl || "",
            length: player.stableLength,
            playing: source.playbackState === MprisPlaybackState.Playing,
            stopped: source.playbackState === MprisPlaybackState.Stopped,
            play: source.canTogglePlaying,
            previous: source.canGoPrevious || source.canSeek,
            next: source.canGoNext,
            shuffle: source.shuffleSupported,
            repeat: source.loopSupported,
            shuffleEnabled: source.shuffle,
            loopState: source.loopState,
            playerVolume: player.usePlayerVolume
        };
    }

    onIncomingChanged: sync()

    function sync() {
        const next = incoming;
        if (!next) {
            if (current && (!settle.running || settle.interval !== DashMetrics.mediaPlayerLossGraceInterval))
                startSettle(DashMetrics.mediaPlayerLossGraceInterval);
            return;
        }
        if (!current || current.key !== next.key) {
            settle.stop();
            current = next;
            return;
        }
        const merged = Object.assign({}, next);
        let incomplete = next.stopped;
        for (const key of ["play", "previous", "next", "shuffle", "repeat", "playerVolume", "length", "artUrl", "title", "identity"]) {
            if (next[key] || !current[key])
                continue;
            merged[key] = current[key];
            incomplete = true;
        }
        if (next.stopped)
            merged.playing = current.playing;
        if (!next.shuffle && current.shuffle)
            merged.shuffleEnabled = current.shuffleEnabled;
        if (!next.repeat && current.repeat)
            merged.loopState = current.loopState;
        current = merged;
        if (!incomplete) {
            settle.stop();
            return;
        }
        if (!settle.running)
            startSettle(DashMetrics.mediaTransitionGraceInterval);
    }

    function startSettle(interval) {
        settle.interval = interval;
        settle.restart();
    }

    property Timer settle: Timer {
        onTriggered: root.current = root.incoming
    }
}
