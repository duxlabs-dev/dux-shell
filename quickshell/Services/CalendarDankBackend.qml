pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Common as DCommon

Item {
    id: root
    readonly property var log: Log.scoped("CalendarDankBackend")

    property bool enabled: false
    property bool preferred: false
    property int _rediscoverMisses: 0
    readonly property int _rediscoverCap: 20

    property string socketPath: ""
    readonly property bool socketFound: socketPath.length > 0
    property bool connected: false
    readonly property bool binaryExists: launchKind.length > 0
    property bool binaryChecked: false
    // "dcal" for a host install, "flatpak" for a sandboxed one, "" for neither.
    property string launchKind: ""
    property string flatpakId: ""

    property var calendars: []
    property var events: []
    property var eventsByDate: ({})
    property var tasks: []
    property var tasksByDate: ({})
    property var _pendingTaskState: ({})
    property string lastError: ""
    property date focusDate: new Date()
    property var _loadedFrom: null
    property var _loadedTo: null

    property var pendingRequests: ({})
    property int requestCounter: 0

    readonly property var fallbackPalette: ["#7287fd", "#f38ba8", "#a6e3a1", "#fab387", "#cba6f7", "#94e2d5", "#f9e2af", "#89dceb"]

    signal eventsUpdated

    onEnabledChanged: {
        if (enabled) {
            _rediscoverMisses = 0;
            if (!connected)
                discoverProcess.running = true;
            return;
        }
        requestSocket.connected = false;
        subscribeSocket.connected = false;
        socketPath = "";
        connected = false;
    }

    onConnectedChanged: {
        if (!connected)
            _rediscoverMisses = 0;
    }

    Component.onCompleted: {
        if (!enabled)
            return;
        discoverProcess.running = true;
    }

    Process {
        id: binaryCheck
        command: ["sh", "-c", "if command -v dcal >/dev/null 2>&1; then echo dcal; exit 0; fi; command -v flatpak >/dev/null 2>&1 || exit 0; for id in dev.duxlabs.calendar com.danklinux.dankcalendar; do if flatpak info \"$id\" >/dev/null 2>&1; then echo \"flatpak $id\"; exit 0; fi; done"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(" ");
                root.launchKind = parts[0] || "";
                root.flatpakId = parts[1] || "";
                root.binaryChecked = true;
            }
        }
    }

    Process {
        id: discoverProcess
        running: false
        command: ["sh", "-c", "s=\"${DANKCAL_SOCKET:-}\"; if [ -S \"$s\" ]; then echo \"$s\"; exit 0; fi; for f in \"${XDG_RUNTIME_DIR:-/tmp}\"/app/dev.duxlabs.calendar/dankcal-*.sock \"${XDG_RUNTIME_DIR:-/tmp}\"/app/com.danklinux.dankcalendar/dankcal-*.sock; do if [ -S \"$f\" ]; then echo \"$f\"; exit 0; fi; done; for f in \"${XDG_RUNTIME_DIR:-/tmp}\"/dankcal-*.sock /tmp/dankcal-*.sock; do [ -S \"$f\" ] || continue; p=$(basename \"$f\" .sock); p=${p#dankcal-}; if kill -0 \"$p\" 2>/dev/null; then echo \"$f\"; exit 0; fi; done"]

        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim().split('\n')[0] || "";
                if (path.length > 0) {
                    root._applySocketPath(path);
                    return;
                }
                if (!root.connected) {
                    if (root.socketPath !== "")
                        root.log.info("dankcal socket gone, waiting for daemon");
                    requestSocket.connected = false;
                    subscribeSocket.connected = false;
                    root.socketPath = "";
                }
                if (!root.binaryChecked)
                    binaryCheck.running = true;
            }
        }
    }

    Timer {
        id: rediscoverTimer
        interval: 3000
        repeat: true
        running: root.enabled && !root.connected && (root.preferred || (root.binaryChecked && root.binaryExists)) && root._rediscoverMisses < root._rediscoverCap
        onTriggered: {
            root._rediscoverMisses++;
            if (!discoverProcess.running)
                discoverProcess.running = true;
        }
    }

    function launch() {
        switch (launchKind) {
        case "dcal":
            Quickshell.execDetached(["dcal", "run", "-d", "--hidden"]);
            break;
        case "flatpak":
            Quickshell.execDetached(["flatpak", "run", flatpakId, "run", "-d", "--hidden"]);
            break;
        default:
            return;
        }
        if (!enabled || connected)
            return;
        _rediscoverMisses = 0;
        discoverProcess.running = true;
    }

    function _applySocketPath(path) {
        const changed = path !== socketPath;
        if (changed)
            log.info("dankcal socket discovered:", path);
        if (!changed && connected)
            return;
        socketPath = path;
        _reconnect();
    }

    function _reconnect() {
        requestSocket.connected = false;
        subscribeSocket.connected = false;
        Qt.callLater(() => requestSocket.connected = true);
    }

    DCommon.DSocket {
        id: requestSocket
        path: root.socketPath
        connected: false

        onConnectionStateChanged: {
            if (linkUp) {
                root.connected = true;
                subscribeSocket.connected = true;
                root.log.info("connected to dankcal:", root.socketPath);
                root.refreshCalendars();
                root.reloadEvents();
                root.reloadTasks();
                return;
            }
            if (!root.connected && !root.socketFound)
                return;
            root.connected = false;
            root._flushPending();
            requestSocket.connected = false;
            subscribeSocket.connected = false;
            root.log.info("dankcal disconnected, rediscovering");
            if (root.enabled)
                discoverProcess.running = true;
        }

        parser: SplitParser {
            onRead: line => {
                if (!line || line.length === 0)
                    return;
                let response;
                try {
                    response = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root._handleResponse(response);
            }
        }
    }

    DCommon.DSocket {
        id: subscribeSocket
        path: root.socketPath
        connected: false

        onConnectionStateChanged: {
            if (linkUp)
                root._sendSubscribe();
        }

        parser: SplitParser {
            onRead: line => {
                if (!line || line.length === 0)
                    return;
                let event;
                try {
                    event = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root._handleEvent(event);
            }
        }
    }

    Timer {
        id: refreshDebounce
        interval: 400
        repeat: false
        onTriggered: {
            root.refreshCalendars();
            root.reloadEvents();
        }
    }

    Timer {
        id: tasksDebounce
        interval: 400
        repeat: false
        onTriggered: root.reloadTasks()
    }

    function _sendSubscribe() {
        subscribeSocket.send({
            "id": _nextId(),
            "method": "subscribe",
            "params": {
                "topics": ["accounts", "calendars", "events", "tasks", "sync"]
            }
        });
    }

    function _nextId() {
        requestCounter++;
        return Date.now() + requestCounter;
    }

    function _flushPending() {
        const ids = Object.keys(pendingRequests);
        for (const id of ids) {
            const cb = pendingRequests[id];
            delete pendingRequests[id];
            if (cb)
                cb({
                    "error": "disconnected"
                });
        }
    }

    function _handleResponse(response) {
        if (response.event) {
            _handleEvent(response);
            return;
        }
        const id = response.id;
        if (!id)
            return;
        const cb = pendingRequests[id];
        if (cb) {
            delete pendingRequests[id];
            cb(response);
        }
    }

    function _handleEvent(event) {
        switch (event.event) {
        case "accounts":
        case "calendars":
            refreshCalendars();
            refreshDebounce.restart();
            break;
        case "events":
            refreshDebounce.restart();
            break;
        case "tasks":
            tasksDebounce.restart();
            break;
        case "sync":
            refreshDebounce.restart();
            tasksDebounce.restart();
            break;
        }
    }

    function sendRequest(method, params, callback) {
        if (!connected) {
            if (callback)
                callback({
                    "error": "not connected to dankcal socket"
                });
            return;
        }
        const id = _nextId();
        const req = {
            "id": id,
            "method": method
        };
        if (params)
            req.params = params;
        if (callback)
            pendingRequests[id] = callback;
        requestSocket.send(req);
    }

    function refreshCalendars() {
        sendRequest("calendars.list", null, response => {
            if (response.error) {
                lastError = response.error;
                return;
            }
            const list = response.result || [];
            for (let i = 0; i < list.length; i++) {
                if (!list[i].color)
                    list[i].color = fallbackPalette[i % fallbackPalette.length];
            }
            calendars = list;
            _rebuildEventsByDate();
            _rebuildTasksByDate();
        });
    }

    function calendarById(id) {
        for (let i = 0; i < calendars.length; i++) {
            if (calendars[i].id === id)
                return calendars[i];
        }
        return null;
    }

    function writableCalendars() {
        return calendars.filter(c => !c.readOnly);
    }

    function defaultCalendar() {
        const writable = writableCalendars().filter(c => !c.hidden);
        return writable.length > 0 ? writable[0] : null;
    }

    function loadEvents(startDate, endDate) {
        const mid = new Date((startDate.getTime() + endDate.getTime()) / 2);
        focusDate = mid;
        _ensureWindow();
    }

    function _ensureWindow() {
        if (!connected)
            return;
        if (!_loadedFrom || !_loadedTo) {
            reloadEvents();
            return;
        }
        const margin = 14 * 86400000;
        const t = focusDate.getTime();
        if (t < _loadedFrom.getTime() + margin || t > _loadedTo.getTime() - margin)
            reloadEvents();
        else
            _rebuildEventsByDate();
    }

    function reloadEvents() {
        if (!connected)
            return;
        const from = new Date(focusDate.getTime() - 60 * 86400000);
        const to = new Date(focusDate.getTime() + 90 * 86400000);
        sendRequest("events.list", {
            "from": from.toISOString(),
            "to": to.toISOString(),
            "limit": 5000
        }, response => {
            if (response.error) {
                lastError = response.error;
                return;
            }
            _loadedFrom = from;
            _loadedTo = to;
            const raw = (response.result || {}).events || [];
            events = raw.map(e => _normalizeEvent(e));
            _rebuildEventsByDate();
        });
    }

    function _dayBoundary(iso) {
        const d = new Date(iso);
        return new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
    }

    function _normalizeEvent(e) {
        const allDay = !!e.allDay;
        const id = e.id || "";
        if (id.startsWith("task_") || id.startsWith("vtodo_"))
            log.warn("daemon event id collides with task prefix:", id);
        return {
            "id": id,
            "calendarId": e.calendarId || "",
            "title": e.summary || "(untitled)",
            "description": e.description || "",
            "location": e.location || "",
            "url": e.url || "",
            "meetingUrl": e.meetingUrl || "",
            "start": allDay ? _dayBoundary(e.start) : new Date(e.start),
            "end": allDay ? _dayBoundary(e.end) : new Date(e.end),
            "allDay": allDay,
            "status": e.status || "confirmed",
            "recurringId": e.recurringId || "",
            "attendees": e.attendees || [],
            "organizer": e.organizer || null,
            "reminders": e.reminders || []
        };
    }

    function decorateEvent(ev) {
        const cal = calendarById(ev.calendarId);
        const out = Object.assign({}, ev);
        out.color = cal ? cal.color : fallbackPalette[0];
        out.calendar = cal ? cal.name : "";
        out.account = cal ? (cal.accountName || cal.accountId || "") : "";
        out.readOnly = cal ? !!cal.readOnly : false;
        out.isMultiDay = ev.start.toDateString() !== ev.end.toDateString();
        return out;
    }

    function _hiddenCalendarIds() {
        const hidden = {};
        for (let i = 0; i < calendars.length; i++) {
            if (calendars[i].hidden)
                hidden[calendars[i].id] = true;
        }
        return hidden;
    }

    function _clampForDay(ev, cur, endDay) {
        const out = Object.assign({}, ev);
        const dayStart = new Date(cur.getFullYear(), cur.getMonth(), cur.getDate());
        const startDay = new Date(ev.start.getFullYear(), ev.start.getMonth(), ev.start.getDate());
        if (dayStart.getTime() === startDay.getTime()) {
            out.start = new Date(ev.start);
        } else {
            out.start = new Date(dayStart);
            if (!ev.allDay)
                out.start.setHours(0, 0, 0, 0);
        }
        if (dayStart.getTime() === endDay.getTime()) {
            out.end = new Date(ev.end);
        } else {
            out.end = new Date(dayStart);
            if (!ev.allDay)
                out.end.setHours(23, 59, 59, 999);
        }
        return out;
    }

    function _rebuildEventsByDate() {
        const hidden = _hiddenCalendarIds();
        const map = {};
        for (const raw of events) {
            if (raw.status === "cancelled")
                continue;
            if (hidden[raw.calendarId])
                continue;
            const ev = decorateEvent(raw);
            const lastInstant = ev.allDay ? new Date(ev.end.getTime() - 1) : ev.end;
            let cur = new Date(ev.start.getFullYear(), ev.start.getMonth(), ev.start.getDate());
            let endDay = new Date(lastInstant.getFullYear(), lastInstant.getMonth(), lastInstant.getDate());
            if (endDay < cur)
                endDay = new Date(cur);
            while (cur <= endDay) {
                const key = Qt.formatDate(cur, "yyyy-MM-dd");
                if (!map[key])
                    map[key] = [];
                if (!map[key].some(e => e.id === ev.id))
                    map[key].push(_clampForDay(ev, cur, endDay));
                cur.setDate(cur.getDate() + 1);
            }
        }
        eventsByDate = map;
        eventsUpdated();
    }

    function createEvent(fields, callback) {
        sendRequest("events.create", fields, response => {
            if (response.error)
                lastError = response.error;
            else
                reloadEvents();
            if (callback)
                callback(response);
        });
    }

    function updateEvent(id, fields, callback) {
        const params = Object.assign({
            "id": id
        }, fields);
        sendRequest("events.update", params, response => {
            if (response.error)
                lastError = response.error;
            else
                reloadEvents();
            if (callback)
                callback(response);
        });
    }

    function deleteEvent(id, callback) {
        sendRequest("events.delete", {
            "id": id
        }, response => {
            if (response.error)
                lastError = response.error;
            else
                reloadEvents();
            if (callback)
                callback(response);
        });
    }

    function reloadTasks() {
        if (!connected)
            return;
        sendRequest("tasks.list", {
            "includeCompleted": true,
            "limit": 5000
        }, response => {
            if (response.error) {
                lastError = response.error;
                return;
            }
            const raw = (response.result || {}).tasks || [];
            tasks = raw.map(t => _applyPendingState(_normalizeTask(t)));
            _rebuildTasksByDate();
        });
    }

    // A completion toggle is applied optimistically; slow providers can serve a
    // reload that predates the write, so the desired state wins over a
    // disagreeing reload until the daemon confirms it or the hold expires.
    function _applyPendingState(t) {
        const pending = _pendingTaskState[t.id];
        if (!pending)
            return t;
        if (t.completed === pending.completed || Date.now() > pending.expires) {
            delete _pendingTaskState[t.id];
            return t;
        }
        return Object.assign({}, t, {
            "completed": pending.completed,
            "status": pending.completed ? "completed" : "needs_action"
        });
    }

    function _normalizeTask(t) {
        const allDay = !!t.allDay;
        return {
            "id": t.id || "",
            "calendarId": t.calendarId || "",
            "title": t.summary || "(untitled)",
            "description": t.description || "",
            "location": t.location || "",
            "status": t.status || "needs_action",
            "completed": t.status === "completed",
            "priority": t.priority || 0,
            "due": t.due ? (allDay ? _dayBoundary(t.due) : new Date(t.due)) : null,
            "allDay": allDay
        };
    }

    function taskById(id) {
        for (let i = 0; i < tasks.length; i++) {
            if (tasks[i].id === id)
                return tasks[i];
        }
        return null;
    }

    function taskCalendars() {
        return calendars.filter(c => c.holdsTasks && !c.readOnly);
    }

    function defaultTaskCalendar() {
        const writable = taskCalendars().filter(c => !c.hidden);
        if (writable.length === 0)
            return null;
        const preferred = SettingsData.defaultTaskCalendarId;
        if (preferred) {
            for (let i = 0; i < writable.length; i++) {
                if (writable[i].id === preferred)
                    return writable[i];
            }
        }
        return writable[0];
    }

    function _taskAsEvent(t) {
        const cal = calendarById(t.calendarId);
        return {
            "id": "vtodo_" + t.id,
            "title": t.title,
            "description": t.description,
            "location": t.location,
            "url": "",
            "calendar": cal ? cal.name : "",
            "color": cal ? cal.color : fallbackPalette[0],
            "readOnly": cal ? !!cal.readOnly : false,
            "start": t.due,
            "end": t.due,
            "allDay": t.allDay,
            "completed": t.completed,
            "status": t.status,
            "isMultiDay": false
        };
    }

    function _rebuildTasksByDate() {
        const hidden = _hiddenCalendarIds();
        const map = {};
        for (const t of tasks) {
            if (!t.due || t.status === "cancelled" || hidden[t.calendarId])
                continue;
            const key = Qt.formatDate(t.due, "yyyy-MM-dd");
            if (!map[key])
                map[key] = [];
            map[key].push(_taskAsEvent(t));
        }
        tasksByDate = map;
    }

    function _patchTask(id, changes) {
        const next = tasks.slice();
        for (let i = 0; i < next.length; i++) {
            if (next[i].id !== id)
                continue;
            next[i] = Object.assign({}, next[i], changes);
            break;
        }
        tasks = next;
        _rebuildTasksByDate();
    }

    function createTask(fields, callback) {
        sendRequest("tasks.create", fields, response => {
            if (response.error)
                lastError = response.error;
            reloadTasks();
            if (callback)
                callback(response);
        });
    }

    function updateTask(id, fields, callback) {
        const params = Object.assign({
            "id": id
        }, fields);
        sendRequest("tasks.update", params, response => {
            if (response.error)
                lastError = response.error;
            reloadTasks();
            if (callback)
                callback(response);
        });
    }

    function completeTask(id, completed, callback) {
        _pendingTaskState[id] = {
            "completed": completed,
            "expires": Date.now() + 15000
        };
        _patchTask(id, {
            "completed": completed,
            "status": completed ? "completed" : "needs_action"
        });
        sendRequest("tasks.complete", {
            "id": id,
            "completed": completed
        }, response => {
            if (response.error) {
                lastError = response.error;
                delete _pendingTaskState[id];
                reloadTasks();
            }
            if (callback)
                callback(response);
        });
    }

    function deleteTask(id, callback) {
        sendRequest("tasks.delete", {
            "id": id
        }, response => {
            if (response.error)
                lastError = response.error;
            reloadTasks();
            if (callback)
                callback(response);
        });
    }
}
