pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import "../Common/WallpaperFormats.js" as WallpaperFormats

Singleton {
    id: root

    readonly property var log: Log.scoped("WallpaperCyclingService")

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
    property real _lastVideoAdvance: 0

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
        cyclingActive = serverSchedulingAvailable && (SessionData.wallpaperCyclingEnabled || SessionData.perMonitorWallpaper);
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
                monitors[name] = {
                    "enabled": !!(s.enabled && wp && !wp.startsWith("#")),
                    "mode": s.mode || "interval",
                    "intervalSec": s.interval || 300,
                    "time": s.time || "06:00"
                };
            }
        }
        return {
            "perMonitor": SessionData.perMonitorWallpaper,
            "global": {
                "enabled": !!(SessionData.wallpaperCyclingEnabled && SessionData.wallpaperPath),
                "mode": SessionData.wallpaperCyclingMode,
                "intervalSec": SessionData.wallpaperCyclingInterval,
                "time": SessionData.wallpaperCyclingTime
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

    function listWallpapers(folder, recursive, currentPath, screenName, goToPrevious) {
        const revision = SessionData.wallpaperRequestRevision(screenName);
        DMSService.sendRequest("wallpaper.list", {
            "folders": [
                {
                    "path": folder,
                    "recursive": recursive
                }
            ],
            "extensions": WallpaperFormats.extensions(true)
        }, response => {
            if (response.error) {
                log.warn("Failed to list wallpapers:", response.error);
                return;
            }
            const result = response.result;
            if (result.missing.length > 0)
                log.warn("Wallpaper folder not available:", result.missing.join(", "));
            if (result.truncated)
                log.warn("Wallpaper list cut short:", folder);
            applyCycledWallpaper(result.items, currentPath, screenName, goToPrevious, revision);
        });
    }

    function cycle(screenName, wallpaperPath, goToPrevious) {
        const currentWallpaper = wallpaperPath || (screenName ? SessionData.getMonitorWallpaper(screenName) : SessionData.wallpaperPath);
        if (!currentWallpaper || currentWallpaper.startsWith("#"))
            return;
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

        listWallpapers(wallpaperDir, recursive, currentWallpaper, screenName || "", goToPrevious);
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

        listWallpapers(folderPath, recursive, "", screenName || "", false);
    }

    function resetScheduleAfterManual() {
        if (!serverSchedulingAvailable)
            return;
        DMSService.sendRequest("wallpaper.trigger", {
            "target": ""
        }, null);
    }

    // A video set to advance plays once and hands over to the next wallpaper when it ends.
    function advancesOnVideoEnd(screenName) {
        if (!serverSchedulingAvailable)
            return false;
        if (SessionData.perMonitorWallpaper) {
            const settings = SessionData.getMonitorCyclingSettings(screenName);
            return !!(settings.enabled && settings.videoEnd);
        }
        return SessionData.wallpaperCyclingEnabled && SessionData.wallpaperCyclingVideoEnd;
    }

    function handleVideoEnded(screenName) {
        if (!advancesOnVideoEnd(screenName) || shouldPauseCycling)
            return;
        if (SessionData.perMonitorWallpaper) {
            cycleNextForMonitor(screenName);
            DMSService.sendRequest("wallpaper.trigger", {
                "target": screenName
            }, null);
            return;
        }
        // Every output plays the shared video and reports its end; the first one advances.
        if (Date.now() - _lastVideoAdvance < 2000)
            return;
        _lastVideoAdvance = Date.now();
        cycleNextManually();
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
        var currentWallpaper = SessionData.getMonitorWallpaper(screenName);
        if (currentWallpaper) {
            cycleToNextWallpaper(screenName, currentWallpaper);
        }
    }

    function cyclePrevForMonitor(screenName) {
        if (!screenName)
            return;
        var currentWallpaper = SessionData.getMonitorWallpaper(screenName);
        if (currentWallpaper) {
            cycleToPrevWallpaper(screenName, currentWallpaper);
        }
    }

    function variantFor(item, screenName) {
        const screen = SessionData._screenByName(screenName) || Quickshell.screens[0];
        if (!item.variants || !screen)
            return item.path;
        const distance = variant => Math.abs(Math.log(variant.width / variant.height * screen.height / screen.width));
        return item.variants.reduce((best, variant) => distance(variant) < distance(best) ? variant : best).path;
    }

    function applyCycledWallpaper(wallpaperList, currentPath, targetScreenName, goToPrevious, revision) {
        if (revision !== SessionData.wallpaperRequestRevision(targetScreenName))
            return;
        if (wallpaperList.length < 1)
            return;
        const isInitialFolderSelect = currentPath === "";
        let currentIndex = -1;
        if (!isInitialFolderSelect) {
            currentIndex = wallpaperList.findIndex(item => item.path === currentPath || (item.variants || []).some(variant => variant.path === currentPath));
        }

        let isRandom = false;
        if (targetScreenName) {
            isRandom = !!SessionData.getMonitorCyclingSettings(targetScreenName).random;
        } else {
            isRandom = !!SessionData.wallpaperCyclingRandom;
        }

        let targetIndex;
        if (isInitialFolderSelect) {
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
                targetIndex = currentIndex <= 0 ? wallpaperList.length - 1 : currentIndex - 1;
            } else {
                targetIndex = (currentIndex + 1) % wallpaperList.length;
            }
        }
        const targetWallpaper = variantFor(wallpaperList[targetIndex], targetScreenName);
        if (targetWallpaper === currentPath)
            return;

        if (targetScreenName) {
            SessionData.setMonitorWallpaper(targetScreenName, targetWallpaper);
        } else {
            SessionData.setWallpaper(targetWallpaper);
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
