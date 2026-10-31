pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

Singleton {
    id: root

    property bool cyclingActive: false
    property bool _lastPushedEnabled: true
    readonly property bool fullscreenShowing: {
        if (!cyclingActive || !ToplevelManager.toplevels?.values)
            return false;
        for (const toplevel of ToplevelManager.toplevels.values) {
            if (toplevel.fullscreen && toplevel.activated)
                return true;
        }
        return false;
    }
    readonly property bool shouldPauseCycling: fullscreenShowing || SessionService.locked
    readonly property bool serverSchedulingAvailable: DMSService.capabilities.includes("wallpaper")
    property real lastCycleSeq: -1
    property var monitorProcesses: ({})

    Connections {
        target: DMSService

        function onWallpaperCycleUpdate(data) {
            if (!data)
                return;
            const seq = data.cycleSeq || 0;
            if (lastCycleSeq < 0) {
                lastCycleSeq = seq;
                return;
            }
            if (seq <= lastCycleSeq)
                return;
            lastCycleSeq = seq;
            if (shouldPauseCycling)
                return;
            const target = data.target || "";
            if (target === "") {
                cycleToNextWallpaper();
            } else {
                cycleNextForMonitor(target);
            }
        }

        function onCapabilitiesReceived() {
            lastCycleSeq = -1;
            _lastPushedEnabled = true;
            updateCyclingState();
        }
    }

    Connections {
        target: SessionData

        function onWallpaperCyclingEnabledChanged() {
            updateCyclingState();
        }

        function onWallpaperCyclingModeChanged() {
            updateCyclingState();
        }

        function onWallpaperCyclingOnLoginChanged() {
            updateCyclingState();
        }

        function onWallpaperCyclingIntervalChanged() {
            updateCyclingState();
        }

        function onWallpaperCyclingTimeChanged() {
            updateCyclingState();
        }

        function onPerMonitorWallpaperChanged() {
            updateCyclingState();
        }

        function onMonitorCyclingSettingsChanged() {
            updateCyclingState();
        }
    }

    Connections {
        target: SessionService

        function onSessionUnlocked() {
            updateCyclingState();
        }
    }

    // Created late from the async DMSShell loader, after loaded and capabilitiesReceived may have fired.
    Component.onCompleted: {
        if (SessionData._hasLoaded)
            updateCyclingState();
    }

    function updateCyclingState() {
        cyclingActive = serverSchedulingAvailable && (SessionData.wallpaperCyclingEnabled || SessionData.wallpaperCyclingOnLogin || SessionData.perMonitorWallpaper);
        if (!cyclingActive && !_lastPushedEnabled)
            return;
        _lastPushedEnabled = cyclingActive;
        pushConfigToServer();
    }

    function buildServerConfig() {
        var monitors = {};
        if (SessionData.perMonitorWallpaper && typeof Quickshell !== "undefined") {
            var screens = Quickshell.screens;
            for (var i = 0; i < screens.length; i++) {
                var name = screens[i].name;
                var s = SessionData.getMonitorCyclingSettings(name);
                var wp = SessionData.getMonitorWallpaper(name);
                // A folder is enough to run the schedule, so on-login can pick from it
                // without a wallpaper being pinned first.
                var hasSource = (wp && !wp.startsWith("#")) || !!s.folderPath;
                monitors[name] = {
                    "enabled": !!((s.enabled || s.onLogin) && hasSource),
                    "mode": s.mode || "interval",
                    "intervalSec": s.interval || 300,
                    "time": s.time || "06:00",
                    "onLogin": !!s.onLogin
                };
            }
        }
        const globalHasSource = (SessionData.wallpaperPath && !SessionData.wallpaperPath.startsWith("#")) || !!SessionData.wallpaperCyclingFolderPath;
        return {
            "perMonitor": SessionData.perMonitorWallpaper,
            "global": {
                "enabled": !!((SessionData.wallpaperCyclingEnabled || SessionData.wallpaperCyclingOnLogin) && globalHasSource),
                "mode": SessionData.wallpaperCyclingMode,
                "intervalSec": SessionData.wallpaperCyclingInterval,
                "time": SessionData.wallpaperCyclingTime,
                "onLogin": !!SessionData.wallpaperCyclingOnLogin
            },
            "monitors": monitors
        };
    }

    function pushConfigToServer() {
        if (!serverSchedulingAvailable)
            return;
        DMSService.sendRequest("wallpaper.setConfig", {
            "config": buildServerConfig()
        }, null);
    }

    function findCommand(wallpaperDir, recursive) {
        const depthArg = recursive ? "" : "-maxdepth 1 ";
        return ["sh", "-c", `find -L "${wallpaperDir}" ${depthArg}-type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.bmp" -o -iname "*.gif" -o -iname "*.webp" -o -iname "*.jxl" -o -iname "*.avif" -o -iname "*.heif" -o -iname "*.exr" -o -iname "*.svg" \\) 2>/dev/null | sort`];
    }

    function monitorProcessFor(screenName) {
        var process = monitorProcesses[screenName];
        if (process)
            return process;
        var newProcesses = Object.assign({}, monitorProcesses);
        process = monitorProcessComponent.createObject(root);
        newProcesses[screenName] = process;
        monitorProcesses = newProcesses;
        return process;
    }
    function cycle(screenName, wallpaperPath, goToPrevious) {
        const currentWallpaper = wallpaperPath || (screenName ? SessionData.getMonitorWallpaper(screenName) : SessionData.wallpaperPath);
        if (!currentWallpaper || currentWallpaper.startsWith("#")) {
            // No wallpaper pinned yet (e.g. first change-on-login): pick from the configured folder.
            const folderPath = screenName ? SessionData.getMonitorCyclingSettings(screenName).folderPath : SessionData.wallpaperCyclingFolderPath;
            if (folderPath)
                cycleFromFolder(screenName, folderPath);
            return;
        }
        let wallpaperDir;
        let recursive = false;

        if (screenName) {
            const monitorSettings = SessionData.getMonitorCyclingSettings(screenName);
            recursive = !!monitorSettings.recursive;
            if (monitorSettings.folderPath && currentWallpaper.startsWith(monitorSettings.folderPath + "/")) {
                wallpaperDir = monitorSettings.folderPath;
            } else {
                wallpaperDir = currentWallpaper.substring(0, currentWallpaper.lastIndexOf('/'));
                if (recursive && wallpaperDir)
                    SessionData.setMonitorCyclingFolderPath(screenName, wallpaperDir);
            }
        } else {
            recursive = !!SessionData.wallpaperCyclingRecursive;
            if (SessionData.wallpaperCyclingFolderPath && currentWallpaper.startsWith(SessionData.wallpaperCyclingFolderPath + "/")) {
                wallpaperDir = SessionData.wallpaperCyclingFolderPath;
            } else {
                wallpaperDir = currentWallpaper.substring(0, currentWallpaper.lastIndexOf('/'));
                if (recursive && wallpaperDir) {
                    SessionData.wallpaperCyclingFolderPath = wallpaperDir;
                    SessionData.saveSettings();
                }
            }
        }

        if (screenName && monitorProcessComponent.status === Component.Ready) {
            var process = monitorProcessFor(screenName);
            process.command = findCommand(wallpaperDir, recursive);
            process.targetScreenName = screenName;
            process.currentWallpaper = currentWallpaper;
            process.goToPrevious = goToPrevious;
            process.revision = SessionData.wallpaperRequestRevision(screenName);
            process.running = true;
            return;
        }

        var globalProcess = goToPrevious ? prevCyclingProcess : cyclingProcess;
        globalProcess.command = findCommand(wallpaperDir, recursive);
        globalProcess.targetScreenName = screenName || "";
        globalProcess.currentWallpaper = currentWallpaper;
        globalProcess.revision = SessionData.wallpaperRequestRevision(screenName || "");
        globalProcess.running = true;
    }

    function cycleToNextWallpaper(screenName, wallpaperPath) {
        cycle(screenName, wallpaperPath, false);
    }

    function cycleToPrevWallpaper(screenName, wallpaperPath) {
        cycle(screenName, wallpaperPath, true);
    }

    function cycleFromFolder(screenName, folderPath) {
        if (!folderPath)
            return;

        let recursive = false;
        if (screenName) {
            SessionData.setMonitorCyclingFolderPath(screenName, folderPath);
            recursive = !!SessionData.getMonitorCyclingSettings(screenName).recursive;
        } else {
            SessionData.wallpaperCyclingFolderPath = folderPath;
            SessionData.saveSettings();
            recursive = !!SessionData.wallpaperCyclingRecursive;
        }

        if (screenName && monitorProcessComponent.status === Component.Ready) {
            var process = monitorProcessFor(screenName);
            process.command = findCommand(folderPath, recursive);
            process.targetScreenName = screenName;
            process.currentWallpaper = "";
            process.goToPrevious = false;
            process.revision = SessionData.wallpaperRequestRevision(screenName);
            process.running = true;
            return;
        }

        var globalProcess = cyclingProcess;
        globalProcess.command = findCommand(folderPath, recursive);
        globalProcess.targetScreenName = screenName || "";
        globalProcess.currentWallpaper = "";
        globalProcess.goToPrevious = false;
        globalProcess.revision = SessionData.wallpaperRequestRevision(screenName || "");
        globalProcess.running = true;
    }

    function resetScheduleAfterManual() {
        if (!serverSchedulingAvailable)
            return;
        DMSService.sendRequest("wallpaper.trigger", {
            "target": ""
        }, null);
    }

    function cycleNextManually() {
        if (!SessionData.wallpaperPath)
            return;
        cycleToNextWallpaper();
        resetScheduleAfterManual();
    }

    function cyclePrevManually() {
        if (!SessionData.wallpaperPath)
            return;
        cycleToPrevWallpaper();
        resetScheduleAfterManual();
    }

    function cycleNextForMonitor(screenName) {
        if (!screenName)
            return;
        // Pass the current wallpaper if set; cycle() falls back to the folder when it is not.
        cycleToNextWallpaper(screenName, SessionData.getMonitorWallpaper(screenName));
    }

    function cyclePrevForMonitor(screenName) {
        if (!screenName)
            return;
        var currentWallpaper = SessionData.getMonitorWallpaper(screenName);
        if (currentWallpaper) {
            cycleToPrevWallpaper(screenName, currentWallpaper);
        }
    }

    function applyCycledWallpaper(text, currentPath, targetScreenName, goToPrevious, revision) {
        if (revision !== SessionData.wallpaperRequestRevision(targetScreenName))
            return;
        if (!text || !text.trim())
            return;
        const files = text.trim().split('\n').filter(file => file.length > 0);
        if (files.length < 1)
            return;
        const wallpaperList = files.sort();
        const isInitialFolderSelect = currentPath === "";
        let currentIndex = -1;
        if (!isInitialFolderSelect) {
            currentIndex = wallpaperList.findIndex(path => path === currentPath);
        }
        if (currentIndex === -1)
            currentIndex = 0;

        let isRandom = false;
        if (targetScreenName) {
            isRandom = !!SessionData.getMonitorCyclingSettings(targetScreenName).random;
        } else {
            isRandom = !!SessionData.wallpaperCyclingRandom;
        }

        let targetIndex;
        if (isInitialFolderSelect && isRandom) {
            targetIndex = Math.floor(Math.random() * wallpaperList.length);
        } else if (isInitialFolderSelect) {
            targetIndex = 0;
        } else if (isRandom) {
            if (wallpaperList.length > 1) {
                do {
                    targetIndex = Math.floor(Math.random() * wallpaperList.length);
                } while (targetIndex === currentIndex)
            } else {
                targetIndex = 0;
            }
        } else {
            if (goToPrevious) {
                targetIndex = currentIndex === 0 ? wallpaperList.length - 1 : currentIndex - 1;
            } else {
                targetIndex = (currentIndex + 1) % wallpaperList.length;
            }
        }
        const targetWallpaper = wallpaperList[targetIndex];
        if (!targetWallpaper || targetWallpaper === currentPath)
            return;

        if (targetScreenName) {
            SessionData.setMonitorWallpaper(targetScreenName, targetWallpaper);
        } else {
            SessionData.setWallpaper(targetWallpaper);
        }
    }

    Component {
        id: monitorProcessComponent
        Process {
            property string revision: ""
            property string targetScreenName: ""
            property string currentWallpaper: ""
            property bool goToPrevious: false
            running: false
            stdout: StdioCollector {
                onStreamFinished: root.applyCycledWallpaper(text, currentWallpaper, targetScreenName, goToPrevious, revision)
            }
        }
    }

    Process {
        id: cyclingProcess
        property string revision: ""
        property string targetScreenName: ""
        property string currentWallpaper: ""
        property bool goToPrevious: false
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyCycledWallpaper(text, cyclingProcess.currentWallpaper, cyclingProcess.targetScreenName, cyclingProcess.goToPrevious, cyclingProcess.revision)
        }
    }

    Process {
        id: prevCyclingProcess
        property string revision: ""
        property string targetScreenName: ""
        property string currentWallpaper: ""
        property bool goToPrevious: true
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyCycledWallpaper(text, prevCyclingProcess.currentWallpaper, prevCyclingProcess.targetScreenName, prevCyclingProcess.goToPrevious, prevCyclingProcess.revision)
        }
    }

    Connections {
        target: SessionData

        function onLoaded() {
            root.updateCyclingState();
        }
    }

    IpcHandler {
        target: "wallpaper"

        function get(): string {
            if (SessionData.perMonitorWallpaper) {
                return "ERROR: Per-monitor mode enabled. Use getFor(screenName) instead.";
            }
            return SessionData.wallpaperPath || "";
        }

        function set(path: string): string {
            if (SessionData.perMonitorWallpaper) {
                return "ERROR: Per-monitor mode enabled. Use setFor(screenName, path) instead.";
            }

            if (!path) {
                return "ERROR: No path provided";
            }

            var absolutePath = path.startsWith("/") ? path : StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/" + path;

            try {
                SessionData.setWallpaper(absolutePath);
                SessionData.wallpaperCyclingFolderPath = "";
                SessionData.saveSettings();
                return "SUCCESS: Wallpaper set to " + absolutePath;
            } catch (e) {
                return "ERROR: Failed to set wallpaper: " + e.toString();
            }
        }

        function clear(): string {
            SessionData.setWallpaper("");
            SessionData.setPerMonitorWallpaper(false);
            SessionData.monitorWallpapers = {};
            SessionData.wallpaperCyclingFolderPath = "";
            SessionData.saveSettings();
            return "SUCCESS: All wallpapers cleared";
        }

        function next(): string {
            if (SessionData.perMonitorWallpaper) {
                return "ERROR: Per-monitor mode enabled. Use nextFor(screenName) instead.";
            }

            if (!SessionData.wallpaperPath) {
                return "ERROR: No wallpaper set";
            }

            try {
                root.cycleNextManually();
                return "SUCCESS: Cycling to next wallpaper";
            } catch (e) {
                return "ERROR: Failed to cycle wallpaper: " + e.toString();
            }
        }

        function prev(): string {
            if (SessionData.perMonitorWallpaper) {
                return "ERROR: Per-monitor mode enabled. Use prevFor(screenName) instead.";
            }

            if (!SessionData.wallpaperPath) {
                return "ERROR: No wallpaper set";
            }

            try {
                root.cyclePrevManually();
                return "SUCCESS: Cycling to previous wallpaper";
            } catch (e) {
                return "ERROR: Failed to cycle wallpaper: " + e.toString();
            }
        }

        function getFor(screenName: string): string {
            if (!screenName) {
                return "ERROR: No screen name provided";
            }
            return SessionData.getMonitorWallpaper(screenName) || "";
        }

        function setFor(screenName: string, path: string): string {
            if (!screenName) {
                return "ERROR: No screen name provided";
            }

            if (!path) {
                return "ERROR: No path provided";
            }

            var absolutePath = path.startsWith("/") ? path : StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/" + path;

            try {
                if (!SessionData.perMonitorWallpaper) {
                    SessionData.setPerMonitorWallpaper(true);
                }
                SessionData.setMonitorWallpaper(screenName, absolutePath);
                SessionData.setMonitorCyclingFolderPath(screenName, "");
                return "SUCCESS: Wallpaper set for " + screenName + " to " + absolutePath;
            } catch (e) {
                return "ERROR: Failed to set wallpaper for " + screenName + ": " + e.toString();
            }
        }

        function nextFor(screenName: string): string {
            if (!screenName) {
                return "ERROR: No screen name provided";
            }

            var currentWallpaper = SessionData.getMonitorWallpaper(screenName);
            if (!currentWallpaper) {
                return "ERROR: No wallpaper set for " + screenName;
            }

            try {
                root.cycleNextForMonitor(screenName);
                return "SUCCESS: Cycling to next wallpaper for " + screenName;
            } catch (e) {
                return "ERROR: Failed to cycle wallpaper for " + screenName + ": " + e.toString();
            }
        }

        function prevFor(screenName: string): string {
            if (!screenName) {
                return "ERROR: No screen name provided";
            }

            var currentWallpaper = SessionData.getMonitorWallpaper(screenName);
            if (!currentWallpaper) {
                return "ERROR: No wallpaper set for " + screenName;
            }

            try {
                root.cyclePrevForMonitor(screenName);
                return "SUCCESS: Cycling to previous wallpaper for " + screenName;
            } catch (e) {
                return "ERROR: Failed to cycle wallpaper for " + screenName + ": " + e.toString();
            }
        }
    }
}
