pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.DCommon.Widgets

DIconButton {
    id: root

    required property string mediaAction
    // The dash's settled snapshot stops a track change flickering the controls; without one the caller owns visibility.
    property bool usePresentation: false
    property var presentation: null
    property bool keepNavigation: false

    readonly property var activePlayer: MprisController.activePlayer
    property bool playing: root.usePresentation ? !!root.presentation?.playing : root.activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property var loopState: root.usePresentation ? root.presentation?.loopState : root.activePlayer?.loopState
    readonly property bool repeatingTrack: root.loopState === MprisLoopState.Track

    function cycleLoopState(): void {
        const player = root.activePlayer;
        if (!player?.canControl || !player.loopSupported)
            return;
        switch (player.loopState) {
        case MprisLoopState.None:
            player.loopState = MprisLoopState.Playlist;
            return;
        case MprisLoopState.Playlist:
            player.loopState = MprisLoopState.Track;
            return;
        case MprisLoopState.Track:
            player.loopState = MprisLoopState.None;
            return;
        }
    }

    checkable: root.mediaAction === "shuffle" || root.mediaAction === "play" || root.mediaAction === "repeat"
    iconFilled: false

    iconName: {
        switch (root.mediaAction) {
        case "shuffle":
            return "shuffle";
        case "previous":
            return "skip_previous";
        case "play":
            return root.playing ? "pause" : "play_arrow";
        case "next":
            return "skip_next";
        case "repeat":
            return root.repeatingTrack ? "repeat_one" : "repeat";
        }
        return "";
    }

    Accessible.name: {
        switch (root.mediaAction) {
        case "shuffle":
            return I18n.tr("Shuffle", "Shuffle media playback");
        case "previous":
            return I18n.tr("Previous", "button going to the previous track, page, day, month or match");
        case "play":
            return root.playing ? I18n.tr("Pause", "verb, button pausing media playback or a printer or print job") : I18n.tr("Play", "verb, media play button accessible name");
        case "next":
            return I18n.tr("Next");
        case "repeat":
            return I18n.tr("Repeat", "verb, media player repeat mode button", true);
        }
        return "";
    }

    visible: {
        if (!root.usePresentation)
            return true;
        switch (root.mediaAction) {
        case "shuffle":
            return !!root.presentation?.shuffle;
        case "previous":
            return root.keepNavigation ? !!root.presentation : !!root.presentation?.previous;
        case "play":
            return !!root.presentation?.play;
        case "next":
            return root.keepNavigation ? !!root.presentation : !!root.presentation?.next;
        case "repeat":
            return !!root.presentation?.repeat;
        }
        return false;
    }

    enabled: {
        switch (root.mediaAction) {
        case "shuffle":
            return !!root.activePlayer?.shuffleSupported && !!root.activePlayer?.canControl;
        case "previous":
            // previousOrRewind() only rewinds past 8 s, but gating on position would need it polled.
            return !!root.activePlayer?.canGoPrevious || (!root.keepNavigation && !!root.activePlayer?.canSeek);
        case "play":
            return !!root.activePlayer?.canTogglePlaying;
        case "next":
            return !!root.activePlayer?.canGoNext;
        case "repeat":
            return !!root.activePlayer?.loopSupported && !!root.activePlayer?.canControl;
        }
        return false;
    }

    checked: {
        switch (root.mediaAction) {
        case "shuffle":
            return root.usePresentation ? !!root.presentation?.shuffleEnabled : !!root.activePlayer?.shuffle;
        case "play":
            return root.playing;
        case "repeat":
            return root.loopState !== undefined && root.loopState !== MprisLoopState.None;
        }
        return false;
    }

    // The player state change would pop the media OSD over controls the user is already looking at.
    onClicked: {
        if (root.mediaAction === "play" || root.mediaAction === "previous" || root.mediaAction === "next")
            SessionData.suppressOSDTemporarily();
        switch (root.mediaAction) {
        case "shuffle":
            root.activePlayer.shuffle = !root.activePlayer.shuffle;
            return;
        case "previous":
            MprisController.previousOrRewind();
            return;
        case "play":
            root.activePlayer.togglePlaying();
            return;
        case "next":
            MprisController.next();
            return;
        case "repeat":
            root.cycleLoopState();
            return;
        }
    }
}
