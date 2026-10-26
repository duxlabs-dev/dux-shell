pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.I3
import qs.Common
import qs.Services
import "../Common/SleepLock.js" as SleepLock
import "../Common/LaunchUnit.js" as LaunchUnit

Singleton {
    id: root
    readonly property var log: Log.scoped("SessionService")

    // Qt.platform.os is "unix" on the BSDs (qtdeclarative qqmlplatform.cpp)
    readonly property bool isBSD: Qt.platform.os === "unix"
    property bool hasUwsm: false
    property bool isElogind: false
    property bool loginctlCommandAvailable: false
    property bool systemctlCommandAvailable: false
    property bool userManagerAvailable: false
    property bool hibernateSupported: false
    readonly property bool softRebootSupported: systemctlCommandAvailable
    // The firmware advertises boot-to-setup in OsIndicationsSupported, the same bit logind checks
    property bool firmwareSetupAdvertised: false
    readonly property bool firmwareSetupSupported: !isBSD && firmwareSetupAdvertised && (systemctlCommandAvailable || loginctlCommandAvailable)
    property bool inhibitorAvailable: true
    property bool idleInhibited: false
    property string inhibitReason: "Keep system awake"
    property string nvidiaCommand: ""

    property bool loginctlAvailable: false
    property string sessionId: ""
    property string sessionPath: ""
    property bool locked: false
    property bool active: false
    property bool idleHint: false
    property bool lockedHint: false
    property bool preparingForSleep: false
    property bool sleepRequested: false
    property string sessionType: ""
    property string userName: ""
    property string seat: ""
    property string display: ""

    signal sessionLocked
    signal sessionUnlocked
    signal sessionResumed
    signal lockEditorRequested
    signal greeterEditorRequested
    signal lidOpened
    signal loginctlStateChanged

    property bool stateInitialized: false
    property string prepareForSleepSubscriptionId: ""
    property bool prepareForSleepSubscriptionPending: false
    property string lidSubscriptionId: ""
    property bool lidSubscriptionPending: false
    property double lastResumeSignalTimestamp: 0
    property var pendingSleepFn: null

    readonly property string socketPath: Quickshell.env("DMS_SOCKET")

    Timer {
        id: sessionInitTimer
        interval: 200
        running: true
        repeat: false
        onTriggered: {
            detectEnvironmentProcess.running = true;
            if (!SettingsData.loginctlLockIntegration) {
                log.debug("loginctl lock integration disabled by user");
                return;
            }
            if (socketPath && socketPath.length > 0) {
                checkDMSCapabilities();
            } else {
                log.debug("DMS_SOCKET not set");
            }
        }
    }

    Timer {
        id: lockBeforeSleepFallback
        // Custom lockers never set WlSessionLock.secure.
        interval: 2000
        repeat: false
        onTriggered: root.flushPendingSleep()
    }

    Timer {
        id: sleepRequestTimeout
        // A refused sleep or a command that skips logind never sends PrepareForSleep.
        interval: 10000
        repeat: false
        onTriggered: root.sleepRequested = false
    }

    onPreparingForSleepChanged: {
        if (!preparingForSleep)
            return;
        sleepRequestTimeout.stop();
        sleepRequested = false;
    }

    Process {
        id: detectEnvironmentProcess
        running: false
        command: ["sh", "-c", `uwsm=0; command -v uwsm >/dev/null 2>&1 && systemctl --user is-active --quiet 'wayland-wm@*.service' 2>/dev/null && uwsm=1
elogind=0; ps -eo comm= | grep -qE '^(elogind|elogind-daemon)$' && elogind=1
loginctl=0; command -v loginctl >/dev/null 2>&1 && loginctl=1
systemctl=0; usermgr=0
if command -v systemctl >/dev/null 2>&1; then systemctl=1; systemctl --user --no-pager show-environment >/dev/null 2>&1 && usermgr=1; fi
hibernate=0; grep -q disk /sys/power/state 2>/dev/null && hibernate=1
fwsetup=0; b=$(od -An -tu1 -j4 -N1 /sys/firmware/efi/efivars/OsIndicationsSupported-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null); [ -n "$b" ] && [ $(($b & 1)) = 1 ] && fwsetup=1
nvidia=; command -v prime-run >/dev/null 2>&1 && nvidia=prime-run
[ -z "$nvidia" ] && command -v nvidia-offload >/dev/null 2>&1 && nvidia=nvidia-offload
printf 'uwsm=%s\nelogind=%s\nloginctl=%s\nsystemctl=%s\nusermgr=%s\nhibernate=%s\nfwsetup=%s\nnvidia=%s\n' "$uwsm" "$elogind" "$loginctl" "$systemctl" "$usermgr" "$hibernate" "$fwsetup" "$nvidia"`]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const eq = line.indexOf("=");
                if (eq <= 0)
                    return;
                const value = line.substring(eq + 1).trim();
                switch (line.substring(0, eq)) {
                case "uwsm":
                    root.hasUwsm = value === "1";
                    return;
                case "elogind":
                    root.isElogind = value === "1";
                    return;
                case "loginctl":
                    root.loginctlCommandAvailable = value === "1";
                    return;
                case "systemctl":
                    root.systemctlCommandAvailable = value === "1";
                    return;
                case "usermgr":
                    root.userManagerAvailable = value === "1";
                    return;
                case "hibernate":
                    root.hibernateSupported = !root.isBSD && value === "1";
                    return;
                case "fwsetup":
                    root.firmwareSetupAdvertised = value === "1";
                    return;
                case "nvidia":
                    root.nvidiaCommand = value;
                    return;
                }
            }
        }
    }

    Process {
        id: hibernateProcess
        running: false

        property string errorOutput: ""

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => hibernateProcess.errorOutput += data.trim()
        }

        onExited: function (exitCode) {
            if (exitCode === 0) {
                errorOutput = "";
                return;
            }
            ToastService.showError(I18n.tr("Hibernate failed"), errorOutput);
            errorOutput = "";
        }
    }

    Process {
        id: uwsmLogout
        property bool notRunning: false
        command: ["uwsm", "stop"]
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.trim().toLowerCase().includes("not running"))
                    uwsmLogout.notRunning = true;
            }
        }

        onExited: function (exitCode) {
            if (exitCode === 0 && !notRunning) {
                return;
            }
            _logout();
        }
    }

    function escapeShellArg(arg) {
        return "'" + arg.replace(/'/g, "'\\''") + "'";
    }

    function needsShellExecution(prefix) {
        if (!prefix || prefix.length === 0)
            return false;
        return /[;&|<>()$`\\"']/.test(prefix);
    }

    function parseEnvVars(envVarsStr) {
        if (!envVarsStr || envVarsStr.trim().length === 0)
            return {};
        const envObj = {};
        const pairs = envVarsStr.trim().split(/\s+/);
        for (const pair of pairs) {
            const eqIndex = pair.indexOf("=");
            if (eqIndex > 0) {
                const key = pair.substring(0, eqIndex);
                const value = pair.substring(eqIndex + 1);
                envObj[key] = value;
            }
        }
        return envObj;
    }

    function splitShellArgs(str) {
        const args = [];
        let current = "";
        let hasToken = false;
        let quote = "";
        let escaped = false;
        for (const ch of str) {
            if (escaped) {
                current += ch;
                escaped = false;
                continue;
            }
            switch (quote) {
            case "'":
                if (ch === "'") {
                    quote = "";
                    continue;
                }
                current += ch;
                continue;
            case "\"":
                switch (ch) {
                case "\"":
                    quote = "";
                    continue;
                case "\\":
                    escaped = true;
                    continue;
                }
                current += ch;
                continue;
            }
            switch (ch) {
            case "\\":
                escaped = true;
                continue;
            case "'":
            case "\"":
                quote = ch;
                hasToken = true;
                continue;
            case " ":
            case "\t":
            case "\n":
                if (!hasToken && current.length === 0)
                    continue;
                args.push(current);
                current = "";
                hasToken = false;
                continue;
            }
            current += ch;
        }
        if (current.length > 0 || hasToken)
            args.push(current);
        return args;
    }

    // Restore pre-wrap Qt paths (Nix) so launched apps use their own.
    function restoreWrapperEnv(env) {
        const restore = (target, snapshot) => {
            const orig = Quickshell.env(snapshot);
            if (orig === null)
                return;
            env[target] = orig.length > 0 ? orig : null;
        };
        restore("NIXPKGS_QT6_QML_IMPORT_PATH", "DMS_ORIG_NIXPKGS_QT6_QML_IMPORT_PATH");
        restore("QT_PLUGIN_PATH", "DMS_ORIG_QT_PLUGIN_PATH");
        return env;
    }

    function resolveDesktopId(desktopId) {
        if (!desktopId)
            return null;
        const entry = DesktopEntries.heuristicLookup(desktopId);
        if (entry || !desktopId.endsWith(".desktop"))
            return entry;
        return DesktopEntries.heuristicLookup(desktopId.slice(0, -8));
    }

    // xdg-open's generic opener ignores Terminal=true, so resolve the handler here and launch it ourselves
    function openPath(path) {
        if (!path)
            return;
        const fallback = () => Qt.openUrlExternally("file://" + path);
        if (!DMSService.isConnected) {
            fallback();
            return;
        }
        DMSService.sendRequest("mime.getDefault", {
            "path": path
        }, response => {
            const entry = resolveDesktopId(response?.result?.desktopId);
            if (!entry) {
                fallback();
                return;
            }
            launchDesktopEntry(entry, false, [path]);
        });
    }

    function launchDesktopEntry(desktopEntry, useNvidia, args) {
        if (!desktopEntry || !desktopEntry.command)
            return;
        CompositorService.closeNiriOverviewOnWindowFocus();
        let cmd = args?.length ? [...desktopEntry.command, ...args] : desktopEntry.command;

        const appId = desktopEntry.id || desktopEntry.execString || desktopEntry.exec || "";
        const override = SessionData.getAppOverride(appId);

        const dgpu = useNvidia || (override?.launchOnDgpu && nvidiaCommand);
        if (dgpu && nvidiaCommand)
            cmd = [nvidiaCommand].concat(cmd);

        if (override?.extraFlags) {
            cmd = cmd.concat(splitShellArgs(override.extraFlags));
        }

        const userPrefix = SettingsData.launchPrefix?.trim() || "";
        const defaultPrefix = Quickshell.env("DMS_DEFAULT_LAUNCH_PREFIX") || "";
        const prefix = userPrefix.length > 0 ? userPrefix : defaultPrefix;
        const workDir = desktopEntry.workingDirectory || Quickshell.env("HOME");
        const cursorEnv = typeof SettingsData.getCursorEnvironment === "function" ? SettingsData.getCursorEnvironment() : {};

        const overrideEnv = override?.envVars ? parseEnvVars(override.envVars) : {};
        const finalEnv = restoreWrapperEnv(Object.assign({}, cursorEnv, overrideEnv));

        if (desktopEntry.runInTerminal) {
            const terminal = SessionData.resolveTerminal() || "xterm";
            const escapedCmd = cmd.map(arg => escapeShellArg(arg)).join(" ");
            const shellCmd = prefix.length > 0 ? `${prefix} ${escapedCmd}` : escapedCmd;
            Quickshell.execDetached({
                command: [terminal, "-e", "sh", "-c", shellCmd],
                workingDirectory: workDir,
                environment: finalEnv
            });
            return;
        }

        if (prefix.length > 0 && needsShellExecution(prefix)) {
            const escapedCmd = cmd.map(arg => escapeShellArg(arg)).join(" ");
            Quickshell.execDetached({
                command: ["sh", "-c", `${prefix} ${escapedCmd}`],
                workingDirectory: workDir,
                environment: finalEnv
            });
            return;
        }

        if (prefix.length > 0)
            cmd = LaunchUnit.prefixArgs(prefix, desktopEntry.id, LaunchUnit.randomSuffix()).concat(cmd);

        Quickshell.execDetached({
            command: cmd,
            workingDirectory: workDir,
            environment: finalEnv
        });
    }

    function launchDesktopAction(desktopEntry, action, useNvidia) {
        if (!desktopEntry || !action || !action.command)
            return;
        CompositorService.closeNiriOverviewOnWindowFocus();
        let cmd = action.command;

        const appId = desktopEntry.id || desktopEntry.execString || desktopEntry.exec || "";
        const override = SessionData.getAppOverride(appId);
        const dgpu = useNvidia || (override?.launchOnDgpu && nvidiaCommand);
        if (dgpu && nvidiaCommand)
            cmd = [nvidiaCommand].concat(cmd);

        const userPrefix = SettingsData.launchPrefix?.trim() || "";
        const defaultPrefix = Quickshell.env("DMS_DEFAULT_LAUNCH_PREFIX") || "";
        const prefix = userPrefix.length > 0 ? userPrefix : defaultPrefix;
        const workDir = desktopEntry.workingDirectory || Quickshell.env("HOME");
        const cursorEnv = typeof SettingsData.getCursorEnvironment === "function" ? SettingsData.getCursorEnvironment() : {};
        const finalEnv = restoreWrapperEnv(Object.assign({}, cursorEnv));

        if (prefix.length > 0 && needsShellExecution(prefix)) {
            const escapedCmd = cmd.map(arg => escapeShellArg(arg)).join(" ");
            Quickshell.execDetached({
                command: ["sh", "-c", `${prefix} ${escapedCmd}`],
                workingDirectory: workDir,
                environment: finalEnv
            });
            return;
        }

        if (prefix.length > 0)
            cmd = LaunchUnit.prefixArgs(prefix, desktopEntry.id, LaunchUnit.randomSuffix()).concat(cmd);

        Quickshell.execDetached({
            command: cmd,
            workingDirectory: workDir,
            environment: finalEnv
        });
    }

    // * Session management
    function logout() {
        if (hasUwsm) {
            if (uwsmLogout.running)
                return;
            uwsmLogout.notRunning = false;
            uwsmLogout.running = true;
            return;
        }
        _logout();
    }

    function _logout() {
        if (SettingsData.customPowerActionLogout.length === 0) {
            if (CompositorService.isAqueous) {
                AqueousService.quit();
                return;
            }
            if (CompositorService.isNiri) {
                NiriService.quit();
                return;
            }

            if (CompositorService.isMango) {
                MangoService.quit();
                return;
            }

            if (CompositorService.isLabwc) {
                LabwcService.quit();
                return;
            }

            if (CompositorService.isUmbriel) {
                UmbrielService.action("session-quit:skip-confirmation");
                return;
            }

            if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle) {
                try {
                    I3.dispatch("exit");
                } catch (_) {}
                return;
            }

            if (CompositorService.isHyprland) {
                HyprlandService.exit();
                return;
            }

            DMSService.sendRequest("loginctl.terminate", null, response => {
                if (response.error)
                    log.warn("Failed to terminate session:", response.error);
            });
        } else {
            Quickshell.execDetached(customActionCommand(SettingsData.customPowerActionLogout));
        }
    }

    // systemd-run escapes the shell's cgroup so session teardown can't kill the command mid-run (#3250)
    function customActionCommand(cmd) {
        if (!userManagerAvailable)
            return ["sh", "-c", cmd];
        return ["systemd-run", "--user", "--scope", "--collect", "--quiet", "sh", "-c", cmd];
    }

    function powerManagerCommand(action) {
        if (isBSD)
            return bsdPowerCommand(action);
        const useLoginctl = isElogind || (loginctlCommandAvailable && !systemctlCommandAvailable);
        return [useLoginctl ? "loginctl" : "systemctl", action];
    }

    function bsdPowerCommand(action) {
        switch (action) {
        case "suspend":
        case "suspend-then-hibernate":
            return ["acpiconf", "-s", "3"];
        case "hibernate":
            return ["acpiconf", "-s", "4"];
        case "reboot":
            return ["shutdown", "-r", "now"];
        default:
            return ["shutdown", "-p", "now"];
        }
    }

    function cancelPendingSleep() {
        lockBeforeSleepFallback.stop();
        pendingSleepFn = null;
    }

    function flushPendingSleep() {
        lockBeforeSleepFallback.stop();
        const run = pendingSleepFn;
        pendingSleepFn = null;
        if (run)
            run();
    }

    function onSessionLockSecured() {
        if (pendingSleepFn)
            flushPendingSleep();
    }

    function runSleepAction(run) {
        cancelPendingSleep();
        sleepRequested = true;
        sleepRequestTimeout.restart();
        if (!SleepLock.shouldWaitForLock(SettingsData.lockBeforeSuspend, IdleService.isSessionLockSecure)) {
            run();
            return;
        }
        // Custom hibernate skips logind PrepareForSleep; dump RAM only after the lock is up.
        // Assign before lockRequested: a synchronous secure must see this closure.
        // A second call before the first runs drops the first (last wins).
        pendingSleepFn = run;
        IdleService.lockRequested();
        lockBeforeSleepFallback.restart();
    }

    function suspend() {
        runSleepAction(() => {
            if (SettingsData.customPowerActionSuspend.length === 0) {
                Quickshell.execDetached(powerManagerCommand("suspend"));
            } else {
                Quickshell.execDetached(["sh", "-c", SettingsData.customPowerActionSuspend]);
            }
        });
    }

    function hibernate() {
        runSleepAction(() => {
            hibernateProcess.errorOutput = "";
            if (SettingsData.customPowerActionHibernate.length > 0) {
                hibernateProcess.command = ["sh", "-c", SettingsData.customPowerActionHibernate];
            } else {
                hibernateProcess.command = powerManagerCommand("hibernate");
            }
            hibernateProcess.running = true;
        });
    }

    function suspendThenHibernate() {
        runSleepAction(() => {
            Quickshell.execDetached(powerManagerCommand("suspend-then-hibernate"));
        });
    }

    function suspendWithBehavior(behavior) {
        if (behavior === SettingsData.SuspendBehavior.Hibernate) {
            hibernate();
        } else if (behavior === SettingsData.SuspendBehavior.SuspendThenHibernate) {
            suspendThenHibernate();
        } else {
            suspend();
        }
    }

    function reboot() {
        if (SettingsData.customPowerActionReboot.length === 0) {
            Quickshell.execDetached(powerManagerCommand("reboot"));
        } else {
            Quickshell.execDetached(customActionCommand(SettingsData.customPowerActionReboot));
        }
    }

    function softReboot() {
        Quickshell.execDetached(["systemctl", "soft-reboot"]);
    }

    // Skips customPowerActionReboot: no systemctl or loginctl command sets the firmware flag without also rebooting.
    function rebootToFirmwareSetup() {
        firmwareSetupProcess.running = true;
    }

    Process {
        id: firmwareSetupProcess
        running: false
        command: root.powerManagerCommand("reboot").concat(["--firmware-setup"])

        stderr: StdioCollector {
            id: firmwareSetupErrors
        }

        onExited: exitCode => {
            if (exitCode === 0)
                return;
            ToastService.showError(I18n.tr("Failed to reboot to firmware setup", "error toast, firmware setup is the UEFI/BIOS settings screen"), firmwareSetupErrors.text.trim());
        }
    }

    function poweroff() {
        if (SettingsData.customPowerActionPowerOff.length === 0) {
            Quickshell.execDetached(powerManagerCommand("poweroff"));
        } else {
            Quickshell.execDetached(customActionCommand(SettingsData.customPowerActionPowerOff));
        }
    }

    // Actions added in settings, listed after the built-in ones: firmware setup, boot entries, then custom buttons.
    // The boot entry and custom lists line up index for index with their setting.
    readonly property var bootEntryActions: (SettingsData.powerMenuBootEntries || []).map(entry => "bootnext:" + entry.id)
    readonly property var firmwareSetupActions: SettingsData.powerMenuFirmwareSetup && firmwareSetupSupported ? ["firmwaresetup"] : []
    readonly property var customPowerActions: (SettingsData.customPowerButtons || []).map((button, i) => "custom:" + i)
    readonly property var extraPowerActions: firmwareSetupActions.concat(bootEntryActions, customPowerActions)

    function isPowerActionSupported(action) {
        switch (action) {
        case "hibernate":
            return hibernateSupported;
        case "softreboot":
            return softRebootSupported;
        default:
            return true;
        }
    }

    function executePowerAction(action) {
        const customIndex = customPowerActions.indexOf(action);
        if (customIndex >= 0) {
            const button = SettingsData.customPowerButtons[customIndex];
            if (!button?.command)
                return false;
            Quickshell.execDetached(customActionCommand(button.command));
            return true;
        }
        const bootIndex = bootEntryActions.indexOf(action);
        if (bootIndex >= 0) {
            BootEntryService.rebootTo(SettingsData.powerMenuBootEntries[bootIndex]);
            return true;
        }
        switch (action) {
        case "logout":
            logout();
            return true;
        case "suspend":
            suspend();
            return true;
        case "hibernate":
            hibernate();
            return true;
        case "reboot":
            reboot();
            return true;
        case "softreboot":
            softReboot();
            return true;
        case "firmwaresetup":
            if (!firmwareSetupSupported)
                return false;
            rebootToFirmwareSetup();
            return true;
        case "poweroff":
            poweroff();
            return true;
        case "restart":
            Quickshell.execDetached(["dms", "restart"]);
            return true;
        default:
            return false;
        }
    }

    function getPowerActionData(action) {
        const customIndex = customPowerActions.indexOf(action);
        if (customIndex >= 0) {
            const button = SettingsData.customPowerButtons[customIndex];
            return {
                "icon": button?.icon || "terminal",
                "label": button?.label || button?.command || "",
                "key": ""
            };
        }
        const bootIndex = bootEntryActions.indexOf(action);
        if (bootIndex >= 0) {
            // Boot entries take the digit keys in the order they were added
            return {
                "icon": "restart_alt",
                "label": I18n.tr("Reboot to %1", "power menu action, %1 is a boot entry such as Windows Boot Manager").arg(SettingsData.powerMenuBootEntries[bootIndex].label),
                "key": bootIndex < 9 ? String(bootIndex + 1) : ""
            };
        }
        switch (action) {
        case "reboot":
            return {
                "icon": "restart_alt",
                "label": I18n.tr("Reboot", "verb, power menu action"),
                "key": "R"
            };
        case "softreboot":
            return {
                "icon": "autorenew",
                "label": I18n.tr("Soft reboot"),
                "key": "B"
            };
        case "firmwaresetup":
            return {
                "icon": "developer_board",
                "label": I18n.tr("Reboot to firmware setup", "power menu action, firmware setup is the UEFI/BIOS settings screen"),
                "key": "F"
            };
        case "logout":
            return {
                "icon": "logout",
                "label": I18n.tr("Log out"),
                "key": "X"
            };
        case "poweroff":
            return {
                "icon": "power_settings_new",
                "label": I18n.tr("Power off"),
                "key": "P"
            };
        case "lock":
            return {
                "icon": "lock",
                "label": I18n.tr("Lock", "verb, power menu action that locks the screen"),
                "key": "L"
            };
        case "suspend":
            return {
                "icon": "bedtime",
                "label": I18n.tr("Suspend", "verb, power menu action"),
                "key": "S"
            };
        case "hibernate":
            return {
                "icon": "ac_unit",
                "label": I18n.tr("Hibernate", "verb, power menu action"),
                "key": "H"
            };
        case "restart":
            return {
                "icon": "refresh",
                "label": I18n.tr("Restart DMS"),
                "key": "D"
            };
        case "switchuser":
            return {
                "icon": "switch_account",
                "label": I18n.tr("Switch User"),
                "key": "U"
            };
        default:
            return {
                "icon": "help",
                "label": action,
                "key": "?"
            };
        }
    }

    // * Idle Inhibitor
    signal inhibitorChanged

    readonly property int _maxExpireInterval: 86400000

    Timer {
        id: inhibitExpireTimer
        repeat: false
        running: false
        onTriggered: root._armExpireTimer()
    }

    // Timers use a monotonic clock that stops across suspend, so the deadline is
    // re-checked against the wall clock on resume and after each chunk.
    function _armExpireTimer() {
        inhibitExpireTimer.stop();
        if (!idleInhibited || SessionData.idleInhibitedUntil <= 0)
            return;
        const remaining = SessionData.idleInhibitedUntil - Date.now();
        if (remaining <= 0) {
            disableIdleInhibit();
            return;
        }
        inhibitExpireTimer.interval = Math.min(remaining, _maxExpireInterval);
        inhibitExpireTimer.start();
    }

    onSessionResumed: _armExpireTimer()

    function _setIdleInhibited(enabled) {
        if (idleInhibited === enabled)
            return;
        idleInhibited = enabled;
        inhibitorChanged();
        syncKeepAwake();
    }

    // Both entry points are deliberate: the singletons are created lazily in no fixed order, so
    // whichever of these runs once the session is loaded does the restore; the other no-ops.
    function _restoreIdleInhibit() {
        if (!SessionData._hasLoaded)
            return;
        _setIdleInhibited(SessionData.idleInhibited);
        _armExpireTimer();
    }

    Connections {
        target: SessionData

        function onLoaded() {
            root._restoreIdleInhibit();
        }
    }

    Component.onCompleted: _restoreIdleInhibit()

    function enableIdleInhibit(durationMinutes) {
        SessionData.setIdleInhibited(true, durationMinutes);
        _setIdleInhibited(true);
        _armExpireTimer();
    }

    function disableIdleInhibit() {
        SessionData.setIdleInhibited(false);
        _setIdleInhibited(false);
        _armExpireTimer();
    }

    function toggleIdleInhibit(durationMinutes) {
        if (idleInhibited) {
            disableIdleInhibit();
        } else {
            enableIdleInhibit(durationMinutes);
        }
    }

    function setInhibitReason(reason) {
        inhibitReason = reason;
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                checkDMSCapabilities();
            } else {
                clearPowerSubscriptionState();
            }
        }

        function onCapabilitiesReceived() {
            syncSleepInhibitor();
            syncKeepAwake();
        }
    }

    Connections {
        target: DMSService
        enabled: DMSService.isConnected

        function onCapabilitiesChanged() {
            checkDMSCapabilities();
        }

        function onDbusSignalReceived(subscriptionId, data) {
            if (subscriptionId === prepareForSleepSubscriptionId) {
                handlePrepareForSleepSignal(data);
            } else if (subscriptionId === lidSubscriptionId) {
                handleLidPropertiesChanged(data);
            }
        }
    }

    Connections {
        target: SettingsData

        function onLoginctlLockIntegrationChanged() {
            if (SettingsData.loginctlLockIntegration) {
                if (socketPath && socketPath.length > 0 && loginctlAvailable) {
                    if (!stateInitialized) {
                        stateInitialized = true;
                        getLoginctlState();
                        syncLockBeforeSuspend();
                    }
                }
            } else {
                stateInitialized = false;
            }
            syncSleepInhibitor();
        }

        function onLockBeforeSuspendChanged() {
            if (SettingsData.loginctlLockIntegration) {
                syncLockBeforeSuspend();
            }
            syncSleepInhibitor();
        }

        function onKeepAwakeBlocksSleepChanged() {
            syncKeepAwake();
        }
    }

    Connections {
        target: DMSService
        enabled: SettingsData.loginctlLockIntegration

        function onLoginctlStateUpdate(data) {
            updateLoginctlState(data);
        }
    }

    function checkDMSCapabilities() {
        if (!DMSService.isConnected) {
            return;
        }

        if (DMSService.capabilities.length === 0) {
            return;
        }

        if (DMSService.capabilities.includes("loginctl")) {
            loginctlAvailable = true;
            if (SettingsData.loginctlLockIntegration && !stateInitialized) {
                stateInitialized = true;
                getLoginctlState();
                syncLockBeforeSuspend();
            }
        } else {
            loginctlAvailable = false;
            log.debug("loginctl capability not available in DMS");
        }

        if (DMSService.capabilities.includes("dbus")) {
            ensurePrepareForSleepSubscription();
            ensureLidSubscription();
        } else {
            clearPowerSubscriptionState();
        }
    }

    function clearPowerSubscriptionState() {
        prepareForSleepSubscriptionId = "";
        prepareForSleepSubscriptionPending = false;
        lidSubscriptionId = "";
        lidSubscriptionPending = false;
    }

    function ensureLidSubscription() {
        if (!DMSService.isConnected || !DMSService.capabilities.includes("dbus"))
            return;
        if (lidSubscriptionId || lidSubscriptionPending)
            return;

        lidSubscriptionPending = true;
        DMSService.dbusSubscribe("system", "org.freedesktop.UPower", "/org/freedesktop/UPower", "org.freedesktop.DBus.Properties", "PropertiesChanged", response => {
            lidSubscriptionPending = false;
            if (response.error) {
                log.warn("Failed to subscribe to lid changes:", response.error);
                return;
            }
            lidSubscriptionId = response.result?.subscriptionId || "";
        });
    }

    function handleLidPropertiesChanged(data) {
        if (data?.path !== "/org/freedesktop/UPower" || data.body?.[0] !== "org.freedesktop.UPower")
            return;
        if (data.body?.[1]?.LidIsClosed === false)
            lidOpened();
    }

    function ensurePrepareForSleepSubscription() {
        if (!DMSService.isConnected || !DMSService.capabilities.includes("dbus")) {
            return;
        }

        if (prepareForSleepSubscriptionId || prepareForSleepSubscriptionPending) {
            return;
        }

        prepareForSleepSubscriptionPending = true;
        DMSService.dbusSubscribe("system", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "PrepareForSleep", response => {
            prepareForSleepSubscriptionPending = false;

            if (response.error) {
                log.warn("Failed to subscribe to PrepareForSleep:", response.error);
                return;
            }

            prepareForSleepSubscriptionId = response.result?.subscriptionId || "";
        });
    }

    function emitSessionResumedOnce() {
        const now = Date.now();
        if ((now - lastResumeSignalTimestamp) < 1000) {
            return;
        }
        lastResumeSignalTimestamp = now;
        sessionResumed();
    }

    function handlePrepareForSleepSignal(data) {
        if (!data?.body || data.body.length === 0) {
            return;
        }

        const wasSleeping = preparingForSleep;
        preparingForSleep = data.body[0] === true;

        if (wasSleeping && !preparingForSleep) {
            emitSessionResumedOnce();
        }
    }

    function getLoginctlState() {
        if (!loginctlAvailable)
            return;
        DMSService.sendRequest("loginctl.getState", null, response => {
            if (response.result) {
                updateLoginctlState(response.result);
            }
        });
    }

    function syncLockBeforeSuspend() {
        if (!loginctlAvailable)
            return;
        DMSService.sendRequest("loginctl.setLockBeforeSuspend", {
            enabled: SettingsData.lockBeforeSuspend
        }, response => {
            if (response.error) {
                log.warn("Failed to sync lock before suspend:", response.error);
            } else {
                log.debug("Synced lock before suspend:", SettingsData.lockBeforeSuspend);
            }
        });
    }

    function syncSleepInhibitor() {
        if (!loginctlAvailable)
            return;
        if (!DMSService.apiVersion || DMSService.apiVersion < 4)
            return;
        DMSService.sendRequest("loginctl.setSleepInhibitorEnabled", {
            enabled: SettingsData.loginctlLockIntegration && SettingsData.lockBeforeSuspend
        }, response => {
            if (response.error) {
                log.warn("Failed to sync sleep inhibitor:", response.error);
            } else {
                log.debug("Synced sleep inhibitor:", SettingsData.loginctlLockIntegration);
            }
        });
    }

    function syncKeepAwake() {
        if (!loginctlAvailable)
            return;
        DMSService.sendRequest("loginctl.setKeepAwake", {
            enabled: idleInhibited && SettingsData.keepAwakeBlocksSleep
        }, response => {
            if (response.error)
                log.warn("Failed to sync keep awake:", response.error);
        });
    }

    function updateLoginctlState(state) {
        const wasLocked = locked;
        const wasSleeping = preparingForSleep;

        sessionId = state.sessionId || "";
        sessionPath = state.sessionPath || "";
        locked = state.locked || false;
        active = state.active || false;
        idleHint = state.idleHint || false;
        lockedHint = state.lockedHint || false;
        preparingForSleep = state.preparingForSleep || false;
        sessionType = state.sessionType || "";
        userName = state.userName || "";
        seat = state.seat || "";
        display = state.display || "";

        if (locked && !wasLocked) {
            sessionLocked();
        } else if (!locked && wasLocked) {
            sessionUnlocked();
        }

        if (wasSleeping && !preparingForSleep) {
            emitSessionResumedOnce();
        }

        loginctlStateChanged();
    }
}
