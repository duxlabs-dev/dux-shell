pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Common.settings

Singleton {
    id: root

    readonly property int levelInfo: 0
    readonly property int levelWarn: 1
    readonly property int levelError: 2
    property string currentMessage: ""
    property int currentLevel: levelInfo
    property bool toastVisible: false
    property var toastQueue: []
    property string currentDetails: ""
    property string currentCommand: ""
    property bool hasDetails: false
    property string wallpaperErrorStatus: ""
    property int maxQueueSize: 3
    property var lastErrorTime: ({})
    property int errorThrottleMs: 1000
    property string currentCategory: ""
    readonly property var stickyCategories: ["greeter-autologin-sync"]

    function isStickyCategory(category) {
        return category && stickyCategories.indexOf(category) >= 0;
    }

    function showToast(message, level = levelInfo, details = "", command = "", category = "") {
        const now = Date.now();
        const messageKey = message + level;

        if (level === levelError) {
            const lastTime = lastErrorTime[messageKey] || 0;
            if (now - lastTime < errorThrottleMs) {
                return;
            }
            lastErrorTime[messageKey] = now;
        }

        if (category && level === levelError) {
            if (currentCategory === category && toastVisible && currentLevel === levelError) {
                currentMessage = message;
                currentDetails = details || "";
                currentCommand = command || "";
                hasDetails = currentDetails.length > 0 || currentCommand.length > 0;
                resetToastState();
                if (hasDetails) {
                    toastTimer.interval = Timing.holdExtraLong;
                } else {
                    toastTimer.interval = Timing.holdLong;
                }
                toastTimer.restart();
                return;
            }

            toastQueue = toastQueue.filter(t => t.category !== category);
        }

        const isDuplicate = toastQueue.some(toast => toast.message === message && toast.level === level);
        if (isDuplicate) {
            return;
        }

        if (toastQueue.length >= maxQueueSize) {
            if (level === levelError) {
                toastQueue = toastQueue.filter(t => t.level !== levelError).slice(0, maxQueueSize - 1);
            } else {
                return;
            }
        }

        toastQueue.push({
            "message": message,
            "level": level,
            "details": details,
            "command": command,
            "category": category
        });
        if (!toastVisible) {
            processQueue();
        }
    }

    function showInfo(message, details = "", command = "", category = "") {
        showToast(message, levelInfo, details, command, category);
    }

    function showWarning(message, details = "", command = "", category = "") {
        showToast(message, levelWarn, details, command, category);
    }

    function showError(message, details = "", command = "", category = "") {
        showToast(message, levelError, details, command, category);
    }

    function dismissCategory(category) {
        if (!category) {
            return;
        }

        if (currentCategory === category && toastVisible) {
            hideToast();
            return;
        }

        toastQueue = toastQueue.filter(t => t.category !== category);
    }

    function hideToast() {
        toastVisible = false;
        currentMessage = "";
        currentDetails = "";
        currentCommand = "";
        currentCategory = "";
        hasDetails = false;
        currentLevel = levelInfo;
        toastTimer.stop();
        resetToastState();
        if (toastQueue.length > 0) {
            processQueue();
        }
    }

    function processQueue() {
        if (toastQueue.length === 0) {
            return;
        }

        const toast = toastQueue.shift();
        currentMessage = toast.message;
        currentLevel = toast.level;
        currentDetails = toast.details || "";
        currentCommand = toast.command || "";
        currentCategory = toast.category || "";
        hasDetails = currentDetails.length > 0 || currentCommand.length > 0;
        toastVisible = true;
        resetToastState();

        if (isStickyCategory(toast.category)) {
            toastTimer.stop();
        } else if (toast.level === levelError && hasDetails) {
            toastTimer.interval = Timing.holdExtraLong;
            toastTimer.start();
        } else {
            toastTimer.interval = toast.level === levelError ? Timing.holdLong : toast.level === levelWarn ? Timing.holdMedium : Timing.holdShort;
            toastTimer.start();
        }
    }

    signal resetToastState

    function stopTimer() {
        toastTimer.stop();
    }

    function restartTimer() {
        if (isStickyCategory(currentCategory)) {
            return;
        }
        if (hasDetails && currentLevel === levelError) {
            toastTimer.interval = Timing.holdExtraLong;
            toastTimer.restart();
        }
    }

    function clearWallpaperError() {
        wallpaperErrorStatus = "";
    }

    Timer {
        id: toastTimer

        interval: Timing.holdLong
        running: false
        repeat: false
        onTriggered: hideToast()
    }

    Connections {
        target: SessionData

        function onLoadErrorOccurred(file, message) {
            root.showError(I18n.tr("Failed to parse %1").arg(file), message);
        }
    }

    Connections {
        target: Processes

        function onToastRequested(severity, title, body, command, category) {
            switch (severity) {
            case root.levelWarn:
                root.showWarning(title, body, command, category);
                break;
            case root.levelError:
                root.showError(title, body, command, category);
                break;
            default:
                root.showInfo(title, body, command, category);
                break;
            }
        }

        function onToastCategoryDismissed(category) {
            root.dismissCategory(category);
        }
    }
}
