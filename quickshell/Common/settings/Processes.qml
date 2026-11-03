pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import "../PamStack.js" as PamStack

Singleton {
    id: root

    signal toastRequested(int severity, string title, string body, string command, string category)
    signal toastCategoryDismissed(string category)

    property var settingsRoot: null

    onSettingsRootChanged: {
        if (settingsRoot)
            consumeGreeterAutoLoginPendingSync();
    }

    readonly property string greeterAutoLoginPendingSyncPath: (Quickshell.env("DMS_GREET_CFG_DIR") || "/var/cache/dms-greeter") + "/.local/state/auto-login-sync-pending"

    function consumeGreeterAutoLoginPendingSync() {
        if (!settingsRoot)
            return;
        greeterAutoLoginPendingCheckProcess.running = true;
    }

    property var greeterAutoLoginPendingCheckProcess: Process {
        command: ["sh", "-c", "if [ -f " + JSON.stringify(root.greeterAutoLoginPendingSyncPath) + " ]; then rm -f " + JSON.stringify(root.greeterAutoLoginPendingSyncPath) + "; echo pending; fi"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                if ((text || "").trim() !== "pending" || !root.settingsRoot)
                    return;
                if (!root.settingsRoot.greeterAutoLogin)
                    root.settingsRoot.set("greeterAutoLogin", true);
                else
                    root.scheduleGreeterAutoLoginSync();
            }
        }
    }

    property string greetdPamText: ""
    property string systemAuthPamText: ""
    property string commonAuthPamText: ""
    property string passwordAuthPamText: ""
    property string systemLoginPamText: ""
    property string systemLocalLoginPamText: ""
    property string commonAuthPcPamText: ""
    property string loginPamText: ""
    property string dankshellU2fPamText: ""
    property string u2fKeysText: ""

    property string fingerprintProbeOutput: ""
    property int fingerprintProbeExitCode: 0
    property bool fingerprintProbeFinalized: false

    property string pamProbeOutput: ""
    property bool pamProbeFinalized: false

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string u2fKeysPath: homeDir ? homeDir + "/.config/Yubico/u2f_keys" : ""
    property bool authProbeRequested: false
    readonly property bool homeU2fKeysDetected: u2fKeysPath !== "" && (authWatchers.item?.u2fKeys.loaded ?? false) && u2fKeysText.trim() !== ""
    readonly property bool lockU2fCustomConfigDetected: PamStack.moduleEnabled(dankshellU2fPamText, "pam_u2f")
    readonly property bool lockU2fCustomSourceDetected: (settingsRoot?.lockU2fPamPath || "") !== "" && (authWatchers.item?.customU2fPam.loaded ?? false)
    readonly property bool greeterPamHasFprint: greeterPamStackHasModule("pam_fprintd")
    readonly property bool greeterPamHasU2f: greeterPamStackHasModule("pam_u2f")

    function envFlag(name) {
        const value = (Quickshell.env(name) || "").trim().toLowerCase();
        if (value === "1" || value === "true" || value === "yes" || value === "on")
            return true;
        if (value === "0" || value === "false" || value === "no" || value === "off")
            return false;
        return null;
    }

    readonly property var forcedFprintAvailable: envFlag("DMS_FORCE_FPRINT_AVAILABLE")
    readonly property var forcedU2fAvailable: envFlag("DMS_FORCE_U2F_AVAILABLE")

    // --- Derived auth probe state ---

    readonly property bool pamFprintSupportDetected: pamProbeFinalized && pamProbeOutput.includes("pam_fprintd.so:true")
    readonly property bool pamU2fSupportDetected: pamProbeFinalized && pamProbeOutput.includes("pam_u2f.so:true")

    readonly property string fingerprintProbeState: {
        if (forcedFprintAvailable !== null)
            return forcedFprintAvailable ? "ready" : "probe_failed";
        if (!fingerprintProbeFinalized)
            return "probe_failed";
        return PamStack.fingerprintProbeState(fingerprintProbeExitCode, fingerprintProbeOutput, pamFprintSupportDetected);
    }

    // --- Lock fingerprint capabilities ---

    readonly property bool lockFingerprintCanEnable: {
        if (forcedFprintAvailable !== null)
            return forcedFprintAvailable;
        switch (fingerprintProbeState) {
        case "ready":
        case "missing_enrollment":
            return true;
        default:
            return false;
        }
    }

    readonly property bool lockFingerprintReady: {
        if (forcedFprintAvailable !== null)
            return forcedFprintAvailable;
        return fingerprintProbeState === "ready";
    }

    readonly property string lockFingerprintReason: {
        if (forcedFprintAvailable !== null)
            return forcedFprintAvailable ? "ready" : "probe_failed";
        return fingerprintProbeState;
    }

    // --- Greeter fingerprint capabilities ---

    readonly property bool greeterFingerprintCanEnable: {
        if (forcedFprintAvailable !== null)
            return forcedFprintAvailable;
        if (greeterPamHasFprint)
            return fingerprintProbeState !== "missing_reader";
        switch (fingerprintProbeState) {
        case "ready":
        case "missing_enrollment":
            return true;
        default:
            return false;
        }
    }

    readonly property bool greeterFingerprintReady: {
        if (forcedFprintAvailable !== null)
            return forcedFprintAvailable;
        return fingerprintProbeState === "ready";
    }

    readonly property string greeterFingerprintReason: {
        if (forcedFprintAvailable !== null)
            return forcedFprintAvailable ? "ready" : "probe_failed";
        if (greeterPamHasFprint) {
            switch (fingerprintProbeState) {
            case "ready":
                return "configured_externally";
            case "missing_enrollment":
                return "missing_enrollment";
            case "missing_reader":
                return "missing_reader";
            default:
                return "probe_failed";
            }
        }
        return fingerprintProbeState;
    }

    readonly property string greeterFingerprintSource: {
        if (forcedFprintAvailable !== null)
            return forcedFprintAvailable ? "dms" : "none";
        if (greeterPamHasFprint)
            return "pam";
        switch (fingerprintProbeState) {
        case "ready":
        case "missing_enrollment":
            return "dms";
        default:
            return "none";
        }
    }

    // --- Lock U2F capabilities ---

    readonly property bool lockU2fReady: {
        if (forcedU2fAvailable !== null)
            return forcedU2fAvailable;
        return lockU2fCustomSourceDetected || lockU2fCustomConfigDetected || homeU2fKeysDetected;
    }

    readonly property bool lockU2fCanEnable: {
        if (forcedU2fAvailable !== null)
            return forcedU2fAvailable;
        return lockU2fReady || pamU2fSupportDetected;
    }

    readonly property string lockU2fReason: {
        if (forcedU2fAvailable !== null)
            return forcedU2fAvailable ? "ready" : "probe_failed";
        if (lockU2fReady)
            return "ready";
        if (lockU2fCanEnable)
            return "missing_key_registration";
        return "missing_pam_support";
    }

    // --- Greeter U2F capabilities ---

    readonly property bool greeterU2fReady: {
        if (forcedU2fAvailable !== null)
            return forcedU2fAvailable;
        if (greeterPamHasU2f)
            return true;
        return homeU2fKeysDetected;
    }

    readonly property bool greeterU2fCanEnable: {
        if (forcedU2fAvailable !== null)
            return forcedU2fAvailable;
        if (greeterPamHasU2f)
            return true;
        return greeterU2fReady || pamU2fSupportDetected;
    }

    readonly property string greeterU2fReason: {
        if (forcedU2fAvailable !== null)
            return forcedU2fAvailable ? "ready" : "probe_failed";
        if (greeterPamHasU2f)
            return "configured_externally";
        if (greeterU2fReady)
            return "ready";
        if (greeterU2fCanEnable)
            return "missing_key_registration";
        return "missing_pam_support";
    }

    readonly property string greeterU2fSource: {
        if (forcedU2fAvailable !== null)
            return forcedU2fAvailable ? "dms" : "none";
        if (greeterPamHasU2f)
            return "pam";
        if (greeterU2fCanEnable)
            return "dms";
        return "none";
    }

    // --- Aggregates ---

    readonly property bool fprintdAvailable: lockFingerprintReady || greeterFingerprintReady
    readonly property bool u2fAvailable: lockU2fReady || greeterU2fReady

    // --- Auth detection ---

    readonly property var _fprintProbeCommand: ["sh", "-c", "if command -v fprintd-list >/dev/null 2>&1; then fprintd-list \"${USER:-$(id -un)}\" 2>&1; else printf '__missing_command__\\n'; exit 127; fi"]
    readonly property var _pamProbeCommand: ["sh", "-c", "for module in pam_fprintd.so pam_u2f.so; do found=false; for dir in /usr/lib64/security /usr/lib/security /lib/security /lib/x86_64-linux-gnu/security /usr/lib/x86_64-linux-gnu/security /usr/lib/aarch64-linux-gnu/security /run/current-system/sw/lib/security; do if [ -f \"$dir/$module\" ]; then found=true; break; fi; done; printf '%s:%s\\n' \"$module\" \"$found\"; done"]

    function detectAuthCapabilities() {
        authProbeRequested = true;
        // FileView cannot watch paths that do not exist yet, so reload the U2F PAM
        authWatchers.item.dankshellU2fPam.reload();
        authWatchers.item.u2fKeys.reload();

        if (forcedFprintAvailable === null) {
            fingerprintProbeFinalized = false;
            Proc.runCommand("fprint-probe", _fprintProbeCommand, (output, exitCode) => {
                fingerprintProbeOutput = output || "";
                fingerprintProbeExitCode = exitCode;
                fingerprintProbeFinalized = true;
            }, 0);
        }

        pamProbeFinalized = false;
        Proc.runCommand("pam-probe", _pamProbeCommand, (output, _exitCode) => {
            pamProbeOutput = output || "";
            pamProbeFinalized = true;
        }, 0);
    }

    function detectFprintd() {
        detectAuthCapabilities();
    }

    function detectU2f() {
        detectAuthCapabilities();
    }

    // --- Auth apply pipeline ---

    property bool authApplyRunning: false
    property bool authApplyQueued: false
    property bool authApplyRerunRequested: false
    property bool authApplyTerminalFallbackFromPrecheck: false
    property string authApplyStdout: ""
    property string authApplyStderr: ""
    property string authApplySudoProbeStderr: ""
    property string authApplyTerminalFallbackStderr: ""

    function scheduleAuthApply() {
        if (!settingsRoot)
            return;

        authApplyQueued = true;
        if (authApplyRunning) {
            authApplyRerunRequested = true;
            return;
        }

        authApplyDebounce.restart();
    }

    function beginAuthApply() {
        if (!authApplyQueued || authApplyRunning || !settingsRoot)
            return;

        authApplyQueued = false;
        authApplyRerunRequested = false;
        authApplyStdout = "";
        authApplyStderr = "";
        authApplySudoProbeStderr = "";
        authApplyTerminalFallbackStderr = "";
        authApplyTerminalFallbackFromPrecheck = false;
        authApplyRunning = true;
        authApplySudoProbeProcess.running = true;
    }

    function launchAuthApplyTerminalFallback(fromPrecheck, details) {
        authApplyTerminalFallbackFromPrecheck = fromPrecheck;
        if (details && details !== "")
            toastRequested(0, I18n.tr("Authentication changes need sudo. Opening terminal so you can use password or fingerprint."), details, "", "auth-sync");
        authApplyTerminalFallbackStderr = "";
        authApplyTerminalFallbackProcess.running = true;
    }

    function finishAuthApply() {
        const shouldRerun = authApplyQueued || authApplyRerunRequested;
        authApplyRunning = false;
        authApplyRerunRequested = false;
        if (shouldRerun)
            authApplyDebounce.restart();
    }

    // --- Greeter auto-login sync pipeline ---

    property bool greeterAutoLoginSyncRunning: false
    property bool greeterAutoLoginSyncQueued: false
    property bool greeterAutoLoginSyncRerunRequested: false
    property string greeterAutoLoginSyncStdout: ""
    property string greeterAutoLoginSyncStderr: ""

    function scheduleGreeterAutoLoginSync() {
        if (!settingsRoot)
            return;

        greeterAutoLoginSyncQueued = true;
        if (greeterAutoLoginSyncRunning) {
            greeterAutoLoginSyncRerunRequested = true;
            return;
        }

        greeterAutoLoginSyncDebounce.restart();
    }

    function beginGreeterAutoLoginSync() {
        if (!greeterAutoLoginSyncQueued || greeterAutoLoginSyncRunning || !settingsRoot)
            return;

        greeterAutoLoginSyncQueued = false;
        greeterAutoLoginSyncRerunRequested = false;
        greeterAutoLoginSyncStdout = "";
        greeterAutoLoginSyncStderr = "";
        greeterAutoLoginSyncRunning = true;
        greeterAutoLoginSyncSudoProbeProcess.running = true;
    }

    function deferGreeterAutoLoginSyncToPill(details) {
        toastCategoryDismissed("greeter-autologin-sync");
        SessionData.set("greeterSyncPending", true);
        toastRequested(1, I18n.tr("Auto-login change needs a sync"), I18n.tr("Administrator access is required. Press Apply changes in Settings → Greeter.") + (details ? "\n\n" + details : ""), "dms-greeter sync --autologin", "greeter-autologin-sync");
        finishGreeterAutoLoginSync();
    }

    function greeterAutoLoginSyncSuccessToast(details) {
        const enabling = settingsRoot && settingsRoot.greeterAutoLogin;
        // Clear the sticky in-progress toast, then confirm with an auto-dismissing toast.
        toastCategoryDismissed("greeter-autologin-sync");
        if (enabling) {
            toastRequested(1, I18n.tr("Auto-login enabled"), I18n.tr("You'll skip the greeter password after the next reboot. The lock screen and signing out still require your password.") + (details ? "\n\n" + details : ""), "", "");
        } else {
            toastRequested(0, I18n.tr("Auto-login disabled"), I18n.tr("You'll enter your password at the greeter after the next reboot.") + (details ? "\n\n" + details : ""), "", "");
        }
    }

    function finishGreeterAutoLoginSync() {
        const shouldRerun = greeterAutoLoginSyncQueued || greeterAutoLoginSyncRerunRequested;
        greeterAutoLoginSyncRunning = false;
        greeterAutoLoginSyncRerunRequested = false;
        if (shouldRerun)
            greeterAutoLoginSyncDebounce.restart();
    }

    function greeterPamStackHasModule(moduleName) {
        const includedPamStacks = [["system-auth", systemAuthPamText], ["common-auth", commonAuthPamText], ["password-auth", passwordAuthPamText], ["system-login", systemLoginPamText], ["system-local-login", systemLocalLoginPamText], ["common-auth-pc", commonAuthPcPamText], ["login", loginPamText]];
        return PamStack.stackHasModule(greetdPamText, includedPamStacks, moduleName);
    }

    Timer {
        id: authApplyDebounce
        interval: 300
        repeat: false
        onTriggered: root.beginAuthApply()
    }

    Timer {
        id: greeterAutoLoginSyncDebounce
        interval: 300
        repeat: false
        onTriggered: root.beginGreeterAutoLoginSync()
    }

    property var greeterAutoLoginSyncProcess: Process {
        command: ["dms-greeter", "sync", "--yes", "--autologin"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.greeterAutoLoginSyncStdout = text || ""
        }

        stderr: StdioCollector {
            onStreamFinished: root.greeterAutoLoginSyncStderr = text || ""
        }

        onExited: exitCode => {
            const out = (root.greeterAutoLoginSyncStdout || "").trim();
            const err = (root.greeterAutoLoginSyncStderr || "").trim();

            if (exitCode === 0) {
                let details = out;
                if (err !== "")
                    details = details !== "" ? details + "\n\nstderr:\n" + err : "stderr:\n" + err;
                root.greeterAutoLoginSyncSuccessToast(details);
                root.finishGreeterAutoLoginSync();
                return;
            }

            let details = "";
            if (out !== "")
                details = out;
            if (err !== "")
                details = details !== "" ? details + "\n\nstderr:\n" + err : "stderr:\n" + err;
            root.deferGreeterAutoLoginSyncToPill(details);
        }
    }

    property var greeterAutoLoginSyncSudoProbeProcess: Process {
        command: ["sudo", "-n", "true"]
        running: false

        onExited: exitCode => {
            const enabling = root.settingsRoot && root.settingsRoot.greeterAutoLogin;
            if (exitCode === 0) {
                root.toastRequested(1, enabling ? I18n.tr("Applying auto-login on startup...") : I18n.tr("Disabling auto-login on startup..."), "", "dms-greeter sync --autologin", "greeter-autologin-sync");
                root.greeterAutoLoginSyncProcess.running = true;
                return;
            }

            root.deferGreeterAutoLoginSyncToPill("");
        }
    }

    property var authApplyProcess: Process {
        command: ["dms", "auth", "sync", "--yes"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.authApplyStdout = text || ""
        }

        stderr: StdioCollector {
            onStreamFinished: root.authApplyStderr = text || ""
        }

        onExited: exitCode => {
            const out = (root.authApplyStdout || "").trim();
            const err = (root.authApplyStderr || "").trim();

            if (exitCode === 0) {
                let details = out;
                if (err !== "")
                    details = details !== "" ? details + "\n\nstderr:\n" + err : "stderr:\n" + err;
                root.toastRequested(0, I18n.tr("Authentication changes applied"), details, "", "auth-sync");
                root.detectAuthCapabilities();
                root.finishAuthApply();
                return;
            }

            let details = "";
            if (out !== "")
                details = out;
            if (err !== "")
                details = details !== "" ? details + "\n\nstderr:\n" + err : "stderr:\n" + err;
            root.toastRequested(1, I18n.tr("Background authentication sync failed. Trying terminal mode."), details, "", "auth-sync");
            root.launchAuthApplyTerminalFallback(false, "");
        }
    }

    property var authApplySudoProbeProcess: Process {
        command: ["sudo", "-n", "true"]
        running: false

        stderr: StdioCollector {
            onStreamFinished: root.authApplySudoProbeStderr = text || ""
        }

        onExited: exitCode => {
            const err = (root.authApplySudoProbeStderr || "").trim();
            if (exitCode === 0) {
                root.toastRequested(0, I18n.tr("Applying authentication changes..."), "", "", "auth-sync");
                root.authApplyProcess.running = true;
                return;
            }

            root.launchAuthApplyTerminalFallback(true, err);
        }
    }

    property var authApplyTerminalFallbackProcess: Process {
        command: ["dms", "auth", "sync", "--terminal", "--yes"]
        running: false

        stderr: StdioCollector {
            onStreamFinished: root.authApplyTerminalFallbackStderr = text || ""
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                const message = root.authApplyTerminalFallbackFromPrecheck ? I18n.tr("Terminal opened. Complete authentication there; it will close automatically when done.") : I18n.tr("Terminal fallback opened. Complete authentication there; it will close automatically when done.");
                root.toastRequested(0, message, "", "", "auth-sync");
            } else {
                let details = (root.authApplyTerminalFallbackStderr || "").trim();
                root.toastRequested(2, I18n.tr("Terminal fallback failed. Install one of the supported terminal emulators or run '%1' manually.", "terminal fallback status, %1 is a command").arg("dms auth sync") + " " + I18n.tr("(exit %1)", "process exit code").arg(exitCode), details, "", "auth-sync");
            }
            root.finishAuthApply();
        }
    }

    Loader {
        id: authWatchers
        active: root.authProbeRequested
        sourceComponent: Item {
            property alias dankshellU2fPam: dankshellU2fPamWatcher
            property alias customU2fPam: customU2fPamWatcher
            property alias u2fKeys: u2fKeysWatcher

            FileView {
                id: greetdPamWatcher
                path: "/etc/pam.d/greetd"
                printErrors: false
                onLoaded: root.greetdPamText = text()
                onLoadFailed: root.greetdPamText = ""
            }

            FileView {
                id: systemAuthPamWatcher
                path: "/etc/pam.d/system-auth"
                printErrors: false
                onLoaded: root.systemAuthPamText = text()
                onLoadFailed: root.systemAuthPamText = ""
            }

            FileView {
                id: commonAuthPamWatcher
                path: "/etc/pam.d/common-auth"
                printErrors: false
                onLoaded: root.commonAuthPamText = text()
                onLoadFailed: root.commonAuthPamText = ""
            }

            FileView {
                id: passwordAuthPamWatcher
                path: "/etc/pam.d/password-auth"
                printErrors: false
                onLoaded: root.passwordAuthPamText = text()
                onLoadFailed: root.passwordAuthPamText = ""
            }

            FileView {
                id: systemLoginPamWatcher
                path: "/etc/pam.d/system-login"
                printErrors: false
                onLoaded: root.systemLoginPamText = text()
                onLoadFailed: root.systemLoginPamText = ""
            }

            FileView {
                id: systemLocalLoginPamWatcher
                path: "/etc/pam.d/system-local-login"
                printErrors: false
                onLoaded: root.systemLocalLoginPamText = text()
                onLoadFailed: root.systemLocalLoginPamText = ""
            }

            FileView {
                id: commonAuthPcPamWatcher
                path: "/etc/pam.d/common-auth-pc"
                printErrors: false
                onLoaded: root.commonAuthPcPamText = text()
                onLoadFailed: root.commonAuthPcPamText = ""
            }

            FileView {
                id: loginPamWatcher
                path: "/etc/pam.d/login"
                printErrors: false
                onLoaded: root.loginPamText = text()
                onLoadFailed: root.loginPamText = ""
            }

            FileView {
                id: dankshellU2fPamWatcher
                path: "/etc/pam.d/dankshell-u2f"
                watchChanges: true
                printErrors: false
                onLoaded: root.dankshellU2fPamText = text()
                onLoadFailed: root.dankshellU2fPamText = ""
            }

            FileView {
                id: customU2fPamWatcher
                path: root.settingsRoot?.lockU2fPamPath || ""
                printErrors: false
            }

            FileView {
                id: u2fKeysWatcher
                path: root.u2fKeysPath
                watchChanges: true
                printErrors: false
                onLoaded: root.u2fKeysText = text()
                onLoadFailed: root.u2fKeysText = ""
            }
        }
    }
}
