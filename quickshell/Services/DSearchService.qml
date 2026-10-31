pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Common as DCommon
import "DSearchProtocol.js" as Protocol
import "DSearchCollections.js" as Collections
import "DSearchConfig.js" as Config

Singleton {
    id: root
    readonly property var log: Log.scoped("DSearchService")

    // Launcher and settings page hold the link while they are open (Ref).
    property int refCount: 0

    property bool dsearchAvailable: false
    property int indexVersion: 0
    property bool supportsTypeFilter: false
    property bool versionChecked: false
    property var capabilities: []
    readonly property bool semanticSupported: capabilities.indexOf("semantic") !== -1
    readonly property bool collectionsSupported: capabilities.indexOf("collections") !== -1
    property bool _checked: false

    // Last semantic.status, normalized. Only trusted once statusKnown.
    property var semanticState: Protocol.normalizeStatus(null)
    property bool statusKnown: false
    readonly property bool semanticEnabled: semanticSupported && statusKnown && semanticState.enabled
    readonly property bool semanticReady: semanticEnabled && semanticState.embedderAvailable
    // tower -> last model.progress report of the download that is running or just ended
    property var modelProgress: ({})
    property string downloadError: ""
    readonly property bool downloading: Object.keys(modelProgress).some(tower => modelProgress[tower].phase === "active") || (statusKnown && semanticState.download.active)

    readonly property string collectionActions: Collections.COLLECTION_ACTIONS
    readonly property string collectionSettings: Collections.COLLECTION_SETTINGS
    readonly property string collectionApps: Collections.COLLECTION_APPS

    readonly property bool linked: link.linkUp
    // True once a connection attempt has found no dsearch to talk to.
    property bool unreachable: false
    readonly property int _actionRevision: ActionCatalogService.revision

    signal searchResultsReceived(var results)
    signal statsReceived(var stats)
    signal errorOccurred(string error)
    signal modelProgressReceived(var progress)

    // Wire state
    property string _versionSocket: ""
    property double _versionAt: 0
    property var _afterCheck: []
    property var _candidates: []
    property int _candidateIndex: 0
    property bool _connecting: false
    property bool _reconnecting: false
    property bool _intentionalClose: false
    property int _reconnectAttempt: 0
    property double _unavailableUntil: 0
    property var _outbox: []
    property var _table: Protocol.createRequestTable()
    property string _instance: ""

    // Collection registration
    property bool _dirty: true
    property var _registered: ({})
    property var _inflight: ({})

    Process {
        id: checkProcess
        command: ["sh", "-c", "command -v dsearch"]
        running: false

        stdout: SplitParser {
            onRead: line => {
                if (line && line.trim().length > 0) {
                    root.dsearchAvailable = true;
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.dsearchAvailable = false;
                root._afterCheck = [];
            } else {
                root._checkVersion();
            }
        }
    }

    function _checkVersion() {
        Proc.runCommand("dsearch-version", ["dsearch", "version", "--json"], (stdout, exitCode) => {
            root.versionChecked = true;
            const info = exitCode === 0 ? Protocol.parseVersion(stdout) : Protocol.parseVersion("");
            if (info.valid) {
                root.indexVersion = info.indexVersion;
                root.supportsTypeFilter = info.supportsTypeFilter;
                root.capabilities = info.capabilities;
            }
            root._versionSocket = info.socket;
            root._versionAt = Date.now();
            const dialing = root._connecting;
            const queued = root._afterCheck;
            root._afterCheck = [];
            queued.forEach(fn => fn());
            if (dialing)
                root._discoverSocket();
        });
    }

    function ensureChecked() {
        if (_checked)
            return;
        rediscover();
    }

    function rediscover() {
        _checked = true;
        checkProcess.running = true;
    }

    function _whenChecked(fn) {
        ensureChecked();
        if (versionChecked)
            fn();
        else
            _afterCheck.push(fn);
    }

    // --- link -------------------------------------------------------------

    DCommon.DSocket {
        id: link
        connected: false

        parser: SplitParser {
            onRead: line => root._onLine(line)
        }

        onConnectionStateChanged: {
            if (linkUp) {
                root._onLinkUp();
                return;
            }
            // The socket cannot be torn down from inside its own handler.
            Qt.callLater(root._onLinkLost);
        }
    }

    Timer {
        id: watchdog
        interval: 2000
        onTriggered: {
            if (link.linkUp)
                return;
            link.connected = false;
            root._dial(root._candidateIndex + 1);
        }
    }

    Timer {
        id: reconnectTimer
        onTriggered: {
            root._versionAt = 0;
            root._ensureLink();
        }
    }

    // Idle close and request timeouts are one-shot: nothing ticks while the shell is quiet.
    Timer {
        id: idleTimer
        interval: 30000
        onTriggered: {
            if (root._linkWanted()) {
                restart();
                return;
            }
            root._closeLink();
        }
    }

    Timer {
        id: timeoutTimer
        onTriggered: {
            const now = Date.now();
            Protocol.expiredRequests(root._table, now).forEach(id => root._resolve(id, {
                    "error": "request timed out",
                    "code": "timeout"
                }));
            root._armTimeout();
        }
    }

    Timer {
        id: registerTimer
        interval: 2000
        onTriggered: root._registerNow()
    }

    onRefCountChanged: {
        if (refCount > 0) {
            idleTimer.stop();
            _whenChecked(() => root._ensureLink());
            return;
        }
        _touch();
    }

    function _linkWanted() {
        return refCount > 0 || _outbox.length > 0 || Protocol.pendingCount(_table) > 0 || downloading || registerTimer.running;
    }

    function _touch() {
        if (link.linkUp && !_linkWanted())
            idleTimer.restart();
    }

    function _ensureLink() {
        if (link.linkUp || _connecting || !dsearchAvailable || !versionChecked)
            return;
        if (Date.now() < _unavailableUntil)
            return;
        _connecting = true;
        _intentionalClose = false;
        // A pid-named socket goes stale when dsearch restarts, so the path is read again.
        if (Date.now() - _versionAt > 5000) {
            _checkVersion();
            return;
        }
        _discoverSocket();
    }

    function _discoverSocket() {
        if (_versionSocket) {
            _candidates = [_versionSocket];
            _dial(0);
            return;
        }
        const dir = Protocol.socketDirectory({
            "runtimeDir": Quickshell.env("XDG_RUNTIME_DIR"),
            "flatpakId": Quickshell.env("FLATPAK_ID"),
            "tmpDir": Quickshell.env("TMPDIR")
        });
        Proc.runCommand("dsearch-sockets", Protocol.socketListCommand(dir), (stdout, exitCode) => {
            root._candidates = Protocol.parseSocketList(stdout);
            root._dial(0);
        }, 0, 3000);
    }

    function _dial(index) {
        if (index >= _candidates.length) {
            _connectFailed("dsearch is not running");
            return;
        }
        _candidateIndex = index;
        link.connected = false;
        link.path = _candidates[index];
        link.connected = true;
        watchdog.restart();
    }

    function _connectFailed(reason) {
        _connecting = false;
        link.connected = false;
        if (_reconnecting) {
            _scheduleReconnect(reason);
            return;
        }
        _unavailableUntil = Date.now() + 3000;
        unreachable = true;
        _failPending(reason);
    }

    function _scheduleReconnect(reason) {
        if (!_linkWanted()) {
            _reconnecting = false;
            _failPending(reason);
            return;
        }
        const delay = Protocol.reconnectDelay(_reconnectAttempt++);
        if (delay === null) {
            _reconnecting = false;
            _unavailableUntil = Date.now() + 30000;
            unreachable = true;
            _failPending(reason);
            return;
        }
        reconnectTimer.interval = delay;
        reconnectTimer.restart();
    }

    function _onLinkUp() {
        watchdog.stop();
        _connecting = false;
        _reconnecting = false;
        _reconnectAttempt = 0;
        _unavailableUntil = 0;
        unreachable = false;
        _adoptInstance(link.path);
        const queued = _outbox;
        _outbox = [];
        queued.forEach(line => link.send(line));
        if (semanticSupported) {
            _send("subscribe", {
                "topics": [Protocol.TOPIC_MODEL_PROGRESS]
            }, null, 4000);
            semanticStatus(null);
        }
        _touch();
    }

    // A dsearch that started since (new pid, new socket) has not been told the catalogs.
    function _adoptInstance(path) {
        if (_instance === path)
            return;
        _instance = path;
        _registered = ({});
        _inflight = ({});
        _dirty = true;
    }

    function _onLinkLost() {
        if (link.linkUp || _intentionalClose)
            return;
        _connecting = false;
        modelProgress = ({});
        _failPending("connection to dsearch lost");
        _reconnecting = true;
        _reconnectAttempt = 0;
        _scheduleReconnect("connection to dsearch lost");
    }

    function _closeLink() {
        _intentionalClose = true;
        watchdog.stop();
        reconnectTimer.stop();
        link.connected = false;
    }

    function _failPending(reason) {
        const entries = Protocol.drainRequests(_table);
        _outbox = [];
        timeoutTimer.stop();
        entries.forEach(entry => {
            if (entry.callback)
                root._callSafe(entry.callback, {
                    "error": reason,
                    "code": "unavailable"
                });
        });
    }

    // --- requests ---------------------------------------------------------

    function _callSafe(callback, response) {
        try {
            callback(response);
        } catch (e) {
            log.warn("dsearch callback failed:", e);
        }
    }

    function _armTimeout() {
        const deadline = Protocol.nextDeadline(_table);
        if (deadline === 0) {
            timeoutTimer.stop();
            return;
        }
        timeoutTimer.interval = Math.max(10, deadline - Date.now());
        timeoutTimer.restart();
    }

    function _resolve(id, response) {
        const entry = Protocol.takeRequest(_table, id);
        if (!entry)
            return;
        _armTimeout();
        if (entry.callback)
            _callSafe(entry.callback, response);
        _touch();
    }

    // Callback receives {result} or {error, code}: code is "unavailable" when no link could be
    // made, "timeout", "too_large" or "server". timeoutMs 0 waits for as long as the link lives.
    function _send(method, params, callback, timeoutMs) {
        const unavailable = !dsearchAvailable ? "dsearch not available" : (!link.linkUp && Date.now() < _unavailableUntil ? "dsearch is not running" : "");
        if (unavailable) {
            if (callback)
                _callSafe(callback, {
                    "error": unavailable,
                    "code": "unavailable"
                });
            return;
        }
        const id = Protocol.addRequest(_table, callback, timeoutMs > 0 ? Date.now() + timeoutMs : 0);
        const encoded = Protocol.encodeRequest(id, method, params);
        if (encoded.error) {
            _resolve(id, {
                "error": encoded.error,
                "code": "too_large"
            });
            return;
        }
        idleTimer.stop();
        if (link.linkUp) {
            link.send(encoded.line);
        } else {
            _outbox.push(encoded.line);
            _whenChecked(() => root._ensureLink());
        }
        _armTimeout();
    }

    function _onLine(line) {
        if (!line || line.length === 0)
            return;
        const message = Protocol.decodeLine(line);
        switch (message.kind) {
        case "response":
            _resolve(message.id, message.error ? {
                    "error": message.error,
                    "code": "server"
                } : {
                    "result": message.result
                });
            break;
        case "event":
            _onEvent(message.topic, message.data);
            break;
        case "hello":
            break;
        case "orphanError":
            log.warn("dsearch rejected a request line:", message.error);
            break;
        default:
            log.warn("Unreadable dsearch line:", line.substring(0, 100));
        }
    }

    function _onEvent(topic, data) {
        if (topic !== Protocol.TOPIC_MODEL_PROGRESS)
            return;
        const progress = Protocol.normalizeProgress(data);
        if (!progress)
            return;
        modelProgressReceived(progress);
        if (progress.tower === "") {
            // The whole download ended; the status says what is installed now.
            downloadError = progress.phase === "error" ? (progress.error || "download failed") : "";
            modelProgress = ({});
            semanticStatus(null);
            _touch();
            return;
        }
        modelProgress = Object.assign({}, modelProgress, {
            [progress.tower]: progress
        });
        if (progress.phase === "error")
            downloadError = progress.error;
        if (progress.phase !== "active")
            semanticStatus(null);
    }

    // --- public API -------------------------------------------------------

    function search(query, params, callback) {
        if (!query || query.length === 0) {
            if (callback) {
                callback({
                    "error": "query is required"
                });
            }
            return;
        }

        ensureChecked();
        if (!dsearchAvailable) {
            if (callback) {
                callback({
                    "error": "dsearch not available"
                });
            }
            return;
        }

        // dsearch refuses collections without semantic.
        const wire = Object.assign({}, params);
        if (!semanticReady || !wire.semantic) {
            delete wire.semantic;
            delete wire.collections;
            delete wire.collectionLimit;
        }

        _send("search", Protocol.buildSearchParams(query, wire), response => {
            // Without a running service the CLI still searches the index file itself.
            if (response.code === "unavailable") {
                root._searchViaCli(query, params, callback);
                return;
            }
            if (response.error) {
                root._finishSearch(response.code === "timeout" ? "search timed out" : "search failed", null, response.error, callback);
                return;
            }
            root._finishSearch("", response.result, "", callback);
        }, 5000);
    }

    function _finishSearch(error, rawResult, detail, callback) {
        if (error) {
            log.warn("search:", detail);
            errorOccurred(error);
            if (callback) {
                callback({
                    "error": error
                });
            }
            return;
        }
        const result = Protocol.normalizeSearchResult(rawResult);
        // The embedder went away since the status was read (helper crashed, model removed).
        if (semanticReady && result.semantic && result.semantic.available === false)
            semanticStatus(null);
        searchResultsReceived(result);
        if (callback) {
            callback({
                "result": result
            });
        }
    }

    function _searchViaCli(query, params, callback) {
        const args = ["dsearch", "search", query, "--json"];
        if (params) {
            if (params.limit !== undefined)
                args.push("-n", String(params.limit));
            if (params.type)
                args.push("-t", params.type);
            if (params.ext)
                args.push("-e", params.ext);
            if (params.folder)
                args.push("--folder", params.folder);
            if (params.field)
                args.push("-f", params.field);
            if (params.fuzzy)
                args.push("--fuzzy");
            if (params.sort)
                args.push("--sort", params.sort);
            if (params.desc !== undefined)
                args.push("--desc=" + (params.desc ? "true" : "false"));
            if (params.minSize !== undefined)
                args.push("--min-size", String(params.minSize));
            if (params.maxSize !== undefined)
                args.push("--max-size", String(params.maxSize));
        }

        Proc.runCommand("dsearch-search-" + (params?.type || "all"), args, (stdout, exitCode) => {
            if (exitCode === 124) {
                root._finishSearch("search timed out", null, "cli timed out", callback);
                return;
            }
            if (exitCode !== 0) {
                root._finishSearch("search failed", null, "cli exit " + exitCode, callback);
                return;
            }
            let parsed = null;
            try {
                parsed = JSON.parse(stdout);
            } catch (e) {
                root._finishSearch("failed to parse search response", null, String(e), callback);
                return;
            }
            root._finishSearch("", parsed, "", callback);
        }, 100, 5000);
    }

    function semanticStatus(callback) {
        if (!semanticSupported) {
            if (callback)
                callback({
                    "error": "semantic search not supported"
                });
            return;
        }
        _send("semantic.status", null, response => {
            if (!response.error)
                root._applyStatus(response.result);
            else
                log.warn("semantic.status:", response.error);
            if (callback)
                callback(response);
        }, 4000);
    }

    function _applyStatus(raw) {
        semanticState = Protocol.normalizeStatus(raw);
        statusKnown = true;
        // The status is the truth about a download; a report that never got its end
        // (dsearch restarted meanwhile) must not hold the link open.
        modelProgress = semanticState.download.active ? semanticState.download.towers : ({});
        if (!semanticState.download.active && semanticState.download.error)
            downloadError = semanticState.download.error;
        if (!semanticEnabled || !collectionsSupported)
            return;
        // A collection dsearch no longer lists (data dir wiped) is sent again.
        [collectionActions, collectionSettings, collectionApps].forEach(name => {
            if (_registered[name] && semanticState.collections[name] === undefined) {
                delete _registered[name];
                _dirty = true;
            }
        });
        if (_dirty)
            scheduleRegistration();
    }

    function refreshSemanticStatus() {
        _whenChecked(() => root.semanticStatus(null));
    }

    // Loads the towers ahead of the first query; the launcher calls it when it opens.
    function warm(modalities) {
        _whenChecked(() => {
            if (!root.semanticSupported)
                return;
            root.semanticStatus(() => {
                if (!root.semanticReady)
                    return;
                root._send("semantic.warm", modalities ? {
                        "modalities": modalities
                    } : null, response => {
                    if (response.error)
                        root.log.warn("semantic.warm:", response.error);
                }, 15000);
            });
        });
    }

    function setCollection(name, items, callback) {
        _send("collections.set", {
            "collection": name,
            "items": items
        }, callback, 30000);
    }

    // dsearch answers at once and reports through model.progress; the link is held
    // while the status says a download is running.
    function downloadModel(towers, callback) {
        downloadError = "";
        _send("model.download", {
            "towers": towers
        }, response => {
            if (response.error) {
                root.log.warn("model.download:", response.error);
                root.downloadError = response.error;
            }
            root.semanticStatus(null);
            if (callback)
                callback(response);
        }, 10000);
    }

    function removeModel(towers, callback) {
        downloadError = "";
        _send("model.remove", {
            "towers": towers
        }, response => {
            if (response.error) {
                root.log.warn("model.remove:", response.error);
                root.downloadError = response.error;
            }
            root.semanticStatus(null);
            if (callback)
                callback(response);
        }, 30000);
    }

    // --- turning semantic search on or off ------------------------------------
    // dsearch reads [semantic].enabled at start: the key is edited in its config.toml and
    // the systemd user unit dsearch.service is restarted.

    property bool configEnabled: false
    property bool restarting: false
    // "", "inline" (config not editable here), "write" or "restart" (dsearch has to be restarted by hand)
    property string configError: ""
    readonly property string configPath: Config.configPath({
        "configHome": Quickshell.env("XDG_CONFIG_HOME"),
        "home": Quickshell.env("HOME")
    })

    FileView {
        id: configFile
        blockLoading: true
        blockWrites: true
        printErrors: false
        watchChanges: false
    }

    function _readConfig() {
        configFile.path = configPath;
        try {
            return configFile.text();
        } catch (e) {
            return "";
        }
    }

    function refreshConfig() {
        configEnabled = Config.readSemanticEnabled(_readConfig());
    }

    function setSemanticEnabled(enabled) {
        if (restarting)
            return;
        configError = "";
        const edited = Config.setSemanticEnabled(_readConfig(), enabled);
        if (edited.error) {
            configError = "inline";
            return;
        }
        configFile.setText(edited.text);
        refreshConfig();
        if (configEnabled !== enabled) {
            configError = "write";
            return;
        }
        restarting = true;
        Proc.runCommand("dsearch-restart", ["systemctl", "--user", "restart", "dsearch.service"], (stdout, exitCode) => {
            root.restarting = false;
            if (exitCode !== 0) {
                root.configError = "restart";
                return;
            }
            root._versionAt = 0;
            root.statusKnown = false;
            root.refreshSemanticStatus();
        }, 0, 30000);
    }

    // --- collection registration -----------------------------------------

    // Settings hit id -> the untranslated index entry; the launcher translates what it shows.
    property var _settingsById: null

    function settingEntry(id) {
        if (!_settingsById) {
            const byId = {};
            SettingsSearchService.settingsIndex.forEach(entry => {
                if (entry && !entry.runtimeType && entry.section)
                    byId[Collections.settingId(entry)] = entry;
            });
            _settingsById = byId;
        }
        return _settingsById[id] || null;
    }

    Connections {
        target: AppSearchService
        function onCacheVersionChanged() {
            root._catalogChanged();
        }
    }

    Connections {
        target: SettingsSearchService
        function onIndexLoadedChanged() {
            root._catalogChanged();
        }
        function onSettingsIndexChanged() {
            root._settingsById = null;
        }
    }

    on_ActionRevisionChanged: _catalogChanged()

    function _catalogChanged() {
        _dirty = true;
        scheduleRegistration();
    }

    // Debounced; nothing is sent before the first connection has said whether semantic search is on.
    function scheduleRegistration() {
        if (!versionChecked || !collectionsSupported || !statusKnown || !semanticEnabled)
            return;
        registerTimer.restart();
    }

    function _collectionSources() {
        const sources = [
            {
                "name": collectionActions,
                "items": ActionCatalogService.indexItems()
            }
        ];
        if (SettingsSearchService.indexLoaded) {
            sources.push({
                "name": collectionSettings,
                "items": Collections.settingsItems(SettingsSearchService.settingsIndex)
            });
        }
        sources.push({
            "name": collectionApps,
            "items": Collections.appItems(AppSearchService.getVisibleApplications().map(app => ({
                        "id": app.id,
                        "name": app.name,
                        "genericName": app.genericName,
                        "comment": app.comment,
                        "keywords": Array.from(app.keywords || []),
                        "categories": Array.from(app.categories || [])
                    })))
        });
        return sources;
    }

    // An unchanged catalog costs one signature and no connection.
    function _registerNow() {
        if (!semanticEnabled || !collectionsSupported)
            return;
        const instance = _instance;
        const todo = _collectionSources().filter(source => source.items.length > 0).map(source => ({
                    "name": source.name,
                    "items": source.items,
                    "signature": Collections.signature(source.items)
                })).filter(source => _registered[source.name] !== source.signature && _inflight[source.name] !== source.signature);
        _dirty = false;
        todo.forEach(source => {
            root._inflight[source.name] = source.signature;
            root.setCollection(source.name, source.items, response => {
                delete root._inflight[source.name];
                if (response.error) {
                    root.log.warn("collections.set", source.name + ":", response.error);
                    root._dirty = true;
                    return;
                }
                if (root._instance === instance)
                    root._registered[source.name] = source.signature;
            });
        });
    }
}
