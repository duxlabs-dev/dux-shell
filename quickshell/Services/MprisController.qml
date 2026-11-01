pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Common

Singleton {
    id: root

    // playerctld mirrors whichever player is active and advertises shuffle/loop the real player may lack
    readonly property string _playerctldBusName: "org.mpris.MediaPlayer2.playerctld"

    readonly property list<MprisPlayer> availablePlayers: {
        const players = Mpris.players.values.filter(p => p.dbusName !== _playerctldBusName);
        const excluded = SettingsData.mediaExcludePlayers || [];
        if (excluded.length === 0)
            return players;
        return players.filter(p => {
            const identity = (p.identity || "").toLowerCase();
            const desktopEntry = ("desktopEntry" in p && p.desktopEntry) ? String(p.desktopEntry).toLowerCase() : "";
            return !excluded.some(ex => Paths.isAppIdMatch(identity, ex, desktopEntry));
        });
    }
    property MprisPlayer activePlayer: null
    property string pinnedIdentity: SessionData.pinnedPlayerIdentity || ""
    property real activePlayerStableLength: 0
    // Chromium can report blank metadata between tracks
    property string stableTitle: ""
    property string stableArtist: ""
    property string stableAlbum: ""
    property bool _mprisRequestInFlight: false
    property bool _mprisPublishDirty: false
    property int _mprisConnectionEpoch: 0
    property int positionConsumers: 0
    property bool refreshingPosition: false

    function refreshPosition(player) {
        if (!player?.positionSupported)
            return;
        refreshingPosition = true;
        player.positionChanged();
        refreshingPosition = false;
    }

    function addPositionRef() {
        positionConsumers++;
    }

    function removePositionRef() {
        positionConsumers = Math.max(0, positionConsumers - 1);
    }

    Connections {
        target: root.activePlayer
        function onTrackTitleChanged() {
            root.activePlayerStableLength = (root.activePlayer && root.activePlayer.lengthSupported && root.activePlayer.length > 1) ? root.activePlayer.length : 0;
            root._syncStableMeta();
            root._checkIdle();
        }
        function onTrackArtistChanged() {
            root._syncStableMeta();
            root._checkIdle();
        }
        function onTrackAlbumChanged() {
            root._syncStableMeta();
        }
        function onLengthChanged() {
            if (root.activePlayer && root.activePlayer.lengthSupported && root.activePlayer.length > 1) {
                root.activePlayerStableLength = root.activePlayer.length;
            }
        }
        function onPlaybackStateChanged() {
            root._syncStableMeta();
            root._checkIdle();
        }
    }

    Connections {
        target: root.activePlayer
        enabled: SettingsData.bluetoothMprisEnabled
        function onLengthChanged() {
            root._scheduleMPRISPublish();
        }
        function onMetadataChanged() {
            root._scheduleMPRISPublish();
        }
        function onPlaybackStateChanged() {
            root._scheduleMPRISPublish();
        }
        function onCanControlChanged() {
            root._scheduleMPRISPublish();
        }
        function onCanPlayChanged() {
            root._scheduleMPRISPublish();
        }
        function onCanPauseChanged() {
            root._scheduleMPRISPublish();
        }
        function onCanGoNextChanged() {
            root._scheduleMPRISPublish();
        }
        function onCanGoPreviousChanged() {
            root._scheduleMPRISPublish();
        }
    }

    Connections {
        target: SettingsData
        function onBluetoothMprisEnabledChanged() {
            if (SettingsData.bluetoothMprisEnabled)
                DMSService.addSubscription("mpris.command");
            root._scheduleMPRISPublish();
        }
    }

    Connections {
        target: DMSService
        function onConnectionStateChanged() {
            root._invalidateMPRISPublishRequests();
            root._scheduleMPRISPublish();
        }
        function onCapabilitiesReceived() {
            if (!DMSService.capabilities.includes("bluetooth"))
                root._invalidateMPRISPublishRequests();
            root._scheduleMPRISPublish();
        }
        function onSubscribeConnectedChanged() {
            root._invalidateMPRISPublishRequests();
            root._scheduleMPRISPublish();
        }
        function onMprisCommandLeaseChanged() {
            root._invalidateMPRISPublishRequests();
            root._scheduleMPRISPublish();
        }
        function onMprisCommandReceived(command) {
            root._dispatchMPRISCommand(command);
        }
    }

    onActivePlayerChanged: {
        activePlayerStableLength = (activePlayer && activePlayer.lengthSupported && activePlayer.length > 1) ? activePlayer.length : 0;
        stableTitle = "";
        stableArtist = "";
        stableAlbum = "";
        _syncStableMeta();
        _checkIdle();
        _scheduleMPRISPublish();
    }
    onActivePlayerStableLengthChanged: _scheduleMPRISPublish()
    onStableTitleChanged: _scheduleMPRISPublish()
    onStableArtistChanged: _scheduleMPRISPublish()
    onStableAlbumChanged: _scheduleMPRISPublish()

    function _syncStableMeta(): void {
        const p = activePlayer;
        if (!p) {
            stableTitle = "";
            stableArtist = "";
            stableAlbum = "";
            return;
        }
        if (isFirefoxYoutubeHoverPreview(p))
            return;
        const metadataPlayer = bestMetadataPlayer(p);
        const nextTitle = displayTrackTitle(metadataPlayer);
        const trackChanged = nextTitle && stableTitle && nextTitle.toLowerCase() !== stableTitle.toLowerCase();
        if (trackChanged) {
            stableArtist = "";
            stableAlbum = "";
        }
        if (nextTitle)
            stableTitle = nextTitle;
        if (metadataPlayer.trackArtist)
            stableArtist = metadataPlayer.trackArtist;
        if (metadataPlayer.trackAlbum)
            stableAlbum = metadataPlayer.trackAlbum;
    }

    // Chromium reports stopped media w/blank metadata, resolve by checking idle status
    Timer {
        id: _idleGraceTimer
        interval: 3000
        onTriggered: {
            if (!root.isIdle(root.activePlayer))
                return;
            root.stableTitle = "";
            root.stableArtist = "";
            root.stableAlbum = "";
            root._resolveActivePlayer();
        }
    }

    function _checkIdle(): void {
        if (!isIdle(activePlayer)) {
            _idleGraceTimer.stop();
            return;
        }
        if (!_idleGraceTimer.running)
            _idleGraceTimer.start();
    }

    onAvailablePlayersChanged: _resolveActivePlayer()
    Component.onCompleted: {
        _resolveActivePlayer();
        if (SettingsData.bluetoothMprisEnabled)
            DMSService.addSubscription("mpris.command");
        _scheduleMPRISPublish();
    }

    Instantiator {
        model: root.availablePlayers
        delegate: QtObject {
            required property MprisPlayer modelData
            readonly property bool playerIsPlaying: modelData.isPlaying
            readonly property string playerTrackTitle: modelData.trackTitle
            readonly property string playerTrackArtist: modelData.trackArtist
            readonly property string playerTrackAlbum: modelData.trackAlbum
            readonly property var playerMetadata: modelData.metadata
            function syncMeta() {
                if (playerIsPlaying)
                    root._resolveActivePlayer();
                root._syncStableMeta();
            }
            onPlayerIsPlayingChanged: {
                root._checkIdle();
                root._resolveActivePlayer();
                root._syncStableMeta();
            }
            onPlayerTrackTitleChanged: syncMeta()
            onPlayerTrackArtistChanged: syncMeta()
            onPlayerTrackAlbumChanged: syncMeta()
            onPlayerMetadataChanged: syncMeta()
        }
    }

    function isIdle(player: MprisPlayer): bool {
        return player && player.playbackState === MprisPlaybackState.Stopped;
    }

    // Known "<title> | <App>" suffixes stripped for matching only; display keeps the full title
    readonly property var _appTitleSuffixes: ["youtube", "youtube music", "soundcloud", "spotify", "chrome", "chromium", "firefox", "brave", "vivaldi", "twitch"]

    function _stripAppTitleSuffix(title: string): string {
        const idx = title.lastIndexOf(" | ");
        if (idx <= 0)
            return title;
        const suffix = title.substring(idx + 3).trim().toLowerCase();
        return _appTitleSuffixes.indexOf(suffix) !== -1 ? title.substring(0, idx).trim() : title;
    }

    function normalizedTrackTitle(player: MprisPlayer): string {
        return _stripAppTitleSuffix((player?.trackTitle || "").trim()).toLowerCase();
    }

    function displayTrackTitle(player: MprisPlayer): string {
        return (player?.trackTitle || "").trim();
    }

    function normalizedTrackArtist(player: MprisPlayer): string {
        return (player?.trackArtist || "").trim().toLowerCase();
    }

    // Artist missing on either side: fall back to URL, then album, before trusting a title-only match
    function isSameTrack(first: MprisPlayer, second: MprisPlayer): bool {
        const firstTitle = normalizedTrackTitle(first);
        if (!firstTitle || firstTitle !== normalizedTrackTitle(second))
            return false;
        const firstArtist = normalizedTrackArtist(first);
        const secondArtist = normalizedTrackArtist(second);
        if (firstArtist && secondArtist)
            return firstArtist === secondArtist;
        const firstUrl = (first?.metadata?.["xesam:url"] || "").toString();
        const secondUrl = (second?.metadata?.["xesam:url"] || "").toString();
        if (firstUrl && secondUrl)
            return firstUrl === secondUrl;
        const firstAlbum = (first?.trackAlbum || "").trim().toLowerCase();
        const secondAlbum = (second?.trackAlbum || "").trim().toLowerCase();
        if (firstAlbum && secondAlbum)
            return firstAlbum === secondAlbum;
        return true;
    }

    function metadataQuality(player: MprisPlayer): int {
        if (!player)
            return -1;
        let quality = player.trackArtist ? 100 : 0;
        quality += player.trackTitle ? 40 : 0;
        quality += player.trackAlbum ? 20 : 0;
        quality += player.trackArtUrl || player.metadata?.["mpris:artUrl"] ? 10 : 0;
        quality += player.metadata?.["xesam:url"] ? 5 : 0;
        return quality;
    }

    function equivalentPlayers(player: MprisPlayer): var {
        if (!player)
            return [];
        return availablePlayers.filter(candidate => {
            return candidate.playbackState !== MprisPlaybackState.Stopped && isSameTrack(player, candidate);
        });
    }

    function bestMetadataPlayer(player: MprisPlayer): MprisPlayer {
        const equivalents = equivalentPlayers(player);
        if (equivalents.length === 0)
            return player;
        return equivalents.reduce((best, candidate) => {
            return metadataQuality(candidate) > metadataQuality(best) ? candidate : best;
        }, player);
    }

    function _bestPlayingPlayer(): MprisPlayer {
        const playing = availablePlayers.filter(player => player.isPlaying);
        if (playing.length === 0)
            return null;

        if (pinnedIdentity !== "") {
            const pinLower = pinnedIdentity.toLowerCase();
            const exact = playing.filter(player => player.identity === pinnedIdentity);
            const matches = exact.length > 0 ? exact : playing.filter(player => (player.identity || "").toLowerCase().includes(pinLower));
            const pinned = matches.find(player => player.canControl) ?? matches[0];
            if (pinned)
                return pinned;
        }

        const controllable = playing.filter(player => player.canControl);
        if (activePlayer?.isPlaying) {
            if (activePlayer.canControl || controllable.length === 0)
                return activePlayer;
            // Playing but not controllable: only a same-track controllable peer may take over
            const mirror = controllable.find(player => isSameTrack(activePlayer, player));
            return mirror || activePlayer;
        }

        if (activePlayer?.canControl && activePlayer.playbackState === MprisPlaybackState.Paused) {
            const onlyEquivalentMirrors = playing.every(player => isSameTrack(activePlayer, player));
            if (onlyEquivalentMirrors)
                return null;
        }
        return controllable[0] || playing[0];
    }

    function _resolveActivePlayer(): void {
        const playing = _bestPlayingPlayer();
        if (playing) {
            if (activePlayer !== playing) {
                activePlayer = playing;
                _persistIdentity(playing.identity);
            }
            return;
        }
        if (activePlayer && availablePlayers.indexOf(activePlayer) >= 0 && (!isIdle(activePlayer) || _idleGraceTimer.running))
            return;
        if (activePlayer && availablePlayers.indexOf(activePlayer) < 0) {
            const successor = availablePlayers.find(p => p.identity === activePlayer.identity);
            if (successor) {
                activePlayer = successor;
                return;
            }
        }
        const savedId = SessionData.lastPlayerIdentity;
        if (savedId) {
            const match = availablePlayers.find(p => p.identity === savedId);
            if (match && !isIdle(match)) {
                activePlayer = match;
                return;
            }
        }
        activePlayer = availablePlayers.find(p => p.canControl && !isIdle(p)) ?? null;
        if (activePlayer)
            _persistIdentity(activePlayer.identity);
    }

    function setActivePlayer(player: MprisPlayer): void {
        activePlayer = player;
        if (player)
            _persistIdentity(player.identity);
    }

    function setPinned(identity: string): void {
        if (SessionData.pinnedPlayerIdentity !== identity)
            SessionData.set("pinnedPlayerIdentity", identity);
        _resolveActivePlayer();
    }

    function _persistIdentity(identity: string): void {
        if (identity && SessionData.lastPlayerIdentity !== identity)
            SessionData.set("lastPlayerIdentity", identity);
    }

    Timer {
        id: _mprisPublishTimer
        interval: 25
        repeat: false
        onTriggered: root._publishMPRISSnapshot()
    }

    Timer {
        id: _mprisRetryTimer
        interval: 2000
        repeat: false
        onTriggered: root._scheduleMPRISPublish()
    }

    Timer {
        interval: 1000
        running: root.positionConsumers > 0 && root.activePlayer?.playbackState === MprisPlaybackState.Playing
        repeat: true
        onTriggered: root.refreshPosition(root.activePlayer)
    }

    function _hasMPRISSubscription(): bool {
        return DMSService.activeSubscriptions.includes("mpris.command");
    }

    function _canPublishMPRIS(): bool {
        return DMSService.isConnected && DMSService.subscribeConnected && DMSService.mprisCommandLease && DMSService.capabilities.includes("bluetooth");
    }

    function _scheduleMPRISPublish(): void {
        const enabled = SettingsData.bluetoothMprisEnabled;
        const subscribed = _hasMPRISSubscription();

        if (!enabled && !subscribed && !_mprisRequestInFlight) {
            _mprisPublishDirty = false;
            return;
        }
        if (!enabled && subscribed && !DMSService.mprisCommandLease && !_mprisRequestInFlight) {
            _mprisPublishDirty = false;
            DMSService.removeSubscription("mpris.command");
            return;
        }

        _mprisPublishDirty = true;
        if (enabled && !subscribed) {
            DMSService.addSubscription("mpris.command");
            return;
        }
        if (_mprisRequestInFlight || !_canPublishMPRIS())
            return;
        if (!_mprisPublishTimer.running)
            _mprisPublishTimer.start();
    }

    function _scheduleMPRISRetry(): void {
        if (!SettingsData.bluetoothMprisEnabled && !_hasMPRISSubscription())
            return;
        if (!_mprisRetryTimer.running)
            _mprisRetryTimer.start();
    }

    function _invalidateMPRISPublishRequests(): void {
        _mprisConnectionEpoch++;
    }

    function _publishMPRISSnapshot(): void {
        if (_mprisRequestInFlight || !_mprisPublishDirty)
            return;
        if (!SettingsData.bluetoothMprisEnabled && !_hasMPRISSubscription()) {
            _mprisPublishDirty = false;
            return;
        }
        if (!_canPublishMPRIS())
            return;

        const enabled = SettingsData.bluetoothMprisEnabled;
        const requestLease = DMSService.mprisCommandLease;
        const requestEpoch = _mprisConnectionEpoch;
        const snapshot = _mprisSnapshot(enabled, requestLease);
        _mprisPublishDirty = false;
        _mprisRequestInFlight = true;
        _mprisRetryTimer.stop();

        DMSService.sendRequest("bluetooth.mpris.publish", snapshot, response => {
            const changedWhileInFlight = root._mprisPublishDirty;
            const currentConnection = requestEpoch === root._mprisConnectionEpoch && requestLease === DMSService.mprisCommandLease && DMSService.isConnected && DMSService.subscribeConnected;
            root._mprisRequestInFlight = false;

            if (!currentConnection) {
                root._mprisPublishDirty = true;
                root._scheduleMPRISPublish();
                return;
            }
            if (response?.error) {
                root._mprisPublishDirty = true;
                root._scheduleMPRISRetry();
                return;
            }

            _mprisRetryTimer.stop();

            if (!enabled && !SettingsData.bluetoothMprisEnabled) {
                root._mprisPublishDirty = false;
                DMSService.removeSubscription("mpris.command");
                return;
            }
            if (changedWhileInFlight || enabled !== SettingsData.bluetoothMprisEnabled)
                root._scheduleMPRISPublish();
        });
    }

    function _mprisSnapshot(enabled: bool, lease: string): var {
        const player = enabled ? activePlayer : null;
        return {
            "lease": lease,
            "enabled": enabled,
            "identity": "Dux Shell",
            "playbackStatus": _mprisPlaybackStatus(player),
            "title": player ? stableTitle : "",
            "artist": player ? stableArtist : "",
            "album": player ? stableAlbum : "",
            "length": player ? _secondsToMicroseconds(activePlayerStableLength) : 0,
            "position": player && player.positionSupported ? _secondsToMicroseconds(player.position) : 0,
            "canControl": player ? player.canControl : false,
            "canPlay": player ? player.canPlay : false,
            "canPause": player ? player.canPause : false,
            "canGoNext": player ? player.canGoNext : false,
            "canGoPrevious": player ? player.canGoPrevious : false
        };
    }

    function _mprisPlaybackStatus(player: MprisPlayer): string {
        if (!player)
            return "Stopped";
        if (player.playbackState === MprisPlaybackState.Playing)
            return "Playing";
        if (player.playbackState === MprisPlaybackState.Paused)
            return "Paused";
        return "Stopped";
    }

    function _secondsToMicroseconds(seconds: real): real {
        if (!Number.isFinite(seconds) || seconds <= 0)
            return 0;
        return Math.round(seconds * 1000000);
    }

    function _dispatchMPRISCommand(command: string): void {
        if (!SettingsData.bluetoothMprisEnabled || !DMSService.mprisCommandLease)
            return;
        switch (command) {
        case "play":
            play();
            break;
        case "pause":
            pause();
            break;
        case "playPause":
            playPause();
            break;
        case "stop":
            stop();
            break;
        case "next":
            next();
            break;
        case "previous":
            previous();
            break;
        }
    }

    function isFirefoxYoutubeHoverPreview(player: MprisPlayer): bool {
        if (!player)
            return false;
        const id = (player.identity || "").toLowerCase();
        if (!id.includes("firefox"))
            return false;
        const url = (player.metadata?.["xesam:url"] || "").toString();
        return /^https?:\/\/(www\.)?youtube\.com\/?($|\?|#)/i.test(url);
    }

    function play(): void {
        const player = activePlayer;
        if (!player?.canPlay)
            return;
        player.play();
    }

    function pause(): void {
        const player = activePlayer;
        if (!player?.canPause)
            return;
        player.pause();
    }

    function playPause(): void {
        const player = activePlayer;
        if (!player?.canTogglePlaying)
            return;
        player.togglePlaying();
    }

    function stop(): void {
        const player = activePlayer;
        if (player)
            player.stop();
    }

    function previousOrRewind(): void {
        if (!activePlayer)
            return;
        if (activePlayer.position > 8 && activePlayer.canSeek)
            activePlayer.position = 0.1;
        else if (activePlayer.canGoPrevious)
            activePlayer.previous();
    }

    function previous(): void {
        const player = activePlayer;
        if (player?.canGoPrevious)
            player.previous();
    }

    function next(): void {
        const player = activePlayer;
        if (player?.canGoNext)
            player.next();
    }
}
