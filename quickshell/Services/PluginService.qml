pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../Common/PluginRanking.js" as PluginRanking

Singleton {
    id: root
    readonly property var log: Log.scoped("PluginService")

    property var availablePlugins: ({})
    property var loadedPlugins: ({})
    property var pluginWidgetComponents: ({})
    property var pluginDaemonComponents: ({})
    property var pluginLauncherComponents: ({})
    property var pluginDesktopComponents: ({})
    property var pluginDashComponents: ({})
    property var pluginDashCardComponents: ({})
    property var availablePluginsList: []
    readonly property string pluginDirectory: Paths.strip(Paths.config) + "/plugins"

    property bool pluginDirectoryExists: false
    property string systemPluginDirectory: "/etc/xdg/quickshell/dms-plugins"
    readonly property string previewApiBase: Site.api + "/previews/"

    property var knownManifests: ({})
    property var pathToPluginId: ({})
    property var pluginInstances: ({})
    property var pluginDaemonInstances: ({})
    property var _daemonSpawnQueue: []
    property var globalVars: ({})
    property var pluginLoadErrors: ({})
    property var _componentRevisions: ({})
    property var directoryModifiedTimes: ({})
    property string pendingSettingsRevealPluginId: ""

    property var _translationLoaders: ({})

    property var _stateCache: ({})
    property var _stateLoaded: ({})
    property var _stateWriters: ({})
    property var _stateDirtyPlugins: ({})
    property bool _stateDirCreated: false

    signal pluginLoaded(string pluginId)
    signal pluginUnloaded(string pluginId)
    signal pluginLoadFailed(string pluginId, string error)
    signal pluginDataChanged(string pluginId)
    signal pluginStateChanged(string pluginId)
    signal registryInstallFinished(string pluginId, bool success)
    signal pluginListUpdated
    signal globalVarChanged(string pluginId, string varName)
    signal requestLauncherUpdate(string pluginId)

    Timer {
        id: resyncDebounce
        interval: 120
        repeat: false
        onTriggered: resyncAll()
    }

    Timer {
        id: _stateWriteTimer
        interval: 150
        repeat: false
        onTriggered: root._flushDirtyStates()
    }

    // Zero-interval so daemons spawn on the next event-loop tick, after any
    // deferred destroy() of a previous generation has fully unregistered its
    // IpcHandlers (quickshell#898 leaves stale registrations otherwise)
    Timer {
        id: _daemonSpawnTimer
        interval: 0
        repeat: false
        onTriggered: root._drainDaemonSpawnQueue()
    }

    Process {
        id: directoryCheckProcess
        command: ["test", "-d", root.pluginDirectory]
        onExited: exitCode => {
            root.pluginDirectoryExists = (exitCode === 0);
        }
    }

    function checkPluginDirectoryExists() {
        directoryCheckProcess.running = true;
    }

    Component.onCompleted: {
        // A FolderListModel never given a folder lists the working directory.
        userWatcher.folder = AdminPolicy.disableUserPlugins ? "" : Paths.toFileUrl(root.pluginDirectory);
        systemWatcher.folder = Paths.toFileUrl(root.systemPluginDirectory);
        Qt.callLater(resyncAll);
        Qt.callLater(checkPluginDirectoryExists);
    }

    FolderListModel {
        id: userWatcher
        showDirs: true
        showFiles: false
        showDotAndDotDot: false

        onCountChanged: resyncDebounce.restart()
        onStatusChanged: {
            if (status === FolderListModel.Ready)
                resyncDebounce.restart();
        }
    }

    FolderListModel {
        id: systemWatcher
        showDirs: true
        showFiles: false
        showDotAndDotDot: false

        onCountChanged: resyncDebounce.restart()
        onStatusChanged: {
            if (status === FolderListModel.Ready)
                resyncDebounce.restart();
        }
    }

    function snapshotModel(model, sourceTag) {
        const out = [];
        const n = model.count;
        const baseDir = sourceTag === "user" ? pluginDirectory : systemPluginDirectory;
        for (let i = 0; i < n; i++) {
            let dirPath = model.get(i, "filePath");
            if (dirPath.startsWith("file://")) {
                dirPath = dirPath.substring(7);
            }
            if (!dirPath.startsWith(baseDir)) {
                continue;
            }
            const manifestPath = dirPath + "/plugin.json";
            out.push({
                path: manifestPath,
                source: sourceTag,
                directory: dirPath,
                modifiedAt: new Date(model.get(i, "fileModified")).getTime() || 0
            });
        }
        return out;
    }

    function resyncAll() {
        const userList = AdminPolicy.disableUserPlugins ? [] : snapshotModel(userWatcher, "user");
        const sysList = snapshotModel(systemWatcher, "system");
        const seenPaths = {};
        const modifiedTimes = {};
        for (const entry of userList.concat(sysList))
            modifiedTimes[entry.directory] = entry.modifiedAt;
        directoryModifiedTimes = modifiedTimes;

        function consider(entry) {
            const key = entry.path;
            seenPaths[key] = true;
            const prev = knownManifests[key];
            if (!prev) {
                loadPluginManifestFile(entry.path, entry.source, Date.now());
            }
        }
        for (let i = 0; i < userList.length; i++)
            consider(userList[i]);
        for (let i = 0; i < sysList.length; i++)
            consider(sysList[i]);

        const removed = [];
        for (const path in knownManifests) {
            if (!seenPaths[path])
                removed.push(path);
        }
        if (removed.length) {
            removed.forEach(function (path) {
                const pid = pathToPluginId[path];
                if (pid) {
                    unregisterPluginByPath(path, pid);
                }
                delete knownManifests[path];
                delete pathToPluginId[path];
            });
            _updateAvailablePluginsList();
            pluginListUpdated();
        }
    }

    function loadPluginManifestFile(manifestPathNoScheme, sourceTag, mtimeEpochMs) {
        const loader = manifestFvComp.createObject(root, {
            absPath: manifestPathNoScheme,
            path: manifestPathNoScheme,
            sourceTag: sourceTag,
            mtimeEpochMs: mtimeEpochMs
        });
    }

    Component {
        id: manifestFvComp
        FileView {
            id: fv
            property string absPath: ""
            property string sourceTag: ""
            property double mtimeEpochMs: 0
            onLoaded: {
                try {
                    let raw = text();
                    if (raw.charCodeAt(0) === 0xFEFF)
                        raw = raw.slice(1);
                    const manifest = JSON.parse(raw);
                    root._onManifestParsed(absPath, manifest, sourceTag, mtimeEpochMs);
                } catch (e) {
                    root.log.error("bad manifest", absPath, e.message);
                    root.knownManifests[absPath] = {
                        mtime: mtimeEpochMs,
                        source: sourceTag,
                        bad: true
                    };
                }
                fv.destroy();
            }
            onLoadFailed: err => {
                // a directory without plugin.json is not a plugin, not a failed one (#3112)
                if (err !== FileViewError.FileNotFound)
                    root.log.warn("manifest load failed", absPath, err);
                fv.destroy();
            }
        }
    }

    readonly property var pluginSurfaceKeys: ["widget", "desktop", "daemon", "launcher", "dash", "dashCard"]

    Connections {
        target: I18n
        function onLocaleApplied() {
            for (const pluginId in root.availablePlugins)
                root._loadPluginTranslations(pluginId, root.availablePlugins[pluginId].pluginDirectory);
        }
    }

    function _dropPluginTranslations(pluginId) {
        const loader = _translationLoaders[pluginId];
        if (loader) {
            loader.destroy();
            delete _translationLoaders[pluginId];
        }
        I18n.unregisterPluginTranslations(pluginId);
    }

    function _loadPluginTranslations(pluginId, dir) {
        if (!dir)
            return;
        const loader = _translationLoaders[pluginId];
        if (loader) {
            loader.destroy();
            delete _translationLoaders[pluginId];
        }
        const candidates = I18n.localeCandidates();
        if (!candidates.length) {
            I18n.unregisterPluginTranslations(pluginId);
            return;
        }
        _tryTranslationCandidate(pluginId, dir, candidates, 0);
    }

    function _tryTranslationCandidate(pluginId, dir, candidates, index) {
        if (index >= candidates.length) {
            delete _translationLoaders[pluginId];
            I18n.unregisterPluginTranslations(pluginId);
            return;
        }
        _translationLoaders[pluginId] = translationFvComp.createObject(root, {
            pluginId: pluginId,
            dir: dir,
            candidates: candidates,
            index: index,
            path: dir + "/translations/" + candidates[index] + ".json"
        });
    }

    Component {
        id: translationFvComp
        FileView {
            id: tfv
            property string pluginId: ""
            property string dir: ""
            property var candidates: []
            property int index: 0
            printErrors: false
            onLoaded: {
                try {
                    I18n.registerPluginTranslations(pluginId, JSON.parse(text()));
                } catch (e) {
                    root.log.warn("bad plugin translations", path, e.message);
                    I18n.unregisterPluginTranslations(pluginId);
                }
                delete root._translationLoaders[pluginId];
                tfv.destroy();
            }
            onLoadFailed: err => {
                tfv.destroy();
                root._tryTranslationCandidate(pluginId, dir, candidates, index + 1);
            }
        }
    }

    function _pluginFilePath(dir, rel) {
        if (!rel)
            return "";
        const path = String(rel);
        let decoded;
        try {
            decoded = decodeURIComponent(path);
        } catch (e) {
            decoded = "..";
        }
        if (decoded.split("/").includes("..")) {
            log.warn("plugin path outside its directory, refusing:", path, "in", dir);
            return "";
        }
        return dir + "/" + (path.startsWith("./") ? path.slice(2) : path);
    }

    function _deriveLegacySurface(type, capabilities) {
        if (type === "daemon")
            return "daemon";
        if (type === "launcher" || (capabilities && capabilities.includes("launcher")))
            return "launcher";
        switch (type) {
        case "desktop":
        case "dash":
        case "dashCard":
            return type;
        }
        return "widget";
    }

    function _resolveComponentPaths(manifest, dir) {
        const paths = {};
        if (manifest.components && typeof manifest.components === "object") {
            for (const surface in manifest.components) {
                if (!pluginSurfaceKeys.includes(surface)) {
                    log.warn("unknown plugin surface", surface, "in", dir);
                    continue;
                }
                const path = _pluginFilePath(dir, manifest.components[surface]);
                if (!path)
                    continue;
                paths[surface] = path;
            }
            return paths;
        }
        const legacyPath = _pluginFilePath(dir, manifest.component);
        if (legacyPath)
            paths[_deriveLegacySurface(manifest.type, manifest.capabilities)] = legacyPath;
        return paths;
    }

    function _onManifestParsed(absPath, manifest, sourceTag, mtimeEpochMs) {
        if (!manifest || !manifest.id || !manifest.name) {
            log.error("invalid manifest fields:", absPath);
            knownManifests[absPath] = {
                mtime: mtimeEpochMs,
                source: sourceTag,
                bad: true
            };
            return;
        }

        const dir = absPath.substring(0, absPath.lastIndexOf('/'));
        const settingsPath = _pluginFilePath(dir, manifest.settings);
        const startupCheckPath = _pluginFilePath(dir, manifest.startupCheck);

        const componentPaths = _resolveComponentPaths(manifest, dir);
        const surfaces = Object.keys(componentPaths);
        if (surfaces.length === 0 && !manifest.lyrics?.command) {
            log.error("no valid component surfaces in manifest:", absPath);
            knownManifests[absPath] = {
                mtime: mtimeEpochMs,
                source: sourceTag,
                bad: true
            };
            return;
        }

        const info = {};
        for (const k in manifest)
            info[k] = manifest[k];

        let perms = manifest.permissions;
        if (typeof perms === "string") {
            perms = perms.split(/\s*,\s*/);
        }
        if (!Array.isArray(perms)) {
            perms = [];
        }
        info.permissions = perms.map(p => String(p).trim());

        info.manifestPath = absPath;
        info.pluginDirectory = dir;
        info.componentPaths = componentPaths;
        info.surfaces = surfaces;
        info.componentPath = componentPaths.widget || componentPaths[surfaces[0]];
        info.settingsPath = settingsPath || null;
        info.startupCheckPath = startupCheckPath || null;
        info.loaded = isPluginLoaded(manifest.id);
        info.type = manifest.type || (manifest.components ? "composite" : "widget");
        info.source = sourceTag;
        info.requires_dms = manifest.requires_dms || null;

        const existing = availablePlugins[manifest.id];
        const shouldReplace = (!existing) || (existing && existing.source === "system" && sourceTag === "user");

        if (shouldReplace) {
            if (existing && existing.loaded && existing.source !== sourceTag) {
                unloadPlugin(manifest.id);
            }
            const newMap = Object.assign({}, availablePlugins);
            newMap[manifest.id] = info;
            availablePlugins = newMap;
            pathToPluginId[absPath] = manifest.id;
            knownManifests[absPath] = {
                mtime: mtimeEpochMs,
                source: sourceTag
            };
            _updateAvailablePluginsList();
            _loadPluginTranslations(manifest.id, dir);
            const isPureDesktop = surfaces.length === 1 && surfaces[0] === "desktop";
            const enabled = isPureDesktop || SettingsData.getPluginSetting(manifest.id, "enabled", false);
            if (enabled && !info.loaded && !installingPlugins[manifest.id])
                runStartupGate(manifest.id);
            pluginListUpdated();
        } else {
            knownManifests[absPath] = {
                mtime: mtimeEpochMs,
                source: sourceTag,
                shadowedBy: existing.source
            };
            pathToPluginId[absPath] = manifest.id;
        }
    }

    function unregisterPluginByPath(absPath, pluginId) {
        const current = availablePlugins[pluginId];
        if (current && current.manifestPath === absPath) {
            if (current.loaded)
                unloadPlugin(pluginId);
            _dropPluginTranslations(pluginId);
            const newMap = Object.assign({}, availablePlugins);
            delete newMap[pluginId];
            availablePlugins = newMap;
        }
    }

    function pluginComponentUrl(pluginId, path) {
        if (!path)
            return "";
        const url = Paths.toFileUrl(path);
        const revision = _componentRevisions[pluginId];
        return revision ? url + "?revision=" + revision : url;
    }

    function _invalidatePluginComponents(pluginId) {
        _componentRevisions = Object.assign({}, _componentRevisions, {
            [pluginId]: (_componentRevisions[pluginId] || 0) + 1
        });
    }

    function _preparePluginReload(pluginId) {
        if (isPluginLoaded(pluginId) && !unloadPlugin(pluginId))
            return false;
        _invalidatePluginComponents(pluginId);
        return true;
    }

    function updatePlugin(pluginId, callback) {
        // Installed entries carry the registry's requires_dms, i.e. the version an update would fetch
        const installed = (DMSService.installedPlugins || []).find(plugin => plugin.id === pluginId);
        if (installed?.requires_dms && !checkPluginCompatibility(installed.requires_dms)) {
            if (callback)
                callback({
                    error: I18n.tr("Requires DMS %1", "plugin incompatibility notice, %1 is the required DMS version").arg(installed.requires_dms)
                });
            return;
        }
        DMSService.update(pluginId, response => {
            if (!response.error)
                forceRescanPlugin(pluginId);
            if (callback)
                callback(response);
        });
    }

    function loadPlugin(pluginId, bustCache) {
        const plugin = availablePlugins[pluginId];
        if (!plugin) {
            log.error("Plugin not found:", pluginId);
            pluginLoadFailed(pluginId, "Plugin not found");
            return false;
        }

        if (plugin.loaded) {
            return true;
        }

        const componentPaths = plugin.componentPaths || {};
        const surfaces = Object.keys(componentPaths);
        if (surfaces.length === 0 && !plugin.lyrics?.command) {
            log.error("Plugin has no component surfaces:", pluginId);
            pluginLoadFailed(pluginId, "No component surfaces");
            return false;
        }

        const newWidgets = Object.assign({}, pluginWidgetComponents);
        const newDesktop = Object.assign({}, pluginDesktopComponents);
        const newDaemons = Object.assign({}, pluginDaemonComponents);
        const newLaunchers = Object.assign({}, pluginLauncherComponents);
        const newDash = Object.assign({}, pluginDashComponents);
        const newDashCards = Object.assign({}, pluginDashCardComponents);
        const newInstances = Object.assign({}, pluginInstances);
        const newDaemonInstances = Object.assign({}, pluginDaemonInstances);

        const prevInstance = newInstances[pluginId];
        if (prevInstance) {
            prevInstance.destroy();
            delete newInstances[pluginId];
        }
        const prevDaemon = newDaemonInstances[pluginId];
        if (prevDaemon) {
            prevDaemon.destroy();
            delete newDaemonInstances[pluginId];
        }

        if (bustCache)
            _invalidatePluginComponents(pluginId);

        try {
            const comps = {};
            for (const surface of surfaces) {
                const url = pluginComponentUrl(pluginId, componentPaths[surface]);
                // A parentless component dies with the first Loader that used it.
                const comp = Qt.createComponent(url, Component.PreferSynchronous, root);
                comps[surface] = comp;
                if (comp.status === Component.Error) {
                    const error = comp.errorString();
                    log.error("component error", pluginId, surface, error);
                    _destroyComponents(Object.values(comps));
                    _setLoadError(pluginId, {
                        title: error,
                        details: ""
                    });
                    pluginLoadFailed(pluginId, error);
                    return false;
                }
            }

            if (comps.launcher)
                newLaunchers[pluginId] = comps.launcher;

            if (comps.daemon) {
                newDaemons[pluginId] = comps.daemon;
                _daemonSpawnQueue.push(pluginId);
                _daemonSpawnTimer.restart();
            }

            if (comps.widget)
                newWidgets[pluginId] = comps.widget;
            if (comps.desktop)
                newDesktop[pluginId] = comps.desktop;
            if (comps.dash)
                newDash[pluginId] = comps.dash;
            if (comps.dashCard)
                newDashCards[pluginId] = comps.dashCard;

            pluginWidgetComponents = newWidgets;
            pluginDesktopComponents = newDesktop;
            pluginDashComponents = newDash;
            pluginDashCardComponents = newDashCards;
            pluginDaemonComponents = newDaemons;
            pluginLauncherComponents = newLaunchers;
            pluginInstances = newInstances;
            pluginDaemonInstances = newDaemonInstances;

            plugin.loaded = true;
            const newLoaded = Object.assign({}, loadedPlugins);
            newLoaded[pluginId] = plugin;
            loadedPlugins = newLoaded;

            _clearLoadError(pluginId);
            pluginLoaded(pluginId);
            return true;
        } catch (e) {
            log.error("Error loading plugin:", pluginId, e.message);
            _setLoadError(pluginId, {
                title: e.message,
                details: ""
            });
            pluginLoadFailed(pluginId, e.message);
            return false;
        }
    }

    function _createDaemonInstance(pluginId, comp) {
        const instance = comp.createObject(root, {
            "pluginId": pluginId,
            "pluginService": root
        });
        if (!instance) {
            log.error("failed to instantiate daemon surface:", pluginId, comp.errorString());
            return null;
        }
        if (instance.popoutService !== undefined)
            instance.popoutService = PopoutService;
        log.info("Daemon plugin loaded:", pluginId);
        return instance;
    }

    function _drainDaemonSpawnQueue() {
        const queue = _daemonSpawnQueue;
        _daemonSpawnQueue = [];
        const newDaemonInstances = Object.assign({}, pluginDaemonInstances);
        for (const pluginId of queue) {
            const comp = pluginDaemonComponents[pluginId];
            if (!comp || !isPluginLoaded(pluginId) || newDaemonInstances[pluginId])
                continue;
            const daemon = _createDaemonInstance(pluginId, comp);
            if (daemon)
                newDaemonInstances[pluginId] = daemon;
        }
        pluginDaemonInstances = newDaemonInstances;
    }

    function unloadPlugin(pluginId) {
        const plugin = loadedPlugins[pluginId];
        if (!plugin) {
            log.warn("Plugin not loaded:", pluginId);
            return false;
        }

        try {
            const components = [pluginDaemonComponents, pluginLauncherComponents, pluginDesktopComponents, pluginWidgetComponents, pluginDashComponents, pluginDashCardComponents].map(map => map[pluginId]).filter(comp => !!comp);
            const instance = pluginInstances[pluginId];
            if (instance) {
                instance.destroy();
                const newInstances = Object.assign({}, pluginInstances);
                delete newInstances[pluginId];
                pluginInstances = newInstances;
            }

            const daemonInstance = pluginDaemonInstances[pluginId];
            if (daemonInstance) {
                daemonInstance.destroy();
                const newDaemonInstances = Object.assign({}, pluginDaemonInstances);
                delete newDaemonInstances[pluginId];
                pluginDaemonInstances = newDaemonInstances;
            }

            if (pluginDaemonComponents[pluginId]) {
                const newDaemons = Object.assign({}, pluginDaemonComponents);
                delete newDaemons[pluginId];
                pluginDaemonComponents = newDaemons;
            }
            if (pluginLauncherComponents[pluginId]) {
                const newLaunchers = Object.assign({}, pluginLauncherComponents);
                delete newLaunchers[pluginId];
                pluginLauncherComponents = newLaunchers;
            }
            if (pluginDesktopComponents[pluginId]) {
                const newDesktop = Object.assign({}, pluginDesktopComponents);
                delete newDesktop[pluginId];
                pluginDesktopComponents = newDesktop;
            }
            if (pluginWidgetComponents[pluginId]) {
                const newComponents = Object.assign({}, pluginWidgetComponents);
                delete newComponents[pluginId];
                pluginWidgetComponents = newComponents;
            }
            if (pluginDashComponents[pluginId]) {
                const newDash = Object.assign({}, pluginDashComponents);
                delete newDash[pluginId];
                pluginDashComponents = newDash;
            }
            if (pluginDashCardComponents[pluginId]) {
                const newDashCards = Object.assign({}, pluginDashCardComponents);
                delete newDashCards[pluginId];
                pluginDashCardComponents = newDashCards;
            }

            plugin.loaded = false;
            const newLoaded = Object.assign({}, loadedPlugins);
            delete newLoaded[pluginId];
            loadedPlugins = newLoaded;

            _destroyComponents(components);
            _cleanupPluginStateWriter(pluginId);
            pluginUnloaded(pluginId);
            return true;
        } catch (error) {
            log.error("Error unloading plugin:", pluginId, "Error:", error.message);
            return false;
        }
    }

    function _destroyComponents(components) {
        for (const comp of components)
            comp.destroy();
    }

    function getWidgetComponents() {
        return pluginWidgetComponents;
    }

    function getDaemonComponents() {
        return pluginDaemonComponents;
    }

    function getDesktopComponents() {
        return pluginDesktopComponents;
    }

    function getDashComponents() {
        return pluginDashComponents;
    }

    function getDashCardComponents() {
        return pluginDashCardComponents;
    }

    function getAvailablePlugins() {
        return availablePluginsList;
    }

    function _updateAvailablePluginsList() {
        const result = [];
        for (const key in availablePlugins) {
            result.push(availablePlugins[key]);
        }
        availablePluginsList = result;
    }

    function getPluginVariants(pluginId) {
        const plugin = availablePlugins[pluginId];
        if (!plugin) {
            return [];
        }
        const variants = SettingsData.getPluginSetting(pluginId, "variants", []);
        return variants;
    }

    function getAllPluginVariants() {
        const result = [];
        for (const pluginId in availablePlugins) {
            const plugin = availablePlugins[pluginId];
            const hasWidgetSurface = plugin.surfaces ? plugin.surfaces.includes("widget") : (plugin.type === "widget");
            if (!hasWidgetSurface) {
                continue;
            }
            const variants = getPluginVariants(pluginId);
            if (variants.length === 0) {
                result.push({
                    pluginId: pluginId,
                    variantId: null,
                    fullId: pluginId,
                    name: plugin.name,
                    icon: plugin.icon || "extension",
                    description: plugin.description || "Plugin widget",
                    loaded: plugin.loaded
                });
            } else {
                for (let i = 0; i < variants.length; i++) {
                    const variant = variants[i];
                    result.push({
                        pluginId: pluginId,
                        variantId: variant.id,
                        fullId: pluginId + ":" + variant.id,
                        name: plugin.name + " - " + variant.name,
                        icon: variant.icon || plugin.icon || "extension",
                        description: variant.description || plugin.description || "Plugin widget variant",
                        loaded: plugin.loaded
                    });
                }
            }
        }
        return result;
    }

    function createPluginVariant(pluginId, variantName, variantConfig) {
        const variants = getPluginVariants(pluginId);
        const variantId = "variant_" + Date.now();
        const newVariant = Object.assign({}, variantConfig, {
            id: variantId,
            name: variantName
        });
        variants.push(newVariant);
        SettingsData.setPluginSetting(pluginId, "variants", variants);
        pluginDataChanged(pluginId);
        return variantId;
    }

    function removePluginVariant(pluginId, variantId) {
        const variants = getPluginVariants(pluginId);
        const newVariants = variants.filter(function (v) {
            return v.id !== variantId;
        });
        SettingsData.setPluginSetting(pluginId, "variants", newVariants);

        const fullId = pluginId + ":" + variantId;
        removeWidgetFromDankBar(fullId);

        pluginDataChanged(pluginId);
    }

    function removeWidgetFromDankBar(widgetId) {
        function filterWidget(widget) {
            const id = typeof widget === "string" ? widget : widget.id;
            return id !== widgetId;
        }

        const defaultBar = SettingsData.getPrimaryBarConfig();
        if (!defaultBar)
            return;
        const leftWidgets = defaultBar.leftWidgets || [];
        const centerWidgets = defaultBar.centerWidgets || [];
        const rightWidgets = defaultBar.rightWidgets || [];

        const newLeft = leftWidgets.filter(filterWidget);
        const newCenter = centerWidgets.filter(filterWidget);
        const newRight = rightWidgets.filter(filterWidget);

        if (newLeft.length !== leftWidgets.length) {
            SettingsData.setDankBarLeftWidgets(newLeft);
        }
        if (newCenter.length !== centerWidgets.length) {
            SettingsData.setDankBarCenterWidgets(newCenter);
        }
        if (newRight.length !== rightWidgets.length) {
            SettingsData.setDankBarRightWidgets(newRight);
        }
    }

    function updatePluginVariant(pluginId, variantId, variantConfig) {
        const variants = getPluginVariants(pluginId);
        for (let i = 0; i < variants.length; i++) {
            if (variants[i].id === variantId) {
                variants[i] = Object.assign({}, variants[i], variantConfig);
                break;
            }
        }
        SettingsData.setPluginSetting(pluginId, "variants", variants);
        pluginDataChanged(pluginId);
    }

    function getPluginVariantData(pluginId, variantId) {
        const variants = getPluginVariants(pluginId);
        for (let i = 0; i < variants.length; i++) {
            if (variants[i].id === variantId) {
                return variants[i];
            }
        }
        return null;
    }

    function getLoadedPlugins() {
        const result = [];
        for (const key in loadedPlugins) {
            result.push(loadedPlugins[key]);
        }
        return result;
    }

    function isPluginLoaded(pluginId) {
        return loadedPlugins[pluginId] !== undefined;
    }

    function enablePlugin(pluginId, onResult) {
        SettingsData.setPluginSetting(pluginId, "enabled", true);
        return runStartupGate(pluginId, onResult);
    }

    function _setLoadError(pluginId, err) {
        const m = Object.assign({}, pluginLoadErrors);
        m[pluginId] = err;
        pluginLoadErrors = m;
    }

    function _clearLoadError(pluginId) {
        if (!pluginLoadErrors[pluginId])
            return;
        const m = Object.assign({}, pluginLoadErrors);
        delete m[pluginId];
        pluginLoadErrors = m;
    }

    function _normalizeStartupError(result) {
        if (!result)
            return null;
        if (typeof result === "string")
            return {
                "title": result,
                "details": ""
            };
        return {
            "title": result.title || I18n.tr("Plugin dependency missing"),
            "details": result.details || ""
        };
    }

    function _makeStartupCheckObject(pluginId, plugin) {
        const comp = Qt.createComponent(pluginComponentUrl(pluginId, plugin.startupCheckPath), Component.PreferSynchronous);
        if (comp.status === Component.Error)
            throw new Error(comp.errorString());
        return comp.createObject(root);
    }

    function runStartupGate(pluginId, onResult) {
        const plugin = availablePlugins[pluginId];
        if (!plugin) {
            if (onResult)
                onResult(false);
            return false;
        }

        if (!plugin.startupCheckPath) {
            const ok = loadPlugin(pluginId);
            if (onResult)
                onResult(ok);
            return ok;
        }

        let probe = null;
        let settled = false;
        const finish = result => {
            if (settled)
                return;
            settled = true;
            if (probe)
                probe.destroy();
            const err = _normalizeStartupError(result);
            if (err) {
                _setLoadError(pluginId, err);
                const title = I18n.tr("%1 Startup Failed", "plugin error title, %1 is the plugin name").arg(plugin.name || pluginId);
                const body = err.details ? (err.title + "\n\n" + err.details) : err.title;
                if (!onResult)
                    ToastService.showError(title, body, "", "plugin-startup-" + pluginId);
                pluginLoadFailed(pluginId, err.title);
                if (onResult)
                    onResult(false);
                return;
            }
            _clearLoadError(pluginId);
            const ok = loadPlugin(pluginId);
            if (onResult)
                onResult(ok);
        };

        try {
            probe = _makeStartupCheckObject(pluginId, plugin);
            const check = probe?.check;
            if (typeof check !== "function")
                throw new Error("startupCheck has no check function");
            if (check.length >= 1)
                check(finish);
            else
                finish(check());
        } catch (e) {
            const message = String(e?.message || e);
            log.warn("startupCheck failed for", pluginId, message);
            finish(message);
        }
        return true;
    }

    function disablePlugin(pluginId) {
        SettingsData.setPluginSetting(pluginId, "enabled", false);
        return unloadPlugin(pluginId);
    }

    function reloadPlugin(pluginId) {
        if (!_preparePluginReload(pluginId))
            return false;
        const plugin = availablePlugins[pluginId];
        if (plugin)
            _loadPluginTranslations(pluginId, plugin.pluginDirectory);
        return runStartupGate(pluginId);
    }

    function ensureLauncherInstance(pluginId) {
        const existing = pluginInstances[pluginId];
        if (existing)
            return existing;
        const comp = pluginLauncherComponents[pluginId];
        if (!comp)
            return null;
        const instance = comp.createObject(root, {
            "pluginService": root
        });
        if (!instance) {
            log.error("failed to instantiate launcher surface:", pluginId, comp.errorString());
            pluginLoadFailed(pluginId, comp.errorString());
            return null;
        }
        const newInstances = Object.assign({}, pluginInstances);
        newInstances[pluginId] = instance;
        pluginInstances = newInstances;
        return instance;
    }

    // !TODO: plugin API only; the launcher Controller now instantiates per query through ensureLauncherInstance
    function ensureLauncherInstances() {
        for (const pluginId in pluginLauncherComponents)
            ensureLauncherInstance(pluginId);
    }

    function togglePlugin(pluginId) {
        const launcherInstance = pluginLauncherComponents[pluginId] ? ensureLauncherInstance(pluginId) : null;
        const instance = launcherInstance || pluginDaemonInstances[pluginId];
        if (!instance || typeof instance.toggle !== "function")
            return false;
        instance.toggle();
        return true;
    }

    function savePluginData(pluginId, key, value) {
        SettingsData.setPluginSetting(pluginId, key, value);
        pluginDataChanged(pluginId);
        return true;
    }

    function loadPluginData(pluginId, key, defaultValue) {
        return SettingsData.getPluginSetting(pluginId, key, defaultValue);
    }

    function getPluginPath(pluginId) {
        const plugin = availablePlugins[pluginId];
        if (!plugin)
            return "";
        return plugin.pluginDirectory || "";
    }

    function getPluginStatePath(pluginId) {
        return Paths.strip(Paths.state) + "/plugins/" + pluginId + "_state.json";
    }

    function loadPluginState(pluginId, key, defaultValue) {
        if (!_stateLoaded[pluginId])
            _loadStateFromDisk(pluginId);
        const state = _stateCache[pluginId];
        if (!state)
            return defaultValue;
        return state[key] !== undefined ? state[key] : defaultValue;
    }

    function savePluginState(pluginId, key, value) {
        if (!_stateLoaded[pluginId])
            _loadStateFromDisk(pluginId);
        if (!_stateCache[pluginId])
            _stateCache[pluginId] = {};
        _stateCache[pluginId][key] = value;
        _stateDirtyPlugins[pluginId] = true;
        _stateWriteTimer.restart();
        pluginStateChanged(pluginId);
    }

    function clearPluginState(pluginId) {
        _stateCache[pluginId] = {};
        _stateLoaded[pluginId] = true;
        _flushStateToDisk(pluginId);
        pluginStateChanged(pluginId);
    }

    function removePluginStateKey(pluginId, key) {
        if (!_stateCache[pluginId])
            return;
        delete _stateCache[pluginId][key];
        _stateDirtyPlugins[pluginId] = true;
        _stateWriteTimer.restart();
        pluginStateChanged(pluginId);
    }

    function _ensureStateDir() {
        if (_stateDirCreated)
            return;
        _stateDirCreated = true;
        Paths.mkdir(Paths.state + "/plugins");
    }

    function _loadStateFromDisk(pluginId) {
        _stateLoaded[pluginId] = true;
        _ensureStateDir();
        const path = getPluginStatePath(pluginId);
        try {
            const fv = stateLoadFvComp.createObject(root, {
                path: path
            });
            const raw = fv.text();
            if (raw && raw.trim()) {
                _stateCache[pluginId] = JSON.parse(raw);
            } else {
                _stateCache[pluginId] = {};
            }
            _stateWriters[pluginId] = fv;
        } catch (e) {
            _stateCache[pluginId] = {};
        }
    }

    function _flushStateToDisk(pluginId) {
        _ensureStateDir();
        const content = JSON.stringify(_stateCache[pluginId] || {}, null, 2);
        if (_stateWriters[pluginId]) {
            _stateWriters[pluginId].setText(content);
            return;
        }
        const path = getPluginStatePath(pluginId);
        try {
            const fv = stateLoadFvComp.createObject(root, {
                path: path
            });
            _stateWriters[pluginId] = fv;
            fv.setText(content);
        } catch (e) {
            log.warn("Failed to write state for", pluginId, e.message);
        }
    }

    Component {
        id: stateLoadFvComp
        FileView {
            blockLoading: true
            blockWrites: true
            atomicWrites: true
        }
    }

    function _flushDirtyStates() {
        const dirty = _stateDirtyPlugins;
        _stateDirtyPlugins = {};
        for (const pluginId in dirty)
            _flushStateToDisk(pluginId);
    }

    function _cleanupPluginStateWriter(pluginId) {
        if (!_stateWriters[pluginId])
            return;
        _stateWriters[pluginId].destroy();
        delete _stateWriters[pluginId];
    }

    function scanPlugins() {
        const userUrl = Paths.toFileUrl(root.pluginDirectory);
        const systemUrl = Paths.toFileUrl(root.systemPluginDirectory);
        userWatcher.folder = "";
        if (!AdminPolicy.disableUserPlugins)
            userWatcher.folder = userUrl;
        systemWatcher.folder = "";
        systemWatcher.folder = systemUrl;
        resyncDebounce.restart();
        checkPluginDirectoryExists();
    }

    function forceRescanPlugin(pluginId) {
        const plugin = availablePlugins[pluginId];
        if (!plugin || !plugin.manifestPath) {
            return;
        }
        const manifestPath = plugin.manifestPath;
        const source = plugin.source || "user";
        if (!_preparePluginReload(pluginId))
            return;
        delete knownManifests[manifestPath];
        const newMap = Object.assign({}, availablePlugins);
        delete newMap[pluginId];
        availablePlugins = newMap;
        loadPluginManifestFile(manifestPath, source, Date.now());
    }

    function createPluginDirectory() {
        Quickshell.execDetached(["mkdir", "-p", pluginDirectory]);
        Qt.callLater(checkPluginDirectoryExists);
        return true;
    }

    function openPluginDirectory() {
        Qt.openUrlExternally(Paths.toFileUrl(pluginDirectory));
        return true;
    }

    // Actions a plugin offers to the launcher and semantic search; they drop
    // out with the plugin on unload (ActionCatalogService listens for it).
    function registerActions(pluginId, actions) {
        return ActionCatalogService.registerPluginActions(pluginId, actions);
    }

    function unregisterActions(pluginId) {
        ActionCatalogService.unregisterPluginActions(pluginId);
    }

    // Launcher plugin helper functions
    function getLauncherPlugins() {
        const launchers = {};

        // Check plugins that have launcher components
        for (const pluginId in pluginLauncherComponents) {
            const plugin = availablePlugins[pluginId];
            if (plugin && plugin.loaded) {
                launchers[pluginId] = plugin;
            }
        }
        return launchers;
    }

    function getLauncherPlugin(pluginId) {
        const plugin = availablePlugins[pluginId];
        if (plugin && plugin.loaded && pluginLauncherComponents[pluginId]) {
            return plugin;
        }
        return null;
    }

    function getPluginTrigger(pluginId) {
        const plugin = getLauncherPlugin(pluginId);
        if (plugin) {
            // Check if noTrigger is set (always active mode)
            const noTrigger = SettingsData.getPluginSetting(pluginId, "noTrigger", false);
            if (noTrigger) {
                return "";
            }
            // Otherwise load the custom trigger, defaulting to plugin manifest trigger
            const customTrigger = SettingsData.getPluginSetting(pluginId, "trigger", plugin.trigger || "!");
            return customTrigger;
        }
        return null;
    }

    function getAllPluginTriggers() {
        const triggers = {};
        const launchers = getLauncherPlugins();

        for (const pluginId in launchers) {
            const trigger = getPluginTrigger(pluginId);
            if (trigger && trigger.trim() !== "") {
                triggers[trigger] = pluginId;
            }
        }
        return triggers;
    }

    function getPluginsWithEmptyTrigger() {
        const plugins = [];
        const launchers = getLauncherPlugins();

        for (const pluginId in launchers) {
            const trigger = getPluginTrigger(pluginId);
            if (!trigger || trigger.trim() === "") {
                plugins.push(pluginId);
            }
        }
        return plugins;
    }

    function getPluginViewPreference(pluginId) {
        const plugin = availablePlugins[pluginId];
        if (!plugin)
            return null;

        return {
            mode: plugin.viewMode || null,
            enforced: plugin.viewModeEnforced === true
        };
    }

    function getGlobalVar(pluginId, varName, defaultValue) {
        if (globalVars[pluginId] && varName in globalVars[pluginId]) {
            return globalVars[pluginId][varName];
        }
        return defaultValue;
    }

    function setGlobalVar(pluginId, varName, value) {
        const newGlobals = Object.assign({}, globalVars);
        if (!newGlobals[pluginId]) {
            newGlobals[pluginId] = {};
        }
        newGlobals[pluginId] = Object.assign({}, newGlobals[pluginId]);
        newGlobals[pluginId][varName] = value;
        globalVars = newGlobals;
        globalVarChanged(pluginId, varName);
    }

    function previewUrl(plugin) {
        if (!plugin)
            return "";
        if (plugin.previewUrl)
            return plugin.previewUrl;
        if (plugin.id)
            return previewApiBase + plugin.id;
        return plugin.screenshot || "";
    }

    // 16:10 screenshot-only render; the full preview card bakes in title text the card already shows
    function thumbUrl(plugin) {
        if (!plugin)
            return "";
        if (plugin.thumbUrl)
            return plugin.thumbUrl;
        if (plugin.id)
            return previewApiBase + plugin.id + "/thumb";
        return "";
    }

    function heroUrl(plugin) {
        if (!plugin)
            return "";
        return plugin.screenshot || previewUrl(plugin);
    }

    function statusTone(status) {
        switch (status) {
        case "broken":
            return "error";
        case "unmaintained":
            return "warning";
        case "reviewed":
            return "info";
        default:
            return "outline";
        }
    }

    function statusLabel(status) {
        switch (status) {
        case "broken":
            return I18n.tr("broken", "plugin status");
        case "unmaintained":
            return I18n.tr("unmaintained", "plugin status");
        case "deprecated":
            return I18n.tr("deprecated", "plugin status");
        case "reviewed":
            return I18n.tr("reviewed", "plugin status");
        default:
            return status;
        }
    }

    function badgeTone(tone) {
        switch (tone) {
        case "secondary":
            return Theme.secondary;
        case "warning":
            return Theme.warning;
        case "error":
            return Theme.error;
        case "info":
            return Theme.info;
        case "outline":
            return Theme.outline;
        default:
            return Theme.primary;
        }
    }

    function badgeModel(plugin) {
        if (!plugin || (!plugin.id && !plugin.name))
            return [];
        var badges = [];
        if (plugin.featured)
            badges.push({
                label: I18n.tr("featured", "adjective, lowercase plugin badge"),
                icon: "star",
                tone: "secondary"
            });
        if (plugin.firstParty)
            badges.push({
                label: I18n.tr("official", "adjective, lowercase first party plugin or registry badge"),
                icon: "verified",
                tone: "primary"
            });
        else
            badges.push({
                label: I18n.tr("3rd party"),
                icon: "",
                tone: "warning"
            });
        var recency = PluginRanking.recency(plugin);
        if (recency)
            badges.push({
                label: recency === "new" ? I18n.tr("new", "adjective, lowercase plugin badge, recently added") : I18n.tr("updated", "adjective, lowercase plugin badge, recently updated"),
                icon: recency === "new" ? "fiber_new" : "update",
                tone: "secondary"
            });
        var status = plugin.status || [];
        for (var i = 0; i < status.length; i++)
            badges.push({
                label: statusLabel(status[i]),
                icon: "",
                tone: statusTone(status[i])
            });
        return badges;
    }

    property var installingPlugins: ({})

    // The plugin removed last ({id, name, wasEnabled}), kept a few seconds so the plugins page can offer to put it back.
    property var lastUninstalledPlugin: null

    Timer {
        id: undoUninstallTimer
        interval: 8000
        onTriggered: root.lastUninstalledPlugin = null
    }

    // Only a registry plugin (one with a repo in the installed list) can be put back:
    // a plugin the registry does not know would otherwise be swapped for another one.
    function noteUninstalled(pluginId, pluginName, wasEnabled, repo) {
        if (!repo) {
            undoUninstallTimer.stop();
            lastUninstalledPlugin = null;
            return;
        }
        lastUninstalledPlugin = {
            id: pluginId,
            name: pluginName || pluginId,
            wasEnabled: wasEnabled === true
        };
        undoUninstallTimer.restart();
    }

    function undoUninstall() {
        const plugin = lastUninstalledPlugin;
        if (!plugin)
            return;
        undoUninstallTimer.stop();
        lastUninstalledPlugin = null;
        installFromRegistry(plugin.id, plugin.name, plugin.wasEnabled);
    }

    // Plugin id -> id of the user's own +1 reaction on the registry issue, once a click has found or created it.
    property var upvotedPlugins: ({})
    // Plugin id -> what this session changed on top of the registry count (+1, 0 or -1).
    property var upvoteDeltas: ({})
    property var upvotingPlugins: ({})

    function upvoteCount(plugin) {
        return PluginRanking.upvoteCount(plugin.upvotes, upvoteDeltas[plugin.id]);
    }

    function _setUpvote(pluginId, reactionId, delta) {
        const voted = Object.assign({}, upvotedPlugins);
        if (reactionId)
            voted[pluginId] = reactionId;
        else
            delete voted[pluginId];
        upvotedPlugins = voted;
        upvoteDeltas = Object.assign({}, upvoteDeltas, {
            [pluginId]: delta
        });
    }

    function _setUpvoting(pluginId, active) {
        const pending = Object.assign({}, upvotingPlugins);
        if (active)
            pending[pluginId] = true;
        else
            delete pending[pluginId];
        upvotingPlugins = pending;
    }

    // One click: a thumbs-up on the plugin's GitHub issue through the gh CLI when
    // it is installed and signed in, otherwise the issue opens in the browser.
    // One click votes, a second click on a vote takes it back. GitHub keeps one +1 per account.
    function upvotePlugin(plugin) {
        if (!plugin || !plugin.issueUrl || upvotingPlugins[plugin.id])
            return;
        const path = PluginRanking.issueReactionsPath(plugin.issueUrl);
        if (!path) {
            if (/^https:\/\//.test(plugin.issueUrl))
                Qt.openUrlExternally(plugin.issueUrl);
            return;
        }
        const pluginId = plugin.id;
        const issueUrl = plugin.issueUrl;
        const delta = upvoteDeltas[pluginId] || 0;
        const ownReaction = upvotedPlugins[pluginId];
        _setUpvoting(pluginId, true);
        if (ownReaction) {
            Proc.runCommand("plugin-upvote-" + pluginId, ["gh", "api", "--method", "DELETE", path + "/" + ownReaction], (output, exitCode) => {
                _setUpvoting(pluginId, false);
                if (exitCode !== 0) {
                    root.log.warn("gh upvote removal failed", pluginId, exitCode);
                    ToastService.showInfo(I18n.tr("Opening GitHub to remove the upvote", "plugin upvote toast, shown when the GitHub CLI is missing or signed out"));
                    Qt.openUrlExternally(issueUrl);
                    return;
                }
                _setUpvote(pluginId, 0, PluginRanking.nextUpvoteDelta(delta, true, false));
                ToastService.showInfo(I18n.tr("Upvote removed", "plugin upvote toast"));
            }, 0, 15000);
            return;
        }
        Proc.runCommand("plugin-upvote-" + pluginId, ["gh", "api", "--include", "--method", "POST", path, "-f", "content=+1"], (output, exitCode) => {
            _setUpvoting(pluginId, false);
            const reactionId = exitCode === 0 ? PluginRanking.reactionId(output) : 0;
            if (!reactionId) {
                root.log.warn("gh upvote failed", pluginId, exitCode);
                ToastService.showInfo(I18n.tr("Opening GitHub to upvote", "plugin upvote toast, shown when the GitHub CLI is missing or signed out"));
                Qt.openUrlExternally(issueUrl);
                return;
            }
            const added = /^HTTP\/\S+ 201/.test(output || "");
            _setUpvote(pluginId, reactionId, PluginRanking.nextUpvoteDelta(delta, false, added));
            ToastService.showInfo(added ? I18n.tr("Upvoted on GitHub", "plugin upvote toast") : I18n.tr("Already upvoted, click again to remove", "plugin upvote toast"));
        }, 0, 15000);
    }

    Component {
        id: installedPluginWaiter
        Timer {
            id: waiter
            required property string pluginId
            required property var done
            interval: 10000
            running: true

            function complete() {
                if (!root.availablePlugins[pluginId])
                    return;
                stop();
                root.enablePlugin(pluginId, ok => {
                    if (!ok) {
                        const error = root.pluginLoadErrors[pluginId];
                        const message = error ? [error.title, error.details].filter(Boolean).join("\n") : I18n.tr("Failed to enable plugin: %1", "plugin error message, %1 is the plugin name or id").arg(pluginId);
                        done(false, message);
                        destroy();
                        return;
                    }
                    const plugin = root.availablePlugins[pluginId];
                    if (plugin?.type === "desktop") {
                        const config = DesktopWidgetRegistry.getDefaultConfig(pluginId);
                        SettingsData.createDesktopWidgetInstance(pluginId, plugin.name || pluginId, config);
                    }
                    done(true, "");
                    destroy();
                });
            }

            onTriggered: {
                done(false, I18n.tr("Installed plugin could not be loaded: %1", "plugin manifest unavailable after installation").arg(pluginId));
                destroy();
            }
            Component.onCompleted: complete()
            property Connections pluginChanges: Connections {
                target: root
                function onPluginListUpdated() {
                    if (waiter.running)
                        waiter.complete();
                }
            }
        }
    }

    function installFromRegistry(pluginId, pluginName, enableAfterInstall, onDone) {
        if (installingPlugins[pluginId])
            return;
        installingPlugins = Object.assign({}, installingPlugins, {
            [pluginId]: true
        });
        const finish = (success, error) => {
            const pending = Object.assign({}, installingPlugins);
            delete pending[pluginId];
            installingPlugins = pending;
            registryInstallFinished(pluginId, success);
            if (onDone) {
                onDone(success, error);
                return;
            }
            if (!success)
                ToastService.showError(error);
        };
        DMSService.install(pluginId, response => {
            if (response.error) {
                finish(false, I18n.tr("Install failed: %1", "installation error").arg(response.error));
                return;
            }
            scanPlugins();
            if (!enableAfterInstall) {
                finish(true, "");
                return;
            }
            installedPluginWaiter.createObject(root, {
                pluginId: pluginId,
                done: finish
            });
        });
    }

    function checkPluginCompatibility(requiresDms) {
        if (!requiresDms)
            return true;
        return ShellVersionService.checkVersionRequirement(requiresDms, ShellVersionService.getParsedShellVersion());
    }

    function getIncompatiblePlugins() {
        const result = [];
        for (const pluginId in availablePlugins) {
            const plugin = availablePlugins[pluginId];
            if (plugin.loaded && plugin.requires_dms && !checkPluginCompatibility(plugin.requires_dms)) {
                result.push(plugin);
            }
        }
        return result;
    }

    readonly property string _ipcIdPattern: "^[a-zA-Z0-9_\\-:]{1,64}$"

    IpcHandler {
        target: "plugin-scan"

        function scan(): string {
            root.scanPlugins();
            return `SCAN_TRIGGERED: ${Object.keys(root.availablePlugins).length} known before debounce`;
        }

        function rescan(pluginId: string): string {
            if (!pluginId)
                return "ERROR: rescan requires a pluginId";
            if (!new RegExp(root._ipcIdPattern).test(pluginId))
                return `ERROR: invalid pluginId '${pluginId}' (allowed: [a-zA-Z0-9_\\-:]{1,64})`;
            if (!(pluginId in root.availablePlugins))
                return `ERROR: unknown pluginId '${pluginId}' (try 'list' first)`;
            root.forceRescanPlugin(pluginId);
            return `RESCAN_TRIGGERED: ${pluginId}`;
        }

        function reload(pluginId: string): string {
            if (!pluginId)
                return "ERROR: reload requires a pluginId";
            if (!new RegExp(root._ipcIdPattern).test(pluginId))
                return `ERROR: invalid pluginId '${pluginId}' (allowed: [a-zA-Z0-9_\\-:]{1,64})`;
            if (!(pluginId in root.availablePlugins))
                return `ERROR: unknown pluginId '${pluginId}'`;
            root.reloadPlugin(pluginId);
            return `RELOAD_TRIGGERED: ${pluginId}`;
        }

        function list(): string {
            const ids = Object.keys(root.availablePlugins);
            const cap = 256;
            const n = Math.min(ids.length, cap);
            const lines = [];
            for (let i = 0; i < n; i++) {
                const id = ids[i];
                if (!new RegExp(root._ipcIdPattern).test(id))
                    continue;
                const p = root.availablePlugins[id];
                const safeName = String(p.name || "").replace(/[\t\n\r]/g, " ");
                lines.push(`${id}\t${p.loaded ? "loaded" : "unloaded"}\t${p.type || "unknown"}\t${safeName}`);
            }
            const header = `# count=${ids.length} returned=${n}${ids.length > n ? " (truncated, see cap)" : ""}`;
            return header + "\n" + lines.join("\n");
        }

        function status(pluginId: string): string {
            if (!pluginId)
                return "ERROR: status requires a pluginId";
            if (!new RegExp(root._ipcIdPattern).test(pluginId))
                return `ERROR: invalid pluginId '${pluginId}'`;
            const plugin = root.availablePlugins[pluginId];
            if (!plugin)
                return `ERROR: unknown pluginId '${pluginId}'`;
            const errObj = root.pluginLoadErrors[pluginId];
            const err = errObj ? (errObj.title || "") : "";
            const safeErr = String(err).replace(/[\t\n\r]/g, " ");
            return `${plugin.loaded ? "loaded" : "unloaded"}\t${plugin.type || ""}\t${safeErr}`;
        }
    }
}
