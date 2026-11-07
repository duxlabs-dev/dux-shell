pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root

    readonly property var log: Log.scoped("UsersService")

    // Qt.platform.os is "unix" on the BSDs; user management goes through pw(8)
    readonly property bool isBSD: Qt.platform.os === "unix"

    property var users: []
    property string adminGroup: "wheel"
    property string greeterGroup: "greeter"
    property var adminMembers: []
    property var greeterMembers: []
    property bool refreshing: false

    signal operationCompleted(string op, string username, bool success, string message)

    readonly property var _usernameRegex: /^[a-z_][a-z0-9_-]{0,30}\$?$/

    function isValidUsername(name) {
        if (typeof name !== "string")
            return false;
        return _usernameRegex.test(name);
    }

    function userExists(name) {
        for (let i = 0; i < users.length; i++) {
            if (users[i].username === name)
                return true;
        }
        return false;
    }

    function _findUser(name) {
        for (let i = 0; i < users.length; i++) {
            if (users[i].username === name)
                return users[i];
        }
        return null;
    }

    function canDelete(name) {
        const u = _findUser(name);
        if (!u)
            return false;
        if (u.isAdmin && adminMembers.length <= 1)
            return false;
        return true;
    }

    function refresh() {
        if (refreshing)
            return;
        refreshing = true;
        _detectAdminGroup();
    }

    function _detectAdminGroup() {
        Proc.runCommand("usersService-detectGroup", ["sh", "-c", "getent group wheel >/dev/null && echo wheel || (getent group sudo >/dev/null && echo sudo || echo wheel)"], (output, exitCode) => {
            const detected = (output || "").trim() || "wheel";
            root.adminGroup = detected;
            _loadAdminMembers();
        }, 0);
    }

    function _loadAdminMembers() {
        Proc.runCommand("usersService-adminMembers", ["sh", "-c", "getent group " + root.adminGroup + " | awk -F: '{print $4}'"], (output, exitCode) => {
            const members = (output || "").trim().split(",").map(s => s.trim()).filter(s => s.length > 0);
            root.adminMembers = members;
            _detectGreeterGroup();
        }, 0);
    }

    function _detectGreeterGroup() {
        Proc.runCommand("usersService-detectGreeterGroup", ["sh", "-c", "getent group greeter >/dev/null 2>&1 && echo greeter || (getent group greetd >/dev/null 2>&1 && echo greetd || (getent group _greeter >/dev/null 2>&1 && echo _greeter || echo greeter))"], (output, exitCode) => {
            root.greeterGroup = (output || "").trim() || "greeter";
            _loadGreeterMembers();
        }, 0);
    }

    function _loadGreeterMembers() {
        Proc.runCommand("usersService-greeterMembers", ["sh", "-c", "getent group " + root.greeterGroup + " 2>/dev/null | awk -F: '{print $4}'"], (output, exitCode) => {
            const members = (output || "").trim().split(",").map(s => s.trim()).filter(s => s.length > 0);
            root.greeterMembers = members;
            _loadUsers();
        }, 0);
    }

    function _loadUsers() {
        Proc.runCommand("usersService-loadUsers", ["sh", "-c", "getent passwd | awk -F: '$3>=1000 && $3<60000 && $1!=\"nobody\" && $7!~/(nologin|false)$/ && $6!=\"/var/empty\" {print $1\":\"$3\":\"$5\":\"$6\":\"$7}'"], (output, exitCode) => {
            const lines = (output || "").trim().split("\n").filter(l => l.length > 0);
            const list = [];
            const adminSet = {};
            const greeterSet = {};
            for (let i = 0; i < root.adminMembers.length; i++)
                adminSet[root.adminMembers[i]] = true;
            for (let i = 0; i < root.greeterMembers.length; i++)
                greeterSet[root.greeterMembers[i]] = true;

            for (let i = 0; i < lines.length; i++) {
                const parts = lines[i].split(":");
                if (parts.length < 5)
                    continue;
                const username = parts[0];
                list.push({
                    username,
                    uid: parseInt(parts[1], 10),
                    gecos: (parts[2] || "").split(",")[0],
                    home: parts[3] || "",
                    shell: parts[4] || "",
                    isAdmin: adminSet[username] === true,
                    isGreeter: greeterSet[username] === true
                });
            }
            list.sort((a, b) => a.username.localeCompare(b.username));
            root.users = list;
            root.refreshing = false;
        }, 0);
    }

    function createUser(username, password, addToAdmin, addToGreeter, callback) {
        if (!isValidUsername(username)) {
            _emit("create", username, false, I18n.tr("Invalid username"), callback);
            return;
        }
        if (!password || password.length < 1) {
            _emit("create", username, false, I18n.tr("Password cannot be empty"), callback);
            return;
        }
        if (userExists(username)) {
            _emit("create", username, false, I18n.tr("User already exists"), callback);
            return;
        }
        _runUseradd(username, password, addToAdmin === true, addToGreeter === true, callback);
    }

    function setPassword(username, newPassword, callback) {
        if (!isValidUsername(username) || !userExists(username)) {
            _emit("passwd", username, false, I18n.tr("User not found"), callback);
            return;
        }
        if (!newPassword || newPassword.length < 1) {
            _emit("passwd", username, false, I18n.tr("Password cannot be empty"), callback);
            return;
        }
        _runChpasswd(username, newPassword, "passwd", callback);
    }

    function deleteUser(username, callback) {
        if (!userExists(username)) {
            _emit("delete", username, false, I18n.tr("User not found"), callback);
            return;
        }
        if (!canDelete(username)) {
            _emit("delete", username, false, I18n.tr("Cannot delete the only administrator"), callback);
            return;
        }
        _runUserdel(username, callback);
    }

    function setAdmin(username, makeAdmin, callback) {
        if (!userExists(username)) {
            _emit("admin", username, false, I18n.tr("User not found"), callback);
            return;
        }
        if (!makeAdmin) {
            const u = _findUser(username);
            if (u && u.isAdmin && root.adminMembers.length <= 1) {
                _emit("admin", username, false, I18n.tr("Cannot remove the only administrator"), callback);
                return;
            }
        }
        _runAdminToggle(username, makeAdmin === true, callback);
    }

    function setGreeterAccess(username, enable, callback) {
        if (!userExists(username)) {
            _emit("greeter", username, false, I18n.tr("User not found"), callback);
            return;
        }
        _runGreeterToggle(username, enable === true, callback);
    }

    function _finishCreateUser(targetUser, addAdmin, addGreeter, outerCb) {
        function finish(success, message) {
            root._emit("create", targetUser, success, message, outerCb);
        }

        function maybeGreeter(onDone) {
            if (addGreeter) {
                root._runGreeterToggle(targetUser, true, (greeterOk, greeterMsg) => {
                    if (greeterOk)
                        onDone();
                    else
                        finish(false, greeterMsg);
                });
            } else {
                onDone();
            }
        }

        function createMessage() {
            if (addAdmin && addGreeter)
                return I18n.tr("User created with administrator and greeter login access");
            if (addAdmin)
                return I18n.tr("User created with administrator privileges");
            if (addGreeter)
                return I18n.tr("User created with greeter login access");
            return I18n.tr("User created");
        }

        if (addAdmin) {
            root._runAdminToggle(targetUser, true, (adminOk, adminMsg) => {
                if (!adminOk) {
                    finish(false, adminMsg);
                    return;
                }
                maybeGreeter(() => finish(true, createMessage()));
            });
        } else {
            maybeGreeter(() => finish(true, createMessage()));
        }
    }

    function _emit(op, username, success, message, callback) {
        root.operationCompleted(op, username, success, message);
        if (typeof callback === "function") {
            try {
                callback(success, message);
            } catch (e) {
                log.warn("UsersService callback error:", e);
            }
        }
    }

    Component {
        id: useraddComp
        Process {
            id: useraddProc
            property string targetUser: ""
            property string targetPassword: ""
            property bool addAdmin: false
            property bool addGreeter: false
            property var cb: null
            property string capturedErr: ""
            running: false
            stdout: StdioCollector {}
            stderr: StdioCollector {
                onStreamFinished: useraddProc.capturedErr = text || ""
            }
            onExited: exitCode => {
                const svc = root;
                if (exitCode !== 0) {
                    svc._emit("create", useraddProc.targetUser, false, (useraddProc.capturedErr || "").trim() || I18n.tr("useradd failed (exit %1)", "create user error, useradd is a command, %1 is exit code").arg(exitCode), useraddProc.cb);
                    Qt.callLater(() => useraddProc.destroy());
                    return;
                }
                const targetUser = useraddProc.targetUser;
                const targetPassword = useraddProc.targetPassword;
                const addAdmin = useraddProc.addAdmin;
                const addGreeter = useraddProc.addGreeter;
                const outerCb = useraddProc.cb;
                Qt.callLater(() => useraddProc.destroy());

                svc._runChpasswd(targetUser, targetPassword, "create", (pwOk, pwMsg) => {
                    if (!pwOk) {
                        svc._emit("create", targetUser, false, pwMsg, outerCb);
                        return;
                    }
                    svc._finishCreateUser(targetUser, addAdmin, addGreeter, outerCb);
                });
            }
        }
    }

    Component {
        id: chpasswdComp
        Process {
            id: chpasswdProc
            property string targetUser: ""
            property string targetPassword: ""
            property string op: "passwd"
            property var cb: null
            property string capturedErr: ""
            command: root.isBSD ? ["pkexec", "pw", "usermod", "-n", targetUser, "-h", "0"] : ["pkexec", "sh", "-c", "head -n1 | chpasswd"]
            stdinEnabled: true
            running: false
            stdout: StdioCollector {}
            stderr: StdioCollector {
                onStreamFinished: chpasswdProc.capturedErr = text || ""
            }
            onStarted: {
                if (root.isBSD)
                    chpasswdProc.write(chpasswdProc.targetPassword + "\n");
                else
                    chpasswdProc.write(chpasswdProc.targetUser + ":" + chpasswdProc.targetPassword + "\n");
            }
            onExited: exitCode => {
                const op = chpasswdProc.op;
                const targetUser = chpasswdProc.targetUser;
                const cb = chpasswdProc.cb;
                const err = (chpasswdProc.capturedErr || "").trim();
                Qt.callLater(() => chpasswdProc.destroy());

                if (exitCode !== 0) {
                    const msg = err || I18n.tr("Password change failed (exit %1)", "user management error, %1 is the exit code").arg(exitCode);
                    if (op === "create") {
                        if (typeof cb === "function")
                            cb(false, msg);
                    } else {
                        root._emit("passwd", targetUser, false, msg, cb);
                    }
                } else {
                    root.refresh();
                    if (op === "create") {
                        if (typeof cb === "function")
                            cb(true, I18n.tr("Password set"));
                    } else {
                        root._emit("passwd", targetUser, true, I18n.tr("Password updated"), cb);
                    }
                }
            }
        }
    }

    Component {
        id: userdelComp
        Process {
            id: userdelProc
            property string targetUser: ""
            property var cb: null
            property string capturedErr: ""
            running: false
            stdout: StdioCollector {}
            stderr: StdioCollector {
                onStreamFinished: userdelProc.capturedErr = text || ""
            }
            onExited: exitCode => {
                const targetUser = userdelProc.targetUser;
                const cb = userdelProc.cb;
                const err = (userdelProc.capturedErr || "").trim();
                Qt.callLater(() => userdelProc.destroy());

                if (exitCode !== 0) {
                    root._emit("delete", targetUser, false, err || I18n.tr("userdel failed (exit %1)", "delete user error, userdel is a command, %1 is exit code").arg(exitCode), cb);
                } else {
                    root.refresh();
                    root._emit("delete", targetUser, true, I18n.tr("User deleted"), cb);
                }
            }
        }
    }

    Component {
        id: greeterToggleComp
        Process {
            id: greeterToggleProc
            property string targetUser: ""
            property bool enableGreeter: false
            property var cb: null
            property string capturedErr: ""
            running: false
            stdout: StdioCollector {}
            stderr: StdioCollector {
                onStreamFinished: greeterToggleProc.capturedErr = text || ""
            }
            onExited: exitCode => {
                const targetUser = greeterToggleProc.targetUser;
                const enableGreeter = greeterToggleProc.enableGreeter;
                const cb = greeterToggleProc.cb;
                const err = (greeterToggleProc.capturedErr || "").trim();
                Qt.callLater(() => greeterToggleProc.destroy());

                if (exitCode !== 0) {
                    root._emit("greeter", targetUser, false, err || I18n.tr("usermod failed (exit %1)", "user group change error, usermod is a command, %1 is exit code").arg(exitCode), cb);
                } else {
                    root.refresh();
                    root._emit("greeter", targetUser, true, enableGreeter ? I18n.tr("Granted greeter login access") : I18n.tr("Removed greeter login access"), cb);
                }
            }
        }
    }

    Component {
        id: adminToggleComp
        Process {
            id: adminToggleProc
            property string targetUser: ""
            property bool makeAdmin: false
            property var cb: null
            property string capturedErr: ""
            running: false
            stdout: StdioCollector {}
            stderr: StdioCollector {
                onStreamFinished: adminToggleProc.capturedErr = text || ""
            }
            onExited: exitCode => {
                const targetUser = adminToggleProc.targetUser;
                const makeAdmin = adminToggleProc.makeAdmin;
                const cb = adminToggleProc.cb;
                const err = (adminToggleProc.capturedErr || "").trim();
                Qt.callLater(() => adminToggleProc.destroy());

                if (exitCode !== 0) {
                    root._emit("admin", targetUser, false, err || I18n.tr("usermod failed (exit %1)").arg(exitCode), cb);
                } else {
                    root.refresh();
                    root._emit("admin", targetUser, true, makeAdmin ? I18n.tr("Granted administrator privileges") : I18n.tr("Removed administrator privileges"), cb);
                }
            }
        }
    }

    function _runUseradd(username, password, addToAdmin, addToGreeter, callback) {
        const proc = useraddComp.createObject(root, {
            command: root.isBSD ? ["pkexec", "pw", "useradd", "-n", username, "-m", "-s", "/bin/sh"] : ["pkexec", "useradd", "-m", "-s", "/bin/bash", username],
            targetUser: username,
            targetPassword: password,
            addAdmin: addToAdmin,
            addGreeter: addToGreeter,
            cb: callback
        });
        proc.running = true;
    }

    function _runChpasswd(username, password, op, callback) {
        const proc = chpasswdComp.createObject(root, {
            targetUser: username,
            targetPassword: password,
            op: op,
            cb: callback
        });
        proc.running = true;
    }

    function _runUserdel(username, callback) {
        const proc = userdelComp.createObject(root, {
            command: root.isBSD ? ["pkexec", "pw", "userdel", "-n", username, "-r"] : ["pkexec", "userdel", "-r", username],
            targetUser: username,
            cb: callback
        });
        proc.running = true;
    }

    function _groupMemberCmd(group, username, add) {
        if (root.isBSD)
            return ["pkexec", "pw", "groupmod", group, add ? "-m" : "-d", username];
        return add ? ["pkexec", "usermod", "-aG", group, username] : ["pkexec", "gpasswd", "-d", username, group];
    }

    function _runAdminToggle(username, makeAdmin, callback) {
        const cmd = _groupMemberCmd(root.adminGroup, username, makeAdmin);
        const proc = adminToggleComp.createObject(root, {
            command: cmd,
            targetUser: username,
            makeAdmin: makeAdmin,
            cb: callback
        });
        proc.running = true;
    }

    function _runGreeterToggle(username, enableGreeter, callback) {
        const cmd = _groupMemberCmd(root.greeterGroup, username, enableGreeter);
        const proc = greeterToggleComp.createObject(root, {
            command: cmd,
            targetUser: username,
            enableGreeter: enableGreeter,
            cb: callback
        });
        proc.running = true;
    }

}
