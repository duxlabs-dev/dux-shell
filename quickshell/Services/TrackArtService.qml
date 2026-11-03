pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import Quickshell.Services.Mpris
import qs.Common

Singleton {
    id: root

    property string _lastArtUrl: ""
    property var artwork: ({
            url: "",
            key: "",
            source: "",
            colors: []
        })
    readonly property string resolvedArtUrl: artwork.url
    readonly property int resolvedArtSide: _largestArt.url === resolvedArtUrl ? _largestArt.side : 0
    property var _candidateArt: null
    property var _quantizedArt: ({
            url: "",
            colors: []
        })
    property var _largestArt: ({
            key: "",
            url: "",
            side: 0
        })
    property alias _bgArtSource: root.resolvedArtUrl
    property bool loading: false
    // sha1s of placeholder art to reject (Chrome's own logo, shown before real cover).
    readonly property var _artHashDenylist: ["764a730860c5b8a7bbee690ee5a443672ae37dc8"]

    function djb2Hash(str) {
        if (!str)
            return "";
        let hash = 5381;
        for (let i = 0; i < str.length; i++) {
            hash = ((hash << 5) + hash) + str.charCodeAt(i);
            hash = hash & 0x7FFFFFFF;
        }
        return hash.toString(16).padStart(8, '0');
    }

    function _directArtworkUrl(player) {
        if (!player)
            return "";

        let artUrl = player.trackArtUrl || "";
        if (artUrl !== "") {
            return artUrl;
        }

        if (player.metadata && player.metadata["mpris:artUrl"]) {
            artUrl = player.metadata["mpris:artUrl"].toString();
            if (artUrl !== "")
                return artUrl;
        }

        // YouTube publishes no artUrl; derive the thumbnail from the video id.
        if (player.metadata && player.metadata["xesam:url"]) {
            const url = player.metadata["xesam:url"].toString();
            if (url.includes("youtube.com") || url.includes("youtu.be")) {
                const regExp = /^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|\&v=)([^#\&\?]*).*/;
                const match = url.match(regExp);
                if (match && match[2].length === 11) {
                    return "https://img.youtube.com/vi/" + match[2] + "/hqdefault.jpg";
                }
            }
        }

        return "";
    }

    function getArtworkUrl(player) {
        const directUrl = _directArtworkUrl(player);
        if (directUrl !== "")
            return directUrl;

        const equivalent = MprisController.equivalentPlayers(player).find(candidate => {
            return candidate !== player && _directArtworkUrl(candidate) !== "";
        });
        return _directArtworkUrl(equivalent);
    }

    function _publish(candidate, colors) {
        if (candidate.url !== "" && (candidate.key !== _trackKey() || candidate.source !== getArtworkUrl(activePlayer)))
            return;
        artwork = {
            url: candidate.url,
            key: candidate.key,
            source: candidate.source,
            colors: colors
        };
        _candidateArt = null;
        loading = false;
    }

    function _commit(url, artKey, srcUrl) {
        if (url !== "" && url === resolvedArtUrl && artKey !== _committedArtKey && srcUrl === _committedSrcUrl) {
            loading = false;
            return;
        }
        const candidate = {
            url: url,
            key: artKey,
            source: srcUrl,
            serial: _requestSerial
        };
        if (url === "" || url === resolvedArtUrl) {
            _publish(candidate, url === "" ? [] : artwork.colors);
            return;
        }
        if (url === _quantizedArt.url) {
            _publish(candidate, _quantizedArt.colors);
            return;
        }
        _candidateArt = candidate;
        _quantize(url);
    }

    property bool _quantizing: false
    property string _queuedArtUrl: ""

    // Replacing a live source makes ColorQuantizer wait for the whole global thread pool on the gui thread.
    function _quantize(url) {
        if (_quantizing) {
            _queuedArtUrl = url;
            return;
        }
        _queuedArtUrl = "";
        const previous = quantizer.source.toString();
        quantizer.source = url;
        _quantizing = quantizer.source.toString() !== previous;
    }

    function _startQueued() {
        if (_queuedArtUrl !== "" && !_quantizing)
            _quantize(_queuedArtUrl);
    }

    ColorQuantizer {
        id: quantizer
        depth: 4
        rescaleSize: 64
        onColorsChanged: {
            root._quantizing = false;
            root._quantizedArt = {
                url: source.toString(),
                colors: Array.from(colors)
            };
            const candidate = root._candidateArt;
            if (candidate && candidate.serial === root._requestSerial && candidate.url === source.toString())
                root._publish(candidate, root._quantizedArt.colors);
            // colorsChanged fires twice per run; start the queued source after both have seen this one.
            if (root._queuedArtUrl !== "")
                Qt.callLater(root._startQueued);
        }
    }

    // Chrome can attach the previous track's late, smaller cover to the new track.
    function _noteLargestArt(artKey, art, current) {
        if (artKey !== _pendingArtKey)
            return;
        const known = _largestArt.key === artKey;
        if (known && (current ? art.side > 0 && art.side < _largestArt.side : art.side <= _largestArt.side))
            return;
        _largestArt = {
            key: artKey,
            url: art.url,
            side: art.side
        };
    }

    function loadArtwork(url, artKey, requestSerial) {
        if (!url || url === "") {
            // Keep stale art; only blank once the empty url debounce settles.
            _lastArtUrl = "";
            loading = false;
            if (!_clearDebounce.running) {
                _clearDebounce.interval = _emptyArtClearMs;
                _clearDebounce.start();
            }
            return;
        }
        _clearDebounce.stop();
        // Same url must re-issue under a new serial; the bump cancelled the in-flight load.
        if (url === _lastArtUrl && requestSerial === _lastIssuedSerial)
            return;
        _lastArtUrl = url;
        _lastIssuedSerial = requestSerial;

        if (url.startsWith("http://") || url.startsWith("https://")) {
            loading = true;
            const targetUrl = url;
            const hash = djb2Hash(url);
            const cacheDir = Paths.strip(Paths.imagecache);
            const filePath = cacheDir + "/remote_" + hash;
            const localFileUrl = "file://" + filePath;

            Proc.runCommand(null, ["test", "-f", filePath], (output, exitCode) => {
                if (_lastArtUrl !== targetUrl || _requestSerial !== requestSerial)
                    return;

                if (exitCode === 0) {
                    _commit(localFileUrl, artKey, targetUrl);
                } else {
                    const dlCmd = "\"$0\" dl -o \"$1\" \"$2\" >/dev/null && mv \"$1\" \"$3\" || { rm -f \"$1\"; exit 1; }";

                    // YouTube: try the 16:9 maxres thumbnail before falling back.
                    if (targetUrl.includes("img.youtube.com/vi/")) {
                        const videoId = targetUrl.split("/vi/")[1].split("/")[0];
                        const maxresUrl = "https://img.youtube.com/vi/" + videoId + "/maxresdefault.jpg";
                        const mqUrl = "https://img.youtube.com/vi/" + videoId + "/mqdefault.jpg";
                        const tmpPath = filePath + "." + requestSerial + ".tmp";

                        Proc.runCommand(null, ["sh", "-c", dlCmd, Proc.dmsBin, tmpPath, maxresUrl, filePath], (maxOutput, maxExitCode) => {
                            if (_lastArtUrl !== targetUrl || _requestSerial !== requestSerial)
                                return;

                            if (maxExitCode === 0) {
                                _commit(localFileUrl, artKey, targetUrl);
                            } else {
                                Proc.runCommand(null, ["sh", "-c", dlCmd, Proc.dmsBin, tmpPath, mqUrl, filePath], (mqOutput, mqExitCode) => {
                                    if (_lastArtUrl !== targetUrl || _requestSerial !== requestSerial)
                                        return;

                                    _commit(mqExitCode === 0 ? localFileUrl : targetUrl, artKey, targetUrl);
                                }, 50, 15000);
                            }
                        }, 50, 15000);
                    } else {
                        const tmpPath = filePath + "." + requestSerial + ".tmp";
                        Proc.runCommand(null, ["sh", "-c", dlCmd, Proc.dmsBin, tmpPath, targetUrl, filePath], (dlOutput, dlExitCode) => {
                            if (_lastArtUrl !== targetUrl || _requestSerial !== requestSerial)
                                return;

                            _commit(dlExitCode === 0 ? localFileUrl : targetUrl, artKey, targetUrl);
                        }, 50, 15000);
                    }
                }
            }, 50, 5000);
            return;
        }

        loading = true;
        const localUrl = url;
        const filePath = url.startsWith("file://") ? url.substring(7) : url;
        const cacheDir = Paths.strip(Paths.imagecache);
        // Cover lands after metadata, so poll; commit a content-addressed copy so identical bytes keep an identical url
        const script = "f=\"$1\"; d=\"$2\"; i=0; while [ ! -f \"$f\" ] && [ \"$i\" -lt 20 ]; do sleep 0.15; i=$((i + 1)); done; mkdir -p \"$d\" && cp \"$f\" \"$d/in.$$\" || exit 1; s=$(sha1sum \"$d/in.$$\" | cut -c1-40); if [ -f \"$d/art_$s\" ]; then rm -f \"$d/in.$$\"; else mv \"$d/in.$$\" \"$d/art_$s\" || exit 1; fi; set -- $(od -An -tu1 -j12 -N12 \"$d/art_$s\"); p=0; if [ \"$1 $2 $3 $4\" = \"73 72 68 82\" ]; then w=$(( $5 << 24 | $6 << 16 | $7 << 8 | $8 )); h=$(( $9 << 24 | ${10} << 16 | ${11} << 8 | ${12} )); p=$(( w > h ? w : h )); fi; echo \"$s $p\"";
        Proc.runCommand(null, ["sh", "-c", script, "sh", filePath, cacheDir], (output, exitCode) => _artProbed(localUrl, artKey, requestSerial, output, exitCode), 0, 5000);
    }

    function _artProbed(localUrl, artKey, requestSerial, output, exitCode) {
        const [sha, sideText] = (output || "").trim().split(" ");
        const art = {
            url: "file://" + Paths.strip(Paths.imagecache) + "/art_" + sha,
            side: Number(sideText) || 0
        };
        const current = _lastArtUrl === localUrl && _requestSerial === requestSerial;
        const usable = exitCode === 0 && _artHashDenylist.indexOf(sha) === -1;
        if (usable)
            _noteLargestArt(artKey, art, current);
        if (!current) {
            // probes finish in any order, so the larger cover can land after the late one was picked
            if (usable && art.url === _largestArt.url && artKey === _pendingArtKey)
                _commit(art.url, artKey, getArtworkUrl(activePlayer));
            return;
        }
        if (exitCode !== 0) {
            _commit("", "", "");
            return;
        }
        if (!usable) {
            _lastArtUrl = "";
            loading = false;
            _clearDebounce.interval = _placeholderArtClearMs;
            _clearDebounce.restart();
            return;
        }
        _commit(_largestArt.url, artKey, localUrl);
    }

    readonly property int _emptyArtClearMs: 800
    readonly property int _placeholderArtClearMs: 4000

    Timer {
        id: _clearDebounce
        interval: root._emptyArtClearMs
        onTriggered: {
            if (root._lastArtUrl === "")
                root._commit("", "", "");
        }
    }

    property MprisPlayer activePlayer: MprisController.activePlayer

    readonly property string _committedArtKey: artwork.key
    property string _pendingArtKey: ""
    readonly property string _committedSrcUrl: artwork.source
    property string _pendingSrcUrl: ""
    property int _requestSerial: 0
    property int _lastIssuedSerial: -1

    onActivePlayerChanged: _updateArtUrl()

    Connections {
        target: MprisController
        function onAvailablePlayersChanged() {
            root._updateArtUrl();
        }
    }

    Connections {
        target: root.activePlayer
        function onIsPlayingChanged() {
            root._updateArtUrl();
        }
        function onTrackTitleChanged() {
            root._updateArtUrl();
        }
        function onTrackArtistChanged() {
            root._updateArtUrl();
        }
        function onTrackAlbumChanged() {
            root._updateArtUrl();
        }
        function onTrackArtUrlChanged() {
            root._updateArtUrl();
        }
        function onMetadataChanged() {
            root._updateArtUrl();
        }
    }

    function _trackKey(player) {
        const p = player ?? activePlayer;
        if (!p)
            return "";
        // dbusName is constant per player; uniqueId is per-track and would churn the key.
        const playerId = p.dbusName || p.identity || "";
        const tid = p.metadata && p.metadata["mpris:trackid"] ? p.metadata["mpris:trackid"].toString() : "";
        return playerId + " " + tid + " " + (p.trackTitle || "") + " " + (p.trackArtist || "");
    }

    function artReadyFor(player) {
        const url = getArtworkUrl(player);
        return url !== "" && url === _committedSrcUrl && _trackKey(player) === _committedArtKey && !loading && resolvedArtUrl !== "";
    }

    Timer {
        id: artUpdate
        interval: 0
        onTriggered: root._loadCurrentArtwork()
    }

    Timer {
        id: reusedSourceDelay
        interval: 150
        onTriggered: root.loadArtwork(root._pendingSrcUrl, root._pendingArtKey, root._requestSerial)
    }

    function _updateArtUrl() {
        artUpdate.restart();
    }

    function _loadCurrentArtwork() {
        const key = _trackKey();
        const url = getArtworkUrl(activePlayer);
        if (key !== _pendingArtKey || url !== _pendingSrcUrl) {
            _requestSerial++;
            _candidateArt = null;
            reusedSourceDelay.stop();
        }
        _pendingArtKey = key;
        _pendingSrcUrl = url;
        if (url !== "")
            _clearDebounce.stop();
        if (key !== "" && key === _committedArtKey && url === _committedSrcUrl) {
            _clearDebounce.stop();
            loading = false;
            return;
        }
        if (key !== "" && url !== "" && url === _committedSrcUrl && key !== _committedArtKey) {
            loading = true;
            if (!reusedSourceDelay.running)
                reusedSourceDelay.start();
            return;
        }
        loadArtwork(url, key, _requestSerial);
    }
}
