.pragma library

// Lock.qml writes phases through IdleService; this library only computes transitions.
const IDLE = "idle";
const SECURING_LOCK = "securingLock";
const RESTORING_WORKSPACES = "restoringWorkspaces";
const LOCK_VISIBLE = "lockVisible";
const FADING_LOCK_UI = "fadingLockUi";
const REVEALING_CHROME = "revealingChrome";

const LOCK_REQUESTED = "lockRequested";
const SECURE = "secure";
const UNLOCK_REQUESTED = "unlockRequested";
const LOCK_UI_FADED_OUT = "lockUiFadedOut";
const CHROME_SHOWN = "chromeShown";
const EXTERNAL_UNLOCK = "externalUnlock";
const WORKSPACE_MOVED = "workspaceMoved";
const WORKSPACE_UNAVAILABLE = "workspaceUnavailable";
const WORKSPACE_RESTORED = "workspaceRestored";
const RESET = "reset";

// The gate is deliberately narrow: reduced motion still needs session lock and restore.
function next(phase, event, transitionEnabled) {
    switch (phase) {
        case IDLE:
            if (event === LOCK_REQUESTED)
                return SECURING_LOCK;
            return IDLE;
        case SECURING_LOCK:
            if (event === SECURE) return LOCK_VISIBLE;
            if (event === EXTERNAL_UNLOCK) return RESTORING_WORKSPACES;
            if (event === RESET) return IDLE;
            return SECURING_LOCK;
        case LOCK_VISIBLE:
            if (event === UNLOCK_REQUESTED) return FADING_LOCK_UI;
            if (event === EXTERNAL_UNLOCK) return RESTORING_WORKSPACES;
            if (event === RESET) return IDLE;
            return LOCK_VISIBLE;
        case FADING_LOCK_UI:
            if (event === LOCK_UI_FADED_OUT) return RESTORING_WORKSPACES;
            if (event === EXTERNAL_UNLOCK) return RESTORING_WORKSPACES;
            if (event === RESET) return IDLE;
            return FADING_LOCK_UI;
        case RESTORING_WORKSPACES:
            if (event === WORKSPACE_RESTORED) return REVEALING_CHROME;
            if (event === WORKSPACE_UNAVAILABLE) return REVEALING_CHROME;
            if (event === RESET) return IDLE;
            return RESTORING_WORKSPACES;
        case REVEALING_CHROME:
            if (event === CHROME_SHOWN || event === RESET) return IDLE;
            return REVEALING_CHROME;
        default:
            return phase;
    }
}

// Releasing the lock before the UI finishes fading would expose the desktop behind it.
function shouldKeepSessionLocked(phase) {
    return phase === SECURING_LOCK || phase === LOCK_VISIBLE || phase === FADING_LOCK_UI;
}

// Drawing the UI before the lock is secure would flash it over the live desktop.
function shouldShowLockUi(phase) {
    return phase === LOCK_VISIBLE;
}

function shouldHoldInputSurface(phase) {
    return false;
}
