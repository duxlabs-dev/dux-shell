pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("CacheData")

    readonly property int cacheConfigVersion: 3

    readonly property string _stateUrl: StandardPaths.writableLocation(StandardPaths.GenericCacheLocation)
    readonly property string _stateDir: Paths.strip(_stateUrl)

    property bool _loading: false
    property bool _hasLoaded: false
    property int _loadedCacheVersion: 0

    readonly property var _pinKeys: ["brightnessDevicePins", "wifiNetworkPins", "bluetoothDevicePins", "audioInputDevicePins", "audioOutputDevicePins"]
    readonly property var _historyKeys: ["browserUsageHistory", "filePickerUsageHistory"]
    readonly property var _dataKeys: ["fileBrowserSettings", "processFilterTypes", "pluginViewSort", "pluginViewFilter", "dashFocusCardId", "controlCenterCollapsedCategories", "mediaLyricsOpen", "matugenPreviews", "matugenSeedPreviews", "matugenAppliedKey", "lockScreenPlacementSamples"].concat(_pinKeys, _historyKeys)

    property string pluginViewFilter: "enabled"
    property string dashFocusCardId: ""
    property var controlCenterCollapsedCategories: []
    property bool mediaLyricsOpen: false
    property var matugenPreviews: ({})
    property var matugenSeedPreviews: ({})
    property string matugenAppliedKey: ""
    property var lockScreenPlacementSamples: ({})
    property var pluginViewSort: ({
            by: "modified",
            descending: true
        })
    property var processFilterTypes: ["user", "system"]

    property var browserUsageHistory: ({})
    property var filePickerUsageHistory: ({})

    property var brightnessDevicePins: ({})
    property var wifiNetworkPins: ({})
    property var bluetoothDevicePins: ({})
    property var audioInputDevicePins: ({})
    property var audioOutputDevicePins: ({})

    property var fileBrowserSettings: ({})

    Component.onCompleted: {
        loadCache();
    }

    function loadCache() {
        _loading = true;
        try {
            parseCache(cacheFile.text());
        } finally {
            _loading = false;
            _hasLoaded = true;
        }
    }

    function set(key, value) {
        if (_dataKeys.indexOf(key) < 0) {
            log.warn("Unknown cache key:", key);
            return;
        }
        root[key] = value;
        saveCache();
    }

    function migratePins(pins) {
        if (!pins)
            return;
        if (!_hasLoaded)
            loadCache();
        if (_loadedCacheVersion >= cacheConfigVersion)
            return;

        let migrated = false;
        for (const key of _pinKeys) {
            const legacy = pins[key];
            if (!legacy || Object.keys(legacy).length === 0)
                continue;
            if (Object.keys(root[key] || {}).length > 0)
                continue;
            root[key] = legacy;
            migrated = true;
        }

        if (!migrated)
            return;
        log.info("Migrated device pins from settings.json");
        saveCache();
    }

    function migrateUsageHistories(histories) {
        if (!histories)
            return;
        if (!_hasLoaded)
            loadCache();

        let migrated = false;
        for (const key of _historyKeys) {
            const legacy = histories[key];
            if (!legacy || Object.keys(legacy).length === 0)
                continue;
            if (Object.keys(root[key] || {}).length > 0)
                continue;
            root[key] = legacy;
            migrated = true;
        }

        if (!migrated)
            return;
        log.info("Migrated usage histories from settings.json");
        saveCache();
    }

    function parseCache(content) {
        _loading = true;
        try {
            if (content && content.trim()) {
                const cache = JSON.parse(content);
                _loadedCacheVersion = cache.configVersion || 0;

                pluginViewFilter = ["all", "enabled", "disabled", "updates"].includes(cache.pluginViewFilter) ? cache.pluginViewFilter : "enabled";
                dashFocusCardId = typeof cache.dashFocusCardId === "string" ? cache.dashFocusCardId : "";
                controlCenterCollapsedCategories = Array.isArray(cache.controlCenterCollapsedCategories) ? cache.controlCenterCollapsedCategories.filter(id => typeof id === "string") : [];
                mediaLyricsOpen = cache.mediaLyricsOpen === true;
                matugenPreviews = typeof cache.matugenPreviews?.key === "string" ? cache.matugenPreviews : {};
                matugenSeedPreviews = cache.matugenSeedPreviews && typeof cache.matugenSeedPreviews === "object" && !Array.isArray(cache.matugenSeedPreviews) ? cache.matugenSeedPreviews : {};
                matugenAppliedKey = typeof cache.matugenAppliedKey === "string" ? cache.matugenAppliedKey : "";
                lockScreenPlacementSamples = cache.lockScreenPlacementSamples && typeof cache.lockScreenPlacementSamples === "object" && !Array.isArray(cache.lockScreenPlacementSamples) ? cache.lockScreenPlacementSamples : {};
                const pluginSort = cache.pluginViewSort;
                pluginViewSort = {
                    by: ["name", "author", "modified"].includes(pluginSort?.by) ? pluginSort.by : "modified",
                    descending: typeof pluginSort?.descending === "boolean" ? pluginSort.descending : true
                };
                processFilterTypes = Array.isArray(cache.processFilterTypes) ? cache.processFilterTypes.filter(value => value === "user" || value === "system") : ["user", "system"];

                if (cache.fileBrowserSettings !== undefined) {
                    fileBrowserSettings = cache.fileBrowserSettings;
                } else if (cache.fileBrowserViewMode !== undefined) {
                    fileBrowserSettings = {
                        "wallpaper": {
                            "lastPath": cache.wallpaperLastPath || "",
                            "viewMode": cache.fileBrowserViewMode || "grid",
                            "sortBy": cache.fileBrowserSortBy || "name",
                            "sortAscending": cache.fileBrowserSortAscending !== undefined ? cache.fileBrowserSortAscending : true,
                            "iconSizeIndex": cache.fileBrowserIconSizeIndex !== undefined ? cache.fileBrowserIconSizeIndex : 1,
                            "showSidebar": cache.fileBrowserShowSidebar !== undefined ? cache.fileBrowserShowSidebar : true
                        },
                        "profile": {
                            "lastPath": cache.profileLastPath || "",
                            "viewMode": cache.fileBrowserViewMode || "grid",
                            "sortBy": cache.fileBrowserSortBy || "name",
                            "sortAscending": cache.fileBrowserSortAscending !== undefined ? cache.fileBrowserSortAscending : true,
                            "iconSizeIndex": cache.fileBrowserIconSizeIndex !== undefined ? cache.fileBrowserIconSizeIndex : 1,
                            "showSidebar": cache.fileBrowserShowSidebar !== undefined ? cache.fileBrowserShowSidebar : true
                        },
                        "file": {
                            "lastPath": "",
                            "viewMode": "list",
                            "sortBy": "name",
                            "sortAscending": true,
                            "iconSizeIndex": 1,
                            "showSidebar": true
                        }
                    };
                }
                fileBrowserSettings = withLegacyLastPaths(fileBrowserSettings, cache);

                for (const key of _pinKeys.concat(_historyKeys)) {
                    root[key] = cache[key] !== undefined ? cache[key] : {};
                }

                if (cache.configVersion === undefined) {
                    migrateFromUndefinedToV1(cache);
                    cleanupUnusedKeys();
                    saveCache();
                }
            }
        } catch (e) {
            log.warn("Failed to parse cache:", e.message);
        } finally {
            _loading = false;
        }
    }

    function withLegacyLastPaths(settings, legacy) {
        const merged = Object.assign({}, settings);
        for (const [bucket, lastPath] of [["wallpaper", legacy.wallpaperLastPath], ["profile", legacy.profileLastPath]]) {
            if (!lastPath || merged[bucket]?.lastPath)
                continue;
            merged[bucket] = Object.assign({}, merged[bucket], {
                "lastPath": lastPath
            });
        }
        return merged;
    }

    function saveCache() {
        if (_loading)
            return;
        const data = {
            "processFilterTypes": processFilterTypes,
            "pluginViewSort": pluginViewSort,
            "pluginViewFilter": pluginViewFilter,
            "dashFocusCardId": dashFocusCardId,
            "controlCenterCollapsedCategories": controlCenterCollapsedCategories,
            "mediaLyricsOpen": mediaLyricsOpen,
            "matugenPreviews": matugenPreviews,
            "matugenSeedPreviews": matugenSeedPreviews,
            "matugenAppliedKey": matugenAppliedKey,
            "lockScreenPlacementSamples": lockScreenPlacementSamples,
            "fileBrowserSettings": fileBrowserSettings,
            "configVersion": cacheConfigVersion
        };
        for (const key of _pinKeys.concat(_historyKeys)) {
            data[key] = root[key];
        }
        cacheFile.setText(JSON.stringify(data, null, 2));
    }

    function migrateFromUndefinedToV1(cache) {
        log.info("Migrating configuration from undefined to version 1");
    }

    function cleanupUnusedKeys() {
        const validKeys = _dataKeys.concat(["configVersion"]);

        try {
            const content = cacheFile.text();
            if (!content || !content.trim())
                return;
            const cache = JSON.parse(content);
            let needsSave = false;

            for (const key in cache) {
                if (!validKeys.includes(key)) {
                    log.debug("Removing unused key:", key);
                    delete cache[key];
                    needsSave = true;
                }
            }

            if (needsSave) {
                cacheFile.setText(JSON.stringify(cache, null, 2));
            }
        } catch (e) {
            log.warn("Failed to cleanup unused keys:", e.message);
        }
    }

    function loadLauncherCache() {
        try {
            var content = launcherCacheFile.text();
            if (content && content.trim())
                return JSON.parse(content);
        } catch (e) {
            log.warn("Failed to parse launcher cache:", e.message);
        }
        return null;
    }

    function saveLauncherCache(sections) {
        if (_loading)
            return;
        launcherCacheFile.setText(JSON.stringify(sections));
    }

    FileView {
        id: launcherCacheFile

        path: _stateDir + "/dms/launcher_cache.json"
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
    }

    FileView {
        id: cacheFile

        path: _stateDir + "/dms/cache.json"
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        onLoaded: {
            parseCache(cacheFile.text());
        }
        onLoadFailed: error => {
            log.info("No cache file found, starting fresh");
        }
    }
}
