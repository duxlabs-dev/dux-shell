pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.DDash

QtObject {
    id: root

    property var track: null
    property var player: null
    property bool playing: false
    property bool stopped: false
    property real rate: 1
    property bool settling: false
    property string url: ""
    property string embeddedText: ""
    property var backend: DMSService
    property bool enabled: false

    readonly property bool available: DMSService.capabilities.includes("lyrics")
    readonly property bool canSeekLines: synced && (player?.canSeek ?? false) && duration > 0
    readonly property string fileUrl: url.startsWith("file://") ? url : ""
    readonly property string trackKey: track ? JSON.stringify([track.key, track.title, track.artist, track.album, fileUrl, MediaOptions.enabledLyricsProviders]) : ""
    readonly property int duration: Math.round(track?.length ?? 0)
    readonly property real position: player?.position ?? 0
    readonly property string busName: player?.dbusName ?? ""

    property var lines: []
    property var plainLines: []
    property bool synced: false
    property string attributionName: ""
    property string attributionUrl: ""
    property string attributionText: ""
    property int activeIndex: -1
    property real wordTime: -1
    property real wordEnd: -1
    property int wordRevision: 0
    property real sampleTime: 0
    property var cueTimes: []
    property var focusedGroups: []
    property string state: "idle"
    readonly property bool pending: state === "loading" || (state === "idle" && enabled && requestDelay.running)
    property string requestedKey: ""
    property string requestedSong: ""
    property string shownSong: ""
    property string shownResult: ""
    property bool refreshPending: false
    property int requestedDuration: 0
    property var requestId: null
    readonly property bool staleDuration: duration !== requestedDuration && state !== "ready" && state !== "instrumental"
    property int serial: 0
    property real anchorPosition: 0
    property real anchorWall: 0
    property bool anchorPlaying: false
    property real anchorRate: 1
    property real positionWall: 0
    property var probe: null
    property bool positionTrusted: true
    property string clockBus: ""
    property var memo: null

    onTrackKeyChanged: {
        cancel();
        refreshPending = holdsSong();
        if (!refreshPending)
            restart();
        requestedKey = "";
        if (enabled)
            resume();
    }
    onEnabledChanged: {
        if (!enabled) {
            cancel();
            stopClock();
            if (state === "loading") {
                requestedKey = "";
                state = "idle";
            }
            remember();
            return;
        }
        resume();
    }
    onStaleDurationChanged: {
        if (!enabled || !staleDuration)
            return;
        requestDelay.restart();
    }
    onEmbeddedTextChanged: {
        if (enabled && (state === "none" || state === "error"))
            useEmbeddedText(state);
    }
    onPositionChanged: {
        if (MprisController.refreshingPosition || flooredEcho())
            return;
        scheduleAnchor();
    }
    onRateChanged: updatePlaybackClock()
    onPlayingChanged: {
        probe = null;
        updatePlaybackClock();
    }
    Component.onDestruction: {
        cancel();
        stopClock();
        remember();
    }

    function cancel() {
        serial++;
        if (requestId !== null)
            backend.cancelRequest(requestId);
        requestId = null;
        requestDelay.stop();
    }

    function stopClock() {
        tick.stop();
        anchorUpdate.stop();
    }

    function resume() {
        recall();
        if (requestedKey !== trackKey || staleDuration || state === "idle" || state === "error") {
            requestDelay.restart();
            return;
        }
        reanchor();
    }

    function remember() {
        if (requestedKey === "" || (state !== "ready" && state !== "instrumental" && state !== "none"))
            return;
        memo = {
            requestedKey,
            requestedDuration,
            requestedSong,
            lines,
            plainLines,
            synced,
            cueTimes,
            attributionName,
            attributionUrl,
            attributionText,
            shownSong,
            shownResult,
            state
        };
    }

    function recall() {
        const last = memo;
        if (!last || last.requestedKey !== trackKey || requestedKey === trackKey)
            return;
        refreshPending = false;
        clearContent();
        for (const name in last)
            root[name] = last[name];
    }

    function songTitle() {
        return (track?.title ?? "").trim().toLowerCase();
    }

    function holdsSong() {
        const title = songTitle();
        return (state === "ready" || state === "instrumental") && title !== "" && title === shownSong;
    }

    function clear() {
        clearContent();
        state = "idle";
    }

    function restart() {
        const switched = clockBus !== "" && clockBus === busName;
        clockBus = busName;
        clear();
        positionTrusted = !switched;
        if (!switched)
            return;
        anchorPosition = 0;
        anchorWall = Date.now();
        anchorPlaying = playing;
        anchorRate = rate;
    }

    function clearContent() {
        stopClock();
        lines = [];
        plainLines = [];
        synced = false;
        attributionName = "";
        attributionUrl = "";
        attributionText = "";
        activeIndex = -1;
        wordTime = -1;
        wordEnd = -1;
        cueTimes = [];
        focusedGroups = [];
        probe = null;
        wordRevision++;
        shownSong = "";
        shownResult = "";
    }

    function request() {
        cancel();
        if (!enabled)
            return;
        const refreshing = refreshPending && holdsSong();
        if (settling) {
            if (!refreshing)
                state = "loading";
            requestDelay.restart();
            return;
        }
        refreshPending = false;
        if (!refreshing)
            clear();
        requestedKey = trackKey;
        requestedDuration = duration;
        requestedSong = songTitle();
        const snapshot = track;
        if (!snapshot || ((!snapshot.title || !snapshot.artist) && !fileUrl)) {
            if (!refreshing)
                useEmbeddedText("none");
            return;
        }
        if (!refreshing)
            state = "loading";
        lookup({
            "title": snapshot.title || "",
            "artist": snapshot.artist || "",
            "album": snapshot.album || "",
            "duration": requestedDuration,
            "fileUrl": fileUrl,
            "providers": MediaOptions.enabledLyricsProviders
        }, false, refreshing);
    }

    function lookup(query, allowNetwork, refreshing) {
        const token = serial;
        const networkQuery = !allowNetwork && query.providers.length > 0 ? query : null;
        const params = Object.assign({
            "allowNetwork": allowNetwork
        }, query);
        requestId = backend.sendRequest("lyrics.get", params, response => root.receive(token, response, refreshing, networkQuery), DashMetrics.mediaLyricsRequestTimeout) ?? null;
    }

    function receive(token, response, refreshing, networkQuery) {
        if (token !== serial || !enabled)
            return;
        requestId = null;
        const result = response.error ? null : response.result;
        const found = !!result?.found && (result.instrumental || (result.synced ?? []).length > 0 || (result.plain ?? "").trim() !== "");
        if (networkQuery) {
            lookup(networkQuery, true, refreshing || found);
            if (!found)
                return;
        }
        if (refreshing && !found)
            return;
        const resultKey = found ? JSON.stringify([result.instrumental === true, result.synced ?? [], result.voices ?? {}, result.plain ?? "", result.attribution ?? {}]) : "";
        if (refreshing && resultKey === shownResult)
            return;
        if (response.error) {
            useEmbeddedText("error");
            return;
        }
        if (!result?.found) {
            useEmbeddedText("none");
            return;
        }
        shownSong = requestedSong;
        shownResult = resultKey;
        if (result.instrumental) {
            clearContent();
            state = "instrumental";
            return;
        }
        lines = prepareLines(result.synced ?? [], result.voices ?? {});
        synced = lines.length > 0;
        plainLines = (result.plain ?? "").trim().split("\n");
        if (!synced && !plainLines.some(line => line.trim() !== "")) {
            useEmbeddedText("none");
            return;
        }
        attributionName = result.attribution?.name ?? "";
        attributionUrl = result.attribution?.url ?? "";
        attributionText = result.attribution?.text ?? "";
        state = "ready";
        reanchor();
    }

    function prepareLines(source, voices) {
        const parts = source.filter(line => Number.isFinite(line.t) && line.t >= 0 && typeof line.x === "string").map(line => ({
                    t: line.t,
                    e: Number.isFinite(line.e) && line.e > line.t ? line.e : 0,
                    x: line.x,
                    w: wordsFor(line),
                    voice: typeof line.voice === "string" ? line.voice : "",
                    background: line.background === true,
                    group: Number.isInteger(line.group) && line.group > 0 ? line.group : 0
                })).sort((a, b) => a.t - b.t);
        const singers = [...new Set(parts.filter(part => part.voice && !part.background && voices[part.voice]?.type !== "group").map(part => part.voice))];
        const nextStarts = new Map();
        const events = new Set();
        for (let i = parts.length - 1; i >= 0; i--) {
            const part = parts[i];
            const lane = part.voice + "\u0000" + part.background;
            const following = nextStarts.get(lane);
            const next = following?.t === part.t ? following.next : following?.t ?? Infinity;
            const cues = part.w.slice().sort((a, b) => a.t - b.t);
            const last = cues[cues.length - 1];
            if (part.e <= part.t) {
                const trackEnd = track?.length > part.t ? track.length : Infinity;
                part.e = last?.e > last?.t ? Math.max(...cues.map(word => word.e)) : next > part.t ? Math.min(next, trackEnd) : trackEnd;
            }
            if (last && part.e <= last.t)
                part.e = next > last.t ? next : Infinity;
            if (next > part.t)
                part.e = Math.min(part.e, next);
            nextStarts.set(lane, {
                t: part.t,
                next
            });
            part.cues = cues;
            const voice = voices[part.voice];
            const singerIndex = singers.indexOf(part.voice);
            part.voiceIndex = Math.max(0, singerIndex);
            part.chorus = singers.length > 1 && singerIndex < 0 && voice?.type === "group";
            part.side = singers.length > 1 && singerIndex >= 0 ? (singerIndex % 2 === 0 ? -1 : 1) : 0;
            part.voiceName = typeof voice?.name === "string" ? voice.name : "";
            events.add(part.t);
            if (Number.isFinite(part.e))
                events.add(part.e);
            for (const word of cues)
                events.add(word.t);
        }
        const groups = new Map();
        for (const part of parts) {
            const key = part.group ? "group:" + part.group : "time:" + part.t;
            let group = groups.get(key);
            if (!group) {
                group = {
                    t: part.t,
                    e: part.e,
                    parts: [],
                    x: ""
                };
                groups.set(key, group);
            }
            group.t = Math.min(group.t, part.t);
            group.e = Math.max(group.e, part.e);
            group.parts.push(part);
        }
        const prepared = [...groups.values()].sort((a, b) => a.t - b.t);
        for (const group of prepared) {
            group.parts.sort((a, b) => Number(a.background) - Number(b.background) || a.t - b.t);
            group.x = group.parts.map(part => part.x).join("\n");
        }
        cueTimes = [...events].sort((a, b) => a - b).map(t => ({
                    t
                }));
        return prepared;
    }

    function wordsFor(line) {
        if (!Array.isArray(line.w) || !line.w.every(word => Number.isFinite(word.t) && word.t >= line.t && typeof word.x === "string"))
            return [];
        if (line.w.map(word => word.x).join("") !== line.x)
            return [];
        return line.w.map(word => ({
                    t: word.t,
                    e: Number.isFinite(word.e) && word.e > word.t ? word.e : word.t,
                    x: word.x
                }));
    }

    function useEmbeddedText(fallback) {
        if (!embeddedText.trim()) {
            state = fallback;
            return;
        }
        plainLines = embeddedText.trim().split("\n");
        synced = false;
        shownSong = requestedSong;
        state = "ready";
    }

    function seekToLine(index) {
        if (!synced || duration <= 0 || !player?.canSeek)
            return false;
        const line = lines[index];
        if (!line || !Number.isFinite(line.t))
            return false;
        player.position = Math.max(0.1, Math.min(line.t, duration * 0.99));
        positionTrusted = true;
        reanchor();
        return true;
    }

    function currentTime() {
        if (!anchorPlaying)
            return anchorPosition;
        return anchorPosition + (Date.now() - anchorWall) * anchorRate / 1000;
    }

    function updatePlaybackClock() {
        const predicted = currentTime();
        const sampled = position + (anchorPlaying ? (Date.now() - positionWall) * anchorRate / 1000 : 0);
        const pendingSeek = !stopped && anchorUpdate.running && Math.abs(sampled - predicted) >= DashMetrics.mediaLyricsPositionTolerance && reachable(sampled);
        anchorUpdate.stop();
        anchorPosition = pendingSeek ? sampled : predicted;
        anchorWall = Date.now();
        anchorPlaying = playing;
        anchorRate = rate;
        resync();
    }

    // Quickshell fetches Position only on track, state and seek events and extrapolates from there,
    // so a player whose Position lagged at that moment stays off until the next seek (#3650).
    function probePosition() {
        const token = serial;
        const name = busName;
        DMSService.dbusGetProperty("session", name, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Position", response => root.receivePosition(token, name, response));
    }

    function receivePosition(token, name, response) {
        if (token !== serial || name !== busName || !playing || response.error)
            return;
        const observed = Number(response.result?.value) / 1e6;
        if (!Number.isFinite(observed) || observed < 0)
            return;
        const wall = Date.now();
        const previous = probe;
        probe = {
            position: observed,
            wall
        };
        if (!previous)
            return;
        const advanced = previous.position + (wall - previous.wall) * rate / 1000;
        if (Math.abs(observed - advanced) > DashMetrics.mediaLyricsPositionProbeDrift)
            return;
        positionTrusted = true;
        if (Math.abs(observed - currentTime()) < DashMetrics.mediaLyricsPositionProbeThreshold)
            return;
        anchorPosition = observed;
        anchorWall = wall;
        anchorPlaying = playing;
        anchorRate = rate;
        resync();
    }

    // pear-desktop floors Position to whole seconds on pause, resume and track events.
    function flooredEcho() {
        const lead = currentTime() - position;
        const whole = Math.abs(position - Math.round(position)) < DashMetrics.mediaLyricsWholeSecondSlack;
        return whole && lead >= 0 && lead < 1 + DashMetrics.mediaLyricsPositionTolerance;
    }

    function scheduleAnchor() {
        positionWall = Date.now();
        if (enabled && synced && !stopped && !anchorUpdate.running)
            anchorUpdate.start();
    }

    // the Position Get quickshell issues on a track change can still answer with the old track (#4025)
    function reachable(observed) {
        return positionTrusted || observed <= currentTime() + DashMetrics.mediaLyricsTrackStartSlack;
    }

    function reanchor(force = true) {
        anchorUpdate.stop();
        const sampled = player?.position ?? 0;
        const observed = reachable(sampled) ? sampled : currentTime();
        if (!force && anchorPlaying && Math.abs(observed - currentTime()) < DashMetrics.mediaLyricsPositionTolerance)
            return false;
        anchorPosition = observed;
        anchorWall = Date.now();
        anchorPlaying = playing;
        anchorRate = rate;
        resync();
        return true;
    }

    function resync() {
        tick.stop();
        if (!enabled || !synced)
            return;
        const at = currentTime();
        sampleTime = at;
        const nextIndex = indexFor(at, lines);
        const focused = [];
        for (let i = 0; i <= nextIndex; i++) {
            if (i === nextIndex || lines[i].parts.some(part => part.t <= at && at < part.e))
                focused.push(i);
        }
        if (focused.join() !== focusedGroups.join())
            focusedGroups = focused;
        activeIndex = nextIndex;
        const parts = lines[activeIndex]?.parts ?? [];
        const lead = parts.find(part => !part.background && part.t <= at);
        const timing = wordTiming(lead ?? lines[activeIndex]?.parts[0], at);
        wordTime = timing.t;
        wordEnd = timing.e;
        const next = cueTimes[indexFor(at, cueTimes) + 1]?.t ?? Infinity;
        wordRevision++;
        if (!playing || rate <= 0 || !Number.isFinite(next))
            return;
        tick.interval = Math.max(1, Math.min(2147483647, (next - at) * 1000 / rate));
        tick.start();
    }

    function wordTiming(part, at) {
        const cues = part?.cues ?? [];
        const index = indexFor(at, cues);
        const word = cues[index];
        if (!word)
            return {
                t: -1,
                e: -1
            };
        return {
            t: word.t,
            e: Math.min(part.e, cues[index + 1]?.t ?? Infinity, word.e)
        };
    }

    function indexFor(at, timeline) {
        let low = 0;
        let high = timeline.length - 1;
        let found = -1;
        while (low <= high) {
            const mid = (low + high) >> 1;
            if (timeline[mid].t <= at) {
                found = mid;
                low = mid + 1;
                continue;
            }
            high = mid - 1;
        }
        return found;
    }

    property Timer tick: Timer {
        onTriggered: {
            if (root.anchorUpdate.running && root.reanchor(false))
                return;
            root.resync();
        }
    }

    property Timer anchorUpdate: Timer {
        interval: 0
        onTriggered: root.reanchor(false)
    }

    property Timer positionProbe: Timer {
        interval: root.positionTrusted ? DashMetrics.mediaLyricsPositionProbeInterval : DashMetrics.mediaLyricsPositionSettleInterval
        repeat: true
        triggeredOnStart: true
        running: root.enabled && root.synced && root.playing && !root.stopped && root.busName !== "" && DMSService.isConnected
        onTriggered: root.probePosition()
    }

    property Timer requestDelay: Timer {
        interval: DashMetrics.mediaLyricsLoadingDelay
        onTriggered: root.request()
    }
}
