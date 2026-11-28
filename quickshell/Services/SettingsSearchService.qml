pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.DDash
import "../Common/CompositorAnimations.js" as CompositorAnimations
import "../Common/NotchGeometry.js" as NotchGeometry

Singleton {
    id: root
    readonly property var log: Log.scoped("SettingsSearchService")

    property string query: ""
    property var results: []
    property string targetSection: ""
    property string highlightSection: ""
    property var registeredCards: ({})
    property var settingsIndex: []
    property bool indexLoaded: false
    property var _translatedCache: []
    property bool _reading: false
    property var _buildItems: []
    property var _buildCache: []
    property bool _rebuildQueued: false
    property bool _building: false
    property var _squashMemo: null
    readonly property url indexUrl: Qt.resolvedUrl("../translations/settings_search_index.json")
    readonly property int buildSliceMs: 2
    property int _scrollPass: 0
    property int _stablePasses: 0
    property real _appliedY: 0
    property string _lastGeometry: ""
    readonly property int settleInterval: 250
    readonly property int stablePassesNeeded: 4
    readonly property int maxScrollPasses: 12

    Connections {
        target: I18n

        function onTranslationsChanged() {
            root._refreshTranslatedCache();
        }

        function onTranslationsLoadedChanged() {
            root._refreshTranslatedCache();
        }
    }

    Connections {
        target: PluginService

        function onPluginListUpdated() {
            root._refreshTranslatedCache();
        }
    }

    Connections {
        target: UsersService

        function onAdminGroupChanged() {
            root._refreshTranslatedCache();
        }

        function onGreeterGroupChanged() {
            root._refreshTranslatedCache();
        }
    }

    Connections {
        target: SettingsTabs

        function onPageMapChanged() {
            root._refreshTranslatedCache();
        }
    }

    Connections {
        target: PopoutService

        function onSettingsModalChanged() {
            if (PopoutService.settingsModal)
                root._prepareIndex();
        }
    }

    // Settings creates this service, so its first open lands here rather than in onSettingsModalChanged.
    Component.onCompleted: _prepareIndex()

    // The index reads as settings opens, and its cache builds in short slices between events.
    function _buildStep() {
        if (!_building)
            return;
        if (!_buildSlice(buildSliceMs)) {
            Qt.callLater(_buildStep);
            return;
        }
        if (query)
            results = _searchEntries(query, 15);
    }

    readonly property var conditionMap: ({
            "isNiri": () => CompositorService.isNiri,
            "pointerCapable": () => CompositorService.supportsPointerConfig,
            "inputCapable": () => CompositorService.supportsInputConfig,
            "isHyprland": () => CompositorService.isHyprland,
            "isMango": () => CompositorService.isMango,
            "nativeOverviewCapable": () => CompositorService.supportsNativeOverview,
            "smartDockCapable": () => CompositorService.supportsSmartDock,
            "workspaceFollowFocusCapable": () => CompositorService.supportsWorkspaceFollowFocus,
            "isHyprlandOrNiri": () => CompositorService.isHyprland || CompositorService.isNiri,
            "isNiriOrMango": () => CompositorService.isNiri || CompositorService.isMango,
            "windowRulesCapable": () => CompositorService.supportsWindowRules,
            "layoutCapable": () => CompositorService.supportsLayoutConfig,
            "animationsCapable": () => CompositorService.supportsAnimationsConfig,
            "animationsPopupsCapable": () => CompositorAnimations.groups(CompositorService.compositor).includes("popups"),
            "keybindsAvailable": () => KeybindsService.available,
            "globalShortcutsAvailable": () => GlobalShortcutsService.available,
            "soundsAvailable": () => !MultimediaService.unavailable,
            "cupsAvailable": () => CupsService.cupsAvailable,
            "networkAvailable": () => NetworkService.networkAvailable,
            "wallpaperFoldersAdded": () => SessionData.wallpaperFolders.length > 0,
            "dmsConnected": () => DMSService.isConnected && DMSService.apiVersion >= 23,
            "matugenAvailable": () => Theme.matugenAvailable,
            "greeterAvailable": () => GreeterService.available,
            "frameEnabled": () => SettingsData.frameEnabled,
            "islandEnabled": () => root.conditionBarFor("islandEnabled") !== null,
            "islandFree": () => root.conditionBarFor("islandFree") !== null,
            "islandDocked": () => root.conditionBarFor("islandDocked") !== null,
            "dotEnabled": () => SettingsData.dotBarConfig?.enabled ?? false,
            "cellularAvailable": () => NetworkService.cellularAvailable,
            "connectionEditorAvailable": () => NetworkService.connectionEditorSupported,
            "wifiDeviceAvailable": () => NetworkService.wifiDevicePresent,
            "hotspotAvailable": () => NetworkService.hotspotAvailable,
            "tailscaleAvailable": () => TailscaleService.available,
            "fcitx5Available": () => Fcitx5Service.available,
            "dockEnabled": () => (SettingsData.dockConfigs ?? []).some(dock => dock.enabled),
            "notchDisplay": () => root.conditionBarFor("notchDisplay") !== null
        })

    readonly property var islandBarFilters: ({
            "islandEnabled": cfg => true,
            "islandFree": cfg => SettingsData.islandFreePlacement(cfg),
            "islandDocked": cfg => !SettingsData.islandFreePlacement(cfg)
        })

    function notchBarConfigs() {
        const ids = [];
        for (const layout of ShellLayout.layouts) {
            if (!NotchGeometry.cutout(DMSService.deviceCompatible, layout.screen.width, layout.screen.height, layout.screen.scale))
                continue;
            for (const instance of layout.instances) {
                if (instance.edge === "top" && instance.kind !== "island")
                    ids.push(instance.barId);
            }
        }
        return SettingsData.barConfigs.filter(cfg => ids.includes(cfg.id));
    }

    // Bar rows show only for the selected bar, so pick one that meets the condition.
    function conditionBarFor(conditionKey, preferredId) {
        const filter = islandBarFilters[conditionKey];
        const bars = filter ? SettingsData.enabledIslandBarConfigs.filter(filter) : conditionKey === "notchDisplay" ? notchBarConfigs() : [];
        return bars.find(cfg => cfg.id === preferredId) ?? bars[0] ?? null;
    }

    property var pluginSettingLabels: ({})

    Instantiator {
        model: root.indexLoaded ? (PluginService.availablePluginsList || []).filter(plugin => !!plugin.settingsPath) : []

        FileView {
            required property var modelData

            path: "file://" + modelData.settingsPath
            printErrors: false
            onLoaded: root._indexPluginSettings(modelData.id, text())
        }
    }

    property var barWidgetLabels: ({})
    readonly property var presentBarWidgets: {
        const present = {};
        for (const config of SettingsData.barConfigs) {
            for (const sectionId of ["left", "center", "right"]) {
                for (const entry of config[sectionId + "Widgets"] ?? [])
                    present[typeof entry === "string" ? entry : entry.id] = true;
            }
        }
        return present;
    }

    onPresentBarWidgetsChanged: _refreshTranslatedCache()

    function _barWidgetSearchEntries() {
        const entries = [];
        for (const widget of BarWidgetCatalog.widgets) {
            const present = presentBarWidgets[widget.id] === true;
            entries.push({
                section: "",
                label: widget.text,
                tabIndex: 22,
                category: present ? "Bar widgets" : "Add widget",
                keywords: [widget.id, "widget", "bar"],
                icon: widget.icon,
                description: widget.description,
                conditionKey: "",
                runtimeType: present ? "barWidget" : "barWidgetAdd",
                runtimeId: widget.id
            });
            if (!present)
                continue;
            const labels = barWidgetLabels[BarWidgetCatalog.optionsFile(widget.id)] || [];
            for (const label of labels) {
                entries.push({
                    section: "",
                    label: label,
                    tabIndex: 22,
                    category: widget.text,
                    keywords: [widget.id, "widget", "bar"],
                    icon: widget.icon,
                    description: "",
                    conditionKey: "",
                    runtimeType: "barWidget",
                    runtimeId: widget.id
                });
            }
        }
        return entries;
    }

    function _indexPluginSettings(pluginId, source) {
        const labels = [];
        const pattern = /\blabel:\s*(?:I18n\.tr\()?"((?:[^"\\]|\\.)*)"/g;
        let match;
        while ((match = pattern.exec(source)) !== null) {
            if (match[1] && labels.indexOf(match[1]) === -1)
                labels.push(match[1]);
        }
        if (JSON.stringify(pluginSettingLabels[pluginId] ?? []) === JSON.stringify(labels))
            return;
        const next = Object.assign({}, pluginSettingLabels);
        next[pluginId] = labels;
        pluginSettingLabels = next;
        _refreshTranslatedCache();
    }

    FileView {
        id: indexFile
        blockLoading: true
        onLoaded: {
            if (root._reading)
                root._readIndex();
        }
        onLoadFailed: error => root.log.warn("Failed to load index:", error)
    }

    // The index and its search cache stay once built; they build off the open path so neither settings nor a keystroke waits.
    function _prepareIndex() {
        if (indexLoaded || _reading)
            return;
        _reading = true;
        indexFile.path = indexUrl;
    }

    // Blocks until the cache is built; a search only waits on it before the first build finishes.
    function ensureIndex() {
        if (!indexLoaded)
            _readIndex();
        while (_building)
            _buildSlice(Number.POSITIVE_INFINITY);
    }

    function _readIndex() {
        _reading = false;
        indexFile.path = indexUrl;
        const text = indexFile.text();
        Qt.callLater(() => {
            if (!root._reading)
                indexFile.path = "";
        });
        try {
            const labels = {};
            settingsIndex = JSON.parse(text).filter(entry => {
                if (entry.runtimeType !== "barWidgetOption")
                    return true;
                labels[entry.optionFile] = (labels[entry.optionFile] ?? []).concat(entry.label);
                return false;
            });
            barWidgetLabels = labels;
            indexLoaded = true;
            _startBuild();
        } catch (e) {
            log.warn("Failed to parse index:", e);
            settingsIndex = [];
            _translatedCache = [];
        }
    }

    function _startBuild() {
        _buildItems = settingsIndex.concat(_runtimeSearchEntries());
        _buildCache = [];
        _rebuildQueued = false;
        _squashMemo = new Map();
        _building = true;
        Qt.callLater(_buildStep);
    }

    // Returns true once the cache is complete and no rebuild is queued.
    function _buildSlice(budgetMs) {
        const deadline = Date.now() + budgetMs;
        const items = _buildItems;
        const cache = _buildCache;
        while (cache.length < items.length && Date.now() < deadline)
            cache.push(_cacheEntry(items[cache.length], cache.length));
        if (cache.length < items.length)
            return false;
        _building = false;
        _squashMemo = null;
        _translatedCache = cache;
        _buildItems = [];
        _buildCache = [];
        if (!_rebuildQueued)
            return true;
        _startBuild();
        return false;
    }

    function registerCard(settingKey, item, flickable, collapsible) {
        if (!settingKey)
            return;
        var cards = Object.assign({}, registeredCards);
        cards[settingKey] = {
            item: item,
            flickable: flickable,
            collapsible: collapsible ?? null
        };
        registeredCards = cards;
        if (targetSection !== settingKey)
            return;
        _expandFor(cards[settingKey]);
        scrollTimer.restart();
    }

    function unregisterCard(settingKey, item) {
        if (!settingKey)
            return;
        if (item && registeredCards[settingKey] && registeredCards[settingKey].item !== item)
            return;
        var cards = Object.assign({}, registeredCards);
        delete cards[settingKey];
        registeredCards = cards;
    }

    function navigateToSection(section) {
        targetSection = section;
        _scrollPass = 0;
        _stablePasses = 0;
        _lastGeometry = "";
        scrollTimer.interval = Timing.settleShort;
        const entry = registeredCards[section];
        if (!entry)
            return;
        _expandFor(entry);
        scrollTimer.restart();
    }

    function _expandFor(entry) {
        if (!entry)
            return;
        _expand(entry.collapsible);
        _expand(entry.item);
    }

    function _expand(card) {
        if (!card || card.collapsible !== true || card.expanded)
            return;
        card.expanded = true;
    }

    function scrollToTarget() {
        if (!targetSection)
            return;
        const entry = registeredCards[targetSection];
        if (!entry || !entry.item || !entry.flickable)
            return;
        const flickable = entry.flickable;
        const item = entry.item;
        const contentItem = flickable.contentItem;

        if (!contentItem)
            return;
        const userScrolled = _scrollPass > 0 && Math.abs(flickable.contentY - _appliedY) > 1;
        if (userScrolled) {
            _finishScroll();
            return;
        }
        const mapped = item.mapToItem(contentItem, 0, 0);
        const maxY = Math.max(0, flickable.contentHeight - flickable.height);
        const targetY = Math.min(maxY, Math.max(0, mapped.y - 16));
        flickable.contentY = targetY;
        _appliedY = flickable.contentY;

        highlightSection = targetSection;
        highlightTimer.restart();
        const geometry = mapped.y + ":" + flickable.contentHeight;
        _stablePasses = geometry === _lastGeometry ? _stablePasses + 1 : 0;
        _lastGeometry = geometry;
        _scrollPass++;
        if (_stablePasses < stablePassesNeeded && _scrollPass < maxScrollPasses) {
            scrollTimer.interval = settleInterval;
            scrollTimer.restart();
            return;
        }
        _finishScroll();
    }

    function _finishScroll() {
        targetSection = "";
        scrollTimer.interval = Timing.settleShort;
    }

    function clearHighlight() {
        highlightSection = "";
    }

    Timer {
        id: scrollTimer
        interval: Timing.settleShort
        onTriggered: root.scrollToTarget()
    }

    Timer {
        id: highlightTimer
        interval: Timing.holdMedium
        onTriggered: root.highlightSection = ""
    }

    function checkCondition(item) {
        if (!item.conditionKey)
            return true;
        const condFn = conditionMap[item.conditionKey];
        if (!condFn)
            return true;
        return condFn();
    }

    function _itemLabel(item) {
        switch (item.runtimeType) {
        case "plugin":
            return item.label;
        case "pageLabel":
            return SettingsTabs.page(SettingsTabs.pageForTabIndex(item.tabIndex))?.text ?? "";
        default:
            return I18n.tr(item.label);
        }
    }

    function translateItem(item) {
        const isRuntimePlugin = item.runtimeType === "plugin";
        const label = _itemLabel(item);
        const description = isRuntimePlugin ? (item.description || "") : _withArgs(I18n.tr(item.description || ""), item.descriptionArgs);
        const category = I18n.tr(item.category);
        return {
            section: item.section,
            label: label,
            tabIndex: item.tabIndex,
            category: item.parentLabel ? I18n.tr(item.parentLabel) + " › " + category : category,
            keywords: item.keywords || [],
            icon: item.icon || "settings",
            description: description,
            conditionKey: item.conditionKey,
            runtimeType: item.runtimeType || "",
            runtimeId: item.runtimeId || "",
            page: item.page || (isRuntimePlugin ? SettingsTabs.pluginPrefix + item.runtimeId : "")
        };
    }

    function _withArgs(text, args) {
        if (!args)
            return text;
        return args.reduce((acc, arg) => acc.arg(_descriptionArgument(arg)), text);
    }

    function _descriptionArgument(arg) {
        if (typeof arg === "string")
            return arg;
        if (arg?.service !== "UsersService")
            return "";
        switch (arg.property) {
        case "adminGroup":
        case "greeterGroup":
            return UsersService[arg.property];
        default:
            return "";
        }
    }

    function _cacheEntry(item, order) {
        const t = translateItem(item);
        const sourceDescription = _withArgs(item.description || "", item.descriptionArgs);
        const labelLower = _lowerVariants([item.label, t.label]);
        const categoryLower = _lowerVariants([item.category, item.parentLabel, t.category]);
        const descriptionLower = item.runtimeType === "plugin" ? [] : _lowerVariants([sourceDescription, t.description]);
        const labelSquash = _squashVariants(labelLower);
        const categorySquash = _squashVariants(categoryLower);
        const descriptionSquash = _squashVariants(descriptionLower);
        const keywordsSquash = _squashVariants(t.keywords);
        return {
            section: t.section,
            label: t.label,
            tabIndex: t.tabIndex,
            category: t.category,
            keywords: t.keywords,
            icon: t.icon,
            description: t.description,
            conditionKey: t.conditionKey,
            runtimeType: t.runtimeType,
            runtimeId: t.runtimeId,
            page: t.page,
            level: _entryLevel(t.section),
            order: order,
            labelSearch: labelLower,
            categorySearch: categoryLower,
            descriptionSearch: descriptionLower,
            labelSquash: labelSquash,
            categorySquash: categorySquash,
            descriptionSquash: descriptionSquash,
            keywordsSquash: keywordsSquash,
            haystack: labelLower.concat(categoryLower, descriptionLower, t.keywords).join("\n"),
            haystackSquash: labelSquash.concat(categorySquash, descriptionSquash, keywordsSquash).join("\n")
        };
    }

    function _runtimeSearchEntries() {
        var entries = _barWidgetSearchEntries();
        for (const entry of DashRegistry.entries) {
            for (const spec of entry.options ?? []) {
                entries.push({
                    section: "dashOptions:" + entry.id + ":" + spec.key,
                    label: spec.text,
                    tabIndex: 43,
                    category: entry.text,
                    parentLabel: "Dashboard",
                    keywords: [entry.id, entry.text, "dash", "options"],
                    icon: entry.icon,
                    description: spec.description ?? ""
                });
            }
        }
        var plugins = PluginService.availablePluginsList || [];
        for (var i = 0; i < plugins.length; i++) {
            var plugin = plugins[i];
            entries.push({
                section: "",
                label: plugin.name || plugin.id,
                tabIndex: 12,
                category: "Plugins",
                keywords: [plugin.id || ""],
                icon: plugin.icon || "extension",
                description: plugin.description || "",
                conditionKey: "",
                runtimeType: "plugin",
                runtimeId: plugin.id || ""
            });
            var labels = pluginSettingLabels[plugin.id] || [];
            for (var j = 0; j < labels.length; j++) {
                entries.push({
                    section: "",
                    label: labels[j],
                    tabIndex: 12,
                    category: plugin.name || plugin.id,
                    keywords: [plugin.id || "", plugin.name || ""],
                    icon: plugin.icon || "extension",
                    description: "",
                    conditionKey: "",
                    runtimeType: "plugin",
                    runtimeId: plugin.id || ""
                });
            }
        }
        return entries;
    }

    function _lowerVariants(values) {
        var out = [];
        for (var i = 0; i < values.length; i++) {
            var value = values[i];
            if (!value)
                continue;
            var lower = String(value).toLowerCase();
            if (out.indexOf(lower) === -1)
                out.push(lower);
        }
        return out;
    }

    function _squash(value) {
        return String(value).toLowerCase().replace(/[^a-z0-9]+/g, "");
    }

    // Labels, categories and keywords repeat across entries, and the regex dominates the build.
    function _squashMemoized(value) {
        if (!_squashMemo)
            return _squash(value);
        let squashed = _squashMemo.get(value);
        if (squashed === undefined) {
            squashed = _squash(value);
            _squashMemo.set(value, squashed);
        }
        return squashed;
    }

    function _squashVariants(values) {
        var out = [];
        for (var i = 0; i < values.length; i++) {
            if (!values[i])
                continue;
            var squashed = _squashMemoized(values[i]);
            if (squashed && out.indexOf(squashed) === -1)
                out.push(squashed);
        }
        return out;
    }

    readonly property var labelScores: ({
            "exact": 10000,
            "plural": 9500,
            "prefix": 5000,
            "wordStart": 3000,
            "includes": 1000
        })
    readonly property var squashScores: ({
            "exact": 9000,
            "plural": 8500,
            "prefix": 4500,
            "wordStart": 900,
            "includes": 900
        })
    // V4 regex has no \p{} classes, so word breaks are whitespace and punctuation ranges.
    readonly property var wordBreak: /[\s!-\/:-@\[-`{-~\u2000-\u206f\u3000-\u303f]/

    function _entryLevel(section) {
        const id = String(section);
        if (id.startsWith("_hub_"))
            return 2;
        if (id.startsWith("_tab_"))
            return 1;
        return 0;
    }

    function _singular(value) {
        if (value.length <= 3 || !value.endsWith("s") || value.endsWith("ss"))
            return value;
        return value.slice(0, -1);
    }

    function _startsWord(field, query) {
        for (var at = field.indexOf(query, 1); at > 0; at = field.indexOf(query, at + 1)) {
            if (wordBreak.test(field[at - 1]))
                return true;
        }
        return false;
    }

    function _labelScore(labels, query, scores) {
        var score = 0;
        for (var i = 0; i < labels.length; i++) {
            var label = labels[i];
            if (label === query)
                return scores.exact;
            if (_singular(label) === _singular(query))
                score = Math.max(score, scores.plural);
            else if (label.startsWith(query))
                score = Math.max(score, scores.prefix);
            else if (_startsWord(label, query))
                score = Math.max(score, scores.wordStart);
            else if (label.includes(query))
                score = Math.max(score, scores.includes);
        }
        return score;
    }

    function _keywordScore(entry, query, querySquash) {
        var score = 0;
        for (const keyword of entry.keywords) {
            if (keyword === query)
                return 900;
            if (keyword.startsWith(query))
                score = Math.max(score, 800);
            else if (keyword.includes(query))
                score = Math.max(score, 400);
        }
        if (!querySquash)
            return score;
        for (const keyword of entry.keywordsSquash) {
            if (keyword === querySquash)
                return Math.max(score, 850);
            if (keyword.startsWith(querySquash))
                score = Math.max(score, 750);
        }
        return score;
    }

    function _fieldsContainWord(fields, word) {
        for (var i = 0; i < fields.length; i++) {
            if (fields[i].includes(word))
                return true;
        }
        return false;
    }

    // Every score needs the query, its singular or each of its words inside one field.
    function _mayMatch(entry, query, querySingular, querySquash, squashSingular, queryWords) {
        if (entry.haystack.includes(query) || entry.haystack.includes(querySingular))
            return true;
        if (querySquash && (entry.haystackSquash.includes(querySquash) || entry.haystackSquash.includes(squashSingular)))
            return true;
        if (queryWords.length < 2)
            return false;
        return queryWords.every(word => entry.haystack.includes(word));
    }

    function _refreshTranslatedCache() {
        if (_building) {
            _rebuildQueued = true;
            return;
        }
        if (!indexLoaded)
            return;
        _startBuild();
        if (query)
            results = _searchEntries(query, 15);
    }

    function _searchEntries(text, maxResults) {
        var queryLower = (text || "").toLowerCase().trim();
        if (!queryLower)
            return [];
        if (_translatedCache.length === 0)
            ensureIndex();

        var querySquash = _squash(queryLower);
        var queryWords = queryLower.split(/\s+/).filter(w => w.length > 0);
        var querySingular = _singular(queryLower);
        var squashSingular = _singular(querySquash);
        var scored = [];
        var cache = _translatedCache;
        var limit = maxResults > 0 ? maxResults : 15;

        for (var i = 0; i < cache.length; i++) {
            var entry = cache[i];
            if (!_mayMatch(entry, queryLower, querySingular, querySquash, squashSingular, queryWords))
                continue;
            if (!checkCondition(entry))
                continue;

            var labelScore = _labelScore(entry.labelSearch, queryLower, labelScores);
            if (querySquash)
                labelScore = Math.max(labelScore, _labelScore(entry.labelSquash, querySquash, squashScores));

            var score = Math.max(labelScore, _keywordScore(entry, queryLower, querySquash));
            if (_fieldsContainWord(entry.categorySearch, queryLower) || (querySquash && _fieldsContainWord(entry.categorySquash, querySquash)))
                score = Math.max(score, 500);
            if (_fieldsContainWord(entry.descriptionSearch, queryLower) || (querySquash && _fieldsContainWord(entry.descriptionSquash, querySquash)))
                score = Math.max(score, 250);

            if (score === 0 && queryWords.length > 1) {
                var allMatch = true;
                for (var w = 0; w < queryWords.length; w++) {
                    var word = queryWords[w];
                    if (_fieldsContainWord(entry.labelSearch, word))
                        continue;
                    if (_fieldsContainWord(entry.descriptionSearch, word))
                        continue;
                    if (_fieldsContainWord(entry.categorySearch, word))
                        continue;
                    var inKeywords = false;
                    for (var k = 0; k < entry.keywords.length; k++) {
                        if (entry.keywords[k].includes(word)) {
                            inKeywords = true;
                            break;
                        }
                    }
                    if (!inKeywords) {
                        allMatch = false;
                        break;
                    }
                }
                if (allMatch)
                    score = 300;
            }

            if (score > 0) {
                scored.push({
                    item: entry,
                    score: score,
                    labelTier: labelScore >= labelScores.wordStart ? 2 : labelScore > 0 ? 1 : 0
                });
            }
        }

        scored.sort((a, b) => {
            if (b.labelTier !== a.labelTier)
                return b.labelTier - a.labelTier;
            if (a.labelTier > 0 && b.item.level !== a.item.level)
                return b.item.level - a.item.level;
            if (b.score !== a.score)
                return b.score - a.score;
            if (b.item.level !== a.item.level)
                return b.item.level - a.item.level;
            const aRuntime = !!a.item.runtimeType;
            const bRuntime = !!b.item.runtimeType;
            if (aRuntime !== bRuntime)
                return aRuntime ? 1 : -1;
            if (a.item.label.length !== b.item.label.length)
                return a.item.label.length - b.item.label.length;
            return a.item.order - b.item.order;
        });
        return scored.slice(0, limit).map(s => s.item);
    }

    function searchForLauncher(text) {
        return _searchEntries(text, 15);
    }

    function search(text) {
        query = text;
        if (!text) {
            results = [];
            return;
        }
        results = _searchEntries(text, 15);
    }

    function clear() {
        query = "";
        results = [];
    }
}
