pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("AppSearchService")
    property int refCount: 0

    property var applications: []
    property var _cachedCategories: null
    property var _cachedVisibleApps: null
    property var _searchIndex: null
    property var _hiddenAppsSet: new Set()

    property var _transformCache: ({})
    property var _cachedDefaultSections: []
    property var _cachedDefaultFlatModel: []
    property bool _defaultCacheValid: false
    property int cacheVersion: 0

    readonly property int maxResults: 10
    readonly property int frecencySampleSize: 10

    readonly property var timeBuckets: [
        {
            "maxDays": 4,
            "weight": 100
        },
        {
            "maxDays": 14,
            "weight": 70
        },
        {
            "maxDays": 31,
            "weight": 50
        },
        {
            "maxDays": 90,
            "weight": 30
        },
        {
            "maxDays": 99999,
            "weight": 10
        }
    ]

    function refreshApplications() {
        applications = DesktopEntries.applications.values;
        _cachedCategories = null;
        _cachedVisibleApps = null;
        _searchIndex = null;
        invalidateLauncherCache();
    }

    function invalidateLauncherCache() {
        _transformCache = {};
        _defaultCacheValid = false;
        _cachedDefaultSections = [];
        _cachedDefaultFlatModel = [];
        cacheVersion++;
    }

    function getOrTransformApp(app, transformFn) {
        const id = app.id || app.execString || app.exec || "";
        if (!id)
            return transformFn(app);
        const cached = _transformCache[id];
        if (cached) {
            const currentIcon = app.icon || "";
            const cachedSourceIcon = cached._sourceIcon || "";
            if (currentIcon === cachedSourceIcon)
                return cached;
        }
        const transformed = transformFn(app);
        transformed._sourceIcon = app.icon || "";
        _transformCache[id] = transformed;
        return transformed;
    }

    function getCachedDefaultSections() {
        if (!_defaultCacheValid)
            return null;
        return _cachedDefaultSections;
    }

    function setCachedDefaultSections(sections, flatModel) {
        _cachedDefaultSections = sections.map(function (s) {
            return Object.assign({}, s, {
                items: s.items ? s.items.slice() : []
            });
        });
        _cachedDefaultFlatModel = flatModel.slice();
        _defaultCacheValid = true;
    }

    function isCacheValid() {
        return _defaultCacheValid;
    }

    function _rebuildHiddenSet() {
        _hiddenAppsSet = new Set(SessionData.hiddenApps || []);
        _cachedVisibleApps = null;
        _searchIndex = null;
    }

    function isAppHidden(app) {
        if (!app)
            return false;
        const appId = app.id || app.execString || app.exec || "";
        return _hiddenAppsSet.has(appId);
    }

    function _visibleSearchIndex() {
        if (_searchIndex !== null)
            return _searchIndex;
        const apps = getVisibleApplications();
        _searchIndex = {
            apps: apps,
            entries: apps.map(app => ({
                        app: app,
                        name: (app.name || "").toLowerCase(),
                        nameWords: tokenize(app.name || ""),
                        genericName: (app.genericName || "").toLowerCase(),
                        comment: (app.comment || "").toLowerCase(),
                        id: (app.id || "").toLowerCase(),
                        keywords: app.keywords ? app.keywords.map(k => k.toLowerCase()) : []
                    }))
        };
        return _searchIndex;
    }

    function getVisibleApplications() {
        if (_cachedVisibleApps === null) {
            const seen = new Set();
            _cachedVisibleApps = applications.filter(app => {
                if (isAppHidden(app))
                    return false;
                const id = app.id;
                if (id && seen.has(id))
                    return false;
                if (id)
                    seen.add(id);
                return true;
            });
        }
        return _cachedVisibleApps.map(app => applyAppOverride(app));
    }

    Connections {
        target: SessionData
        function onHiddenAppsChanged() {
            root._rebuildHiddenSet();
            root.invalidateLauncherCache();
        }
        function onAppOverridesChanged() {
            root._cachedVisibleApps = null;
            root._searchIndex = null;
            root.invalidateLauncherCache();
        }
    }

    Connections {
        target: AppUsageHistoryData
        function onAppUsageRankingChanged() {
            root.invalidateLauncherCache();
        }
    }

    function applyAppOverride(app) {
        if (!app)
            return app;
        const appId = app.id || app.execString || app.exec || "";
        const override = SessionData.getAppOverride(appId);
        if (!override)
            return app;
        return Object.assign({}, app, {
            name: override.name || app.name,
            icon: override.icon || app.icon,
            comment: override.comment || app.comment,
            _override: override
        });
    }

    readonly property string dmsLogoPath: Qt.resolvedUrl("../assets/danklogo2.svg")

    readonly property var builtInPlugins: ({
            "dms_settings": {
                id: "dms_settings",
                name: I18n.tr("Settings", "settings window title"),
                icon: "svg+corner:" + dmsLogoPath + "|settings",
                cornerIcon: "settings",
                comment: "dms",
                action: "ipc:settings",
                categories: ["Settings", "System"],
                defaultTrigger: "",
                isLauncher: false
            },
            "dms_notepad": {
                id: "dms_notepad",
                name: I18n.tr("Notepad", "Notepad"),
                icon: "svg+corner:" + dmsLogoPath + "|description",
                cornerIcon: "description",
                comment: "dms",
                action: "ipc:notepad",
                categories: ["Office", "Utility"],
                defaultTrigger: "",
                isLauncher: false
            },
            "dms_sysmon": {
                id: "dms_sysmon",
                name: I18n.tr("System Monitor", "sysmon window title"),
                icon: "svg+corner:" + dmsLogoPath + "|monitor_heart",
                cornerIcon: "monitor_heart",
                comment: "dms",
                action: "ipc:processlist",
                categories: ["System", "Monitor"],
                defaultTrigger: "",
                isLauncher: false
            },
            "dms_colorpicker": {
                id: "dms_colorpicker",
                name: I18n.tr("Color Picker"),
                icon: "svg+corner:" + dmsLogoPath + "|palette",
                cornerIcon: "palette",
                comment: "dms",
                action: "ipc:color-picker",
                categories: ["Graphics", "Utility"],
                defaultTrigger: "",
                isLauncher: false
            },
            "dms_power": {
                id: "dms_power",
                name: I18n.tr("Power"),
                cornerIcon: "power_settings_new",
                comment: "dms",
                defaultTrigger: "pw",
                isLauncher: true,
                viewMode: "list",
                viewModeEnforced: true,
                defaultSectionPriority: 2.3
            },
            "dms_vpn": {
                id: "dms_vpn",
                name: I18n.tr("VPN", "virtual private network, widget and page title"),
                cornerIcon: "vpn_key",
                comment: "dms",
                defaultTrigger: "",
                isLauncher: true,
                viewMode: "list",
                viewModeEnforced: true,
                defaultSectionPriority: 2.4
            },
            "dms_qr_generator": {
                id: "dms_qr_generator",
                name: I18n.tr("QR Generator"),
                icon: "svg+corner:" + dmsLogoPath + "|qr_code",
                cornerIcon: "qr_code",
                comment: "dms",
                action: "ipc:qr-generator",
                categories: ["Utility"],
                defaultTrigger: "qrg",
                isLauncher: true,
                viewMode: "list",
                viewModeEnforced: true
            },
            "dms_settings_search": {
                id: "dms_settings_search",
                name: I18n.tr("Search settings", "launcher plugin name that searches DMS settings"),
                cornerIcon: "search",
                comment: I18n.tr("DMS Settings"),
                defaultTrigger: "?",
                isLauncher: true
            },
            "dms_clipboard_search": {
                id: "dms_clipboard_search",
                name: I18n.tr("Clipboard"),
                cornerIcon: "content_paste",
                comment: "dms",
                defaultTrigger: "cb",
                isLauncher: true,
                viewMode: "list",
                viewModeEnforced: true
            }
        })

    function getBuiltInPluginTrigger(pluginId) {
        const plugin = builtInPlugins[pluginId];
        if (!plugin)
            return null;
        return SettingsData.getBuiltInPluginSetting(pluginId, "trigger", plugin.defaultTrigger);
    }

    readonly property var coreApps: {
        SettingsData.builtInPluginSettings;
        const apps = [];
        for (const pluginId in builtInPlugins) {
            if (!SettingsData.getBuiltInPluginSetting(pluginId, "enabled", true))
                continue;
            const plugin = builtInPlugins[pluginId];
            if (plugin.isLauncher && !plugin.action)
                continue;
            apps.push({
                name: plugin.name,
                icon: plugin.icon,
                comment: plugin.comment,
                action: plugin.action,
                categories: plugin.categories,
                isCore: true,
                builtInPluginId: pluginId,
                cornerIcon: plugin.cornerIcon
            });
        }
        return apps;
    }

    function getBuiltInLauncherPlugins() {
        const result = {};
        for (const pluginId in builtInPlugins) {
            const plugin = builtInPlugins[pluginId];
            if (!plugin.isLauncher)
                continue;
            if (!SettingsData.getBuiltInPluginSetting(pluginId, "enabled", true))
                continue;
            result[pluginId] = plugin;
        }
        return result;
    }

    function getBuiltInLauncherTriggers() {
        const triggers = {};
        const launchers = getBuiltInLauncherPlugins();
        for (const pluginId in launchers) {
            const trigger = getBuiltInPluginTrigger(pluginId);
            if (trigger && trigger.trim() !== "")
                triggers[trigger] = pluginId;
        }
        return triggers;
    }

    function getBuiltInLauncherPluginsWithEmptyTrigger() {
        const result = [];
        const launchers = getBuiltInLauncherPlugins();
        for (const pluginId in launchers) {
            const trigger = getBuiltInPluginTrigger(pluginId);
            if (!trigger || trigger.trim() === "")
                result.push(pluginId);
        }
        return result;
    }

    readonly property var powerLauncherKeywords: ({
            lock: ["lock"],
            logout: ["logout", "exit", "sign out"],
            suspend: ["suspend", "sleep"],
            hibernate: ["hibernate"],
            reboot: ["reboot", "restart"],
            softreboot: ["soft reboot"],
            firmwaresetup: ["firmware", "bios", "uefi"],
            poweroff: ["poweroff", "shutdown", "halt"],
            restart: ["restart", "shell", "reload"]
        })

    function getPowerLauncherActions() {
        const ids = ["lock", "logout", "suspend", "hibernate", "reboot", "softreboot", "poweroff", "restart"];
        return ids.filter(a => SessionService.isPowerActionSupported(a)).concat(SessionService.extraPowerActions).map(a => {
            const data = SessionService.getPowerActionData(a);
            return {
                action: a,
                name: data.label,
                icon: data.icon,
                keywords: powerLauncherKeywords[a] || []
            };
        }).filter(a => a.name);
    }

    function getBuiltInLauncherItems(pluginId, query, allowEmptyQuery) {
        if (pluginId === "dms_power") {
            const q = (query || "").toString().trim().toLowerCase();
            return getPowerLauncherActions().filter(a => {
                if (!q)
                    return true;
                if (a.name.toLowerCase().includes(q))
                    return true;
                return a.keywords.some(k => k.includes(q));
            }).map(a => ({
                        name: a.name,
                        icon: "material:" + a.icon,
                        comment: I18n.tr("Power"),
                        action: "power:" + a.action,
                        keywords: a.keywords,
                        isBuiltInLauncher: true,
                        builtInPluginId: pluginId
                    }));
        }

        if (pluginId === "dms_clipboard_search") {
            const trimmed = (query || "").toString().trim();
            const entries = ClipboardService.getCachedLauncherSearchEntries(trimmed, 20).slice().sort((a, b) => {
                if (a.pinned !== b.pinned)
                    return b.pinned ? 1 : -1;
                return (b.id || 0) - (a.id || 0);
            });
            return entries.map(entry => ({
                        type: "clipboard",
                        data: entry
                    }));
        }

        if (pluginId === "dms_vpn") {
            if (!DMSNetworkService.vpnAvailable)
                return [];
            const q = (query || "").toString().trim().toLowerCase();
            if (!q && !allowEmptyQuery && !getBuiltInPluginTrigger(pluginId))
                return [];
            return (DMSNetworkService.profiles || []).map(profile => {
                const id = profile.uuid || profile.name || "";
                const active = DMSNetworkService.isActiveVpnUuid(id);
                const connecting = DMSNetworkService.isVpnConnectingUuid(id);
                const typeLabel = VPNService.getVpnTypeFromProfile(profile);
                return {
                    name: profile.name || I18n.tr("VPN", "virtual private network, widget and page title"),
                    icon: active ? "material:vpn_lock" : "material:vpn_key_off",
                    comment: typeLabel,
                    action: "vpn:" + id,
                    keywords: ["vpn", typeLabel],
                    badgeLabel: connecting ? I18n.tr("Connecting...") : (active ? I18n.tr("Connected") : I18n.tr("Disconnected")),
                    isBuiltInLauncher: true,
                    builtInPluginId: pluginId
                };
            }).filter(item => {
                if (!q)
                    return true;
                if (item.name.toLowerCase().includes(q))
                    return true;
                return item.keywords.some(k => k.toLowerCase().includes(q));
            });
        }

        if (pluginId === "dms_qr_generator") {
            const text = (query || "").toString().trim();
            return [
                {
                    name: text.length > 0 ? text : I18n.tr("Enter text to encode"),
                    icon: "material:qr_code",
                    comment: I18n.tr("QR Generator"),
                    action: "qr_generate:" + text,
                    isBuiltInLauncher: true,
                    builtInPluginId: pluginId
                }
            ];
        }

        if (pluginId !== "dms_settings_search")
            return [];

        const results = SettingsSearchService.searchForLauncher(query);
        const items = [];
        for (let i = 0; i < results.length; i++) {
            const r = results[i];
            items.push({
                name: r.label,
                type: "setting",
                section: "settings",
                icon: "material:" + r.icon,
                comment: r.description || r.category,
                action: r.page ? "settings_page:" + r.page : "settings_nav:" + r.tabIndex + ":" + r.section,
                categories: ["Settings"],
                keywords: r.keywords || [],
                source: I18n.tr("Settings", "settings window title"),
                badgeLabel: I18n.tr("Setting"),
                isCore: true,
                isBuiltInLauncher: true,
                builtInPluginId: pluginId
            });
        }
        return items;
    }

    function executeBuiltInLauncherItem(item) {
        if (!item?.action)
            return false;

        const parts = item.action.split(":");
        switch (parts[0]) {
        case "settings_nav":
            {
                const tabIndex = parseInt(parts[1]);
                const section = parts.slice(2).join(":");
                SettingsSearchService.navigateToSection(section);
                PopoutService.openSettingsWithTabIndex(tabIndex);
                return true;
            }
        case "settings_page":
            PopoutService.openSettingsWithTab(parts.slice(1).join(":"));
            return true;
        case "qr_generate":
            PopoutService.showQRGeneratorModal(parts.slice(1).join(":"));
            return true;
        case "power":
            return executePowerLauncherAction(parts.slice(1).join(":"));
        case "vpn":
            {
                const id = parts.slice(1).join(":");
                if (!id)
                    return false;
                DMSNetworkService.toggleVpn(id);
                return true;
            }
        }
        return false;
    }

    function executePowerLauncherAction(action) {
        if (action === "lock") {
            IdleService.lockRequested();
            return true;
        }
        return SessionService.executePowerAction(action);
    }

    function getCoreApps(query) {
        if (!query || query.length === 0)
            return coreApps;
        const lowerQuery = query.toLowerCase();
        return coreApps.filter(app => app.name.toLowerCase().includes(lowerQuery) || app.comment.toLowerCase().includes(lowerQuery));
    }

    function executeCoreApp(app) {
        if (!app?.action)
            return false;

        const parts = app.action.split(":");
        if (parts[0] !== "ipc")
            return false;

        switch (parts[1]) {
        case "settings":
            PopoutService.focusOrToggleSettings();
            return true;
        case "notepad":
            PopoutService.toggleNotepad();
            return true;
        case "processlist":
            PopoutService.toggleProcessListModal();
            return true;
        case "color-picker":
            PopoutService.showColorPicker();
            return true;
        case "qr-generator":
            PopoutService.showQRGeneratorModal();
            return true;
        }
        return false;
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.refreshApplications();
        }
    }

    Connections {
        target: SettingsData
        function onBuiltInPluginSettingsChanged() {
            root.invalidateLauncherCache();
        }
        function onLauncherPluginVisibilityChanged() {
            root.invalidateLauncherCache();
        }
    }

    Component.onCompleted: {
        _rebuildHiddenSet();
        refreshApplications();
    }

    function tokenize(text) {
        return text.toLowerCase().trim().split(/[\s\-_]+/).filter(w => w.length > 0);
    }

    function wordBoundaryMatch(text, query) {
        return wordBoundaryMatchWords(tokenize(text), tokenize(query));
    }

    function wordBoundaryMatchWords(textWords, queryWords) {
        if (queryWords.length === 0)
            return false;
        if (queryWords.length > textWords.length)
            return false;

        for (var i = 0; i <= textWords.length - queryWords.length; i++) {
            let allMatch = true;
            for (var j = 0; j < queryWords.length; j++) {
                if (!textWords[i + j].startsWith(queryWords[j])) {
                    allMatch = false;
                    break;
                }
            }
            if (allMatch)
                return true;
        }
        return false;
    }

    function levenshteinDistance(s1, s2) {
        const len1 = s1.length;
        const len2 = s2.length;
        const matrix = [];

        for (var i = 0; i <= len1; i++) {
            matrix[i] = [i];
        }
        for (var j = 0; j <= len2; j++) {
            matrix[0][j] = j;
        }

        for (var i = 1; i <= len1; i++) {
            for (var j = 1; j <= len2; j++) {
                const cost = s1[i - 1] === s2[j - 1] ? 0 : 1;
                matrix[i][j] = Math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost);
            }
        }
        return matrix[len1][len2];
    }

    function fuzzyMatchScore(text, query, words) {
        const queryLower = query.toLowerCase();
        const maxDistance = query.length <= 2 ? 0 : query.length === 3 ? 1 : query.length <= 6 ? 2 : 3;

        let bestScore = 0;

        if (Math.abs(text.length - query.length) <= maxDistance) {
            const distance = levenshteinDistance(text.toLowerCase(), queryLower);
            if (distance <= maxDistance) {
                const maxLen = Math.max(text.length, query.length);
                bestScore = 1 - (distance / maxLen);
            }
        }

        for (const word of words || tokenize(text)) {
            if (Math.abs(word.length - query.length) > maxDistance)
                continue;
            const wordDistance = levenshteinDistance(word, queryLower);
            if (wordDistance <= maxDistance) {
                const maxLen = Math.max(word.length, query.length);
                const score = 1 - (wordDistance / maxLen);
                bestScore = Math.max(bestScore, score);
            }
        }

        return bestScore;
    }

    function calculateFrecency(app) {
        const usageRanking = AppUsageHistoryData.appUsageRanking || {};
        const appId = app.id || (app.execString || app.exec || "");
        const idVariants = [appId, appId.replace(".desktop", ""), app.id, app.id ? app.id.replace(".desktop", "") : null].filter(id => id);

        let usageData = null;
        for (const variant of idVariants) {
            if (usageRanking[variant]) {
                usageData = usageRanking[variant];
                break;
            }
        }

        if (!usageData || !usageData.usageCount) {
            return {
                "frecency": 0,
                "daysSinceUsed": 999999
            };
        }

        const usageCount = usageData.usageCount || 0;
        const lastUsed = usageData.lastUsed || 0;
        const now = Date.now();
        const daysSinceUsed = (now - lastUsed) / (1000 * 60 * 60 * 24);

        let timeBucketWeight = 10;
        for (const bucket of timeBuckets) {
            if (daysSinceUsed <= bucket.maxDays) {
                timeBucketWeight = bucket.weight;
                break;
            }
        }

        const contextBonus = 100;
        const sampleSize = Math.min(usageCount, frecencySampleSize);
        const frecency = (timeBucketWeight * contextBonus * sampleSize) / 100;

        return {
            "frecency": frecency,
            "daysSinceUsed": daysSinceUsed
        };
    }

    function searchApplications(query) {
        if (!query || query.length === 0)
            return getVisibleApplications();
        if (applications.length === 0)
            return [];

        const queryLower = query.toLowerCase().trim();
        const queryWords = tokenize(queryLower);
        const scoredApps = [];
        const results = [];
        const index = _visibleSearchIndex();
        const visibleApps = index.apps;

        for (const entry of index.entries) {
            const app = entry.app;
            const name = entry.name;
            const genericName = entry.genericName;
            const comment = entry.comment;
            const id = entry.id;
            const keywords = entry.keywords;

            let textScore = 0;
            let matchType = "none";

            if (name === queryLower) {
                textScore = 10000;
                matchType = "exact";
            } else if (name.startsWith(queryLower)) {
                textScore = 5000;
                matchType = "prefix";
            } else if (wordBoundaryMatchWords(entry.nameWords, queryWords)) {
                textScore = 3000;
                matchType = "word_boundary";
            } else if (name.includes(queryLower)) {
                textScore = 500;
                matchType = "substring";
            } else if (genericName && genericName.startsWith(queryLower)) {
                textScore = 800;
                matchType = "generic_prefix";
            } else if (genericName && genericName.includes(queryLower)) {
                textScore = 400;
                matchType = "generic";
            } else if (id && id.includes(queryLower)) {
                textScore = 350;
                matchType = "id";
            }

            if (matchType === "none" && keywords.length > 0) {
                for (const keyword of keywords) {
                    if (keyword.startsWith(queryLower)) {
                        textScore = 300;
                        matchType = "keyword_prefix";
                        break;
                    } else if (keyword.includes(queryLower)) {
                        textScore = 150;
                        matchType = "keyword";
                        break;
                    }
                }
            }

            if (matchType === "none" && comment && comment.includes(queryLower)) {
                textScore = 50;
                matchType = "comment";
            }

            if (matchType === "none") {
                const fuzzyScore = fuzzyMatchScore(name, queryLower, entry.nameWords);
                if (fuzzyScore > 0) {
                    textScore = fuzzyScore * 100;
                    matchType = "fuzzy";
                }
            }

            if (matchType !== "none") {
                const frecencyData = calculateFrecency(app);

                results.push({
                    "app": app,
                    "textScore": textScore,
                    "frecency": frecencyData.frecency,
                    "daysSinceUsed": frecencyData.daysSinceUsed,
                    "matchType": matchType
                });
            }
        }

        for (const result of results) {
            const frecencyBonus = result.frecency > 0 ? Math.min(result.frecency, 2000) : 0;
            const recencyBonus = result.daysSinceUsed < 1 ? 1500 : result.daysSinceUsed < 7 ? 1000 : result.daysSinceUsed < 30 ? 500 : 0;

            const finalScore = result.textScore + frecencyBonus + recencyBonus;

            scoredApps.push({
                "app": result.app,
                "score": finalScore
            });
        }

        if (SessionData.searchAppActions) {
            const actionResults = searchAppActions(queryLower, visibleApps);
            for (const actionResult of actionResults) {
                scoredApps.push({
                    app: actionResult.app,
                    score: actionResult.score
                });
            }
        }

        scoredApps.sort((a, b) => b.score - a.score);
        return scoredApps.slice(0, maxResults).map(item => item.app);
    }

    function searchAppActions(query, apps) {
        const results = [];
        for (const app of apps) {
            if (!app.actions || app.actions.length === 0)
                continue;
            for (const action of app.actions) {
                const actionName = (action.name || "").toLowerCase();
                if (!actionName)
                    continue;

                let score = 0;
                if (actionName === query) {
                    score = 8000;
                } else if (actionName.startsWith(query)) {
                    score = 4000;
                } else if (actionName.includes(query)) {
                    score = 400;
                }

                if (score > 0) {
                    results.push({
                        app: {
                            name: action.name,
                            icon: action.icon || app.icon,
                            comment: app.name,
                            categories: app.categories || [],
                            isAction: true,
                            parentApp: app,
                            actionData: action
                        },
                        score: score
                    });
                }
            }
        }
        return results;
    }

    readonly property var _categoryMap: ({
            "AudioVideo": I18n.tr("Media", "launcher app category for audio and video apps"),
            "Audio": I18n.tr("Media"),
            "Video": I18n.tr("Media"),
            "Development": I18n.tr("Development", "launcher app category"),
            "TextEditor": I18n.tr("Development"),
            "IDE": I18n.tr("Development"),
            "Education": I18n.tr("Education", "launcher app category"),
            "Game": I18n.tr("Games", "launcher app category"),
            "Graphics": I18n.tr("Graphics", "launcher app category"),
            "Photography": I18n.tr("Graphics"),
            "Network": I18n.tr("Internet"),
            "WebBrowser": I18n.tr("Internet"),
            "Email": I18n.tr("Internet"),
            "Office": I18n.tr("Office", "launcher app category"),
            "WordProcessor": I18n.tr("Office"),
            "Spreadsheet": I18n.tr("Office"),
            "Presentation": I18n.tr("Office"),
            "Science": I18n.tr("Science", "launcher app category"),
            "Settings": I18n.tr("Settings"),
            "System": I18n.tr("System"),
            "Utility": I18n.tr("Utilities"),
            "Accessories": I18n.tr("Utilities"),
            "FileManager": I18n.tr("Utilities"),
            "TerminalEmulator": I18n.tr("Utilities")
        })

    on_CategoryMapChanged: _cachedCategories = null

    function getCategoriesForApp(app) {
        if (!app?.categories)
            return [];

        const mappedCategories = new Set();
        for (const cat of app.categories) {
            const mapped = _categoryMap[cat];
            if (mapped)
                mappedCategories.add(mapped);
        }
        return Array.from(mappedCategories);
    }

    property var categoryIcons: ({
            "All": "apps",
            "Media": "music_video",
            "Development": "code",
            "Games": "sports_esports",
            "Graphics": "photo_library",
            "Internet": "web",
            "Office": "content_paste",
            "Settings": "settings",
            "System": "host",
            "Utilities": "build"
        })

    function getCategoryIcon(category) {
        // Check if it's a plugin category
        const pluginIcon = getPluginCategoryIcon(category);
        if (pluginIcon) {
            return pluginIcon;
        }
        return categoryIcons[category] || "folder";
    }

    function getAllCategories() {
        if (_cachedCategories)
            return _cachedCategories;

        const categories = new Set([I18n.tr("All")]);
        for (const app of applications) {
            const appCategories = getCategoriesForApp(app);
            appCategories.forEach(cat => categories.add(cat));
        }

        for (const app of coreApps) {
            const appCategories = getCategoriesForApp(app);
            appCategories.forEach(cat => categories.add(cat));
        }

        _cachedCategories = Array.from(categories).sort();
        return _cachedCategories;
    }

    function getAppsInCategory(category) {
        const visibleApps = getVisibleApplications();
        if (category === I18n.tr("All"))
            return visibleApps;

        return visibleApps.filter(app => {
            const appCategories = getCategoriesForApp(app);
            return appCategories.includes(category);
        });
    }

    function getPluginIdForCategory(category) {
        if (typeof PluginService === "undefined")
            return null;

        const launchers = PluginService.getLauncherPlugins();
        for (const pluginId in launchers) {
            if ((launchers[pluginId].name || pluginId) === category)
                return pluginId;
        }
        return null;
    }

    // Plugin launcher support functions
    function getPluginCategories() {
        if (typeof PluginService === "undefined") {
            return [];
        }

        const categories = [];
        const launchers = PluginService.getLauncherPlugins();

        for (const pluginId in launchers) {
            const plugin = launchers[pluginId];
            const categoryName = plugin.name || pluginId;
            categories.push(categoryName);
        }

        return categories;
    }

    function getPluginCategoryIcon(category) {
        const pluginId = getPluginIdForCategory(category);
        if (!pluginId)
            return null;

        return PluginService.getLauncherPlugins()[pluginId].icon || "extension";
    }

    function getPluginItems(category, query) {
        const pluginId = getPluginIdForCategory(category);
        if (!pluginId)
            return [];

        return getPluginItemsForPlugin(pluginId, query);
    }

    function getPluginItemsForPlugin(pluginId, query) {
        if (typeof PluginService === "undefined") {
            return [];
        }

        const instance = PluginService.ensureLauncherInstance(pluginId);
        if (!instance)
            return [];

        try {
            if (typeof instance.getItems === "function")
                return instance.getItems(query || "") || [];
        } catch (e) {
            log.warn("Error getting items from plugin", pluginId, ":", e);
        }

        return [];
    }

    function executePluginItem(item, pluginId) {
        if (typeof PluginService === "undefined")
            return false;

        const instance = PluginService.ensureLauncherInstance(pluginId);
        if (!instance)
            return false;

        try {
            if (typeof instance.executeItem === "function") {
                instance.executeItem(item);
                return true;
            }
        } catch (e) {
            log.warn("Error executing item from plugin", pluginId, ":", e);
        }

        return false;
    }

    function getPluginPasteArgs(pluginId, item) {
        if (typeof PluginService === "undefined")
            return null;

        const instance = PluginService.ensureLauncherInstance(pluginId);
        if (!instance)
            return null;

        if (typeof instance.getPasteArgs === "function")
            return instance.getPasteArgs(item);

        if (typeof instance.getPasteText === "function") {
            const text = instance.getPasteText(item);
            if (text)
                return ["dms", "cl", "copy", text];
        }

        return null;
    }

    function getPluginLauncherCategories(pluginId) {
        if (typeof PluginService === "undefined")
            return [];

        const instance = PluginService.ensureLauncherInstance(pluginId);
        if (!instance)
            return [];

        if (typeof instance.getCategories !== "function")
            return [];

        try {
            return instance.getCategories() || [];
        } catch (e) {
            log.warn("Error getting categories from plugin", pluginId, ":", e);
            return [];
        }
    }

    function setPluginLauncherCategory(pluginId, categoryId) {
        if (typeof PluginService === "undefined")
            return;

        const instance = PluginService.ensureLauncherInstance(pluginId);
        if (!instance)
            return;

        if (typeof instance.setCategory !== "function")
            return;

        try {
            instance.setCategory(categoryId);
        } catch (e) {
            log.warn("Error setting category on plugin", pluginId, ":", e);
        }
    }

    signal uninstallAppConfirmRequested(string appId, string appName, string flatpakId)

    property string _uninstallingAppId: ""
    property string _uninstallingAppName: ""
    property string _uninstallingStderr: ""

    Process {
        id: flatpakUninstallProc
        running: false
        command: []

        stderr: StdioCollector {
            onStreamFinished: {
                root._uninstallingStderr = (text || "").trim();
            }
        }

        onExited: exitCode => {
            const appName = root._uninstallingAppName;
            const appId = root._uninstallingAppId;
            const err = root._uninstallingStderr;
            root._uninstallingAppName = "";
            root._uninstallingAppId = "";
            root._uninstallingStderr = "";

            if (exitCode === 0) {
                ToastService.showInfo(I18n.tr("Uninstalled: %1", "uninstallation success").arg(appName));
                if (appId) {
                    SessionData.removePinnedApp(appId);
                    SessionData.removeBarPinnedApp(appId);
                }
                root.refreshApplications();
            } else {
                ToastService.showError(I18n.tr("Uninstall failed: %1", "uninstallation error").arg(appName), err);
            }
        }
    }

    function requestUninstallFlatpak(appId, appName, flatpakId) {
        if (!flatpakId)
            return;
        uninstallAppConfirmRequested(appId, appName, flatpakId);
    }

    function uninstallFlatpak(appId, appName, flatpakId) {
        if (!flatpakId)
            return;
        if (flatpakUninstallProc.running) {
            ToastService.showWarning(I18n.tr("An uninstallation is already in progress", "toast warning message"));
            return;
        }

        _uninstallingAppId = appId || "";
        _uninstallingAppName = appName || flatpakId;
        _uninstallingStderr = "";
        flatpakUninstallProc.command = ["flatpak", "uninstall", "-y", "--app", flatpakId];
        flatpakUninstallProc.running = true;

        ToastService.showInfo(I18n.tr("Uninstalling: %1", "uninstallation progress").arg(_uninstallingAppName));
    }
}
