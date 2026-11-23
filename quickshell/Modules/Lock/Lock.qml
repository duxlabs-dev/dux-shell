pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import "../../Common/LockTransitionState.js" as LockTransitionState

Scope {
    id: root

    readonly property var log: Log.scoped("Lock")

    property string sharedPasswordBuffer: ""
    property bool inputRevealed: false
    property bool shouldLock: false

    onSharedPasswordBufferChanged: {
        if (!powerOffFadeTimer.running)
            return;
        cancelPowerOffFade();
    }

    onShouldLockChanged: {
        inputRevealed = false;
        IdleService.isShellLocked = shouldLock;
    }

    property bool lockInitiatedLocally: false
    property bool pendingLock: false
    property bool externalUnlockPending: false
    property bool securePending: false
    property bool lockPendingDuringReveal: false
    property var savedLockWorkspaces: ({})
    property var targetLockWorkspaces: ({})
    readonly property int maxLockRetries: 3
    property int lockRetryAttempts: 0
    property bool lockRetryPending: false
    property bool lockPowerOffArmed: false
    property bool customLockerSpawned: false
    readonly property bool powerOffOnLock: SettingsData.lockScreenPowerOffMonitorsOnLock || IdleService.lockPowerOffRequested
    property real powerOffFadeTarget: 0
    property bool powerOffFadeInstant: false

    function beginPowerOff() {
        if (!SettingsData.fadeToDpmsEnabled || SettingsData.fadeToDpmsGracePeriod <= 0) {
            applyMonitorsOff();
            return;
        }
        powerOffFadeInstant = false;
        powerOffFadeTarget = 1;
        powerOffFadeTimer.restart();
    }

    function applyMonitorsOff() {
        IdleService.monitorsOff = true;
        CompositorService.powerOffMonitors();
        dpmsReapplyTimer.start();
    }

    function resetPowerOffFade() {
        powerOffFadeTimer.stop();
        powerOffFadeInstant = true;
        powerOffFadeTarget = 0;
    }

    function cancelPowerOffFade() {
        resetPowerOffFade();
        IdleService.lockPowerOffRequested = false;
    }

    // Avoid startup lock when using dms-greeter (#2952)
    function freshGreeterLogin() {
        const authTime = Number(Quickshell.env("DMS_GREETER_AUTH_TIME") || 0);
        if (!authTime)
            return false;
        return (Date.now() / 1000 - authTime) < 120;
    }

    function setLockPhase(event) {
        IdleService.lockTransitionPhase = LockTransitionState.next(IdleService.lockTransitionPhase, event, SettingsData.fadeToLockEnabled);
    }

    function applySecureUi() {
        setLockPhase("secure");
        IdleService.lockUiVisible = true;
    }

    function clearWorkspaceTransitionState() {
        lockWorkspaceTimer.stop();
        savedLockWorkspaces = ({});
        targetLockWorkspaces = ({});
    }

    function captureWorkspaceStates() {
        clearWorkspaceTransitionState();
        for (var screen of Quickshell.screens) {
            var result = CompositorService.captureLockWorkspace(screen.name);
            if (!result) {
                clearWorkspaceTransitionState();
                return false;
            }
            log.debug("[LockWorkspace] captured screen", screen.name, "id", result.workspaceRecord.id, "name", result.workspaceRecord.name, "output", result.workspaceRecord.output, "key", result.workspaceKey);
            savedLockWorkspaces[screen.name] = result;
        }
        if (Object.keys(savedLockWorkspaces).length === 0) {
            clearWorkspaceTransitionState();
            return false;
        }
        return true;
    }

    function switchToLockWorkspaces() {
        var reservedTargets = [];
        var resolvedTargets = ({});

        // Resolve every screen before dispatch: a later screen with no safe
        // target must not leave earlier screens switched away from their workspaces.
        for (var name of Object.keys(savedLockWorkspaces)) {
            var state = savedLockWorkspaces[name];
            var target = CompositorService.findLockWorkspaceTarget(name, state, reservedTargets);
            if (!target) {
                reservedTargets = [];
                resolvedTargets = ({});
                clearWorkspaceTransitionState();
                return false;
            }
            resolvedTargets[name] = target;
        }

        var switchedNames = [];
        for (var name of Object.keys(savedLockWorkspaces)) {
            var resolved = resolvedTargets[name];
            log.debug("[LockWorkspace] switching screen", name, "target id", resolved.id, "name", resolved.name, "output", resolved.output);
            var switched = CompositorService.switchToLockWorkspace(resolved, name);
            log.debug("[LockWorkspace] switch result", name, switched);
            if (!switched) {
                for (var i = switchedNames.length - 1; i >= 0; i--) {
                    var rollbackName = switchedNames[i];
                    log.debug("[LockWorkspace] rollback screen", rollbackName);
                    CompositorService.restoreLockWorkspace(savedLockWorkspaces[rollbackName]);
                }
                clearWorkspaceTransitionState();
                return false;
            }
            switchedNames.push(name);
        }

        targetLockWorkspaces = resolvedTargets;
        return true;
    }

    function restoreLockWorkspaces() {
        if (Object.keys(savedLockWorkspaces).length === 0) {
            return false;
        }
        for (var name of Object.keys(savedLockWorkspaces)) {
            var savedState = savedLockWorkspaces[name];
            log.debug("[LockWorkspace] restoring screen", name, "saved id", savedState.workspaceRecord.id, "name", savedState.workspaceRecord.name, "output", savedState.workspaceRecord.output, "key", savedState.workspaceKey);
            var restored = CompositorService.restoreLockWorkspace(savedState);
            log.debug("[LockWorkspace] restore result", name, restored);
            if (!restored) {
                clearWorkspaceTransitionState();
                return false;
            }
        }
        clearWorkspaceTransitionState();
        return true;
    }

    function finishWorkspaceMove() {
        lockWorkspaceTimer.stop();
        setLockPhase("workspaceMoved");
        if (externalUnlockPending) {
            externalUnlockPending = false;
            lockWorkspaceTimer.stop();
            completeExternalUnlock();
            return;
        }
        if (securePending) {
            securePending = false;
            if (IdleService.lockTransitionPhase === "securingLock")
                applySecureUi();
        }
        if (lockInitiatedLocally)
            notifyLoginctl(true);
        if (!pendingLock)
            shouldLock = true;
    }

    function completeExternalUnlock() {
        lockWorkspaceTimer.stop();
        shouldLock = false;
        pendingLock = false;
        lockInitiatedLocally = false;
        setLockPhase("externalUnlock");
        if (restoreLockWorkspaces()) {
            setLockPhase("workspaceRestored");
        } else {
            setLockPhase("workspaceUnavailable");
        }
        IdleService.showChrome(finishChromeReveal);
        externalUnlockPending = false;
        securePending = false;
    }

    function finishChromeReveal() {
        setLockPhase("chromeShown");
        if (lockPendingDuringReveal) {
            lockPendingDuringReveal = false;
            lock();
        }
    }

    function closeTransientUi() {
        PopoutManager.closeAllPopouts();
        ModalManager.closeAllModalsExcept(null);
        TrayMenuManager.closeAllMenus();
        NotificationService.dismissAllPopups();
    }

    function beginLockTransition(externallyInitiated) {
        if (SettingsData.customPowerActionLock?.length > 0) {
            spawnCustomLocker();
            return;
        }
        if (IdleService.lockTransitionPhase === "revealingChrome") {
            lockPendingDuringReveal = true;
            return;
        }
        if (shouldLock || pendingLock || IdleService.lockTransitionPhase !== "idle")
            return;

        resetLockRetry();
        lockInitiatedLocally = !externallyInitiated;
        lockPowerOffArmed = powerOffOnLock;

        if (!SessionService.active && SessionService.loginctlAvailable && SettingsData.loginctlLockIntegration)
            pendingLock = true;

        setLockPhase("lockRequested");
        if (SettingsData.fadeToLockEnabled) {
            IdleService.fadeToLockRequested();
            closeTransientUi();
            IdleService.hideChrome(finishChromeHidden);
            return;
        }

        if (!externallyInitiated)
            notifyLoginctl(true);
        if (!pendingLock)
            shouldLock = true;
    }

    function finishChromeHidden() {
        if (IdleService.lockTransitionPhase !== "hidingChrome")
            return;
        IdleService.dismissFadeToLock();
        if (captureWorkspaceStates() && switchToLockWorkspaces()) {
            setLockPhase("chromeHidden");
            if (Theme.reduceMotion) {
                finishWorkspaceMove();
            } else {
                lockWorkspaceTimer.start();
            }
        } else {
            setLockPhase("workspaceUnavailable");
            if (lockInitiatedLocally)
                notifyLoginctl(true);
            if (!pendingLock)
                shouldLock = true;
        }
    }

    function cancelLockTransition() {
        clearWorkspaceTransitionState();
        pendingLock = false;
        lockInitiatedLocally = false;
        securePending = false;
        IdleService.cancelChromeFade();
        IdleService.lockUiVisible = false;
        setLockPhase("reset");
        IdleService.dismissFadeToLock();
    }

    function finishUnlockFade() {
        if (IdleService.lockTransitionPhase !== "fadingLockUi")
            return;
        log.debug("[LockWorkspace] finishUnlockFade phase", IdleService.lockTransitionPhase, "saved keys", Object.keys(savedLockWorkspaces), "lockInitiatedLocally", lockInitiatedLocally, "shouldLock", shouldLock);
        shouldLock = false;
        setLockPhase("lockUiFadedOut");
        notifyLoginctl(false);
        if (restoreLockWorkspaces()) {
            setLockPhase("workspaceRestored");
        } else {
            setLockPhase("workspaceUnavailable");
        }
        lockInitiatedLocally = false;
        securePending = false;
        IdleService.showChrome(finishChromeReveal);
    }

    function resetTransition() {
        clearWorkspaceTransitionState();
        externalUnlockPending = false;
        securePending = false;
        lockPendingDuringReveal = false;
        IdleService.resetChrome();
        IdleService.lockUiVisible = false;
        setLockPhase("reset");
        IdleService.dismissFadeToLock();
    }

    Component.onCompleted: {
        IdleService.lockComponent = this;
        IdleService.isSessionLockSecure = sessionLock.secure;
        if (SettingsData.lockAtStartup && !freshGreeterLogin()) {
            lock();
            return;
        }
        // A shell restarted into a locked session: after a logind Unlock
        // ignored for a lock it started, only lockedHint still says locked,
        // and the state can arrive before this module's Connections exist.
        if (SessionService.locked || SessionService.lockedHint)
            followLoginctlLock();
    }

    function notifyLockedHint(locked: bool) {
        if (!SettingsData.loginctlLockIntegration || !DMSService.isConnected)
            return;
        DMSService.setLockedHint(locked, () => {});
    }

    function notifyLoginctl(lockAction: bool) {
        if (!SettingsData.loginctlLockIntegration || !DMSService.isConnected)
            return;
        if (lockAction)
            DMSService.lockSession(() => {});
        else
            DMSService.unlockSession(() => {});
    }

    function spawnCustomLocker() {
        clearWorkspaceTransitionState();
        log.info("Handing the lock to the custom lock command instead of the session lock");
        IdleService.lockPowerOffRequested = false;
        Quickshell.execDetached(["sh", "-c", SettingsData.customPowerActionLock]);
        // The custom locker manages its own surface; DMS never engages
        // WlSessionLock here, so isShellLocked stays false and the fade
        // overlay would never be dismissed. Hand off by dismissing it now.
        IdleService.dismissFadeToLock();
        customLockerSpawned = true;
        resetTransition();
    }

    function handleLoginctlCustomLock(): bool {
        if (!(SettingsData.customPowerActionLock?.length > 0))
            return false;
        if (!customLockerSpawned)
            spawnCustomLocker();
        return true;
    }

    function followLoginctlLock() {
        if (shouldLock || pendingLock)
            return;
        if (handleLoginctlCustomLock())
            return;
        beginLockTransition(true);
    }

    function resetLockRetry() {
        lockRetryAttempts = 0;
        lockRetryPending = false;
        lockRetryTimer.stop();
    }

    function handleLockLost() {
        if (lockRetryAttempts >= maxLockRetries) {
            log.error("Compositor refused session lock", maxLockRetries, "times - resetting lock state");
            forceReset();
            return;
        }
        lockRetryAttempts++;
        lockRetryPending = true;
        lockRetryTimer.restart();
        log.warn("Session lock lost while lock requested - retry", lockRetryAttempts, "/", maxLockRetries);
    }

    function lock() {
        beginLockTransition();
    }

    function lockAndOutputsOff() {
        IdleService.lockPowerOffRequested = true;
        if (sessionLock.secure) {
            beginPowerOff();
            return;
        }
        beginLockTransition();
    }

    function unlock() {
        if (!shouldLock)
            return;
        if (IdleService.lockTransitionPhase === "fadingLockUi") {
            log.debug("[LockWorkspace] unlock ignored during fade", "phase", IdleService.lockTransitionPhase);
            return;
        }
        resetLockRetry();

        if (SettingsData.fadeToLockEnabled && IdleService.lockTransitionPhase === "lockVisible") {
            setLockPhase("unlockRequested");
            IdleService.lockUiVisible = false;
            if (Theme.reduceMotion)
                finishUnlockFade();
            return;
        }

        if (IdleService.lockTransitionPhase !== "idle")
            resetTransition();

        notifyLoginctl(false);
        shouldLock = false;
    }

    function forceReset() {
        lockInitiatedLocally = false;
        pendingLock = false;
        shouldLock = false;
        customLockerSpawned = false;
        resetLockRetry();
        resetPowerOffFade();
        IdleService.lockPowerOffRequested = false;
        resetTransition();
    }

    function activate() {
        lock();
    }

    Connections {
        target: SessionService

        function onSessionLocked() {
            root.followLoginctlLock();
        }

        function onSessionUnlocked() {
            customLockerSpawned = false;
            log.debug("[LockWorkspace] onSessionUnlocked phase", IdleService.lockTransitionPhase, "pendingLock", pendingLock, "shouldLock", shouldLock, "lockInitiatedLocally", lockInitiatedLocally, "saved keys", Object.keys(savedLockWorkspaces));
            if (AdminPolicy.disableLogindUnlock)
                return;
            if (pendingLock) {
                pendingLock = false;
                lockInitiatedLocally = false;
            }
            switch (IdleService.lockTransitionPhase) {
            case "fadingLockUi":
            case "restoringWorkspaces":
            case "revealingChrome":
                return;
            }
            if (lockInitiatedLocally)
                return;
            switch (IdleService.lockTransitionPhase) {
            case "movingWorkspaces":
            case "securingLock":
                if (lockWorkspaceTimer.running)
                    externalUnlockPending = true;
                completeExternalUnlock();
                return;
            case "lockVisible":
                completeExternalUnlock();
                return;
            default:
                resetTransition();
                return;
            }
        }

        function onSessionResumed() {
            if (!shouldLock || sessionLock.locked)
                return;
            resumeRelockTimer.restart();
        }

        function onLockEditorRequested() {
            if (shouldLock)
                return;
            demoWindow.showDemo();
        }

        function onGreeterEditorRequested() {
            if (shouldLock)
                return;
            demoWindow.showDemo(true);
        }

        function onLoginctlStateChanged() {
            if (!SessionService.active || !pendingLock)
                return;
            if (IdleService.lockTransitionPhase === "hidingChrome") {
                pendingLock = false;
                return;
            }
            if (IdleService.lockTransitionPhase === "securingLock") {
                pendingLock = false;
                shouldLock = true;
                return;
            }
            pendingLock = false;
            lockInitiatedLocally = true;
            lockPowerOffArmed = powerOffOnLock;
            shouldLock = true;
        }
    }

    Connections {
        target: IdleService

        function onLockRequested() {
            beginLockTransition();
        }

        function onCancelFadeToLock() {
            log.debug("[LockWorkspace] cancelFadeToLock phase", IdleService.lockTransitionPhase,
                "shouldLock", shouldLock, "secure", sessionLock.secure,
                "saved keys", Object.keys(savedLockWorkspaces));
            if (sessionLock.secure
                || IdleService.lockTransitionPhase === "movingWorkspaces"
                || (IdleService.lockTransitionPhase === "securingLock" && Object.keys(savedLockWorkspaces).length > 0)
                || IdleService.lockTransitionPhase === "fadingLockUi"
                || IdleService.lockTransitionPhase === "restoringWorkspaces"
                || IdleService.lockTransitionPhase === "revealingChrome") {
                log.debug("[LockWorkspace] cancelFadeToLock ignored", IdleService.lockTransitionPhase,
                    "secure", sessionLock.secure, "saved keys", Object.keys(savedLockWorkspaces));
                return;
            }
            cancelLockTransition();
        }

        function onMonitorsOffChanged() {
            if (!IdleService.monitorsOff)
                root.resetPowerOffFade();
        }
    }

    Pam {
        id: sharedPam
        lockSecured: root.shouldLock && sessionLock.secure
        buffer: root.sharedPasswordBuffer
        onUnlockRequested: root.unlock()
    }

    WlSessionLock {
        id: sessionLock

        locked: shouldLock && !lockRetryPending

        WlSessionLockSurface {
            id: lockSurface

            property string currentScreenName: screen?.name ?? ""
            property bool isActiveScreen: {
                if (Quickshell.screens.length <= 1)
                    return true;
                const screens = SettingsData.getFilteredScreens("lockScreen");
                return screens.length === 0 || screens.includes(screen);
            }

            color: isActiveScreen ? "transparent" : SettingsData.lockScreenInactiveColor

            LockSurface {
                anchors.fill: parent
                visible: lockSurface.isActiveScreen
                lock: sessionLock
                pam: sharedPam
                sharedPasswordBuffer: root.sharedPasswordBuffer
                inputRevealed: root.inputRevealed
                onInputRevealRequested: revealed => root.inputRevealed = revealed
                screenName: lockSurface.currentScreenName
                isLocked: shouldLock
                lockUiVisible: IdleService.lockUiVisible
                onUnlockRequested: root.unlock()
                onLockUiFadeFinished: root.finishUnlockFade()
                onPasswordChanged: newPassword => {
                    root.sharedPasswordBuffer = newPassword;
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: root.powerOffFadeTarget
                visible: opacity > 0 || powerOffFadeTimer.running

                Behavior on opacity {
                    enabled: !root.powerOffFadeInstant
                    NumberAnimation {
                        duration: SettingsData.fadeToDpmsGracePeriod * 1000
                        easing.type: Easing.OutCubic
                    }
                }

                MouseArea {
                    property real baselineX: -1
                    property real baselineY: -1

                    anchors.fill: parent
                    enabled: powerOffFadeTimer.running
                    hoverEnabled: enabled
                    onEnabledChanged: {
                        baselineX = -1;
                        baselineY = -1;
                    }
                    onPressed: root.cancelPowerOffFade()
                    onWheel: root.cancelPowerOffFade()
                    onPositionChanged: mouse => {
                        if (baselineX < 0) {
                            baselineX = mouse.x;
                            baselineY = mouse.y;
                            return;
                        }
                        if (Math.abs(mouse.x - baselineX) < 5 && Math.abs(mouse.y - baselineY) < 5)
                            return;
                        root.cancelPowerOffFade();
                    }
                }
            }
        }
    }

    Connections {
        target: sessionLock

        function onSecureChanged() {
            log.debug("[LockWorkspace] onSecureChanged secure", sessionLock.secure, "phase", IdleService.lockTransitionPhase);
            IdleService.isSessionLockSecure = sessionLock.secure;
            notifyLockedHint(sessionLock.secure);
            if (!sessionLock.secure)
                return;
            SessionService.onSessionLockSecured();
            IdleService.dismissFadeToLock();
            lockRetryAttempts = 0;
            pendingLock = false;
            if (lockPowerOffArmed && powerOffOnLock)
                beginPowerOff();
            lockPowerOffArmed = false;
            if (IdleService.lockTransitionPhase === "securingLock") {
                applySecureUi();
            } else {
                securePending = true;
            }
        }

        function onLockedChanged() {
            if (sessionLock.locked)
                return;
            if (shouldLock && (IdleService.monitorsOff || lockPowerOffArmed || IdleService.lockPowerOffRequested))
                return;
            resetPowerOffFade();
            if (IdleService.monitorsOff) {
                IdleService.monitorsOff = false;
                CompositorService.powerOnMonitors();
            }
            IdleService.lockPowerOffRequested = false;
            if (shouldLock && !lockRetryPending)
                handleLockLost();
        }
    }

    LockScreenDemo {
        id: demoWindow
    }

    IpcHandler {
        target: "lock"

        function lock() {
            root.lock();
        }

        function lockAndOutputsOff() {
            root.lockAndOutputsOff();
        }

        function unlock() {
            if (AdminPolicy.disableLockIpcUnlock)
                return;
            root.unlock();
        }

        function forceReset() {
            if (AdminPolicy.disableLockIpcUnlock)
                return;
            root.forceReset();
        }

        function demo() {
            if (AdminPolicy.disableLockIpcUnlock)
                return;
            demoWindow.showDemo();
        }

        function isLocked(): bool {
            return sessionLock.secure;
        }

        function status(): string {
            return JSON.stringify({
                shouldLock: root.shouldLock,
                sessionLockLocked: sessionLock.locked,
                sessionLockSecure: sessionLock.secure,
                lockRetryAttempts: root.lockRetryAttempts,
                lockInitiatedLocally: root.lockInitiatedLocally,
                pendingLock: root.pendingLock,
                customLocker: SettingsData.customPowerActionLock?.length > 0,
                customLockerSpawned: root.customLockerSpawned,
                loginctlLocked: SessionService.locked,
                loginctlActive: SessionService.active
            });
        }
    }

    Timer {
        id: powerOffFadeTimer
        interval: SettingsData.fadeToDpmsGracePeriod * 1000
        repeat: false
        onTriggered: root.applyMonitorsOff()
    }

    Timer {
        id: lockWorkspaceTimer
        interval: Theme.expressiveDurations.expressiveEffects
        repeat: false
        onTriggered: root.finishWorkspaceMove()
    }

    IdleMonitor {
        timeout: 1
        respectInhibitors: false
        enabled: powerOffFadeTimer.running
        onIsIdleChanged: {
            if (isIdle)
                return;
            if (!powerOffFadeTimer.running)
                return;
            root.cancelPowerOffFade();
        }
    }

    Timer {
        id: lockRetryTimer
        interval: Timing.settleSlow
        repeat: false
        onTriggered: root.lockRetryPending = false
    }

    Timer {
        id: resumeRelockTimer
        interval: Timing.settleSlow
        repeat: false
        onTriggered: {
            if (!root.shouldLock || sessionLock.locked)
                return;
            if (IdleService.monitorsOff || root.lockPowerOffArmed || IdleService.lockPowerOffRequested)
                return;
            root.log.warn("Session lock dead after resume - re-locking");
            root.resetLockRetry();
            root.lockRetryPending = true;
            root.lockRetryPending = false;
        }
    }

    Timer {
        id: dpmsReapplyTimer
        interval: Timing.settleShort
        repeat: false
        onTriggered: IdleService.reapplyDpmsIfNeeded()
    }
}
