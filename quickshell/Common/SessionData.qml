pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "settings/SessionSpec.js" as Spec
import "../DCommon/Common/MaterialWallpaper.js" as MaterialWallpaper
import "settings/SessionStore.js" as Store
import "../DCommon/Common/settings/SpecUtil.js" as SpecUtil

Singleton {
    id: root
    readonly property var log: Log.scoped("SessionData")

    readonly property int sessionConfigVersion: 7

    signal loaded
    signal brightnessDisplayHintChanged(string deviceName)
    signal loadErrorOccurred(string file, string message)

    property bool _parseError: false
    property bool _hasLoaded: false
    property bool _isReadOnly: false
    property bool _hasUnsavedChanges: false
    property var _loadedSessionSnapshot: null
    readonly property var _hooks: ({
            "updateLocale": updateLocale
        })
    readonly property string _stateUrl: StandardPaths.writableLocation(StandardPaths.GenericStateLocation)
    readonly property string _stateDir: Paths.strip(_stateUrl)

    property bool isLightMode: false
    property bool doNotDisturb: false
    property real doNotDisturbUntil: 0
    property bool doNotDisturbHeldByScreenShare: false
    property bool screenShareDndDismissed: false
    property var screenShareDismissedIds: []
    property bool idleInhibited: false
    property real idleInhibitedUntil: 0
    property string terminalOverride: ""
    property int updaterNotifiedUnix: 0
    property int updaterNotifiedCount: 0
    property bool isSwitchingMode: false
    property bool suppressOSD: true

    readonly property var terminalOptions: ["ghostty", "kitty", "foot", "alacritty", "wezterm", "konsole", "gnome-terminal", "xterm"]
    property var installedTerminals: []

    function resolveTerminal() {
        if (terminalOverride && terminalOverride.length > 0) {
            return terminalOverride;
        }
        const env = Quickshell.env("TERMINAL");
        if (env && env.length > 0) {
            return env;
        }
        return "";
    }

    function probeTerminals() {
        if (terminalProbe.running || installedTerminals.length > 0)
            return;
        terminalProbe.running = true;
    }

    Process {
        id: terminalProbe
        running: false
        command: ["sh", "-c", "for t in ghostty kitty foot alacritty wezterm konsole gnome-terminal xterm; do command -v \"$t\" >/dev/null 2>&1 && echo \"$t\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.trim().split("\n").filter(line => line.length > 0);
                root.installedTerminals = found;
            }
        }
    }

    Timer {
        id: dndExpireTimer
        repeat: false
        running: false
        onTriggered: root.setDoNotDisturb(false, 0, "timer")
    }

    Timer {
        id: screenShareReleaseTimer
        interval: 4000
        repeat: false
        running: false
        onTriggered: root._endScreenShareDnd()
    }

    function _armDndExpireTimer() {
        dndExpireTimer.stop();
        if (!doNotDisturb || doNotDisturbUntil <= 0)
            return;
        const remaining = doNotDisturbUntil - Date.now();
        if (remaining <= 0) {
            setDoNotDisturb(false, 0, "timer");
            return;
        }
        dndExpireTimer.interval = remaining;
        dndExpireTimer.start();
    }

    onDoNotDisturbChanged: _armDndExpireTimer()
    onDoNotDisturbUntilChanged: _armDndExpireTimer()

    Timer {
        id: osdSuppressTimer
        interval: 2000
        running: true
        onTriggered: root.suppressOSD = false
    }

    function suppressOSDTemporarily() {
        suppressOSD = true;
        osdSuppressTimer.restart();
    }

    Connections {
        target: SessionService
        function onSessionResumed() {
            root.suppressOSD = true;
            osdSuppressTimer.restart();
            root._applyDndExpirySanity();
            Qt.callLater(root.syncScreenShareDnd);
        }
    }

    Connections {
        target: typeof SettingsData !== "undefined" ? SettingsData : null
        function onNotificationDndWhileScreenSharingChanged() {
            root.syncScreenShareDnd();
        }
    }

    property var materialWallpapers: ({})
    property var materialWallpaperProfiles: ({})
    property int wallpaperRevision: 0
    property int wallpaperScopeRevision: 0
    property var monitorWallpaperRevisions: ({})
    property var previousMonitorWallpapers: ({})
    onWallpaperPathChanged: wallpaperRevision++
    onPerMonitorWallpaperChanged: wallpaperScopeRevision++
    onPerModeWallpaperChanged: wallpaperScopeRevision++
    onMonitorWallpapersChanged: {
        const revisions = Object.assign({}, monitorWallpaperRevisions);
        for (const screen of Quickshell.screens) {
            if (_findMonitorValue(previousMonitorWallpapers, screen.name) !== _findMonitorValue(monitorWallpapers, screen.name))
                revisions[screen.name] = (revisions[screen.name] ?? 0) + 1;
        }
        previousMonitorWallpapers = monitorWallpapers;
        monitorWallpaperRevisions = revisions;
    }

    function wallpaperRequestRevision(screenName) {
        const inherited = !screenName || _findMonitorValue(monitorWallpapers, screenName) === undefined;
        const mode = perModeWallpaper ? (isLightMode ? "light" : "dark") : "shared";
        return mode + "/" + wallpaperScopeRevision + "/" + (inherited ? wallpaperRevision : 0) + "/" + (monitorWallpaperRevisions[screenName] ?? 0);
    }

    function invalidateWallpaperRequests(screenName) {
        if (!screenName) {
            wallpaperRevision++;
            return;
        }
        const revisions = Object.assign({}, monitorWallpaperRevisions);
        revisions[screenName] = (revisions[screenName] ?? 0) + 1;
        monitorWallpaperRevisions = revisions;
    }

    property string wallpaperPath: ""
    property bool perMonitorWallpaper: false
    property var monitorWallpapers: ({})
    property bool perModeWallpaper: false
    property string wallpaperPathLight: ""
    property string wallpaperPathDark: ""
    property var monitorWallpapersLight: ({})
    property var monitorWallpapersDark: ({})
    property var monitorWallpaperFillModes: ({})

    // Map: screenName -> { scrollX, scrollY } (0-100 range, like workspace percentage)
    property var monitorScrollPositions: ({})

    function setMonitorScrollPosition(screenName, scrollX, scrollY) {
        var newPositions = Object.assign({}, monitorScrollPositions);
        newPositions[screenName] = {
            scrollX: scrollX,
            scrollY: scrollY
        };
        monitorScrollPositions = newPositions;
    }

    function getMonitorScrollPosition(screenName) {
        return monitorScrollPositions[screenName] || {
            scrollX: 50,
            scrollY: 50
        };
    }

    function clearMonitorScrollPosition(screenName) {
        var newPositions = Object.assign({}, monitorScrollPositions);
        delete newPositions[screenName];
        monitorScrollPositions = newPositions;
    }

    property string wallpaperTransition: "fade"
    readonly property var availableWallpaperTransitions: ["none", "fade", "wipe", "disc", "stripes", "iris bloom", "pixelate", "portal"]
    property var includedTransitions: availableWallpaperTransitions.filter(t => t !== "none")

    property bool wallpaperCyclingEnabled: false
    property bool wallpaperCyclingRandom: false
    property bool wallpaperCyclingRecursive: false
    property string wallpaperCyclingMode: "interval"
    property int wallpaperCyclingInterval: 300
    property string wallpaperCyclingTime: "06:00"
    property string wallpaperCyclingFolderPath: ""
    property var monitorCyclingSettings: ({})

    property bool nightModeEnabled: false
    property int nightModeTemperature: 4500
    property int nightModeHighTemperature: 6500
    property bool nightModeAutoEnabled: false
    property string nightModeAutoMode: "time"
    property int nightModeStartHour: 18
    property int nightModeStartMinute: 0
    property int nightModeEndHour: 6
    property int nightModeEndMinute: 0
    property int nightModeTransitionMinutes: 60
    property real displayGamma: 1.0
    property real displayContrast: 1.0
    property real latitude: 0.0
    property real longitude: 0.0
    property bool nightModeUseIPLocation: false
    property string nightModeLocationName: ""

    property bool themeModeAutoEnabled: false
    property string themeModeAutoMode: "time"
    property int themeModeStartHour: 18
    property int themeModeStartMinute: 0
    property int themeModeEndHour: 6
    property int themeModeEndMinute: 0
    property bool themeModeShareGammaSettings: true
    property string themeModeNextTransition: ""

    property var dockPins: ({})
    property var barPinnedApps: []
    property var hiddenTrayIds: []
    property var trayItemOrder: []
    property var recentColors: []
    property bool showThirdPartyPlugins: false
    property bool pluginBrowserInstalledFirst: false
    property bool pluginBrowserHideInstalled: true
    property string pluginBrowserSortMode: "default"
    property string lastBrightnessDevice: ""
    property var brightnessExponentialDevices: ({})
    property var brightnessUserSetValues: ({})
    property var brightnessExponentValues: ({})

    property bool nvidiaGpuTempEnabled: false
    property bool nonNvidiaGpuTempEnabled: false
    property var enabledGpuPciIds: []

    property string wifiDeviceOverride: ""

    property string weatherLocation: "New York, NY"
    property string weatherCoordinates: "40.7128,-74.0060"

    property var hiddenApps: []
    property var appOverrides: ({})
    property bool searchAppActions: true

    property string vpnLastConnected: ""

    property string bluetoothAdapterOverride: ""

    property string lastPlayerIdentity: ""
    property string pinnedPlayerIdentity: ""

    property var deviceMaxVolumes: ({})
    property var hiddenOutputDeviceNames: []
    property var hiddenInputDeviceNames: []

    property string locale: ""
    property string timeLocale: ""

    property string notepadLastMode: ""

    property var niriOutputSettings: ({})
    property var hyprlandOutputSettings: ({})
    property var activeDisplayProfile: ({})
    property var activeDisplayProfileModes: ({})
    property var desktopWidgetGridSettings: ({})
    property var lockScreenWidgetGridSettings: ({})
    property var desktopWidgetInstancePositions: ({})
    property var lockScreenAutoPositions: ({})
    property var greeterAutoPositions: ({})
    property var islandFreePositions: ({})
    property var builtInPluginState: ({})
    property bool greeterSyncPending: false
    property var greeterSyncBaseline: ({})
    property string lastAppliedIconTheme: ""

    property string launcherLastMode: "all"
    property string launcherLastFileSearchType: "all"
    property string launcherLastQuery: ""
    property var launcherQueryHistory: []
    property string appDrawerLastMode: "apps"
    property string niriOverviewLastMode: "apps"
    property bool showConfigReloadToast: true

    Component.onCompleted: {
        loadSettings();
    }

    property var _pendingMigration: null

    function loadSettings() {
        _hasUnsavedChanges = false;
        _pendingMigration = null;

        try {
            const txt = settingsFile.text();
            let obj = (txt && txt.trim()) ? JSON.parse(txt) : null;

            if (obj?.brightnessLogarithmicDevices && !obj?.brightnessExponentialDevices)
                obj.brightnessExponentialDevices = obj.brightnessLogarithmicDevices;

            if (obj?.nightModeStartTime !== undefined) {
                const parts = obj.nightModeStartTime.split(":");
                obj.nightModeStartHour = parseInt(parts[0]) || 18;
                obj.nightModeStartMinute = parseInt(parts[1]) || 0;
            }
            if (obj?.nightModeEndTime !== undefined) {
                const parts = obj.nightModeEndTime.split(":");
                obj.nightModeEndHour = parseInt(parts[0]) || 6;
                obj.nightModeEndMinute = parseInt(parts[1]) || 0;
            }

            const oldVersion = obj?.configVersion ?? 0;
            if (obj && oldVersion === 0)
                migrateFromUndefinedToV1(obj);

            if (obj && oldVersion < sessionConfigVersion) {
                const settingsDataRef = (typeof SettingsData !== "undefined") ? SettingsData : null;
                const migrated = Store.migrateToVersion(obj, sessionConfigVersion, settingsDataRef);
                if (migrated) {
                    _pendingMigration = migrated;
                    obj = migrated;
                }
            }

            Store.parse(root, obj);
            _applyDndExpirySanity();
            _applyIdleInhibitExpirySanity();

            _loadedSessionSnapshot = getCurrentSessionJson();
            _hasLoaded = true;

            if (typeof Theme !== "undefined")
                Theme.generateSystemThemesFromCurrentTheme();

            loaded();
            Qt.callLater(root.syncScreenShareDnd);

            _checkSessionWritable();
        } catch (e) {
            _parseError = true;
            const msg = e.message;
            log.error("Failed to parse session.json - file will not be overwritten.");
            Qt.callLater(() => loadErrorOccurred("session.json", msg));
        }
    }

    function _checkSessionWritable() {
        sessionWritableCheckProcess.running = true;
    }

    function _onWritableCheckComplete(writable) {
        const wasReadOnly = _isReadOnly;
        _isReadOnly = !writable;
        if (_isReadOnly) {
            _hasUnsavedChanges = _checkForUnsavedChanges();
        } else {
            _loadedSessionSnapshot = getCurrentSessionJson();
            _hasUnsavedChanges = false;
            if (wasReadOnly && _pendingMigration)
                settingsFile.setText(JSON.stringify(_pendingMigration, null, 2));
        }
        _pendingMigration = null;
    }

    function _checkForUnsavedChanges() {
        if (!_hasLoaded || !_loadedSessionSnapshot)
            return false;
        const current = getCurrentSessionJson();
        return current !== _loadedSessionSnapshot;
    }

    function getCurrentSessionJson() {
        return JSON.stringify(Store.toJson(root), null, 2);
    }

    function parseSettings(content) {
        _parseError = false;
        try {
            let obj = (content && content.trim()) ? JSON.parse(content) : null;

            if (obj?.brightnessLogarithmicDevices && !obj?.brightnessExponentialDevices)
                obj.brightnessExponentialDevices = obj.brightnessLogarithmicDevices;

            if (obj?.nightModeStartTime !== undefined) {
                const parts = obj.nightModeStartTime.split(":");
                obj.nightModeStartHour = parseInt(parts[0]) || 18;
                obj.nightModeStartMinute = parseInt(parts[1]) || 0;
            }
            if (obj?.nightModeEndTime !== undefined) {
                const parts = obj.nightModeEndTime.split(":");
                obj.nightModeEndHour = parseInt(parts[0]) || 6;
                obj.nightModeEndMinute = parseInt(parts[1]) || 0;
            }

            const oldVersion = obj?.configVersion ?? 0;
            if (obj && oldVersion === 0)
                migrateFromUndefinedToV1(obj);

            if (obj && oldVersion < sessionConfigVersion) {
                const settingsDataRef = (typeof SettingsData !== "undefined") ? SettingsData : null;
                const migrated = Store.migrateToVersion(obj, sessionConfigVersion, settingsDataRef);
                if (migrated) {
                    _pendingMigration = migrated;
                    obj = migrated;
                }
            }

            Store.parse(root, obj);
            _applyDndExpirySanity();
            _applyIdleInhibitExpirySanity();

            _loadedSessionSnapshot = getCurrentSessionJson();
            _hasLoaded = true;

            if (typeof Theme !== "undefined")
                Theme.generateSystemThemesFromCurrentTheme();

            loaded();
            Qt.callLater(root.syncScreenShareDnd);
        } catch (e) {
            _parseError = true;
            const msg = e.message;
            log.error("Failed to parse session.json - file will not be overwritten.");
            Qt.callLater(() => loadErrorOccurred("session.json", msg));
        }
    }

    function _applyDndExpirySanity() {
        if (doNotDisturb && doNotDisturbUntil > 0 && Date.now() >= doNotDisturbUntil) {
            doNotDisturb = false;
            doNotDisturbUntil = 0;
        } else if (!doNotDisturb && doNotDisturbUntil !== 0) {
            doNotDisturbUntil = 0;
        }
        _armDndExpireTimer();
    }

    function _applyIdleInhibitExpirySanity() {
        if (idleInhibited && idleInhibitedUntil > 0 && Date.now() >= idleInhibitedUntil) {
            idleInhibited = false;
            idleInhibitedUntil = 0;
        } else if (!idleInhibited && idleInhibitedUntil !== 0) {
            idleInhibitedUntil = 0;
        }
    }

    function saveSettings() {
        if (_parseError || !_hasLoaded)
            return;
        settingsFile.setText(getCurrentSessionJson());
        if (_isReadOnly)
            _checkSessionWritable();
    }

    function set(key, value) {
        Spec.set(root, key, value, saveSettings, _hooks);
    }

    function isDefault(keys) {
        return keys.every(key => !(key in Spec.SPEC) || SpecUtil.isDefault(root[key], Spec.SPEC[key].def));
    }

    function resetToDefault(keys) {
        for (const key of keys) {
            if (key in Spec.SPEC)
                set(key, SpecUtil.cloneDef(Spec.SPEC[key].def));
        }
    }

    function importFromSettings(payload) {
        if (!payload)
            return;
        if (!_hasLoaded)
            loadSettings();
        if (_parseError)
            return;

        let imported = false;
        for (const key in payload) {
            if (!(key in Spec.SPEC))
                continue;
            const current = root[key];
            const isEmpty = current === Spec.SPEC[key].def || (typeof current === "object" && current !== null && Object.keys(current).length === 0);
            if (!isEmpty)
                continue;
            root[key] = payload[key];
            imported = true;
        }

        if (imported) {
            log.info("Imported machine-specific state from settings.json");
            saveSettings();
        }
    }

    function getNiriOutputSetting(outputId, key, defaultValue) {
        if (!niriOutputSettings[outputId])
            return defaultValue;
        return niriOutputSettings[outputId][key] !== undefined ? niriOutputSettings[outputId][key] : defaultValue;
    }

    function setNiriOutputSetting(outputId, key, value) {
        const updated = JSON.parse(JSON.stringify(niriOutputSettings));
        if (!updated[outputId])
            updated[outputId] = {};
        updated[outputId][key] = value;
        niriOutputSettings = updated;
        saveSettings();
    }

    function getNiriOutputSettings(outputId) {
        const settings = niriOutputSettings[outputId];
        return settings ? JSON.parse(JSON.stringify(settings)) : {};
    }

    function getHyprlandOutputSetting(outputId, key, defaultValue) {
        if (!hyprlandOutputSettings[outputId])
            return defaultValue;
        return hyprlandOutputSettings[outputId][key] !== undefined ? hyprlandOutputSettings[outputId][key] : defaultValue;
    }

    function setHyprlandOutputSetting(outputId, key, value) {
        const updated = JSON.parse(JSON.stringify(hyprlandOutputSettings));
        if (!updated[outputId])
            updated[outputId] = {};
        updated[outputId][key] = value;
        hyprlandOutputSettings = updated;
        saveSettings();
    }

    function removeHyprlandOutputSetting(outputId, key) {
        if (!hyprlandOutputSettings[outputId] || !(key in hyprlandOutputSettings[outputId]))
            return;
        const updated = JSON.parse(JSON.stringify(hyprlandOutputSettings));
        delete updated[outputId][key];
        hyprlandOutputSettings = updated;
        saveSettings();
    }

    function getActiveDisplayProfile(compositor) {
        return activeDisplayProfile[compositor] || "";
    }

    function setActiveDisplayProfile(compositor, profileId) {
        const updated = JSON.parse(JSON.stringify(activeDisplayProfile));
        updated[compositor] = profileId;
        activeDisplayProfile = updated;
        saveSettings();
    }

    function setActiveDisplayProfileModes(compositor, modes) {
        if (JSON.stringify(activeDisplayProfileModes[compositor] || {}) === JSON.stringify(modes || {}))
            return;
        const updated = JSON.parse(JSON.stringify(activeDisplayProfileModes));
        updated[compositor] = modes;
        activeDisplayProfileModes = updated;
        saveSettings();
    }

    function getWidgetGridSetting(lockScreen, screenKey, property, defaultValue) {
        const store = lockScreen ? lockScreenWidgetGridSettings : desktopWidgetGridSettings;
        const val = store?.[screenKey]?.[property];
        return val !== undefined ? val : defaultValue;
    }

    function setWidgetGridSetting(lockScreen, screenKey, property, value) {
        const allSettings = JSON.parse(JSON.stringify((lockScreen ? lockScreenWidgetGridSettings : desktopWidgetGridSettings) || {}));
        if (!allSettings[screenKey])
            allSettings[screenKey] = {};
        allSettings[screenKey][property] = value;
        if (lockScreen)
            lockScreenWidgetGridSettings = allSettings;
        else
            desktopWidgetGridSettings = allSettings;
        saveSettings();
    }

    readonly property var widgetAnchorKeys: ({
            x: "anchorX",
            y: "anchorY"
        })

    function mergedWidgetPosition(current, updates) {
        const merged = Object.assign({}, current || {}, updates);
        for (const key in merged) {
            if (merged[key] === undefined)
                delete merged[key];
        }
        return merged;
    }

    function updateDesktopWidgetInstancePosition(instanceId, screenKey, positionUpdates) {
        const updated = JSON.parse(JSON.stringify(desktopWidgetInstancePositions));
        if (!updated[instanceId])
            updated[instanceId] = {};
        updated[instanceId][screenKey] = mergedWidgetPosition(updated[instanceId][screenKey], positionUpdates);
        desktopWidgetInstancePositions = updated;
        saveSettings();
    }

    // Fractions of the screen so the anchor survives resolution and scale changes.
    function setIslandFreePosition(key, x, y) {
        const next = {
            "x": Math.max(0, Math.min(1, x)),
            "y": Math.max(0, Math.min(1, y))
        };
        const current = islandFreePositions[key];
        if (current && current.x === next.x && current.y === next.y)
            return;
        const updated = Object.assign({}, islandFreePositions);
        updated[key] = next;
        islandFreePositions = updated;
        saveSettings();
    }

    function syncDesktopWidgetPositionToAllScreens(instanceId) {
        const positions = desktopWidgetInstancePositions[instanceId] || {};
        const screenKeys = Object.keys(positions).filter(k => k !== "_synced");
        if (screenKeys.length === 0)
            return;
        const sourcePos = positions[screenKeys[0]];
        if (!sourcePos)
            return;
        const screen = Array.from(Quickshell.screens.values()).find(s => SettingsData.getScreenDisplayName(s) === screenKeys[0]);
        if (!screen)
            return;
        const synced = {};
        if (sourcePos.x !== undefined)
            synced.x = sourcePos.x / screen.width;
        if (sourcePos.y !== undefined)
            synced.y = sourcePos.y / screen.height;
        if (sourcePos.width !== undefined)
            synced.width = sourcePos.width;
        if (sourcePos.height !== undefined)
            synced.height = sourcePos.height;
        if (sourcePos.anchorX !== undefined)
            synced.anchorX = sourcePos.anchorX;
        if (sourcePos.anchorY !== undefined)
            synced.anchorY = sourcePos.anchorY;
        const updated = JSON.parse(JSON.stringify(desktopWidgetInstancePositions));
        updated[instanceId]["_synced"] = synced;
        desktopWidgetInstancePositions = updated;
        saveSettings();
    }

    function setGreeterAutoPositions(screenKey, placement) {
        if (JSON.stringify(greeterAutoPositions[screenKey] ?? null) === JSON.stringify(placement))
            return;
        const updated = Object.assign({}, greeterAutoPositions);
        updated[screenKey] = placement;
        greeterAutoPositions = updated;
        saveSettings();
    }
    function setLockScreenAutoPositions(screenKey, placement) {
        if (JSON.stringify(lockScreenAutoPositions[screenKey] ?? null) === JSON.stringify(placement))
            return;
        const updated = Object.assign({}, lockScreenAutoPositions);
        updated[screenKey] = placement;
        lockScreenAutoPositions = updated;
        saveSettings();
    }

    function copyDesktopWidgetInstancePositions(fromId, toId) {
        const source = desktopWidgetInstancePositions[fromId];
        if (!source)
            return;
        const updated = JSON.parse(JSON.stringify(desktopWidgetInstancePositions));
        updated[toId] = JSON.parse(JSON.stringify(source));
        desktopWidgetInstancePositions = updated;
        saveSettings();
    }
    // Detached greeter clocks keep the spot the lock screen picked for them.
    function pinPublishedLockPosition(fromId, toId, synced) {
        const updated = JSON.parse(JSON.stringify(desktopWidgetInstancePositions));
        let pinned = false;
        for (const screenKey in lockScreenAutoPositions) {
            const entry = lockScreenAutoPositions[screenKey];
            const position = entry?.positions?.[fromId];
            if (!position || !(entry.width > 0) || !(entry.height > 0))
                continue;
            const key = synced ? "_synced" : screenKey;
            if (!updated[toId])
                updated[toId] = {};
            updated[toId][key] = mergedWidgetPosition(updated[toId][key], {
                x: synced ? position.x / entry.width : position.x,
                y: synced ? position.y / entry.height : position.y,
                anchorX: undefined,
                anchorY: undefined
            });
            pinned = true;
            if (synced)
                break;
        }
        if (!pinned)
            return;
        desktopWidgetInstancePositions = updated;
        saveSettings();
    }
    function removeDesktopWidgetInstancePositions(instanceId) {
        if (!(instanceId in desktopWidgetInstancePositions))
            return;
        const updated = JSON.parse(JSON.stringify(desktopWidgetInstancePositions));
        delete updated[instanceId];
        desktopWidgetInstancePositions = updated;
        saveSettings();
    }

    function resetDesktopWidgetInstanceGeometry(instanceId, keys) {
        if (!(instanceId in desktopWidgetInstancePositions))
            return;
        const updated = JSON.parse(JSON.stringify(desktopWidgetInstancePositions));
        for (const screenKey in updated[instanceId]) {
            for (const key of keys) {
                delete updated[instanceId][screenKey][key];
                if (key in widgetAnchorKeys)
                    delete updated[instanceId][screenKey][widgetAnchorKeys[key]];
            }
        }
        desktopWidgetInstancePositions = updated;
        saveSettings();
    }

    function setBuiltInPluginState(pluginId, state) {
        const updated = JSON.parse(JSON.stringify(builtInPluginState));
        updated[pluginId] = state;
        builtInPluginState = updated;
        saveSettings();
    }

    function migrateFromUndefinedToV1(settings) {
        if (typeof SettingsData !== "undefined") {
            for (const key of ["acMonitorTimeout", "acLockTimeout", "acSuspendTimeout", "batteryMonitorTimeout", "batteryLockTimeout", "batterySuspendTimeout", "lockBeforeSuspend", "loginctlLockIntegration", "launchPrefix"]) {
                if (settings[key] !== undefined && !SettingsData.isManaged(key))
                    SettingsData.set(key, settings[key]);
            }
        }
        if (typeof CacheData !== "undefined") {
            CacheData.fileBrowserSettings = CacheData.withLegacyLastPaths(CacheData.fileBrowserSettings, settings);
            CacheData.saveCache();
        }
    }

    function setLightMode(lightMode, skipWallpaperSync) {
        isSwitchingMode = true;
        if (!skipWallpaperSync)
            syncWallpaperForCurrentMode(lightMode);
        isLightMode = lightMode;
        saveSettings();
        Qt.callLater(() => {
            isSwitchingMode = false;
        });
    }

    function setDoNotDisturb(enabled, durationMinutes, origin) {
        const src = origin || "user";
        if (src === "user") {
            if (!enabled && _screenShareShouldHold()) {
                screenShareDndDismissed = true;
                screenShareDismissedIds = _screencastIds();
            }
            if (doNotDisturbHeldByScreenShare)
                doNotDisturbHeldByScreenShare = false;
        }

        const minutes = Number(durationMinutes) || 0;
        doNotDisturb = enabled;
        doNotDisturbUntil = (enabled && minutes > 0) ? Date.now() + minutes * 60 * 1000 : 0;
        saveSettings();

        if (src !== "screenshare")
            Qt.callLater(syncScreenShareDnd);
    }

    function setIdleInhibited(enabled, durationMinutes) {
        const next = !!enabled;
        const minutes = Number(durationMinutes) || 0;
        const nextUntil = (next && minutes > 0) ? Date.now() + minutes * 60 * 1000 : 0;
        if (idleInhibited === next && idleInhibitedUntil === nextUntil)
            return;
        idleInhibited = next;
        idleInhibitedUntil = nextUntil;
        saveSettings();
    }

    function setDoNotDisturbUntilTimestamp(timestampMs) {
        const target = Number(timestampMs) || 0;
        if (target <= Date.now()) {
            setDoNotDisturb(false);
            return;
        }
        if (doNotDisturbHeldByScreenShare)
            doNotDisturbHeldByScreenShare = false;
        doNotDisturb = true;
        doNotDisturbUntil = target;
        saveSettings();
    }

    function _screenShareShouldHold() {
        if (typeof SettingsData === "undefined" || !SettingsData.notificationDndWhileScreenSharing)
            return false;
        if (typeof PrivacyService === "undefined" || !PrivacyService.screensharingActive)
            return false;
        return true;
    }

    function _screencastIds() {
        return (typeof PrivacyService !== "undefined") ? PrivacyService.screencastSourceIds() : [];
    }

    function _dismissalApplies() {
        if (!screenShareDndDismissed)
            return false;
        const dismissed = screenShareDismissedIds || [];
        if (!dismissed.length)
            return true;
        const current = _screencastIds();
        if (!current.length)
            return true;
        return current.some(id => dismissed.indexOf(id) !== -1);
    }

    function _releaseScreenShareDndHold() {
        if (!doNotDisturbHeldByScreenShare)
            return;
        doNotDisturbHeldByScreenShare = false;
        if (!doNotDisturb || doNotDisturbUntil > 0) {
            saveSettings();
            return;
        }
        setDoNotDisturb(false, 0, "screenshare");
    }

    function _endScreenShareDnd() {
        _clearScreenShareDismissal();
        _releaseScreenShareDndHold();
    }

    function _clearScreenShareDismissal() {
        if (!screenShareDndDismissed)
            return;
        screenShareDndDismissed = false;
        screenShareDismissedIds = [];
        saveSettings();
    }

    function syncScreenShareDnd() {
        if (!_screenShareShouldHold()) {
            if (!doNotDisturbHeldByScreenShare && !screenShareDndDismissed)
                return;
            const settingOn = typeof SettingsData !== "undefined" && SettingsData.notificationDndWhileScreenSharing;
            if (!settingOn) {
                screenShareReleaseTimer.stop();
                _endScreenShareDnd();
                return;
            }
            screenShareReleaseTimer.restart();
            return;
        }

        screenShareReleaseTimer.stop();

        if (!_dismissalApplies())
            _clearScreenShareDismissal();

        if (screenShareDndDismissed || doNotDisturb)
            return;

        doNotDisturbHeldByScreenShare = true;
        setDoNotDisturb(true, 0, "screenshare");
    }

    function setWallpaper(imagePath) {
        wallpaperPath = imagePath;
        if (perModeWallpaper) {
            if (isLightMode) {
                wallpaperPathLight = imagePath;
            } else {
                wallpaperPathDark = imagePath;
            }
        }
        saveSettings();

        if (typeof Theme !== "undefined") {
            Theme.generateSystemThemesFromCurrentTheme();
        }
    }

    function setWallpaperColor(color) {
        wallpaperPath = color;
        if (perModeWallpaper) {
            if (isLightMode) {
                wallpaperPathLight = color;
            } else {
                wallpaperPathDark = color;
            }
        }
        saveSettings();

        if (typeof Theme !== "undefined") {
            Theme.generateSystemThemesFromCurrentTheme();
        }
    }

    function setWallpaperForMode(path, light) {
        if (light) {
            wallpaperPathLight = path;
        } else {
            wallpaperPathDark = path;
        }
        syncWallpaperForCurrentMode();
        saveSettings();

        if (light !== isLightMode)
            return;
        if (typeof Theme !== "undefined") {
            Theme.generateSystemThemesFromCurrentTheme();
        }
    }

    function clearWallpaper() {
        setWallpaper("");
    }

    function materialWallpaperTarget(screenName) {
        const screen = perMonitorWallpaper ? _screenByName(screenName) : null;
        return {
            screen: perMonitorWallpaper ? screenName : "",
            key: screen ? SettingsData.getScreenDisplayName(screen) : "",
            separate: perModeWallpaper,
            light: isLightMode,
            perMonitor: perMonitorWallpaper
        };
    }

    function materialWallpaperTargetAvailable(target) {
        if (!target || target.separate !== perModeWallpaper || target.perMonitor !== perMonitorWallpaper)
            return false;
        if (!target.perMonitor)
            return true;
        const screen = _screenByName(target.screen);
        return !!screen && SettingsData.getScreenDisplayName(screen) === target.key;
    }

    function materialWallpaperEntry(target) {
        const slot = target.separate ? (target.light ? "light" : "dark") : "shared";
        const inherits = !target.perMonitor || _findMonitorValue(monitorWallpapers, target.screen) === undefined;
        const slots = inherits ? materialWallpapers[""] : _findMonitorValue(materialWallpapers, target.screen);
        const key = inherits ? "" : target.key;
        return MaterialWallpaper.entry({
            "": materialWallpapers[""],
            [key]: slots
        }, key, slot);
    }

    function getMonitorMaterialWallpaper(screenName) {
        return MaterialWallpaper.composition(materialWallpaperEntry(materialWallpaperTarget(screenName)), materialWallpaperProfiles);
    }

    function writeMonitorWallpaper(map, screenName, path, inherit = false) {
        const screen = _screenByName(screenName);
        if (!screen)
            return map;
        const identifier = SettingsData.getScreenDisplayName(screen);
        const next = Object.assign({}, map);
        delete next[screen.name];
        if (screen.model)
            delete next[screen.model];
        delete next[identifier];
        if (!inherit)
            next[identifier] = path;
        return next;
    }

    function setMaterialWallpaperPreset(target, preset) {
        return setMaterialWallpaper(target, Object.assign({}, materialWallpaperEntry(target), {
            preset
        }));
    }

    function setMaterialWallpaperSeed(target, seed) {
        if (!MaterialWallpaper.validSeed(seed))
            return false;
        return setMaterialWallpaper(target, Object.assign({}, materialWallpaperEntry(target), {
            seed
        }));
    }

    function setMaterialWallpaper(target, value) {
        if (!materialWallpaperTargetAvailable(target))
            return false;
        const entry = MaterialWallpaper.normalizeEntry(value);
        const slot = target.separate ? (target.light ? "light" : "dark") : "shared";
        let store = Object.assign({}, materialWallpapers);
        const existingSlots = target.perMonitor ? _findMonitorValue(store, target.screen) : store[""];
        const slots = Object.assign({}, existingSlots ?? {});
        slots[slot] = entry;
        if (target.perMonitor)
            store = writeMonitorWallpaper(store, target.screen, slots);
        else
            store[""] = slots;
        materialWallpapers = store;
        invalidateWallpaperRequests(target.screen);
        if (target.perMonitor) {
            setMonitorCyclingEnabled(target.screen, false);
            setMonitorCyclingFolderPath(target.screen, "");
            if (target.separate) {
                if (target.light)
                    monitorWallpapersLight = writeMonitorWallpaper(monitorWallpapersLight, target.screen, "");
                else
                    monitorWallpapersDark = writeMonitorWallpaper(monitorWallpapersDark, target.screen, "");
            }
            if (!target.separate || target.light === isLightMode)
                monitorWallpapers = writeMonitorWallpaper(monitorWallpapers, target.screen, "");
        } else {
            wallpaperCyclingEnabled = false;
            wallpaperCyclingFolderPath = "";
            if (target.separate) {
                if (target.light)
                    wallpaperPathLight = "";
                else
                    wallpaperPathDark = "";
            }
            if (!target.separate || target.light === isLightMode)
                wallpaperPath = "";
        }
        saveSettings();
        if ((!target.separate || target.light === isLightMode) && (!target.perMonitor || target.screen === Theme.wallpaperSourceScreen))
            Theme.generateSystemThemesFromCurrentTheme();
        return true;
    }

    function materialWallpaperProfileList() {
        return MaterialWallpaper.profiles(materialWallpaperProfiles);
    }

    function addMaterialWallpaperProfile(layout, fallbackName = "") {
        const normalized = MaterialWallpaper.normalizeLayout(layout);
        if (!normalized)
            return "";
        const id = MaterialWallpaper.profileId(normalized.name || fallbackName, materialWallpaperProfiles);
        if (!normalized.name)
            normalized.name = fallbackName || id;
        materialWallpaperProfiles = Object.assign({}, materialWallpaperProfiles, {
            [id]: normalized
        });
        saveSettings();
        return id;
    }

    function removeMaterialWallpaperProfile(id) {
        const store = Object.assign({}, materialWallpaperProfiles);
        if (MaterialWallpaper.builtinIds.includes(id))
            store[id] = null;
        else
            delete store[id];
        materialWallpaperProfiles = store;
        saveSettings();
    }

    function restoreMaterialWallpaperProfiles() {
        const store = {};
        for (const id of Object.keys(materialWallpaperProfiles)) {
            if (materialWallpaperProfiles[id])
                store[id] = materialWallpaperProfiles[id];
        }
        materialWallpaperProfiles = store;
        saveSettings();
    }

    function setPerMonitorWallpaper(enabled) {
        perMonitorWallpaper = enabled;
        if (enabled && perModeWallpaper) {
            syncWallpaperForCurrentMode();
        }
        saveSettings();

        if (typeof Theme !== "undefined") {
            Theme.generateSystemThemesFromCurrentTheme();
        }
    }

    function setPerModeWallpaper(enabled) {
        if (enabled === perModeWallpaper)
            return;
        const compositions = {};
        const mode = isLightMode ? "light" : "dark";
        for (const key of Object.keys(materialWallpapers)) {
            const slots = materialWallpapers[key];
            const entry = MaterialWallpaper.entry(materialWallpapers, key, perModeWallpaper ? mode : "shared");
            compositions[key] = enabled ? Object.assign({}, slots, {
                light: entry,
                dark: entry
            }) : Object.assign({}, slots, {
                shared: entry
            });
        }
        materialWallpapers = compositions;
        if (enabled && wallpaperCyclingEnabled) {
            setWallpaperCyclingEnabled(false);
        }
        if (enabled && perMonitorWallpaper) {
            var monitorCyclingAny = false;
            for (var key in monitorCyclingSettings) {
                if (monitorCyclingSettings[key].enabled) {
                    monitorCyclingAny = true;
                    break;
                }
            }
            if (monitorCyclingAny) {
                var newSettings = Object.assign({}, monitorCyclingSettings);
                for (var screenName in newSettings) {
                    newSettings[screenName].enabled = false;
                }
                monitorCyclingSettings = newSettings;
            }
        }

        perModeWallpaper = enabled;
        if (enabled) {
            if (perMonitorWallpaper) {
                monitorWallpapersLight = Object.assign({}, monitorWallpapers);
                monitorWallpapersDark = Object.assign({}, monitorWallpapers);
            } else {
                wallpaperPathLight = wallpaperPath;
                wallpaperPathDark = wallpaperPath;
            }
        } else {
            syncWallpaperForCurrentMode();
        }
        saveSettings();

        if (typeof Theme !== "undefined") {
            Theme.generateSystemThemesFromCurrentTheme();
        }
    }

    function setMonitorWallpaper(screenName, path) {
        if (!_screenByName(screenName)) {
            log.warn("Screen not found");
            return;
        }
        monitorWallpapers = writeMonitorWallpaper(monitorWallpapers, screenName, path, !path);
        if (perModeWallpaper) {
            if (isLightMode)
                monitorWallpapersLight = writeMonitorWallpaper(monitorWallpapersLight, screenName, path, !path);
            else
                monitorWallpapersDark = writeMonitorWallpaper(monitorWallpapersDark, screenName, path, !path);
        }

        saveSettings();

        if (typeof Theme !== "undefined" && typeof Quickshell !== "undefined" && typeof SettingsData !== "undefined") {
            var screens = Quickshell.screens;
            if (screens.length > 0) {
                var targetMonitor = (SettingsData.matugenTargetMonitor && SettingsData.matugenTargetMonitor !== "") ? SettingsData.matugenTargetMonitor : screens[0].name;
                if (screenName === targetMonitor) {
                    Theme.generateSystemThemesFromCurrentTheme();
                }
            }
        }
    }

    function setWallpaperTransition(transition) {
        wallpaperTransition = transition;
        saveSettings();
    }

    function setWallpaperCyclingEnabled(enabled) {
        wallpaperCyclingEnabled = enabled;
        saveSettings();
    }

    function setWallpaperCyclingRandom(random) {
        wallpaperCyclingRandom = random;
        saveSettings();
    }

    function setWallpaperCyclingRecursive(recursive) {
        wallpaperCyclingRecursive = recursive;
        saveSettings();
    }

    function setWallpaperCyclingMode(mode) {
        wallpaperCyclingMode = mode;
        saveSettings();
    }

    function setWallpaperCyclingInterval(interval) {
        wallpaperCyclingInterval = interval;
        saveSettings();
    }

    function setWallpaperCyclingTime(time) {
        wallpaperCyclingTime = time;
        saveSettings();
    }

    function updateMonitorCyclingSetting(screenName, key, value) {
        const screen = _screenByName(screenName);
        if (!screen) {
            log.warn("Screen not found");
            return;
        }

        const identifier = typeof SettingsData !== "undefined" ? SettingsData.getScreenDisplayName(screen) : screen.name;
        const newSettings = {};
        for (const existing in monitorCyclingSettings) {
            const isThisScreen = existing === screen.name || (screen.model && existing === screen.model);
            if (!isThisScreen)
                newSettings[existing] = monitorCyclingSettings[existing];
        }

        newSettings[identifier] = getMonitorCyclingSettings(screenName);
        newSettings[identifier][key] = value;
        monitorCyclingSettings = newSettings;
        saveSettings();
    }

    function setMonitorCyclingEnabled(screenName, enabled) {
        updateMonitorCyclingSetting(screenName, "enabled", enabled);
    }

    function setMonitorCyclingRandom(screenName, random) {
        updateMonitorCyclingSetting(screenName, "random", random);
    }

    function setMonitorCyclingRecursive(screenName, recursive) {
        updateMonitorCyclingSetting(screenName, "recursive", recursive);
    }

    function setMonitorCyclingMode(screenName, mode) {
        updateMonitorCyclingSetting(screenName, "mode", mode);
    }

    function setMonitorCyclingInterval(screenName, interval) {
        updateMonitorCyclingSetting(screenName, "interval", interval);
    }

    function setMonitorCyclingTime(screenName, time) {
        updateMonitorCyclingSetting(screenName, "time", time);
    }

    function setMonitorCyclingFolderPath(screenName, folderPath) {
        updateMonitorCyclingSetting(screenName, "folderPath", folderPath);
    }

    function setNightModeEnabled(enabled) {
        nightModeEnabled = enabled;
        saveSettings();
    }

    function setNightModeTemperature(temperature) {
        nightModeTemperature = temperature;
        saveSettings();
    }

    function setNightModeHighTemperature(temperature) {
        nightModeHighTemperature = temperature;
        saveSettings();
    }

    function setNightModeAutoEnabled(enabled) {
        nightModeAutoEnabled = enabled;
        saveSettings();
    }

    function setNightModeAutoMode(mode) {
        nightModeAutoMode = mode;
        saveSettings();
    }

    function setNightModeStartHour(hour) {
        nightModeStartHour = hour;
        saveSettings();
    }

    function setNightModeStartMinute(minute) {
        nightModeStartMinute = minute;
        saveSettings();
    }

    function setNightModeEndHour(hour) {
        nightModeEndHour = hour;
        saveSettings();
    }

    function setNightModeEndMinute(minute) {
        nightModeEndMinute = minute;
        saveSettings();
    }

    function setNightModeTransitionMinutes(minutes) {
        nightModeTransitionMinutes = minutes;
        saveSettings();
    }

    function setDisplayGamma(gamma) {
        displayGamma = gamma;
        saveSettings();
    }

    function setDisplayContrast(contrast) {
        displayContrast = contrast;
        saveSettings();
    }

    function setNightModeUseIPLocation(use) {
        nightModeUseIPLocation = use;
        saveSettings();
    }

    function setLatitude(lat) {
        latitude = lat;
        saveSettings();
    }

    function setLongitude(lng) {
        longitude = lng;
        saveSettings();
    }

    function setNightModeLocationName(name) {
        nightModeLocationName = name;
        saveSettings();
    }

    function setThemeModeAutoEnabled(enabled) {
        themeModeAutoEnabled = enabled;
        saveSettings();
    }

    function setThemeModeAutoMode(mode) {
        themeModeAutoMode = mode;
        saveSettings();
    }

    function setThemeModeStartHour(hour) {
        themeModeStartHour = hour;
        saveSettings();
    }

    function setThemeModeStartMinute(minute) {
        themeModeStartMinute = minute;
        saveSettings();
    }

    function setThemeModeEndHour(hour) {
        themeModeEndHour = hour;
        saveSettings();
    }

    function setThemeModeEndMinute(minute) {
        themeModeEndMinute = minute;
        saveSettings();
    }

    function setThemeModeShareGammaSettings(share) {
        themeModeShareGammaSettings = share;
        saveSettings();
    }

    function getDockPins(id) {
        return dockPins[id] ?? [];
    }
    function setDockPins(id, apps) {
        dockPins = Object.assign({}, dockPins, {
            [id]: [...new Set(apps)]
        });
        saveSettings();
    }
    function removeDockPins(id) {
        const next = Object.assign({}, dockPins);
        delete next[id];
        dockPins = next;
        saveSettings();
    }
    function removePinnedApp(appId) {
        if (!appId)
            return;
        const next = {};
        for (const id in dockPins)
            next[id] = dockPins[id].filter(pin => pin !== appId);
        dockPins = next;
        saveSettings();
    }
    function setBarPinnedApps(apps) {
        barPinnedApps = apps;
        saveSettings();
    }

    function addBarPinnedApp(appId) {
        if (!appId)
            return;
        var currentPinned = [...barPinnedApps];
        if (currentPinned.indexOf(appId) === -1) {
            currentPinned.push(appId);
            setBarPinnedApps(currentPinned);
        }
    }

    function removeBarPinnedApp(appId) {
        if (!appId)
            return;
        var currentPinned = barPinnedApps.filter(id => id !== appId);
        setBarPinnedApps(currentPinned);
    }

    function hideTrayId(trayId) {
        if (!trayId)
            return;
        const current = [...hiddenTrayIds];
        if (current.indexOf(trayId) === -1) {
            current.push(trayId);
            hiddenTrayIds = current;
            saveSettings();
        }
    }

    function showTrayId(trayId) {
        if (!trayId)
            return;
        hiddenTrayIds = hiddenTrayIds.filter(id => id !== trayId);
        saveSettings();
    }

    function isHiddenTrayId(trayId) {
        return trayId && hiddenTrayIds.indexOf(trayId) !== -1;
    }

    function setTrayItemOrder(order) {
        trayItemOrder = order;
        saveSettings();
    }

    function addRecentColor(color) {
        const colorStr = color.toString();
        let recent = recentColors.slice();
        recent = recent.filter(c => c !== colorStr);
        recent.unshift(colorStr);
        if (recent.length > 5)
            recent = recent.slice(0, 5);
        recentColors = recent;
        saveSettings();
    }

    function removeRecentColor(color) {
        const colorStr = color.toString();
        const recent = recentColors.filter(c => c !== colorStr);
        if (recent.length === recentColors.length)
            return;
        recentColors = recent;
        saveSettings();
    }

    function setShowThirdPartyPlugins(enabled) {
        showThirdPartyPlugins = enabled;
        saveSettings();
    }

    function setPluginBrowserInstalledFirst(enabled) {
        pluginBrowserInstalledFirst = enabled;
        saveSettings();
    }

    function setPluginBrowserHideInstalled(enabled) {
        pluginBrowserHideInstalled = enabled;
        saveSettings();
    }

    function setPluginBrowserSortMode(mode) {
        if (mode === "type" || mode === "contributor")
            mode = "author";
        if (mode !== "default" && mode !== "recommended" && mode !== "name" && mode !== "author" && mode !== "category")
            mode = "default";
        pluginBrowserSortMode = mode;
        saveSettings();
    }

    function setLastBrightnessDevice(device) {
        lastBrightnessDevice = device;
        saveSettings();
    }

    function setBrightnessExponential(deviceName, enabled) {
        var newSettings = Object.assign({}, brightnessExponentialDevices);
        if (enabled) {
            newSettings[deviceName] = true;
        } else {
            delete newSettings[deviceName];
        }
        brightnessExponentialDevices = newSettings;
        saveSettings();
        brightnessDisplayHintChanged(deviceName);
    }

    function getBrightnessExponential(deviceName) {
        return brightnessExponentialDevices[deviceName] === true;
    }

    function setBrightnessUserSetValue(deviceName, value) {
        var newValues = Object.assign({}, brightnessUserSetValues);
        newValues[deviceName] = value;
        brightnessUserSetValues = newValues;
        saveSettings();
    }

    function clearBrightnessUserSetValue(deviceName) {
        var newValues = Object.assign({}, brightnessUserSetValues);
        delete newValues[deviceName];
        brightnessUserSetValues = newValues;
        saveSettings();
    }

    function setBrightnessExponent(deviceName, exponent) {
        var newValues = Object.assign({}, brightnessExponentValues);
        if (exponent !== undefined && exponent !== null) {
            newValues[deviceName] = exponent;
        } else {
            delete newValues[deviceName];
        }
        brightnessExponentValues = newValues;
        saveSettings();
    }

    function getBrightnessExponent(deviceName) {
        const value = brightnessExponentValues[deviceName];
        return value !== undefined ? value : 1.2;
    }

    function setEnabledGpuPciIds(pciIds) {
        enabledGpuPciIds = pciIds;
        saveSettings();
    }

    function setWifiDeviceOverride(device) {
        wifiDeviceOverride = device || "";
        saveSettings();
    }

    function setWeatherLocation(displayName, coordinates) {
        weatherLocation = displayName;
        weatherCoordinates = coordinates;
        saveSettings();
    }

    function hideApp(appId) {
        if (!appId)
            return;
        const current = [...hiddenApps];
        if (current.indexOf(appId) === -1) {
            current.push(appId);
            hiddenApps = current;
            saveSettings();
        }
    }

    function showApp(appId) {
        if (!appId)
            return;
        hiddenApps = hiddenApps.filter(id => id !== appId);
        saveSettings();
    }

    function isAppHidden(appId) {
        return appId && hiddenApps.indexOf(appId) !== -1;
    }

    function setAppOverride(appId, overrides) {
        if (!appId)
            return;
        const newOverrides = Object.assign({}, appOverrides);
        if (!overrides || Object.keys(overrides).length === 0) {
            delete newOverrides[appId];
        } else {
            newOverrides[appId] = overrides;
        }
        appOverrides = newOverrides;
        saveSettings();
    }

    function getAppOverride(appId) {
        if (!appId)
            return null;
        return appOverrides[appId] || null;
    }

    function clearAppOverride(appId) {
        if (!appId)
            return;
        const newOverrides = Object.assign({}, appOverrides);
        delete newOverrides[appId];
        appOverrides = newOverrides;
        saveSettings();
    }

    function setSearchAppActions(enabled) {
        searchAppActions = enabled;
        saveSettings();
    }

    function setVpnLastConnected(uuid) {
        vpnLastConnected = uuid || "";
        saveSettings();
    }

    function setDeviceMaxVolume(nodeName, maxPercent) {
        if (!nodeName)
            return;
        const updated = Object.assign({}, deviceMaxVolumes);
        const clamped = Math.max(100, Math.min(200, Math.round(maxPercent)));
        if (clamped === 100) {
            delete updated[nodeName];
        } else {
            updated[nodeName] = clamped;
        }
        deviceMaxVolumes = updated;
        saveSettings();
    }

    function setHiddenOutputDeviceNames(deviceNames) {
        if (!Array.isArray(deviceNames))
            return;
        hiddenOutputDeviceNames = deviceNames;
        saveSettings();
    }

    function setHiddenInputDeviceNames(deviceNames) {
        if (!Array.isArray(deviceNames))
            return;
        hiddenInputDeviceNames = deviceNames;
        saveSettings();
    }

    function getDeviceMaxVolume(nodeName) {
        if (!nodeName)
            return 100;
        return deviceMaxVolumes[nodeName] ?? 100;
    }

    function updateLocale() {
        if (!locale) {
            I18n._pickTranslation();
            return;
        }
        I18n.useLocale(locale, locale.startsWith("en") ? "" : I18n.folder + "/" + locale + ".json");
    }

    function setNotepadLastMode(mode) {
        if (notepadLastMode === mode)
            return;
        notepadLastMode = mode;
        saveSettings();
    }

    function setLauncherLastMode(mode) {
        launcherLastMode = mode;
        saveSettings();
    }

    function getLauncherRestoreMode() {
        if (!SettingsData.rememberLastMode)
            return "all";
        return launcherLastMode || "all";
    }

    function setLauncherLastFileSearchType(type) {
        launcherLastFileSearchType = type;
        saveSettings();
    }

    function setLauncherLastQuery(query) {
        launcherLastQuery = query;
        saveSettings();
    }

    function clearLauncherHistory() {
        launcherLastQuery = "";
        launcherQueryHistory = [];
        saveSettings();
    }

    function addLauncherHistory(query, skipLastQuery) {
        if (!SettingsData.launcherHistoryEnabled)
            return;
        let q = query.trim();

        if (!skipLastQuery)
            setLauncherLastQuery(q);

        if (!q)
            return;

        if (launcherQueryHistory.length > 0 && launcherQueryHistory[0] === q) {
            return;
        }

        let history = [...launcherQueryHistory];

        let idx = history.indexOf(q);
        if (idx !== -1)
            history.splice(idx, 1);

        history.unshift(q);
        if (history.length > 50)
            history = history.slice(0, 50);

        launcherQueryHistory = history;
        saveSettings();
    }

    function setAppDrawerLastMode(mode) {
        appDrawerLastMode = mode;
        saveSettings();
    }

    function setNiriOverviewLastMode(mode) {
        niriOverviewLastMode = mode;
        saveSettings();
    }

    function syncWallpaperForCurrentMode(mode) {
        if (!perModeWallpaper)
            return;
        var light = (mode !== undefined) ? mode : isLightMode;
        if (perMonitorWallpaper) {
            monitorWallpapers = light ? Object.assign({}, monitorWallpapersLight) : Object.assign({}, monitorWallpapersDark);
            return;
        }

        wallpaperPath = light ? wallpaperPathLight : wallpaperPathDark;
    }

    function _screenByName(screenName) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === screenName)
                return screens[i];
        }
        return null;
    }

    function _findMonitorValue(map, screenName) {
        const screen = _screenByName(screenName);
        if (!screen)
            return map[screenName];

        if (map[screen.name] !== undefined)
            return map[screen.name];
        if (screen.model && map[screen.model] !== undefined)
            return map[screen.model];
        if (typeof SettingsData !== "undefined") {
            var displayName = SettingsData.getScreenDisplayName(screen);
            if (displayName && map[displayName] !== undefined)
                return map[displayName];
        }
        return undefined;
    }

    function getMonitorWallpaper(screenName) {
        if (!perMonitorWallpaper)
            return wallpaperPath;
        var value = _findMonitorValue(monitorWallpapers, screenName);
        return value !== undefined ? value : wallpaperPath;
    }

    function getMonitorWallpaperFillMode(screenName) {
        var globalFillMode = (typeof SettingsData !== "undefined") ? SettingsData.wallpaperFillMode : "Fill";
        if (!perMonitorWallpaper)
            return globalFillMode;
        var value = _findMonitorValue(monitorWallpaperFillModes, screenName);
        return value !== undefined ? value : globalFillMode;
    }

    function setMonitorWallpaperFillMode(screenName, mode) {
        var screen = null;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === screenName) {
                screen = screens[i];
                break;
            }
        }

        if (!screen)
            return;

        var identifier = typeof SettingsData !== "undefined" ? SettingsData.getScreenDisplayName(screen) : screen.name;

        var newModes = {};
        for (var key in monitorWallpaperFillModes) {
            var isThisScreen = key === screen.name || (screen.model && key === screen.model);
            if (!isThisScreen)
                newModes[key] = monitorWallpaperFillModes[key];
        }

        newModes[identifier] = mode;
        monitorWallpaperFillModes = newModes;
        saveSettings();
    }

    function getMonitorCyclingSettings(screenName) {
        var defaults = {
            "enabled": false,
            "random": false,
            "recursive": false,
            "mode": "interval",
            "interval": 300,
            "time": "06:00",
            "folderPath": ""
        };
        var value = _findMonitorValue(monitorCyclingSettings, screenName);
        return Object.assign({}, defaults, value !== undefined ? value : {});
    }

    FileView {
        id: settingsFile

        path: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/dms/session.json"
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            _hasUnsavedChanges = false;
            parseSettings(settingsFile.text());
        }
        onSaveFailed: error => {
            root._isReadOnly = true;
            root._hasUnsavedChanges = root._checkForUnsavedChanges();
        }
    }

    Process {
        id: sessionWritableCheckProcess

        property string sessionPath: Paths.strip(settingsFile.path)

        command: ["sh", "-c", "[ ! -f \"" + sessionPath + "\" ] || [ -w \"" + sessionPath + "\" ] && echo 'writable' || echo 'readonly'"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const result = text.trim();
                root._onWritableCheckComplete(result === "writable");
            }
        }
    }
}
