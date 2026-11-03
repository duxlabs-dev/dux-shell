pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Services
import qs.Modules.DDash
import qs.Modules.DDash.Media

Singleton {
    id: root

    property int refCount: 0
    readonly property bool allowed: DashRegistry.option("media", "lyrics") === true && controller.available
    readonly property bool subscribed: refCount > 0 && controller.available
    onSubscribedChanged: {
        MediaAccentService.lyricsConsumers += subscribed ? 1 : -1;
        if (subscribed) {
            MprisController.addPositionRef();
            return;
        }
        MprisController.removePositionRef();
    }
    property var activePlayer: subscribed ? MprisController.activePlayer : null
    readonly property real stableLength: subscribed ? MprisController.activePlayerStableLength : 0

    readonly property LyricsController controller: LyricsController {
        enabled: root.subscribed && !!root.presenter.current
        track: root.presenter.current
        settling: root.presenter.settling
        player: root.activePlayer
        playing: root.activePlayer?.playbackState === MprisPlaybackState.Playing
        stopped: !root.activePlayer || root.activePlayer.playbackState === MprisPlaybackState.Stopped
        rate: root.activePlayer?.rate ?? 1
        url: root.activePlayer?.metadata?.["xesam:url"] ?? ""
        embeddedText: root.activePlayer?.metadata?.["xesam:asText"] ?? ""
    }

    readonly property MediaPresentation presenter: MediaPresentation {
        player: root
    }

    function addRef() {
        refCount++;
    }

    function removeRef() {
        refCount = Math.max(0, refCount - 1);
    }
}
