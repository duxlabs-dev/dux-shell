pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root

    readonly property var log: Log.scoped("SessionsService")

    property var sessions: []
    property string currentSessionId: ""
    property string currentSeat: ""
    property bool refreshing: false
    property bool loaded: false
    property var _afterLoad: []
    property bool loginctlAvailable: false
    property bool isBSD: Qt.platform.os === "unix"

    signal switchFailed(string sessionId, string username, string message)
    signal switchRequested

    function isCurrent(sessionId) {
        return sessionId === currentSessionId;
    }

    function findByUsername(username) {
        for (let i = 0; i < sessions.length; i++) {
            const s = sessions[i];
            if (s.username === username && !s.current)
                return s;
        }
        return null;
    }

    function findById(sessionId) {
        for (let i = 0; i < sessions.length; i++) {
            if (sessions[i].sessionId === sessionId)
                return sessions[i];
        }
        return null;
    }

    function otherSessions() {
        return sessions.filter(s => !s.current);
    }

    function ensureLoaded(fn) {
        if (loaded) {
            fn();
            return;
        }
        _afterLoad = _afterLoad.concat([fn]);
        refresh();
    }

    function _finishRefresh() {
        refreshing = false;
        loaded = true;
        const queued = _afterLoad;
        _afterLoad = [];
        for (const fn of queued)
            fn();
    }

    function refresh() {
        if (refreshing)
            return;
        refreshing = true;
        Proc.runCommand("sessionsService-detect", ["sh", "-c", "command -v loginctl >/dev/null 2>&1"], (output, exitCode) => {
            root.loginctlAvailable = exitCode === 0;
            if (root.loginctlAvailable) {
                Proc.runCommand("sessionsService-current", ["sh", "-c", "echo \"${XDG_SESSION_ID}:$(loginctl show-session \"${XDG_SESSION_ID}\" -p Seat --value 2>/dev/null)\""], (currentOutput, currentExitCode) => {
                    const trimmed = (currentOutput || "").trim();
                    const parts = trimmed.split(":");
                    root.currentSessionId = parts[0] || "";
                    root.currentSeat = parts[1] || "";
                    _loadSessions();
                }, 0);
                return;
            }
            _loadPortableCurrentSession();
        }, 0);
    }

    function _loadPortableCurrentSession() {
        const script = "uid=$(id -u); user=$(id -un); tty=$(tty 2>/dev/null || true); tty=${tty#/dev/}; sid=${XDG_SESSION_ID:-self}; printf '%s|%s|%s\n' \"$sid\" \"$uid\" \"$user\"; printf '%s\n' \"$tty\"";
        Proc.runCommand("sessionsService-portable-current", ["sh", "-c", script], (output, exitCode) => {
            const lines = (output || "").trim().split("\n");
            const fields = (lines[0] || "self|0|").split("|");
            root.currentSessionId = fields[0] || "self";
            root.currentSeat = "";
            root.sessions = [
                {
                    sessionId: root.currentSessionId,
                    uid: parseInt(fields[1] || "0", 10),
                    username: fields[2] || "",
                    seat: "",
                    tty: lines[1] || "",
                    type: (Quickshell.env("WAYLAND_DISPLAY") || "") !== "" ? "wayland" : "",
                    sessionClass: "user",
                    active: true,
                    state: "active",
                    remote: false,
                    current: true
                }
            ];
            root._finishRefresh();
        }, 0);
    }

    function _loadSessions() {
        if (!root.loginctlAvailable) {
            _loadPortableCurrentSession();
            return;
        }
        const script = "loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}' | while read id; do loginctl show-session \"$id\" -p Id -p User -p Name -p Seat -p TTY -p Type -p Class -p Active -p State -p Remote 2>/dev/null | tr '\\n' '|'; echo; done";
        Proc.runCommand("sessionsService-list", ["sh", "-c", script], (output, exitCode) => {
            const lines = (output || "").trim().split("\n").filter(l => l.length > 0);
            const list = [];
            for (let i = 0; i < lines.length; i++) {
                const fields = {};
                const pairs = lines[i].split("|");
                for (let j = 0; j < pairs.length; j++) {
                    const eq = pairs[j].indexOf("=");
                    if (eq <= 0)
                        continue;
                    fields[pairs[j].substring(0, eq)] = pairs[j].substring(eq + 1);
                }
                if (!fields.Id)
                    continue;
                if (fields.Class !== "user")
                    continue;
                if (fields.State === "closing")
                    continue;
                const sessionId = fields.Id;
                list.push({
                    sessionId: sessionId,
                    uid: parseInt(fields.User || "0", 10),
                    username: fields.Name || "",
                    seat: fields.Seat || "",
                    tty: fields.TTY || "",
                    type: fields.Type || "",
                    sessionClass: fields.Class || "",
                    active: fields.Active === "yes",
                    state: fields.State || "",
                    remote: fields.Remote === "yes",
                    current: sessionId === root.currentSessionId
                });
            }
            list.sort((a, b) => {
                if (a.current !== b.current)
                    return a.current ? -1 : 1;
                if (a.username !== b.username)
                    return a.username.localeCompare(b.username);
                return parseInt(a.sessionId, 10) - parseInt(b.sessionId, 10);
            });
            root.sessions = list;
            root._finishRefresh();
        }, 0);
    }

    function activate(sessionId, callback) {
        if (!sessionId) {
            _fail("", "", I18n.tr("No session selected"), callback);
            return;
        }
        if (sessionId === root.currentSessionId) {
            _fail(sessionId, "", I18n.tr("Already on that session"), callback);
            return;
        }
        const session = findById(sessionId);
        const username = session ? session.username : "";
        _spawnActivate(sessionId, username, callback);
    }

    function switchToUser(target, callback) {
        if (!target) {
            _fail("", "", I18n.tr("No user specified"), callback);
            return;
        }
        let session = findById(target);
        if (!session)
            session = findByUsername(target);
        if (!session) {
            _fail("", target, I18n.tr("No active session found for %1", "switch user error, %1 is a session id or username").arg(target), callback);
            return;
        }
        if (session.current) {
            _fail(session.sessionId, session.username, I18n.tr("Already on that session"), callback);
            return;
        }
        _spawnActivate(session.sessionId, session.username, callback);
    }

    function _fail(sessionId, username, message, callback) {
        log.warn("switch failed:", sessionId, username, message);
        root.switchFailed(sessionId, username, message);
        if (typeof callback === "function") {
            try {
                callback(false, message);
            } catch (e) {
                log.warn("SessionsService callback error:", e);
            }
        }
    }

    Component {
        id: activateComp
        Process {
            id: activateProc
            property string targetSession: ""
            property string targetUsername: ""
            property var cb: null
            property string capturedErr: ""
            running: false
            stdout: StdioCollector {}
            stderr: StdioCollector {
                onStreamFinished: activateProc.capturedErr = text || ""
            }
            onExited: exitCode => {
                const svc = root;
                const sessionId = activateProc.targetSession;
                const username = activateProc.targetUsername;
                const cb = activateProc.cb;
                const err = (activateProc.capturedErr || "").trim();
                Qt.callLater(() => activateProc.destroy());

                if (exitCode !== 0) {
                    svc._fail(sessionId, username, err || I18n.tr("loginctl activate failed (exit %1)", "switch user error, loginctl is a command, %1 is exit code").arg(exitCode), cb);
                    return;
                }
                if (typeof cb === "function") {
                    try {
                        cb(true, "");
                    } catch (e) {
                        svc.log.warn("activate cb error:", e);
                    }
                }
            }
        }
    }

    function _spawnActivate(sessionId, username, callback) {
        if (!root.loginctlAvailable) {
            _fail(sessionId, username, I18n.tr("Session switching requires loginctl/elogind"), callback);
            return;
        }
        const proc = activateComp.createObject(root, {
            command: ["loginctl", "activate", sessionId],
            targetSession: sessionId,
            targetUsername: username,
            cb: callback
        });
        proc.running = true;
    }

    IpcHandler {
        target: "sessions"

        function list(): string {
            if (!root.loaded)
                root.refresh();
            const lines = [];
            for (let i = 0; i < root.sessions.length; i++) {
                const s = root.sessions[i];
                lines.push([s.sessionId, s.username, s.seat || "-", s.tty || "-", s.type || "-", s.current ? "*current*" : ""].join("\t"));
            }
            return lines.join("\n");
        }

        function refresh(): string {
            root.refresh();
            return "ok";
        }

        function open(): string {
            root.refresh();
            root.switchRequested();
            return "ok";
        }

        function activate(sessionId: string): string {
            if (!sessionId)
                return "ERROR: missing session id";
            root.ensureLoaded(() => root.activate(sessionId, null));
            return "ok";
        }

        function switchTo(target: string): string {
            if (!target)
                return "ERROR: missing target (username or session id)";
            root.ensureLoaded(() => root.switchToUser(target, null));
            return "ok";
        }
    }
}
