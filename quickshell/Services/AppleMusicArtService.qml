pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root

    readonly property var log: Log.scoped("AppleMusicArt")
    readonly property bool enabled: MediaOptions.animatedArt

    // file:// url of the current album's downloaded animated cover, or empty.
    property string animatedArtUrl: ""

    readonly property var _fetchCmd: [Proc.dmsBin, "dl", "--connect-timeout", "5", "--timeout", "15"]
    readonly property string _artDir: Paths.strip(Paths.cache) + "/applemusic-art"
    property string _token: ""
    // artist\nalbum (lowercased) -> file url or "" for a known miss; never refetched this session.
    property var _cache: ({})
    property int _serial: 0

    readonly property string _artist: MprisController.activePlayer?.trackArtist || ""
    readonly property string _album: MprisController.activePlayer?.trackAlbum || ""
    readonly property string _cacheKey: _artist !== "" && _album !== "" ? (_artist + "\n" + _album).toLowerCase() : ""

    property bool _pruned: false

    on_CacheKeyChanged: _schedule()
    onEnabledChanged: {
        _pruneOnce();
        _schedule();
    }
    Component.onCompleted: {
        _pruneOnce();
        _schedule();
    }

    function _pruneOnce() {
        if (_pruned || !enabled)
            return;
        _pruned = true;
        _prune();
    }

    // Downloaded covers are a few MB each; drop anything untouched for 30 days so the
    // cache can't grow without bound.
    function _prune() {
        Proc.runCommand(null, ["sh", "-c", 'test -d "$1" && find "$1" -type f -mtime +30 -delete', "sh", _artDir], () => {}, 50, 10000);
    }

    function _schedule() {
        _serial++;
        _debounce.stop();
        if (!enabled || _cacheKey === "") {
            animatedArtUrl = "";
            return;
        }
        if (_cacheKey in _cache) {
            animatedArtUrl = _cache[_cacheKey];
            return;
        }
        animatedArtUrl = "";
        _debounce.restart();
    }

    Timer {
        id: _debounce
        interval: 1500
        onTriggered: root._lookup()
    }

    function _artPath(key) {
        return _artDir + "/" + Qt.md5(key) + ".mp4";
    }

    // Disk cache first: a hit needs no network; touching keeps _prune from evicting active covers.
    function _lookup() {
        const key = _cacheKey;
        const serial = _serial;
        Proc.runCommand(null, ["sh", "-c", 'test -s "$1" && touch "$1"', "sh", _artPath(key)], (output, exitCode) => {
            if (serial !== _serial)
                return;
            if (exitCode === 0) {
                _store(key, serial, "file://" + _artPath(key));
                return;
            }
            _search(key, serial);
        }, 50, 5000);
    }

    // Bidirectional contains, so "Album" still matches "Album (Deluxe Edition)" either way round.
    function _looseMatch(a, b) {
        if (a === "" || b === "")
            return false;
        const la = a.toLowerCase();
        const lb = b.toLowerCase();
        return la.includes(lb) || lb.includes(la);
    }

    // US storefront only (search default and the catalog paths below); albums absent there become misses.
    function _search(key, serial) {
        const term = encodeURIComponent(_artist + " " + _album);
        Proc.runCommand(null, _fetchCmd.concat(["https://itunes.apple.com/search?media=music&entity=album&limit=1&term=" + term]), (output, exitCode) => {
            if (serial !== _serial)
                return;
            if (exitCode !== 0) {
                log.warn("itunes search failed");
                return;
            }
            let result;
            try {
                result = JSON.parse(output).results[0] || null;
            } catch (e) {
                log.warn("itunes search parse failed");
                return;
            }
            // A fuzzy first hit for a different record would cache the wrong video under this key.
            if (!result || !result.collectionId || !_looseMatch(result.artistName || "", _artist) || !_looseMatch(result.collectionName || "", _album)) {
                _store(key, serial, "");
                return;
            }
            if (_token !== "") {
                _fetchEditorialVideo(key, serial, result.collectionId);
                return;
            }
            _fetchToken("https://music.apple.com/us/album/" + result.collectionId, token => {
                if (serial !== _serial)
                    return;
                _token = token;
                _fetchEditorialVideo(key, serial, result.collectionId);
            });
        }, 50, 20000);
    }

    // The anonymous web-player JWT sits in the main JS bundle referenced by any album page.
    function _fetchToken(pageUrl, callback) {
        const script = "p=$(\"$0\" dl \"$1\" | grep -oE '/assets/index~[a-zA-Z0-9]+\\.js' | head -1) && \"$0\" dl \"https://music.apple.com$p\" | grep -oE '\"eyJ[A-Za-z0-9._-]+\"' | head -1 | tr -d '\"'";
        Proc.runCommand(null, ["sh", "-c", script, Proc.dmsBin, pageUrl], (output, exitCode) => {
            const token = (output || "").trim();
            if (exitCode !== 0 || token === "") {
                log.warn("failed to obtain web-player token");
                return;
            }
            callback(token);
        }, 50, 30000);
    }

    function _fetchEditorialVideo(key, serial, albumId) {
        const url = "https://amp-api.music.apple.com/v1/catalog/us/albums/" + albumId + "?extend=editorialVideo";
        Proc.runCommand(null, _fetchCmd.concat(["-H", "Authorization: Bearer " + _token, "-H", "Origin: https://music.apple.com", url]), (output, exitCode) => {
            if (serial !== _serial)
                return;
            if (exitCode !== 0) {
                // Token may have expired; rescrape on the next lookup.
                _token = "";
                log.warn("editorial video lookup failed");
                return;
            }
            let video;
            try {
                const ev = JSON.parse(output).data[0].attributes.editorialVideo;
                video = ev ? (ev.motionDetailSquare?.video || ev.motionSquareVideo1x1?.video || "") : "";
            } catch (e) {
                log.warn("editorial video parse failed");
                return;
            }
            if (video === "") {
                _store(key, serial, "");
                return;
            }
            _fetchMaster(key, serial, video);
        }, 50, 20000);
    }

    function _fetchMaster(key, serial, m3u8Url) {
        Proc.runCommand(null, _fetchCmd.concat([m3u8Url]), (output, exitCode) => {
            if (serial !== _serial)
                return;
            if (exitCode !== 0) {
                log.warn("master playlist fetch failed");
                return;
            }
            const variant = _pickVariant(output);
            if (!variant) {
                _store(key, serial, "");
                return;
            }
            const variantUrl = variant.startsWith("http") ? variant : m3u8Url.slice(0, m3u8Url.lastIndexOf("/") + 1) + variant;
            _fetchVariant(key, serial, variantUrl);
        }, 50, 20000);
    }

    // Highest-bandwidth avc1 rendition at or below 768px, else the smallest one above;
    // hvc1 is skipped for decoder compatibility.
    function _pickVariant(master) {
        const lines = master.split("\n");
        let best = null;
        let bestBw = -1;
        let smallestOver = null;
        let smallestOverW = Infinity;
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i];
            if (!l.startsWith("#EXT-X-STREAM-INF:") || l.indexOf("avc1") === -1)
                continue;
            const res = /RESOLUTION=(\d+)x/.exec(l);
            if (!res)
                continue;
            let j = i + 1;
            while (j < lines.length && (lines[j].startsWith("#") || lines[j].trim() === ""))
                j++;
            if (j >= lines.length)
                continue;
            const uri = lines[j].trim();
            const w = parseInt(res[1], 10);
            if (w > 768) {
                if (w < smallestOverW) {
                    smallestOverW = w;
                    smallestOver = uri;
                }
                continue;
            }
            const bw = /AVERAGE-BANDWIDTH=(\d+)/.exec(l);
            const bwv = bw ? parseInt(bw[1], 10) : 0;
            if (bwv > bestBw) {
                bestBw = bwv;
                best = uri;
            }
        }
        return best || smallestOver;
    }

    // The rendition playlist is BYTERANGE segments over one progressive mp4 (EXT-X-MAP).
    function _fetchVariant(key, serial, variantUrl) {
        Proc.runCommand(null, _fetchCmd.concat([variantUrl]), (output, exitCode) => {
            if (serial !== _serial)
                return;
            if (exitCode !== 0) {
                log.warn("rendition playlist fetch failed");
                return;
            }
            const m = /#EXT-X-MAP:URI="([^"]+)"/.exec(output);
            if (!m) {
                _store(key, serial, "");
                return;
            }
            const mp4 = m[1].startsWith("http") ? m[1] : variantUrl.slice(0, variantUrl.lastIndexOf("/") + 1) + m[1];
            _download(key, serial, mp4);
        }, 50, 20000);
    }

    // Download once and play the local file: streaming the HLS through the ffmpeg
    // backend truncates on some TLS stacks, and the cache survives restarts.
    function _download(key, serial, url) {
        const path = _artPath(key);
        // Per-process temp then atomic rename, so a concurrent download for the same
        // album (rapid track flip-flop) can't interleave writes into one file; the
        // temp is removed on failure rather than stranded as a .part.
        const script = 'mkdir -p "${1%/*}" && { test -s "$1" || { t="$1.$$.part"; "$0" dl --connect-timeout 5 --timeout 60 -o "$t" "$2" >/dev/null && mv -f "$t" "$1" || { rm -f "$t"; exit 1; }; }; }';
        Proc.runCommand(null, ["sh", "-c", script, Proc.dmsBin, path, url], (output, exitCode) => {
            if (serial !== _serial)
                return;
            if (exitCode !== 0) {
                log.warn("artwork download failed");
                return;
            }
            _store(key, serial, "file://" + path);
        }, 50, 90000);
    }

    function _store(key, serial, url) {
        _cache[key] = url;
        if (serial === _serial)
            animatedArtUrl = url;
    }
}
