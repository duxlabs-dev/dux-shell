import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Modules.DDash.Media

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property real stableLength: MprisController.activePlayerStableLength
    property var allPlayers: MprisController.availablePlayers
    property bool live: Window.window?.visible ?? false
    property bool audioRefHeld: false
    property string entryId: "media"
    readonly property var options: DashRegistry.resolvedOptions(entryId)
    readonly property string playerStyle: options?.playerStyle ?? MediaOptions.defaultPlayerStyle
    readonly property bool lyricsEnabled: (options?.lyrics ?? MediaOptions.defaults.lyrics) && DMSService.capabilities.includes("lyrics")
    readonly property bool smoothLyrics: options?.smoothLyrics ?? MediaOptions.defaults.smoothLyrics
    property bool lyricsOpen: false
    property Item lyricsFocusTarget: null
    property Item lyricsOpener: null
    readonly property var presentation: mediaPresentation.current
    readonly property bool idle: !presentation
    property bool wallpaperEnabled: MediaOptions.albumArtBackdrop
    property string panel: ""
    property Item panelOpener: null
    property Item contentViewport: null
    readonly property bool blocksTabNavigation: panel !== ""
    property bool isSeeking: false
    property real previousVolume: 0.0

    readonly property color accent: MediaAccentService.accent

    readonly property Item focusTarget: mediaChrome.item?.focusTarget ?? null
    readonly property Item previousFocusTarget: mediaChrome.item?.previousFocusTarget ?? null

    readonly property bool __isChromeBrowser: {
        if (!activePlayer?.identity)
            return false;
        const id = activePlayer.identity.toLowerCase();
        return id.includes("chrome") || id.includes("chromium");
    }
    readonly property bool volumeAvailable: !!((activePlayer && activePlayer.volumeSupported && !__isChromeBrowser) || (AudioService.sink && AudioService.sink.audio))
    readonly property bool usePlayerVolume: activePlayer && activePlayer.volumeSupported && !__isChromeBrowser
    readonly property real reportedVolume: usePlayerVolume ? activePlayer.volume : (AudioService.sink?.audio?.volume ?? 0)
    readonly property real currentVolume: pendingVolume >= 0 ? pendingVolume : reportedVolume
    readonly property real maxVolumePercent: usePlayerVolume ? 100 : AudioService.sinkMaxVolume

    // MPRIS volume round-trips through the player, so successive steps would each read a stale
    // activePlayer.volume and collapse into one. Drive them from the value we last asked for.
    property real pendingVolume: -1

    onReportedVolumeChanged: {
        if (pendingVolume >= 0 && Math.abs(reportedVolume - pendingVolume) < 0.005)
            clearPendingVolume();
    }

    onUsePlayerVolumeChanged: clearPendingVolume()
    onActivePlayerChanged: clearPendingVolume()

    implicitWidth: DashMetrics.contentWidthFor(SettingsData.showWeekNumber, DashMetrics.panelColumnsFor(entryId))
    implicitHeight: mediaChrome.item?.implicitHeight ?? DashMetrics.tabMinHeight

    onPlayerStyleChanged: {
        panel = "";
        lyricsOpen = false;
        isSeeking = false;
        restoreLyrics();
    }

    onLyricsEnabledChanged: {
        if (lyricsEnabled) {
            restoreLyrics();
            return;
        }
        lyricsOpen = false;
    }

    onIdleChanged: {
        if (!idle)
            return;
        panel = "";
        isSeeking = false;
    }

    onLyricsOpenChanged: {
        if (!lyricsOpen)
            lyricsFocusTimer.restart();
    }

    Timer {
        id: lyricsFocusTimer
        interval: 0
        onTriggered: {
            if (!root.live || !root.lyricsOpener?.visible || !root.lyricsOpener.enabled)
                return;
            if (typeof root.lyricsOpener.requestFocus === "function") {
                root.lyricsOpener.requestFocus(false, Qt.OtherFocusReason);
                return;
            }
            root.lyricsOpener.forceActiveFocus(Qt.OtherFocusReason);
        }
    }

    Timer {
        id: pendingVolumeTimer
        interval: DashMetrics.mediaVolumeEchoTimeout
        onTriggered: root.pendingVolume = -1
    }

    MediaPresentation {
        id: mediaPresentation
        player: root
    }

    Timer {
        interval: DashMetrics.mediaPositionPollInterval
        running: root.live && root.activePlayer?.playbackState === MprisPlaybackState.Playing && !root.isSeeking
        repeat: true
        onTriggered: MprisController.refreshPosition(root.activePlayer)
    }

    function syncAudioRef(wanted) {
        if (wanted === audioRefHeld)
            return;
        audioRefHeld = wanted;
        if (wanted) {
            AudioService.addRef();
            return;
        }
        AudioService.removeRef();
    }

    Component.onCompleted: syncAudioRef(live)
    Component.onDestruction: syncAudioRef(false)

    onLiveChanged: {
        syncAudioRef(live);
        if (live) {
            restoreLyrics();
            return;
        }
        panel = "";
        lyricsOpen = false;
    }

    function cycleFocus(backwards) {
        return mediaChrome.item?.cycleFocus(backwards) ?? false;
    }

    function selectablePlayers() {
        return (allPlayers || []).filter(p => p && (p === activePlayer || !MprisController.isIdle(p)));
    }

    function outputStatus(node) {
        if (node !== AudioService.sink)
            return I18n.tr("Available");
        if (node?.audio?.muted)
            return I18n.tr("Muted");
        return presentation?.playing ? I18n.tr("Playing", "Audio output currently playing media") : I18n.tr("Active");
    }

    function togglePanel(panelId, opener) {
        panelOpener = opener ?? null;
        panel = panel === panelId ? "" : panelId;
    }

    function showPanel(panelId) {
        panel = panelId;
    }

    function revealVolume() {
        if (mediaChrome.item?.inlineVolume)
            return;
        showPanel("volume");
    }

    function restoreLyrics() {
        if (live && lyricsEnabled && CacheData.mediaLyricsOpen)
            lyricsOpen = true;
    }

    // A plain Item's activeFocus stays false while a child holds focus.
    function ownsFocus() {
        for (let item = Window.activeFocusItem; item; item = item.parent) {
            if (item === root)
                return true;
        }
        return false;
    }

    function toggleLyrics(opener) {
        if (!lyricsEnabled)
            return;
        lyricsOpener = opener ?? null;
        lyricsOpen = !lyricsOpen;
        CacheData.set("mediaLyricsOpen", lyricsOpen);
        lyricsFocusTimer.stop();
    }

    function getVolumeIcon() {
        if (!volumeAvailable)
            return "volume_off";
        if (usePlayerVolume)
            return currentVolume === 0 ? "music_off" : "music_note";
        return AudioService.sinkVolumeIconName;
    }

    function clearPendingVolume() {
        pendingVolume = -1;
        pendingVolumeTimer.stop();
    }

    function setVolume(ratio) {
        if (!volumeAvailable)
            return;
        const clamped = Math.min(maxVolumePercent / 100, Math.max(0, ratio));
        SessionData.suppressOSDTemporarily();
        if (usePlayerVolume) {
            pendingVolume = clamped;
            pendingVolumeTimer.restart();
            activePlayer.volume = clamped;
            return;
        }
        const audio = AudioService.sink?.audio;
        if (!audio)
            return;
        audio.volume = clamped;
        if (clamped > 0)
            audio.muted = false;
    }

    function adjustVolume(step) {
        setVolume((Math.round(currentVolume * 100) + step) / 100);
    }

    function cycleLoopState() {
        if (!activePlayer?.canControl || !activePlayer.loopSupported)
            return;
        switch (activePlayer.loopState) {
        case MprisLoopState.None:
            activePlayer.loopState = MprisLoopState.Playlist;
            break;
        case MprisLoopState.Playlist:
            activePlayer.loopState = MprisLoopState.Track;
            break;
        case MprisLoopState.Track:
            activePlayer.loopState = MprisLoopState.None;
            break;
        }
    }

    function toggleMute() {
        if (!volumeAvailable)
            return;
        if (!usePlayerVolume) {
            SessionData.suppressOSDTemporarily();
            AudioService.sink.audio.muted = !AudioService.sink.audio.muted;
            return;
        }
        if (currentVolume > 0) {
            root.previousVolume = currentVolume;
            setVolume(0);
            return;
        }
        setVolume(root.previousVolume > 0 ? root.previousVolume : 0.5);
    }

    function handleKeyEvent(event) {
        if (event.key === Qt.Key_F6)
            return cycleFocus(!!(event.modifiers & Qt.ShiftModifier));
        if (event.key === Qt.Key_Escape) {
            if (panel === "")
                return false;
            const panelId = panel;
            panel = "";
            mediaChrome.item?.focusPanelButton(panelId);
            return true;
        }
        if (panel !== "")
            return true;
        if (!activePlayer)
            return false;

        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            if (!activePlayer.canSeek || stableLength <= 0)
                return false;
            const targetPosition = (event.key - Qt.Key_0) * 0.1 * stableLength;
            activePlayer.position = Math.max(0.1, Math.min(targetPosition, stableLength * 0.99));
            return true;
        }

        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_H:
            if (!activePlayer.canSeek)
                return false;
            activePlayer.position = Math.max(0.1, activePlayer.position - 5);
            return true;
        case Qt.Key_Right:
        case Qt.Key_L:
            if (!activePlayer.canSeek || stableLength <= 0)
                return false;
            activePlayer.position = Math.max(0.1, Math.min(stableLength - 1, activePlayer.position + 5));
            return true;
        case Qt.Key_Up:
        case Qt.Key_K:
            if (!volumeAvailable)
                return false;
            adjustVolume(AudioService.wheelVolumeStep);
            revealVolume();
            return true;
        case Qt.Key_Down:
        case Qt.Key_J:
            if (!volumeAvailable)
                return false;
            adjustVolume(-AudioService.wheelVolumeStep);
            revealVolume();
            return true;
        case Qt.Key_Space:
            if (!activePlayer.canTogglePlaying)
                return false;
            activePlayer.togglePlaying();
            return true;
        case Qt.Key_M:
            if (!volumeAvailable)
                return false;
            toggleMute();
            revealVolume();
            return true;
        }
        return false;
    }

    Loader {
        id: mediaChrome
        anchors.fill: parent
        active: !root.idle
        sourceComponent: root.playerStyle === "material" ? materialChrome : bentoChrome
    }

    Loader {
        anchors.fill: parent
        active: root.idle
        sourceComponent: MediaEmptyState {}
    }

    Component {
        id: bentoChrome
        BentoChrome {
            player: root
        }
    }

    Component {
        id: materialChrome
        MaterialChrome {
            player: root
        }
    }
}
