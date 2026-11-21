.pragma library

// dsearch speaks dankgo ipc: one JSON object per line. Right after the dial the
// server writes {apiVersion, capabilities}; requests carry an integer id and are
// answered out of order; subscription events are {event, data} without an id.

// dankgo ipc cuts the connection when a request line exceeds 1 MiB.
var MAX_LINE_BYTES = 1000000;
var SOCKET_APPS = ["dsearch", "danksearch"];
var TOPIC_MODEL_PROGRESS = "model.progress";
var TOWERS = ["text", "image", "audio"];

function parseVersion(text) {
    var info = {
        valid: false,
        version: "",
        indexVersion: 0,
        supportsTypeFilter: false,
        capabilities: [],
        socket: ""
    };
    var parsed;
    try {
        parsed = JSON.parse(text);
    } catch (e) {
        return info;
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
        return info;
    info.valid = true;
    info.version = typeof parsed.version === "string" ? parsed.version : "";
    info.indexVersion = typeof parsed.index_schema === "number" ? parsed.index_schema : 0;
    info.supportsTypeFilter = info.indexVersion >= 2;
    if (Array.isArray(parsed.capabilities))
        info.capabilities = parsed.capabilities.filter(function (c) {
            return typeof c === "string";
        });
    info.socket = typeof parsed.socket === "string" ? parsed.socket : "";
    return info;
}

// Mirrors dankgo paths.App.SocketDir for a non-root user.
function socketDirectory(env) {
    if (env.flatpakId && env.runtimeDir)
        return env.runtimeDir + "/app/" + env.flatpakId;
    if (env.runtimeDir)
        return env.runtimeDir;
    return env.tmpDir || "/tmp";
}

// Same walk as dankgo ipc.FindRunningSocket (name order, dsearch before danksearch),
// except liveness is the owning pid instead of a dial, so no second connection is opened.
function socketListCommand(dir) {
    var script = 'for app in ' + SOCKET_APPS.join(" ") + '; do for f in "$1"/"$app"-*.sock; do ' + '[ -S "$f" ] || continue; pid=${f##*-}; pid=${pid%.sock}; ' + 'case $pid in ""|*[!0-9]*) continue;; esac; ' + 'kill -0 "$pid" 2>/dev/null && printf "%s\\n" "$f"; done; done';
    return ["sh", "-c", script, "sh", dir];
}

function parseSocketList(stdout) {
    var lines = String(stdout || "").split("\n");
    var out = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.length > 0 && line.charAt(0) === "/" && out.indexOf(line) === -1)
            out.push(line);
    }
    return out;
}

function utf8Length(text) {
    var bytes = 0;
    for (var i = 0; i < text.length; i++) {
        var c = text.charCodeAt(i);
        if (c < 0x80) {
            bytes += 1;
        } else if (c < 0x800) {
            bytes += 2;
        } else if (c >= 0xD800 && c <= 0xDBFF) {
            bytes += 4;
            i++;
        } else {
            bytes += 3;
        }
    }
    return bytes;
}

function encodeRequest(id, method, params) {
    var request = {
        id: id,
        method: method
    };
    if (params)
        request.params = params;
    var line = JSON.stringify(request);
    var size = utf8Length(line);
    if (size > MAX_LINE_BYTES)
        return {
            error: "request too large (" + size + " bytes)",
            bytes: size
        };
    return {
        line: line + "\n",
        bytes: size
    };
}

function decodeLine(line) {
    var message;
    try {
        message = JSON.parse(line);
    } catch (e) {
        return {
            kind: "invalid"
        };
    }
    if (!message || typeof message !== "object" || Array.isArray(message))
        return {
            kind: "invalid"
        };
    if (typeof message.event === "string")
        return {
            kind: "event",
            topic: message.event,
            data: message.data
        };
    if (typeof message.id === "number" && ("result" in message || "error" in message))
        return {
            kind: "response",
            id: message.id,
            result: message.result,
            error: typeof message.error === "string" && message.error.length > 0 ? message.error : ""
        };
    if (Array.isArray(message.capabilities) || typeof message.apiVersion === "number")
        return {
            kind: "hello",
            apiVersion: message.apiVersion || 0,
            capabilities: Array.isArray(message.capabilities) ? message.capabilities : []
        };
    // The server answers an unparsable line with id 0, which json omits.
    if (typeof message.error === "string")
        return {
            kind: "orphanError",
            error: message.error
        };
    return {
        kind: "invalid"
    };
}

function createRequestTable() {
    return {
        next: 0,
        pending: {}
    };
}

function addRequest(table, callback, deadline) {
    table.next++;
    table.pending[table.next] = {
        callback: callback,
        deadline: deadline > 0 ? deadline : 0
    };
    return table.next;
}

function takeRequest(table, id) {
    var entry = table.pending[id];
    if (!entry)
        return null;
    delete table.pending[id];
    return entry;
}

function expiredRequests(table, now) {
    var ids = [];
    for (var id in table.pending) {
        var deadline = table.pending[id].deadline;
        if (deadline > 0 && deadline <= now)
            ids.push(Number(id));
    }
    return ids;
}

function nextDeadline(table) {
    var earliest = 0;
    for (var id in table.pending) {
        var deadline = table.pending[id].deadline;
        if (deadline > 0 && (earliest === 0 || deadline < earliest))
            earliest = deadline;
    }
    return earliest;
}

function drainRequests(table) {
    var entries = [];
    for (var id in table.pending)
        entries.push(table.pending[id]);
    table.pending = {};
    return entries;
}

function pendingCount(table) {
    return Object.keys(table.pending).length;
}

function buildSearchParams(query, params) {
    var out = {
        query: query
    };
    if (!params)
        return out;
    if (params.limit !== undefined)
        out.limit = params.limit;
    if (params.type)
        out.type = params.type;
    if (params.ext)
        out.extension = params.ext;
    if (params.folder)
        out.folder = params.folder;
    if (params.field)
        out.field = params.field;
    if (params.fuzzy)
        out.fuzzy = true;
    if (params.sort)
        out.sort_by = params.sort;
    if (params.desc !== undefined)
        out.sort_desc = !!params.desc;
    if (params.minSize !== undefined)
        out.min_size = params.minSize;
    if (params.maxSize !== undefined)
        out.max_size = params.maxSize;
    if (params.semantic)
        out.semantic = true;
    if (params.collections && params.collections.length > 0)
        out.collections = params.collections;
    if (params.collectionLimit !== undefined)
        out.collection_limit = params.collectionLimit;
    return out;
}

// Directory hits arrive in their own array when the type is "all"; the doc_type
// location of every hit is what the launcher reads, so both lists are tagged.
function normalizeSearchResult(result) {
    var normalized = Object.assign({}, result || {});
    normalized.hits = Array.isArray(normalized.hits) ? normalized.hits : [];
    normalized.directory_hits = Array.isArray(normalized.directory_hits) ? normalized.directory_hits : [];
    var collections = {};
    var raw = Array.isArray(normalized.collections) ? normalized.collections : [];
    for (var i = 0; i < raw.length; i++) {
        if (raw[i] && typeof raw[i].collection === "string")
            collections[raw[i].collection] = Array.isArray(raw[i].hits) ? raw[i].hits : [];
    }
    normalized.collections = collections;
    return normalized;
}

function toNumber(value) {
    return typeof value === "number" && isFinite(value) && value >= 0 ? value : 0;
}

function normalizeTower(raw) {
    var tower = {
        installed: false,
        bytes: 0,
        total: 0,
        partial: false,
        error: ""
    };
    if (raw === true || raw === false) {
        tower.installed = raw;
        return tower;
    }
    if (!raw || typeof raw !== "object")
        return tower;
    tower.installed = raw.installed === true;
    tower.bytes = toNumber(raw.bytes !== undefined ? raw.bytes : (raw.size !== undefined ? raw.size : raw.size_bytes));
    tower.total = toNumber(raw.total);
    tower.partial = raw.partial === true;
    tower.error = typeof raw.error === "string" ? raw.error : (typeof raw.reason === "string" ? raw.reason : "");
    return tower;
}

// dsearch lists the towers as [{tower, installed, bytes, total, partial}]; a keyed object is read too.
function normalizeModel(raw) {
    var model = {
        dir: "",
        error: "",
        towers: {}
    };
    for (var t = 0; t < TOWERS.length; t++)
        model.towers[TOWERS[t]] = normalizeTower(null);
    if (!raw || typeof raw !== "object")
        return model;
    model.dir = typeof raw.dir === "string" ? raw.dir : "";
    model.error = typeof raw.error === "string" ? raw.error : (typeof raw.reason === "string" ? raw.reason : "");
    var source = raw.towers;
    if (Array.isArray(source)) {
        for (var i = 0; i < source.length; i++) {
            var name = source[i] && (source[i].tower || source[i].name || source[i].id);
            if (TOWERS.indexOf(name) !== -1)
                model.towers[name] = normalizeTower(source[i]);
        }
    } else if (source && typeof source === "object") {
        for (var j = 0; j < TOWERS.length; j++) {
            if (source[TOWERS[j]] !== undefined)
                model.towers[TOWERS[j]] = normalizeTower(source[TOWERS[j]]);
        }
    }
    if (Array.isArray(raw.installed)) {
        for (var k = 0; k < raw.installed.length; k++) {
            if (model.towers[raw.installed[k]])
                model.towers[raw.installed[k]].installed = true;
        }
    }
    return model;
}

function normalizeStatus(raw) {
    var status = {
        enabled: false,
        embedderAvailable: false,
        embedderReason: "",
        embedderRunning: false,
        model: normalizeModel(null),
        collections: {},
        indexing: {
            pending: 0,
            done: 0,
            pausedReason: ""
        },
        pending: {},
        download: {
            active: false,
            error: "",
            towers: {}
        }
    };
    if (!raw || typeof raw !== "object")
        return status;
    status.enabled = raw.enabled === true;
    var embedder = raw.embedder || {};
    status.embedderAvailable = embedder.available === true;
    status.embedderReason = typeof embedder.reason === "string" ? embedder.reason : "";
    status.embedderRunning = embedder.running === true;
    status.model = normalizeModel(raw.model);
    if (raw.collections && typeof raw.collections === "object" && !Array.isArray(raw.collections))
        status.collections = raw.collections;
    var indexing = raw.indexing || {};
    status.indexing.pending = toNumber(indexing.pending);
    status.indexing.done = toNumber(indexing.done);
    status.indexing.pausedReason = typeof indexing.paused_reason === "string" ? indexing.paused_reason : "";
    if (raw.pending && typeof raw.pending === "object" && !Array.isArray(raw.pending))
        status.pending = raw.pending;
    var download = raw.download || {};
    status.download.active = download.active === true;
    status.download.error = typeof download.error === "string" ? download.error : "";
    var towers = download.towers && typeof download.towers === "object" ? download.towers : {};
    for (var tower in towers) {
        var progress = normalizeProgress(Object.assign({
            tower: tower
        }, towers[tower]));
        if (progress)
            status.download.towers[tower] = progress;
    }
    return status;
}

var PROGRESS_DONE = ["done", "complete", "completed", "installed", "ready", "finished"];

function progressPhase(state) {
    var s = String(state || "").toLowerCase();
    if (s.indexOf("error") !== -1 || s.indexOf("fail") !== -1)
        return "error";
    if (s.indexOf("cancel") !== -1)
        return "cancelled";
    if (PROGRESS_DONE.indexOf(s) !== -1)
        return "done";
    return "active";
}

// A download ends with a report that names no tower: {state: "finished"} or
// {state: "failed", error}. It comes back with tower "" and phase done/error.
function normalizeProgress(raw) {
    if (!raw || typeof raw !== "object")
        return null;
    if (raw.tower === undefined || raw.tower === "") {
        var endPhase = progressPhase(raw.state);
        if (endPhase !== "done" && endPhase !== "error")
            return null;
        return {
            tower: "",
            bytes: 0,
            total: 0,
            fraction: endPhase === "done" ? 1 : 0,
            state: raw.state,
            phase: endPhase,
            error: typeof raw.error === "string" ? raw.error : ""
        };
    }
    if (TOWERS.indexOf(raw.tower) === -1)
        return null;
    var bytes = toNumber(raw.bytes);
    var total = toNumber(raw.total);
    var phase = progressPhase(raw.state);
    return {
        tower: raw.tower,
        bytes: bytes,
        total: total,
        fraction: total > 0 ? Math.min(1, bytes / total) : (phase === "done" ? 1 : 0),
        state: typeof raw.state === "string" ? raw.state : "",
        phase: phase,
        error: typeof raw.error === "string" ? raw.error : ""
    };
}

// Delays are for redialling after the link dropped; null once the attempts are spent.
function reconnectDelay(attempt) {
    var schedule = [400, 1000, 2500, 6000, 15000];
    return attempt < schedule.length ? schedule[attempt] : null;
}
