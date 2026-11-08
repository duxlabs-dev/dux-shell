pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.Common
import qs.Services

Scope {
    id: root

    readonly property var log: Log.scoped("Pam")

    property bool lockSecured: false
    property bool unlockInProgress: false

    readonly property alias passwd: passwd
    readonly property alias fprint: fprint
    readonly property alias u2f: u2f
    property string lockMessage
    property string state
    property string fprintState
    property string u2fState
    property bool u2fPending: false
    property string u2fPendingMode
    property string buffer

    // the prompt pam asked for, e.g. "PIN: "
    property string authPromptText: ""
    property bool responseSubmitted: false
    property bool awaitingUserInput: false
    readonly property bool authBusy: passwd.active && !root.awaitingUserInput
    property var attemptInfoMessages: []
    property bool lockoutAnnouncedThisAttempt: false

    signal flashMsg
    signal unlockRequested

    function resetAuthFlows(): void {
        passwd.abort();
        fprint.stop();
        u2f.abort();
        u2fErrorRetry.running = false;
        u2fPendingTimeout.running = false;
        passwdActiveTimeout.running = false;
        unlockRequestTimeout.running = false;
        root.u2fPending = false;
        root.u2fPendingMode = "";
        root.u2fState = "";
        root.unlockInProgress = false;
    }

    function recoverFromAuthStall(newState: string): void {
        resetAuthFlows();
        root.state = newState;
        flashMsg();
        stateReset.restart();
        fprint.checkAvail();
        u2f.checkAvail();
    }

    // start() runs every auth module before the first prompt (howdy, fprintd), so only on submit
    function submitPassword(): void {
        root.responseSubmitted = true;
        if (!passwd.active) {
            passwd.start();
            return;
        }
        if (passwd.responseRequired) {
            root.responseSubmitted = false;
            root.awaitingUserInput = false;
            passwdActiveTimeout.restart();
            passwd.respond(root.buffer);
        } else {
            // kept and sent when the prompt arrives; a stack that never asks still times out
            passwdActiveTimeout.restart();
        }
    }

    function completeUnlock(): void {
        if (!root.unlockInProgress) {
            root.unlockInProgress = true;
            passwd.abort();
            fprint.stop();
            u2f.abort();
            u2fErrorRetry.running = false;
            u2fPendingTimeout.running = false;
            root.u2fPending = false;
            root.u2fPendingMode = "";
            root.u2fState = "";
            unlockRequestTimeout.restart();
            unlockRequested();
        }
    }

    function proceedAfterPrimaryAuth(): void {
        if (!root.u2fSuppressedByPrimaryPam && SettingsData.enableU2f && SettingsData.u2fMode === "and" && u2f.available) {
            u2f.startForSecondFactor();
        } else {
            if (AdminPolicy.disableCustomLockPam && SettingsData.enableU2f && SettingsData.u2fMode === "and" && !u2fConfigWatcher.loaded)
                log.warn("/etc/pam.d/dankshell-u2f is missing, unlocking without the security key");
            completeUnlock();
        }
    }

    function cancelU2fPending(): void {
        if (!root.u2fPending)
            return;
        u2f.abort();
        u2fErrorRetry.running = false;
        u2fPendingTimeout.running = false;
        root.u2fPending = false;
        root.u2fPendingMode = "";
        root.u2fState = "";
        fprint.checkAvail();
    }

    readonly property bool customPamActive: SettingsData.lockPamPath !== "" && customPamWatcher.loaded
    readonly property bool fprintSuppressedByPrimaryPam: !AdminPolicy.disableCustomLockPam && (SettingsData.lockPamExternallyManaged || (customPamActive && SettingsData.lockPamInlineFprint))
    readonly property bool u2fSuppressedByPrimaryPam: !AdminPolicy.disableCustomLockPam && (SettingsData.lockPamExternallyManaged || (customPamActive && SettingsData.lockPamInlineU2f))
    readonly property bool customU2fPamActive: SettingsData.lockU2fPamPath !== "" && customU2fPamWatcher.loaded

    FileView {
        id: customPamWatcher

        path: SettingsData.lockPamPath !== "" ? SettingsData.lockPamPath : ""
        printErrors: false
    }

    FileView {
        id: dankshellConfigWatcher

        path: "/etc/pam.d/dankshell"
        printErrors: false
    }

    FileView {
        id: u2fConfigWatcher

        path: "/etc/pam.d/dankshell-u2f"
        watchChanges: true
        printErrors: false
    }

    FileView {
        id: fprintConfigWatcher

        path: AdminPolicy.disableCustomLockPam ? "/etc/pam.d/dankshell-fprint" : ""
        printErrors: false
    }

    FileView {
        id: customU2fPamWatcher

        path: SettingsData.lockU2fPamPath !== "" ? SettingsData.lockU2fPamPath : ""
        printErrors: false
    }

    // Fallback stack written by `dms auth resolve-lock` when no managed
    // /etc/pam.d/dankshell exists. See #2789.
    readonly property string userPamDir: Paths.strip(Paths.state) + "/pam"

    FileView {
        id: userPamWatcher

        path: root.userPamDir + "/dankshell"
        printErrors: false
    }

    Process {
        id: resolveUserPam

        command: ["dms", "auth", "resolve-lock", "--quiet"]
        running: false
        onExited: exitCode => {
            if (exitCode === 0)
                userPamWatcher.reload();
        }
    }

    function ensureUserPamConfig(): void {
        if (AdminPolicy.disableCustomLockPam || SettingsData.lockPamExternallyManaged || resolveUserPam.running)
            return;
        resolveUserPam.running = true;
    }

    Component.onCompleted: ensureUserPamConfig()

    PamContext {
        id: passwd

        config: {
            if (AdminPolicy.disableCustomLockPam)
                return dankshellConfigWatcher.loaded ? "dankshell" : "login";
            if (root.customPamActive)
                return SettingsData.lockPamPath.slice(SettingsData.lockPamPath.lastIndexOf("/") + 1);
            if (SettingsData.lockPamExternallyManaged)
                return "login";
            if (dankshellConfigWatcher.loaded)
                return "dankshell";
            if (userPamWatcher.loaded)
                return "dankshell";
            return "login";
        }
        configDirectory: {
            if (AdminPolicy.disableCustomLockPam)
                return "/etc/pam.d";
            if (root.customPamActive) {
                const idx = SettingsData.lockPamPath.lastIndexOf("/");
                return idx > 0 ? SettingsData.lockPamPath.slice(0, idx) : "/";
            }
            if (SettingsData.lockPamExternallyManaged)
                return "/etc/pam.d";
            if (dankshellConfigWatcher.loaded)
                return "/etc/pam.d";
            if (userPamWatcher.loaded)
                return root.userPamDir;
            return Quickshell.shellDir + "/assets/pam";
        }

        onMessageChanged: {
            // collected by position, not text, so it works in any locale
            if (message.length > 0 && !responseRequired)
                root.attemptInfoMessages = root.attemptInfoMessages.concat([message]);
        }

        // not responseRequiredChanged: that only fires on change, so two prompts in
        // a row leave the second unhandled
        onPamMessage: {
            if (!responseRequired)
                return;

            root.authPromptText = (message || "").replace(/:\s*$/, "").trim();

            const notice = root.attemptInfoMessages.filter(m => m !== message);
            if (notice.length > 0) {
                root.lockMessage = notice.join("\n");
                root.lockoutAnnouncedThisAttempt = true;
            }
            root.attemptInfoMessages = [];

            // each prompt needs its own submission, or the second gets the first answer
            if (root.responseSubmitted) {
                root.responseSubmitted = false;
                root.awaitingUserInput = false;
                respond(root.buffer);
            } else {
                root.awaitingUserInput = true;
                passwdActiveTimeout.running = false;
            }
        }

        onCompleted: res => {
            // requisite preauth can lock without ever prompting; surface it here too
            if (!root.lockoutAnnouncedThisAttempt) {
                if (root.attemptInfoMessages.length > 0) {
                    root.lockMessage = root.attemptInfoMessages.join("\n");
                    root.lockoutAnnouncedThisAttempt = true;
                } else {
                    root.lockMessage = "";
                }
                root.attemptInfoMessages = [];
            }

            if (res === PamResult.Success) {
                if (!root.unlockInProgress) {
                    fprint.stop();
                    root.proceedAfterPrimaryAuth();
                }
                return;
            }

            unlockRequestTimeout.running = false;
            root.unlockInProgress = false;
            root.u2fPending = false;
            root.u2fPendingMode = "";
            root.u2fState = "";
            u2fPendingTimeout.running = false;
            u2f.abort();

            if (res === PamResult.Error)
                root.state = "error";
            else if (res === PamResult.MaxTries)
                root.state = "max";
            else if (res === PamResult.Failed)
                root.state = "fail";

            root.responseSubmitted = false;
            root.flashMsg();
            stateReset.restart();
        }
    }

    Connections {
        target: passwd

        function onActiveChanged() {
            root.authPromptText = "";
            root.awaitingUserInput = false;
            if (passwd.active) {
                root.attemptInfoMessages = [];
                root.lockoutAnnouncedThisAttempt = false;
                if (root.responseSubmitted)
                    passwdActiveTimeout.restart();
                else
                    passwdActiveTimeout.running = false;
            } else {
                passwdActiveTimeout.running = false;
            }
        }
    }

    PamContext {
        id: fprint

        readonly property bool available: SettingsData.lockFingerprintReady && (!AdminPolicy.disableCustomLockPam || fprintConfigWatcher.loaded)
        property int tries: 0
        property int errorTries: 0
        property double attemptStartedAt: 0
        property bool completedDuringStart: false
        readonly property int maxErrorTries: 200
        readonly property int daemonIdleExitMs: 30000
        // sessionTimeoutMs mirrors `timeout=` in assets/pam/fprint; under the
        // policy, /etc/pam.d/dankshell-fprint must carry the same value
        readonly property int sessionTimeoutMs: 90000
        readonly property int verifyStartSlackMs: 10000
        readonly property bool retrying: errorRetry.running
        readonly property int retryInterval: errorRetry.interval
        readonly property bool allowed: available && SettingsData.enableFprint && root.lockSecured && !root.fprintSuppressedByPrimaryPam && !root.unlockInProgress && !root.u2fPending && !SessionService.preparingForSleep && !SessionService.sleepRequested && !IdleService.monitorsOff && tries < SettingsData.maxFprintTries
        readonly property string status: {
            if (!available || !SettingsData.enableFprint || !root.lockSecured || root.fprintSuppressedByPrimaryPam)
                return "disabled";
            if (tries >= SettingsData.maxFprintTries)
                return "max";
            if (!allowed)
                return "paused";
            if (active)
                return "active";
            if (retrying)
                return "retrying";
            return errorTries >= maxErrorTries ? "stopped" : "idle";
        }

        function stop(): void {
            errorRetry.stop();
            attemptStartedAt = 0;
            abort();
        }

        // pam_fprintd reports an expired timeout as PAM_AUTHINFO_UNAVAIL, the same
        // result a device fault gives, and its "Verification timed out" message is
        // translated, so age is the signal we can rely on. Its timeout runs from the
        // verify rather than from the claim, which is why the age is measured from
        // the message announcing the verify: a slow claim then cannot make a fault
        // look old enough, and a session that never reached a verify never qualifies.
        // That message lands after pam_fprintd has already armed its deadline, so the
        // age read here runs short of the real timeout and the slack makes it up. The
        // bias is deliberate: a timeout misread as a fault parks the reader behind the
        // backoff, while a fault misread as a timeout costs one extra retry.
        function attemptSettled(): bool {
            return attemptStartedAt > 0 && Date.now() - attemptStartedAt >= sessionTimeoutMs - verifyStartSlackMs;
        }

        function checkAvail(): void {
            if (!allowed) {
                stop();
                return;
            }
            if (!active && !retrying)
                startAttempt();
        }

        function startAttempt(): void {
            if (!allowed || errorTries >= maxErrorTries) {
                stop();
                return;
            }
            if (active)
                return;
            errorRetry.stop();
            if (root.fprintState === "error")
                root.fprintState = "";
            attemptStartedAt = 0;
            completedDuringStart = false;
            if (start())
                return;
            if (!completedDuringStart)
                scheduleErrorRetry();
        }

        function scheduleErrorRetry(): void {
            stop();
            if (!allowed)
                return;
            errorTries++;
            root.fprintState = "error";
            if (errorTries === 1)
                root.flashMsg();
            fprintStateReset.restart();
            if (errorTries < maxErrorTries)
                errorRetry.restart();
        }

        function recover(): void {
            if (!allowed)
                return;
            errorTries = 0;
            if (!active)
                startAttempt();
        }

        onAllowedChanged: {
            if (!allowed)
                stop();
            else
                Qt.callLater(checkAvail);
        }

        config: AdminPolicy.disableCustomLockPam ? "dankshell-fprint" : "fprint"
        configDirectory: AdminPolicy.disableCustomLockPam ? "/etc/pam.d" : Quickshell.shellDir + "/assets/pam"

        onPamMessage: {
            if (attemptStartedAt === 0)
                attemptStartedAt = Date.now();
        }

        onCompleted: res => {
            completedDuringStart = true;
            if (!allowed)
                return;

            switch (res) {
            case PamResult.Success:
                stop();
                passwd.abort();
                root.proceedAfterPrimaryAuth();
                return;
            case PamResult.Error:
                if (attemptSettled()) {
                    stop();
                    errorTries = 0;
                    startAttempt();
                    return;
                }
                scheduleErrorRetry();
                return;
            case PamResult.Failed:
            case PamResult.MaxTries:
                stop();
                tries++;
                errorTries = 0;
                root.fprintState = tries < SettingsData.maxFprintTries ? "fail" : "max";
                root.flashMsg();
                fprintStateReset.restart();
                startAttempt();
                return;
            }
        }
    }

    PamContext {
        id: u2f

        property bool available: SettingsData.lockU2fReady && (!AdminPolicy.disableCustomLockPam || u2fConfigWatcher.loaded)

        function checkAvail(): void {
            if (!available || !SettingsData.enableU2f || !root.lockSecured || root.u2fSuppressedByPrimaryPam) {
                abort();
                return;
            }

            if (SettingsData.u2fMode === "or")
                abort();
        }

        function startForSecondFactor(): void {
            if (!available || !SettingsData.enableU2f || root.u2fSuppressedByPrimaryPam) {
                root.completeUnlock();
                return;
            }
            abort();
            root.u2fPending = true;
            root.u2fPendingMode = "and";
            root.u2fState = "";
            u2fPendingTimeout.restart();
            start();
        }

        function startForAlternativeAuth(): void {
            if (!available || !SettingsData.enableU2f || root.u2fSuppressedByPrimaryPam || SettingsData.u2fMode !== "or" || root.unlockInProgress || root.authBusy || active)
                return;
            abort();
            root.u2fPending = true;
            root.u2fPendingMode = "or";
            root.u2fState = "";
            u2fPendingTimeout.restart();
            start();
        }

        config: {
            if (AdminPolicy.disableCustomLockPam)
                return "dankshell-u2f";
            if (root.customU2fPamActive)
                return SettingsData.lockU2fPamPath.slice(SettingsData.lockU2fPamPath.lastIndexOf("/") + 1);
            return u2fConfigWatcher.loaded ? "dankshell-u2f" : "u2f";
        }
        configDirectory: {
            if (AdminPolicy.disableCustomLockPam)
                return "/etc/pam.d";
            if (root.customU2fPamActive) {
                const idx = SettingsData.lockU2fPamPath.lastIndexOf("/");
                return idx > 0 ? SettingsData.lockU2fPamPath.slice(0, idx) : "/";
            }
            return u2fConfigWatcher.loaded ? "/etc/pam.d" : Quickshell.shellDir + "/assets/pam";
        }

        onMessageChanged: {
            if (message.toLowerCase().includes("touch"))
                root.u2fState = "waiting";
        }

        onCompleted: res => {
            if (!available || root.unlockInProgress)
                return;

            if (res === PamResult.Success) {
                root.completeUnlock();
                return;
            }

            if (res === PamResult.Error || res === PamResult.MaxTries || res === PamResult.Failed) {
                abort();

                if (root.u2fPending) {
                    if (root.u2fPendingMode === "or") {
                        root.u2fPending = false;
                        root.u2fPendingMode = "";
                        root.u2fState = root.u2fState === "waiting" ? "" : "insert";
                        u2fPendingTimeout.running = false;
                        fprint.checkAvail();
                        return;
                    }

                    if (root.u2fState === "waiting") {
                        // AND mode: device was found but auth failed → back to password
                        root.u2fPending = false;
                        root.u2fPendingMode = "";
                        root.u2fState = "";
                        fprint.checkAvail();
                    } else {
                        // AND mode: no device found → keep pending, show "Insert...", retry
                        root.u2fState = "insert";
                        u2fErrorRetry.restart();
                    }
                } else {
                    root.u2fState = "insert";
                }
            }
        }
    }

    Timer {
        id: errorRetry

        // A device wedged by a suspend mid-verify only comes back when fprintd
        // restarts, and fprintd only exits after its idle timeout with no client
        // attached, so the second retry outlasts that instead of climbing to it.
        interval: {
            if (fprint.errorTries <= 1)
                return 1500;
            if (fprint.errorTries === 2)
                return fprint.daemonIdleExitMs + 5000;
            return 60000;
        }
        onTriggered: fprint.startAttempt()
    }

    readonly property bool awaitingActivityRetry: fprint.errorTries > 0 && !fprint.retrying && !fprint.active

    function retryFprintOnActivity(): void {
        if (root.awaitingActivityRetry)
            fprint.recover();
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            fprint.recover();
        }

        function onLidOpened() {
            fprint.recover();
        }
    }

    Timer {
        id: u2fErrorRetry

        interval: 800
        onTriggered: u2f.start()
    }

    Timer {
        id: u2fPendingTimeout

        interval: 30000
        onTriggered: root.cancelU2fPending()
    }

    Timer {
        id: passwdActiveTimeout

        interval: 15000
        onTriggered: {
            if (passwd.active)
                root.recoverFromAuthStall("error");
        }
    }

    Timer {
        id: unlockRequestTimeout

        interval: 8000
        onTriggered: {
            if (root.unlockInProgress)
                root.recoverFromAuthStall("error");
        }
    }

    Timer {
        id: stateReset

        interval: 4000
        onTriggered: {
            if (root.state !== "max")
                root.state = "";
        }
    }

    Timer {
        id: fprintStateReset

        interval: 4000
        onTriggered: {
            if (root.fprintState !== "max")
                root.fprintState = "";
        }
    }

    onLockSecuredChanged: {
        if (!lockSecured) {
            root.resetAuthFlows();
            return;
        }
        root.state = "";
        root.fprintState = "";
        root.u2fState = "";
        root.u2fPending = false;
        root.u2fPendingMode = "";
        root.lockMessage = "";
        root.attemptInfoMessages = [];
        root.lockoutAnnouncedThisAttempt = false;
        root.resetAuthFlows();
        root.responseSubmitted = false;
        fprint.tries = 0;
        fprint.errorTries = 0;
        if (!SettingsData.lockPamExternallyManaged && !dankshellConfigWatcher.loaded && !userPamWatcher.loaded)
            ensureUserPamConfig();
        // FileView cannot watch a path that does not exist yet; re-read so a
        // dedicated service created after startup is used on the next lock.
        u2fConfigWatcher.reload();
        fprint.checkAvail();
        u2f.checkAvail();
    }

    Connections {
        target: SettingsData

        function onEnableFprintChanged(): void {
            if (SettingsData.enableFprint)
                fprint.recover();
            else
                fprint.checkAvail();
        }

        function onLockFingerprintReadyChanged(): void {
            if (SettingsData.lockFingerprintReady)
                fprint.recover();
            else
                fprint.checkAvail();
        }

        function onEnableU2fChanged(): void {
            u2f.checkAvail();
        }

        function onLockU2fReadyChanged(): void {
            u2f.checkAvail();
        }

        function onLockPamPathChanged(): void {
            fprint.checkAvail();
            u2f.checkAvail();
        }

        function onLockPamInlineFprintChanged(): void {
            fprint.checkAvail();
        }

        function onLockPamInlineU2fChanged(): void {
            u2f.checkAvail();
        }

        function onLockPamExternallyManagedChanged(): void {
            if (AdminPolicy.disableCustomLockPam)
                return;
            root.resetAuthFlows();
            if (!SettingsData.lockPamExternallyManaged)
                root.ensureUserPamConfig();
            fprint.checkAvail();
            u2f.checkAvail();
        }

        function onLockU2fPamPathChanged(): void {
            if (AdminPolicy.disableCustomLockPam)
                return;
            u2f.abort();
            u2f.checkAvail();
        }

        function onU2fModeChanged(): void {
            if (root.lockSecured) {
                u2f.abort();
                u2fErrorRetry.running = false;
                u2fPendingTimeout.running = false;
                unlockRequestTimeout.running = false;
                root.u2fPending = false;
                root.u2fPendingMode = "";
                root.u2fState = "";
                u2f.checkAvail();
            }
        }
    }
}
