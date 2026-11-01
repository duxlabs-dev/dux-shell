pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import "Scorer.js" as Scorer
import "ControllerUtils.js" as Utils
import "NavigationHelpers.js" as Nav
import "ItemTransformers.js" as Transform

Item {
    id: root

    property string searchQuery: ""
    property string searchMode: "all"
    property string previousSearchMode: "all"
    property bool autoSwitchedToFiles: false
    property bool isFileSearching: false
    property var sections: []
    property var flatModel: []
    property int selectedFlatIndex: 0
    property var selectedItem: null
    property bool isSearching: false
    property string activePluginId: ""
    property var collapsedSections: ({})
    property bool keyboardNavigationActive: false
    property bool active: false
    property bool retainResultsOnClose: false
    property var _modeSectionsCache: ({})
    property bool _queryDrivenSearch: false
    property bool _diskCacheConsumed: false
    property var sectionViewModes: ({})
    property var pluginViewPreferences: ({})
    property int gridColumns: SettingsData.appLauncherGridColumns
    property int viewModeVersion: 0
    property string viewModeContext: "spotlight"
    property bool forceLinearNavigation: false
    property bool explicitQuerySession: false

    // dmenu mode items
    // come from a socket opened by `dms dmenu`, not from AppSearchService
    property string dmenuSocketPath: ""
    property var dmenuItems: []
    property string dmenuPrompt: "dmenu"
    property string dmenuPlaceholder: ""
    property int dmenuLines: 0
    property bool dmenuPromptOnly: false
    property string dmenuSelect: ""
    property string dmenuMesg: ""
    property bool dmenuPassword: false
    property bool dmenuMarkupRows: false
    property bool dmenuOnlyMatch: false
    property bool dmenuNoCustom: false
    property bool dmenuMultiSelect: false
    property var dmenuActiveRanges: []
    property var dmenuUrgentRanges: []
    property var dmenuMultiSelected: []
    property var dmenuKeybinds: []
    property string dmenuView: ""
    property string dmenuSize: ""
    property string dmenuIcon: ""
    property bool dmenuDisableHistory: false
    property bool _dmenuSelectApplied: false

    readonly property var _dmenuKeyNameMap: (function () {
            var m = ({});
            for (var c = 0; c < 26; c++)
                m[String.fromCharCode(97 + c)] = Qt.Key_A + c;
            for (var d = 0; d <= 9; d++)
                m[String(d)] = Qt.Key_0 + d;
            for (var f = 1; f <= 12; f++)
                m["f" + f] = Qt.Key_F1 + (f - 1);
            m["return"] = Qt.Key_Return;
            m["enter"] = Qt.Key_Enter;
            m["tab"] = Qt.Key_Tab;
            m["space"] = Qt.Key_Space;
            m["escape"] = Qt.Key_Escape;
            m["esc"] = Qt.Key_Escape;
            m["delete"] = Qt.Key_Delete;
            m["backspace"] = Qt.Key_Backspace;
            m["insert"] = Qt.Key_Insert;
            m["home"] = Qt.Key_Home;
            m["end"] = Qt.Key_End;
            m["pageup"] = Qt.Key_PageUp;
            m["pagedown"] = Qt.Key_PageDown;
            m["up"] = Qt.Key_Up;
            m["down"] = Qt.Key_Down;
            m["left"] = Qt.Key_Left;
            m["right"] = Qt.Key_Right;
            m["minus"] = Qt.Key_Minus;
            m["equal"] = Qt.Key_Equal;
            m["comma"] = Qt.Key_Comma;
            m["period"] = Qt.Key_Period;
            m["slash"] = Qt.Key_Slash;
            return m;
        })()

    function _parseDmenuKeySpec(spec) {
        var parts = spec.toLowerCase().split("+").map(function (s) {
            return s.trim();
        }).filter(function (s) {
            return s.length > 0;
        });
        if (parts.length === 0)
            return null;
        var keyToken = parts[parts.length - 1];
        var mods = Qt.NoModifier;
        for (var i = 0; i < parts.length - 1; i++) {
            switch (parts[i]) {
            case "ctrl":
            case "control":
                mods |= Qt.ControlModifier;
                break;
            case "alt":
                mods |= Qt.AltModifier;
                break;
            case "shift":
                mods |= Qt.ShiftModifier;
                break;
            case "meta":
            case "super":
                mods |= Qt.MetaModifier;
                break;
            default:
                return null;
            }
        }
        var key = _dmenuKeyNameMap[keyToken];
        if (key === undefined)
            return null;
        return {
            modifiers: mods,
            key: key
        };
    }

    function matchDmenuKeybind(event) {
        var mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier | Qt.MetaModifier);
        for (var i = 0; i < dmenuKeybinds.length; i++) {
            var kb = dmenuKeybinds[i];
            if (kb.key === event.key && kb.modifiers === mods)
                return kb.n;
        }
        return 0;
    }

    signal itemExecuted
    signal searchCompleted
    signal modeChanged(string mode, bool userInitiated)
    signal queryChanged(string query)
    signal viewModeChanged(string sectionId, string mode)
    signal searchQueryRequested(string query)
    signal sectionExpanded(string sectionId)

    Ref {
        service: AppSearchService
    }

    Loader {
        id: dmenuSocketLoader
        active: false
        onLoaded: item.connected = true

        sourceComponent: Socket {
            path: root.dmenuSocketPath

            parser: SplitParser {
                onRead: line => root._onDmenuSocketLine(line)
            }
        }
    }

    onActiveChanged: {
        ClipboardService.invalidateLauncherSearchCache();
        if (active)
            return;

        if (searchMode === "dmenu") {
            _endDmenuSession();
            if (!dmenuDisableHistory)
                SessionData.addLauncherHistory(searchQuery, explicitQuerySession);
        } else {
            SessionData.addLauncherHistory(searchQuery, explicitQuerySession);
        }
        _cancelSearch();
        selectedFlatIndex = -1;
        selectedItem = null;
        keyboardNavigationActive = false;
        if (retainResultsOnClose && searchMode !== "dmenu")
            return;
        sections = [];
        flatModel = [];
        _clearModeCache();
    }

    onSearchModeChanged: {
        if (searchMode === "apps") {
            _loadAppCategories();
        } else {
            appCategory = "";
            appCategories = [];
        }
    }

    Connections {
        target: SettingsData
        function onSortAppsAlphabeticallyChanged() {
            AppSearchService.invalidateLauncherCache();
            _clearModeCache();
        }
        function onLauncherPluginVisibilityChanged() {
            AppSearchService.invalidateLauncherCache();
            _clearModeCache();
            if (active)
                performSearch();
        }
        function onBuiltInPluginSettingsChanged() {
            AppSearchService.invalidateLauncherCache();
            _clearModeCache();
            if (active)
                performSearch();
        }
    }

    Connections {
        target: ClipboardService
        function onLauncherSearchReady(query) {
            if (!active)
                return;

            const clipboardBuiltInActive = activePluginId === "dms_clipboard_search";
            if (!clipboardBuiltInActive && !clipboardSearchEnabledInAll())
                return;
            if (!clipboardBuiltInActive && searchMode !== "all")
                return;

            const trimmed = (searchQuery || "").trim();
            if (trimmed.length < 2 && query.length > 0)
                return;
            const triggerMatch = detectTrigger(trimmed);
            const effectiveQuery = clipboardBuiltInActive && triggerMatch.pluginId === "dms_clipboard_search" ? triggerMatch.query : trimmed;
            if (query !== effectiveQuery)
                return;
            if (!clipboardBuiltInActive && _refreshClipboardResults())
                return;

            root.requestSearch();
        }
    }

    readonly property int searchCacheVersion: AppSearchService.cacheVersion

    onSearchCacheVersionChanged: {
        _clearModeCache();
        if (!active)
            return;
        if (searchMode === "apps") {
            _loadAppCategories();
            performSearch();
        } else if (!searchQuery && searchMode === "all") {
            performSearch();
        }
    }

    Connections {
        target: PluginService
        function onRequestLauncherUpdate(pluginId) {
            if (!active || !PluginService.pluginInstances[pluginId])
                return;
            if (activePluginId === pluginId) {
                if (activePluginCategories.length <= 1)
                    loadPluginCategories(pluginId);
                performSearch();
                return;
            }
            if (!searchQuery)
                return;
            if (_refreshPluginResults(pluginId))
                return;
            performSearch();
        }
    }

    function pasteSelected() {
        if (!selectedItem)
            return;
        if (selectedItem.type === "clipboard") {
            if (SettingsData.clipboardEnterToPaste) {
                ClipboardService.copyEntry(selectedItem.data, function () {
                    root.itemExecuted();
                });
            } else {
                ClipboardService.pasteEntry(selectedItem.data, function () {
                    root.itemExecuted();
                });
            }
            return;
        }

        const pluginId = selectedItem.pluginId;
        if (!pluginId)
            return;
        const pasteArgs = AppSearchService.getPluginPasteArgs(pluginId, selectedItem.data);
        if (!pasteArgs)
            return;
        ClipboardService.pasteAfterCommand(pasteArgs);
        itemExecuted();
    }

    readonly property var sectionDefinitions: [
        {
            id: "dmenu",
            title: "",
            icon: "list",
            priority: 1,
            defaultViewMode: "list"
        },
        {
            id: "favorites",
            title: I18n.tr("Pinned"),
            icon: "push_pin",
            priority: 1,
            defaultViewMode: "list"
        },
        {
            id: "apps",
            title: I18n.tr("Applications", "launcher section title and settings page name"),
            icon: "apps",
            priority: 2,
            defaultViewMode: "list"
        },
        {
            id: "settings",
            title: I18n.tr("Settings", "settings window title"),
            icon: "settings",
            priority: 2.35,
            defaultViewMode: "list"
        },
        {
            id: "clipboard",
            title: I18n.tr("Clipboard"),
            icon: "content_paste",
            priority: 2.45,
            defaultViewMode: "list"
        },
        {
            id: "browse_plugins",
            title: I18n.tr("Browse"),
            icon: "category",
            priority: 2.5,
            defaultViewMode: "grid"
        },
        {
            id: "files",
            title: I18n.tr("Files", "launcher file search section title and filter option"),
            icon: "folder",
            priority: 4,
            defaultViewMode: "list"
        },
        {
            id: "fallback",
            title: I18n.tr("Commands", "noun, launcher results section title"),
            icon: "terminal",
            priority: 5,
            defaultViewMode: "list"
        }
    ]

    property int historyIndex: -1
    property string typingBackup: ""

    function navigateHistory(direction) {
        let history = SessionData.launcherQueryHistory;
        if (history.length === 0)
            return;

        if (historyIndex === -1)
            typingBackup = searchQuery;

        let nextIndex = historyIndex + (direction === "up" ? 1 : -1);
        if (nextIndex >= history.length)
            nextIndex = history.length - 1;
        if (nextIndex < -1)
            nextIndex = -1;

        if (nextIndex === historyIndex)
            return;
        historyIndex = nextIndex;

        let targetText = (historyIndex === -1) ? typingBackup : history[historyIndex];

        setSearchQuery(targetText);
        searchQueryRequested(targetText);
    }

    property string fileSearchType: "all"
    property string fileSearchExt: ""
    property string fileSearchFolder: ""
    property string fileSearchSort: "score"

    property string pluginFilter: ""
    property string activePluginName: ""
    property var activePluginCategories: []
    property string activePluginCategory: ""
    property string appCategory: ""
    property var appCategories: []

    function sectionViewPreference(sectionId) {
        switch (sectionId) {
        case "clipboard":
            return getPluginViewPref("dms_clipboard_search");
        case "settings":
            return getPluginViewPref("dms_settings_search");
        default:
            if (sectionId?.startsWith("plugin_"))
                return getPluginViewPref(sectionId.substring(7));
            return null;
        }
    }

    function _isDmenuSectionId(sectionId) {
        return sectionId === "dmenu" || (sectionId?.indexOf("dmenu:") === 0);
    }

    function getSectionViewMode(sectionId) {
        if (sectionId === "browse_plugins")
            return "list";
        if (dmenuView && _isDmenuSectionId(sectionId))
            return dmenuView;
        var sectionPref = sectionViewPreference(sectionId);
        if (sectionPref?.enforced)
            return sectionPref.mode;
        if (pluginViewPreferences[sectionId]?.enforced)
            return pluginViewPreferences[sectionId].mode;
        if (sectionViewModes[sectionId])
            return sectionViewModes[sectionId];

        var savedModes = viewModeContext === "appDrawer" ? (SettingsData.appDrawerSectionViewModes || {}) : (SettingsData.spotlightSectionViewModes || {});
        if (savedModes[sectionId])
            return savedModes[sectionId];

        for (var i = 0; i < sectionDefinitions.length; i++) {
            if (sectionDefinitions[i].id === sectionId)
                return sectionDefinitions[i].defaultViewMode || "list";
        }

        if (pluginViewPreferences[sectionId]?.mode)
            return pluginViewPreferences[sectionId].mode;

        return "list";
    }

    function setSectionViewMode(sectionId, mode) {
        if (sectionId === "browse_plugins")
            return;
        if (sectionViewPreference(sectionId)?.enforced)
            return;
        if (pluginViewPreferences[sectionId]?.enforced)
            return;
        sectionViewModes = Object.assign({}, sectionViewModes, {
            [sectionId]: mode
        });
        viewModeVersion++;
        if (viewModeContext === "appDrawer") {
            var savedModes = Object.assign({}, SettingsData.appDrawerSectionViewModes || {}, {
                [sectionId]: mode
            });
            SettingsData.appDrawerSectionViewModes = savedModes;
        } else {
            var savedModes = Object.assign({}, SettingsData.spotlightSectionViewModes || {}, {
                [sectionId]: mode
            });
            SettingsData.spotlightSectionViewModes = savedModes;
        }
        viewModeChanged(sectionId, mode);
    }

    function canChangeSectionViewMode(sectionId) {
        if (sectionId === "browse_plugins" || _isDmenuSectionId(sectionId))
            return false;
        if (sectionViewPreference(sectionId)?.enforced)
            return false;
        return !pluginViewPreferences[sectionId]?.enforced;
    }

    function canCollapseSection(sectionId) {
        return searchMode === "all" && (sections.length > 1 || collapsedSections[sectionId] === true);
    }

    function setPluginViewPreference(pluginId, mode, enforced) {
        var prefs = Object.assign({}, pluginViewPreferences);
        prefs[pluginId] = {
            mode: mode,
            enforced: enforced || false
        };
        pluginViewPreferences = prefs;
    }

    function applyActivePluginViewPreference(pluginId, isBuiltIn) {
        var sectionId = "plugin_" + pluginId;
        var pref = null;
        if (isBuiltIn) {
            var builtIn = AppSearchService.builtInPlugins[pluginId];
            if (builtIn && builtIn.viewMode) {
                pref = {
                    mode: builtIn.viewMode,
                    enforced: builtIn.viewModeEnforced === true
                };
            }
        } else {
            pref = PluginService.getPluginViewPreference(pluginId);
        }

        if (pref && pref.mode) {
            setPluginViewPreference(sectionId, pref.mode, pref.enforced);
        } else {
            var prefs = Object.assign({}, pluginViewPreferences);
            delete prefs[sectionId];
            pluginViewPreferences = prefs;
        }
    }

    function clearActivePluginViewPreference() {
        var prefs = {};
        for (var key in pluginViewPreferences) {
            if (!key.startsWith("plugin_")) {
                prefs[key] = pluginViewPreferences[key];
            }
        }
        pluginViewPreferences = prefs;
    }

    property int _searchVersion: 0
    property bool _pluginPhasePending: false
    property bool _pluginPhaseForceFirst: false
    property var _phase1Items: []
    property var _lastPhase1Items: []
    property var _lastAppItems: []
    property string _lastPhase1Query: ""
    property var _lastSettingsItems: []
    property var _lastClipboardItems: []
    property var _lastPluginItems: ({})
    property var _lastPluginOrder: []
    property string _lastPluginQuery: ""
    property string _lastPluginMode: ""

    property bool _searchPending: false

    function _cancelSearch() {
        _searchVersion++;
        searchDebounce.stop();
        pluginPhaseTimer.stop();
        fileSearchDebounce.stop();
        _searchPending = false;
        _pluginPhasePending = false;
        _pluginPhaseForceFirst = false;
        _phase1Items = [];
        isSearching = false;
        isFileSearching = false;
    }

    // Leading-edge debounce: search immediately when idle, coalesce bursts
    function requestSearch() {
        if (searchDebounce.running) {
            _searchPending = true;
            searchDebounce.restart();
            return;
        }
        _searchPending = false;
        performSearch();
        searchDebounce.restart();
    }

    Timer {
        id: searchDebounce
        interval: 60
        onTriggered: {
            if (!root._searchPending)
                return;
            root._searchPending = false;
            root.performSearch();
        }
    }

    Timer {
        id: pluginPhaseTimer
        interval: 16
        onTriggered: {
            if (!root._pluginPhasePending)
                return;
            root._performPluginPhase();
        }
    }

    function _schedulePluginPhase() {
        pluginPhaseTimer.restart();
    }

    Timer {
        id: fileSearchDebounce
        interval: 200
        onTriggered: root.performFileSearch()
    }

    function getOrTransformApp(app) {
        return AppSearchService.getOrTransformApp(app, transformApp);
    }

    function setSearchQuery(query) {
        _searchVersion++;
        _queryDrivenSearch = true;
        _pluginPhasePending = false;
        _phase1Items = [];
        searchQuery = query;
        requestSearch();

        if (autoSwitchedToFiles && !query.startsWith("/")) {
            restorePreviousMode();
            return;
        }

        if (query.startsWith("/")) {
            var prefix = Utils.parseFileSearchPrefix(query);
            var explicitType = prefix && prefix.type !== null ? prefix.type : null;
            var targetType = explicitType !== null ? explicitType : (SessionData.launcherLastFileSearchType || "all");
            if (searchMode !== "files") {
                setMode("files", true, targetType);
            } else if (fileSearchType !== targetType) {
                fileSearchType = targetType;
            }
            if (explicitType !== null && SessionData.launcherLastFileSearchType !== explicitType) {
                SessionData.setLauncherLastFileSearchType(explicitType);
            }
        }

        var filesInAll = searchMode === "all" && (SettingsData.dankLauncherV2IncludeFilesInAll || SettingsData.dankLauncherV2IncludeFoldersInAll);
        if (searchMode !== "plugins" && (searchMode === "files" || query.startsWith("/") || filesInAll) && query.length > 0) {
            fileSearchDebounce.restart();
        }
    }

    function setMode(mode, isAutoSwitch, fileTypeOverride, notPersist) {
        if (searchMode === "dmenu") {
            return;
        }
        if (searchMode === mode) {
            if (mode === "files" && fileTypeOverride !== undefined && fileSearchType !== fileTypeOverride) {
                fileSearchType = fileTypeOverride;
                performFileSearch();
            }
            return;
        }
        if (isAutoSwitch) {
            previousSearchMode = searchMode;
            autoSwitchedToFiles = true;
        } else {
            autoSwitchedToFiles = false;
        }
        searchMode = mode;
        if (mode === "files") {
            fileSearchType = fileTypeOverride !== undefined ? fileTypeOverride : (SessionData.launcherLastFileSearchType || "all");
        }
        modeChanged(mode, !isAutoSwitch && notPersist !== true);
        performSearch();
        var filesInAll = mode === "all" && (SettingsData.dankLauncherV2IncludeFilesInAll || SettingsData.dankLauncherV2IncludeFoldersInAll) && searchQuery.length > 0;
        if (mode === "files" || filesInAll) {
            fileSearchDebounce.restart();
        }
    }

    function restorePreviousMode() {
        if (!autoSwitchedToFiles)
            return;
        autoSwitchedToFiles = false;
        searchMode = previousSearchMode;
        modeChanged(previousSearchMode, false);
        performSearch();
    }

    function cycleMode(reverse = false) {
        if (searchMode === "dmenu")
            return;
        var modes = ["all", "apps", "files", "plugins"];
        var currentIndex = modes.indexOf(searchMode);
        if (!reverse)
            var nextIndex = (currentIndex + 1) % modes.length;
        else
            var nextIndex = (currentIndex - 1 + modes.length) % modes.length;
        setMode(modes[nextIndex]);
    }

    function reset() {
        _cancelSearch();
        searchQuery = "";
        searchMode = "all";
        previousSearchMode = "all";
        autoSwitchedToFiles = false;
        fileSearchType = "all";
        fileSearchExt = "";
        fileSearchFolder = "";
        fileSearchSort = "score";
        sections = [];
        flatModel = [];
        selectedFlatIndex = 0;
        selectedItem = null;
        activePluginId = "";
        activePluginName = "";
        activePluginCategories = [];
        activePluginCategory = "";
        appCategory = "";
        appCategories = [];
        pluginFilter = "";
        collapsedSections = {};
        _clearModeCache();
        _queryDrivenSearch = false;
    }

    function openSession(query, explicitQuery, mode, searchWhenEmpty) {
        _cancelSearch();
        if (mode && mode.indexOf("dmenu:") === 0) {
            _startDmenuSession(mode.slice("dmenu:".length));
            return;
        }
        DSearchService.ensureChecked();
        if (appCategory !== "" || Object.keys(collapsedSections).length > 0)
            _clearModeCache();
        appCategory = "";
        collapsedSections = {};
        explicitQuerySession = explicitQuery;
        historyIndex = -1;
        previousSearchMode = "all";
        autoSwitchedToFiles = false;
        fileSearchType = SessionData.launcherLastFileSearchType || "all";
        fileSearchExt = "";
        fileSearchFolder = "";
        fileSearchSort = "score";
        activePluginId = "";
        activePluginName = "";
        activePluginCategories = [];
        activePluginCategory = "";
        pluginFilter = "";
        selectedFlatIndex = 0;
        selectedItem = null;
        _queryDrivenSearch = false;
        searchMode = mode;
        if (query) {
            setSearchQuery(query);
            return;
        }
        searchQuery = "";
        if (searchWhenEmpty) {
            performSearch();
            return;
        }
        sections = [];
        flatModel = [];
    }

    function _startDmenuSession(socketPath) {
        _endDmenuSession();
        searchMode = "dmenu";
        searchQuery = "";
        explicitQuerySession = false;
        selectedFlatIndex = 0;
        selectedItem = null;
        dmenuItems = [];
        dmenuPrompt = "dmenu";
        dmenuPlaceholder = "";
        dmenuPromptOnly = false;
        dmenuLines = 0;
        dmenuSelect = "";
        dmenuMesg = "";
        dmenuPassword = false;
        dmenuMarkupRows = false;
        dmenuOnlyMatch = false;
        dmenuNoCustom = false;
        dmenuMultiSelect = false;
        dmenuActiveRanges = [];
        dmenuUrgentRanges = [];
        dmenuMultiSelected = [];
        dmenuKeybinds = [];
        dmenuView = "";
        dmenuSize = "";
        dmenuIcon = "";
        dmenuDisableHistory = false;
        _dmenuSelectApplied = false;
        sections = [];
        flatModel = [];
        dmenuSocketPath = socketPath;
        dmenuSocketLoader.active = true;
    }

    function _endDmenuSession() {
        dmenuSocketLoader.active = false;
        dmenuSocketPath = "";
    }

    function _onDmenuSocketLine(line) {
        if (!line)
            return;
        var msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        switch (msg.type) {
        case "header":
            dmenuPrompt = msg.prompt || "dmenu";
            dmenuPlaceholder = msg.placeholder || "";
            dmenuPromptOnly = !!msg.promptOnly;
            dmenuLines = msg.lines || 0;
            dmenuSelect = msg.select || "";
            dmenuMesg = msg.mesg || "";
            dmenuPassword = !!msg.password;
            dmenuMarkupRows = !!msg.markupRows;
            dmenuOnlyMatch = !!msg.onlyMatch;
            dmenuNoCustom = !!msg.noCustom;
            dmenuMultiSelect = !!msg.multiSelect;
            dmenuActiveRanges = msg.active || [];
            dmenuUrgentRanges = msg.urgent || [];
            dmenuKeybinds = (msg.keybinds || []).map(function (kb) {
                var parsed = root._parseDmenuKeySpec(kb.key);
                return parsed ? {
                    n: kb.n,
                    modifiers: parsed.modifiers,
                    key: parsed.key
                } : null;
            }).filter(function (kb) {
                return kb !== null;
            });
            dmenuSize = msg.size || "";
            dmenuIcon = msg.icon || "";
            dmenuDisableHistory = !!msg.disableHistory;
            dmenuView = msg.view || "";
            if (dmenuView)
                viewModeVersion++;
            break;
        case "item":
            dmenuItems.push(Transform.transformDmenuItem(msg.text, dmenuItems.length, {
                markup: dmenuMarkupRows,
                row: msg.row || null
            }));
            Qt.callLater(performSearch);
            break;
        case "end":
            performSearch();
            _applyDmenuSelect();
            break;
        }
    }

    function _applyDmenuSelect() {
        if (!dmenuSelect || _dmenuSelectApplied)
            return;
        _dmenuSelectApplied = true;
        var lower = dmenuSelect.toLowerCase();
        for (var i = 0; i < flatModel.length; i++) {
            var it = flatModel[i].item;
            if (it && !it.data.nonSelectable && (it.name || "").toLowerCase() === lower) {
                selectedFlatIndex = i;
                updateSelectedItem();
                return;
            }
        }
        for (var i = 0; i < flatModel.length; i++) {
            var it = flatModel[i].item;
            if (it && !it.data.nonSelectable && (it.name || "").toLowerCase().indexOf(lower) !== -1) {
                selectedFlatIndex = i;
                updateSelectedItem();
                return;
            }
        }
    }

    function _resolveDmenuRanges(ranges, length) {
        var set = ({});
        if (!ranges)
            return set;
        for (var i = 0; i < ranges.length; i++) {
            var r = ranges[i];
            var start = r.start;
            var end = r.end;
            if (start < 0)
                start = Math.max(0, length + start);
            if (end === -1)
                end = length;
            else if (end < 0)
                end = Math.max(0, length + end);
            start = Math.max(0, start);
            end = Math.min(length, end);
            for (var j = start; j < end; j++)
                set[j] = true;
        }
        return set;
    }

    function _writeDmenuSelection(payload) {
        var socket = dmenuSocketLoader.item;
        if (socket && socket.connected) {
            socket.write(JSON.stringify(Object.assign({
                type: "select",
                filterText: searchQuery
            }, payload)) + "\n");
            socket.flush();
        }
        _endDmenuSession();
    }

    function _sendDmenuRowSelection(item, keybindN) {
        _writeDmenuSelection({
            kind: "row",
            index: item.data.index,
            text: item.data.text,
            info: item.data.info || "",
            keybindN: keybindN || 0
        });
    }

    function _sendDmenuFreeText(text, keybindN) {
        _writeDmenuSelection({
            kind: "freetext",
            text: text,
            keybindN: keybindN || 0
        });
    }

    function _sendDmenuMultiSelection(items) {
        _writeDmenuSelection({
            kind: "multi",
            items: items
        });
    }

    function _toggleDmenuMultiSelect(item) {
        if (!item || item.type !== "dmenu")
            return;
        var idx = item.data.index;
        var pos = dmenuMultiSelected.indexOf(idx);
        var newSel = dmenuMultiSelected.slice();
        if (pos === -1)
            newSel.push(idx);
        else
            newSel.splice(pos, 1);
        dmenuMultiSelected = newSel;
        performSearch();  // re-render to update the checkbox
    }

    function toggleDmenuMultiSelectHighlighted() {
        if (selectedItem && selectedItem.type === "dmenu" && !selectedItem.data.nonSelectable)
            _toggleDmenuMultiSelect(selectedItem);
    }

    function confirmDmenuMultiSelection() {
        var chosen = dmenuMultiSelected.slice();
        if (chosen.length > 0) {
            chosen.sort(function (a, b) {
                return a - b;
            });
            var byIndex = ({});
            for (var i = 0; i < dmenuItems.length; i++)
                byIndex[dmenuItems[i].data.index] = dmenuItems[i];
            var items = [];
            for (var i = 0; i < chosen.length; i++) {
                var it = byIndex[chosen[i]];
                if (it)
                    items.push({
                        index: it.data.index,
                        text: it.data.text,
                        info: it.data.info || ""
                    });
            }
            if (items.length > 0) {
                _sendDmenuMultiSelection(items);
                itemExecuted();
                return;
            }
        }
        // Nothing checked: fall back to the normal single-accept path.
        if (selectedItem && selectedItem.type === "dmenu" && !selectedItem.data.nonSelectable) {
            _sendDmenuRowSelection(selectedItem);
            itemExecuted();
            return;
        }
        if (searchQuery && !dmenuOnlyMatch && !dmenuNoCustom) {
            _sendDmenuFreeText(searchQuery);
            itemExecuted();
        }
    }

    function acceptDmenuViaKeybind(n) {
        if (searchMode !== "dmenu")
            return;
        if (selectedItem && selectedItem.type === "dmenu" && !selectedItem.data.nonSelectable) {
            _sendDmenuRowSelection(selectedItem, n);
            itemExecuted();
            return;
        }
        if (searchQuery && !dmenuOnlyMatch && !dmenuNoCustom) {
            _sendDmenuFreeText(searchQuery, n);
            itemExecuted();
        }
    }

    function loadPluginCategories(pluginId) {
        if (!pluginId) {
            if (activePluginCategories.length > 0) {
                activePluginCategories = [];
                activePluginCategory = "";
            }
            return;
        }

        const categories = AppSearchService.getPluginLauncherCategories(pluginId);
        if (categories.length === activePluginCategories.length) {
            let same = true;
            for (let i = 0; i < categories.length; i++) {
                if (categories[i].id !== activePluginCategories[i]?.id) {
                    same = false;
                    break;
                }
            }
            if (same)
                return;
        }
        activePluginCategories = categories;
        activePluginCategory = "";
        AppSearchService.setPluginLauncherCategory(pluginId, "");
    }

    function setActivePluginCategory(categoryId) {
        if (activePluginCategory === categoryId)
            return;
        activePluginCategory = categoryId;
        AppSearchService.setPluginLauncherCategory(activePluginId, categoryId);
        performSearch();
    }

    function setAppCategory(category) {
        if (appCategory === category)
            return;
        appCategory = category;
        _queryDrivenSearch = true;
        _clearModeCache();
        performSearch();
    }

    function _loadAppCategories() {
        appCategories = AppSearchService.getAllCategories();
    }

    function setFileSearchType(type) {
        if (fileSearchType === type)
            return;
        fileSearchType = type;
        SessionData.setLauncherLastFileSearchType(type);
        performFileSearch();
    }

    function setFileSearchExt(ext) {
        if (fileSearchExt === ext)
            return;
        fileSearchExt = ext;
        performFileSearch();
    }

    function setFileSearchFolder(folder) {
        if (fileSearchFolder === folder)
            return;
        fileSearchFolder = folder;
        performFileSearch();
    }

    function setFileSearchSort(sort) {
        if (fileSearchSort === sort)
            return;
        fileSearchSort = sort;
        performFileSearch();
    }

    function clearPluginFilter() {
        if (pluginFilter) {
            pluginFilter = "";
            performSearch();
            return true;
        }
        return false;
    }

    function preserveSelectionAfterUpdate(forceFirst) {
        if (forceFirst)
            return function () {
                return getFirstItemIndex();
            };
        var previousSelectedId = selectedItem?.id || "";
        return function (newFlatModel) {
            if (!previousSelectedId)
                return getFirstItemIndex();
            for (var i = 0; i < newFlatModel.length; i++) {
                if (!newFlatModel[i].isHeader && newFlatModel[i].item?.id === previousSelectedId)
                    return i;
            }
            return getFirstItemIndex();
        };
    }

    function performSearch() {
        queryChanged(searchQuery);

        var currentVersion = _searchVersion;
        isSearching = true;
        var shouldResetSelection = _queryDrivenSearch;
        _queryDrivenSearch = false;
        var restoreSelection = preserveSelectionAfterUpdate(shouldResetSelection);

        var cachedSections = AppSearchService.getCachedDefaultSections();
        if (!cachedSections && !_diskCacheConsumed && !searchQuery && searchMode === "all" && !pluginFilter) {
            _diskCacheConsumed = true;
            var diskSections = _loadDiskCache();
            if (diskSections) {
                activePluginId = "";
                activePluginName = "";
                activePluginCategories = [];
                activePluginCategory = "";
                clearActivePluginViewPreference();
                for (var i = 0; i < diskSections.length; i++) {
                    if (collapsedSections[diskSections[i].id] !== undefined)
                        diskSections[i].collapsed = collapsedSections[diskSections[i].id];
                }
                _applyHighlights(diskSections, "");
                flatModel = Scorer.flattenSections(diskSections);
                sections = diskSections;
                selectedFlatIndex = restoreSelection(flatModel);
                updateSelectedItem();
                isSearching = false;
                searchCompleted();
                return;
            }
        }

        if (cachedSections && !searchQuery && searchMode === "all" && !pluginFilter) {
            activePluginId = "";
            activePluginName = "";
            activePluginCategories = [];
            activePluginCategory = "";
            clearActivePluginViewPreference();
            var modeCache = _getCachedModeData("all");
            if (modeCache) {
                _applyHighlights(modeCache.sections, "");
                sections = modeCache.sections;
                flatModel = modeCache.flatModel;
            } else {
                var newSections = cachedSections.map(function (s) {
                    var copy = Object.assign({}, s, {
                        items: s.items ? s.items.slice() : []
                    });
                    if (collapsedSections[s.id] !== undefined)
                        copy.collapsed = collapsedSections[s.id];
                    return copy;
                });
                _applyHighlights(newSections, "");
                flatModel = Scorer.flattenSections(newSections);
                sections = newSections;
                _setCachedModeData("all", sections, flatModel);
            }
            selectedFlatIndex = restoreSelection(flatModel);
            updateSelectedItem();
            isSearching = false;
            searchCompleted();
            return;
        }

        var allItems = [];

        var triggerMatch = (searchMode === "files" || searchMode === "dmenu") ? {
            pluginId: null
        } : detectTrigger(searchQuery);
        if (triggerMatch.pluginId) {
            var pluginChanged = activePluginId !== triggerMatch.pluginId;
            activePluginId = triggerMatch.pluginId;
            activePluginName = getPluginName(triggerMatch.pluginId, triggerMatch.isBuiltIn);
            applyActivePluginViewPreference(triggerMatch.pluginId, triggerMatch.isBuiltIn);

            if (pluginChanged && !triggerMatch.isBuiltIn)
                loadPluginCategories(triggerMatch.pluginId);

            var pluginItems = getPluginItems(triggerMatch.pluginId, triggerMatch.query);
            for (var k = 0; k < pluginItems.length; k++)
                allItems.push(pluginItems[k]);

            if (triggerMatch.isBuiltIn) {
                var builtInItems = AppSearchService.getBuiltInLauncherItems(triggerMatch.pluginId, triggerMatch.query);
                for (var j = 0; j < builtInItems.length; j++) {
                    builtInItems[j]._preScored = 1000 - j;
                    allItems.push(transformBuiltInSearchItem(builtInItems[j], triggerMatch.pluginId));
                }
            }

            var dynamicDefs = buildDynamicSectionDefs(allItems);
            var scoredItems = Scorer.scoreItems(allItems, triggerMatch.query, getFrecencyForItem);
            var sortAlpha = !triggerMatch.query && SettingsData.sortAppsAlphabetically;
            var newSections = Scorer.groupBySection(scoredItems, dynamicDefs, sortAlpha, 500);

            for (var sid in collapsedSections) {
                for (var i = 0; i < newSections.length; i++) {
                    if (newSections[i].id === sid) {
                        newSections[i].collapsed = collapsedSections[sid];
                    }
                }
            }

            _applyHighlights(newSections, triggerMatch.query);
            flatModel = Scorer.flattenSections(newSections);
            sections = newSections;
            selectedFlatIndex = restoreSelection(flatModel);
            updateSelectedItem();

            isSearching = false;
            searchCompleted();
            return;
        }

        activePluginId = "";
        activePluginName = "";
        activePluginCategories = [];
        activePluginCategory = "";
        clearActivePluginViewPreference();

        if (searchMode === "dmenu") {
            var dmenuGroups = [
                {
                    title: "",
                    icon: "",
                    items: []
                }
            ];
            for (var gi = 0; gi < dmenuItems.length; gi++) {
                var gitem = dmenuItems[gi];
                if (gitem.data.header) {
                    var headerIcon = gitem.icon || "";
                    dmenuGroups.push({
                        title: gitem.name || "",
                        icon: headerIcon,
                        iconType: "image",
                        iconVisible: headerIcon !== "",
                        items: []
                    });
                    continue;
                }
                dmenuGroups[dmenuGroups.length - 1].items.push(gitem);
            }

            var activeSet = _resolveDmenuRanges(dmenuActiveRanges, dmenuItems.length);
            var urgentSet = _resolveDmenuRanges(dmenuUrgentRanges, dmenuItems.length);
            var checkedSet = ({});
            for (var ci = 0; ci < dmenuMultiSelected.length; ci++)
                checkedSet[dmenuMultiSelected[ci]] = true;

            var newDmenuSections = [];
            var flat = [];
            var sectionBoundsMap = ({});
            for (var grpIdx = 0; grpIdx < dmenuGroups.length; grpIdx++) {
                var grp = dmenuGroups[grpIdx];
                if (grp.items.length === 0)
                    continue;

                var scoredItems = Scorer.scoreItems(grp.items, searchQuery, null);
                if (searchQuery) {
                    var scoredIdx = ({});
                    for (var si = 0; si < scoredItems.length; si++)
                        scoredIdx[scoredItems[si].item.data.index] = true;
                    for (var pi = 0; pi < grp.items.length; pi++) {
                        var pitem = grp.items[pi];
                        if (pitem.data.permanent && !scoredIdx[pitem.data.index])
                            scoredItems.push({
                                item: pitem,
                                score: 0,
                                order: scoredItems.length
                            });
                    }
                }
                if (scoredItems.length === 0)
                    continue;

                var sectionId = grpIdx === 0 ? "dmenu" : "dmenu:" + grpIdx;
                var dmenuSection = {
                    id: sectionId,
                    title: grp.title,
                    icon: grp.icon,
                    iconType: grp.iconType,
                    iconVisible: grp.iconVisible,
                    priority: 1,
                    items: scoredItems.map(function (s) {
                        s.item.data.active = !!activeSet[s.item.data.index] || s.item.data.rowActive;
                        s.item.data.urgent = !!urgentSet[s.item.data.index] || s.item.data.rowUrgent;
                        s.item.data.checked = !!checkedSet[s.item.data.index];
                        return s.item;
                    }),
                    collapsed: false,
                    flatStartIndex: flat.length
                };
                if (!dmenuMarkupRows)
                    _applyHighlights([dmenuSection], searchQuery);

                var sectionStart = flat.length;
                for (var ii = 0; ii < dmenuSection.items.length; ii++) {
                    flat.push({
                        isHeader: false,
                        item: dmenuSection.items[ii],
                        sectionId: sectionId,
                        sectionIndex: newDmenuSections.length,
                        indexInSection: ii
                    });
                }
                sectionBoundsMap[sectionId] = {
                    start: sectionStart,
                    end: flat.length - 1,
                    count: dmenuSection.items.length
                };
                newDmenuSections.push(dmenuSection);
            }

            flat._sectionBounds = sectionBoundsMap;
            flatModel = flat;
            sections = newDmenuSections;
            selectedFlatIndex = restoreSelection(flatModel);
            updateSelectedItem();
            isSearching = false;
            searchCompleted();
            return;
        }

        if (searchMode === "files") {
            var prefixInfo = Utils.parseFileSearchPrefix(searchQuery);
            var fileQuery = prefixInfo ? prefixInfo.query : searchQuery.trim();
            isFileSearching = fileQuery.length >= 2 && DSearchService.dsearchAvailable;
            sections = [];
            flatModel = [];
            selectedFlatIndex = 0;
            selectedItem = null;
            isSearching = false;
            searchCompleted();
            return;
        }

        if (searchMode === "apps") {
            var isCategoryFiltered = appCategory && appCategory !== I18n.tr("All");
            var cachedSections = AppSearchService.getCachedDefaultSections();
            if (cachedSections && !searchQuery && !isCategoryFiltered) {
                var modeCache = _getCachedModeData("apps");
                if (modeCache) {
                    _applyHighlights(modeCache.sections, "");
                    sections = modeCache.sections;
                    flatModel = modeCache.flatModel;
                } else {
                    var appSectionIds = ["favorites", "apps"];
                    var newSections = cachedSections.filter(function (s) {
                        return appSectionIds.indexOf(s.id) !== -1;
                    }).map(function (s) {
                        var copy = Object.assign({}, s, {
                            items: s.items ? s.items.slice() : []
                        });
                        if (collapsedSections[s.id] !== undefined)
                            copy.collapsed = collapsedSections[s.id];
                        return copy;
                    });
                    _applyHighlights(newSections, "");
                    flatModel = Scorer.flattenSections(newSections);
                    sections = newSections;
                    _setCachedModeData("apps", sections, flatModel);
                }
                selectedFlatIndex = restoreSelection(flatModel);
                updateSelectedItem();
                isSearching = false;
                searchCompleted();
                return;
            }

            if (isCategoryFiltered) {
                var rawApps = AppSearchService.getAppsInCategory(appCategory);
                for (var i = 0; i < rawApps.length; i++) {
                    allItems.push(getOrTransformApp(rawApps[i]));
                }
                var allCoreApps = AppSearchService.getCoreApps("");
                for (var i = 0; i < allCoreApps.length; i++) {
                    var coreAppCats = AppSearchService.getCategoriesForApp(allCoreApps[i]);
                    if (coreAppCats.indexOf(appCategory) !== -1)
                        allItems.push(transformCoreApp(allCoreApps[i]));
                }
            } else {
                var apps = searchApps(searchQuery);
                for (var i = 0; i < apps.length; i++) {
                    allItems.push(apps[i]);
                }
            }

            var scoredItems = Scorer.scoreItems(allItems, searchQuery, getFrecencyForItem);
            var sortAlpha = !searchQuery && SettingsData.sortAppsAlphabetically;
            var newSections = Scorer.groupBySection(scoredItems, buildDynamicSectionDefs(allItems), sortAlpha, searchQuery ? 50 : 500);

            for (var sid in collapsedSections) {
                for (var i = 0; i < newSections.length; i++) {
                    if (newSections[i].id === sid) {
                        newSections[i].collapsed = collapsedSections[sid];
                    }
                }
            }

            _applyHighlights(newSections, searchQuery);
            flatModel = Scorer.flattenSections(newSections);
            sections = newSections;
            selectedFlatIndex = restoreSelection(flatModel);
            updateSelectedItem();

            isSearching = false;
            searchCompleted();
            return;
        }

        if (searchMode === "plugins") {
            if (!searchQuery && !pluginFilter) {
                var browseItems = getPluginBrowseItems();
                for (var k = 0; k < browseItems.length; k++)
                    allItems.push(browseItems[k]);
            } else if (pluginFilter) {
                var isBuiltInFilter = !!AppSearchService.builtInPlugins[pluginFilter];
                applyActivePluginViewPreference(pluginFilter, isBuiltInFilter);

                var filterItems = getPluginItems(pluginFilter, searchQuery);
                for (var k = 0; k < filterItems.length; k++)
                    allItems.push(filterItems[k]);

                var builtInItems = AppSearchService.getBuiltInLauncherItems(pluginFilter, searchQuery, true);
                for (var j = 0; j < builtInItems.length; j++) {
                    allItems.push(transformBuiltInSearchItem(builtInItems[j], pluginFilter));
                }
            } else {
                var emptyTriggerPlugins = getEmptyTriggerPlugins();
                for (var i = 0; i < emptyTriggerPlugins.length; i++) {
                    var pluginId = emptyTriggerPlugins[i];
                    var pItems = getPluginItems(pluginId, searchQuery);
                    for (var k = 0; k < pItems.length; k++)
                        allItems.push(pItems[k]);
                }

                var builtInLauncherPlugins = getBuiltInEmptyTriggerLaunchers();
                for (var i = 0; i < builtInLauncherPlugins.length; i++) {
                    var pluginId = builtInLauncherPlugins[i];
                    var blItems = AppSearchService.getBuiltInLauncherItems(pluginId, searchQuery);
                    for (var j = 0; j < blItems.length; j++) {
                        allItems.push(transformBuiltInSearchItem(blItems[j], pluginId));
                    }
                }
            }

            var dynamicDefs = buildDynamicSectionDefs(allItems);
            var scoredItems = Scorer.scoreItems(allItems, searchQuery, getFrecencyForItem);
            var sortAlpha = !searchQuery && SettingsData.sortAppsAlphabetically;
            var newSections = Scorer.groupBySection(scoredItems, dynamicDefs, sortAlpha, 500);

            for (var sid in collapsedSections) {
                for (var i = 0; i < newSections.length; i++) {
                    if (newSections[i].id === sid) {
                        newSections[i].collapsed = collapsedSections[sid];
                    }
                }
            }

            _applyHighlights(newSections, searchQuery);
            flatModel = Scorer.flattenSections(newSections);
            sections = newSections;
            selectedFlatIndex = restoreSelection(flatModel);
            updateSelectedItem();

            isSearching = false;
            searchCompleted();
            return;
        }

        var apps = searchApps(searchQuery);
        for (var i = 0; i < apps.length; i++) {
            allItems.push(apps[i]);
        }
        _lastAppItems = apps;
        _lastPhase1Query = searchQuery;

        if (searchMode === "all") {
            appendSharedAllResults(allItems, searchQuery);
            if (searchQuery && searchQuery.length >= 2) {
                _pluginPhasePending = true;
                _phase1Items = allItems.slice();
                _pluginPhaseForceFirst = shouldResetSelection;
                _schedulePluginPhase();
                isSearching = true;
                searchCompleted();
                return;
            } else if (!searchQuery) {
                _pluginPhasePending = true;
                _phase1Items = allItems.slice();
                _pluginPhaseForceFirst = shouldResetSelection;
                _schedulePluginPhase();
            }
        }

        var dynamicDefs = buildDynamicSectionDefs(allItems);

        if (currentVersion !== _searchVersion) {
            isSearching = false;
            return;
        }

        var scoredItems = Scorer.scoreItems(allItems, searchQuery, getFrecencyForItem);
        var sortAlpha = !searchQuery && SettingsData.sortAppsAlphabetically;
        var newSections = Scorer.groupBySection(scoredItems, dynamicDefs, sortAlpha, searchQuery ? 50 : 500);

        if (currentVersion !== _searchVersion) {
            isSearching = false;
            return;
        }

        for (var i = 0; i < newSections.length; i++) {
            var sid = newSections[i].id;
            if (collapsedSections[sid] !== undefined) {
                newSections[i].collapsed = collapsedSections[sid];
            }
        }

        _applyHighlights(newSections, searchQuery);
        flatModel = Scorer.flattenSections(newSections);
        sections = newSections;

        selectedFlatIndex = restoreSelection(flatModel);
        updateSelectedItem();

        isSearching = _pluginPhasePending;
        searchCompleted();
    }

    function _performPluginPhase() {
        _pluginPhasePending = false;
        if (!active || searchMode !== "all")
            return;
        if (searchQuery && searchQuery.length < 2)
            return;

        var currentVersion = _searchVersion;
        var restoreSelection = preserveSelectionAfterUpdate(_pluginPhaseForceFirst);
        var allItems = _phase1Items;
        _phase1Items = [];

        if (!searchQuery) {
            var emptyTriggerOrdered = getEmptyTriggerPluginsOrdered();
            for (var i = 0; i < emptyTriggerOrdered.length; i++) {
                if (currentVersion !== _searchVersion)
                    return;
                var plugin = emptyTriggerOrdered[i];
                if (plugin.isBuiltIn) {
                    var blItems = AppSearchService.getBuiltInLauncherItems(plugin.id, searchQuery);
                    for (var j = 0; j < blItems.length; j++)
                        allItems.push(transformBuiltInSearchItem(blItems[j], plugin.id));
                } else {
                    var pItems = getPluginItems(plugin.id, searchQuery);
                    for (var j = 0; j < pItems.length; j++)
                        allItems.push(pItems[j]);
                }
            }

            var browseItems = getPluginBrowseItems();
            for (var i = 0; i < browseItems.length; i++)
                allItems.push(browseItems[i]);
        } else {
            var phase1Items = allItems.slice();
            var pluginItems = {};
            var pluginOrder = [];
            var allPluginsOrdered = getAllVisiblePluginsOrdered();
            for (var i = 0; i < allPluginsOrdered.length; i++) {
                if (currentVersion !== _searchVersion)
                    return;
                var plugin = allPluginsOrdered[i];
                if (plugin.isBuiltIn && (plugin.id === "dms_settings_search" || plugin.id === "dms_clipboard_search"))
                    continue;
                var items = _pluginQueryItems(plugin);
                pluginItems[plugin.id] = items;
                pluginOrder.push(plugin.id);
                for (var j = 0; j < items.length; j++)
                    allItems.push(items[j]);
            }
            _lastPhase1Items = phase1Items;
            _lastPluginItems = pluginItems;
            _lastPluginOrder = pluginOrder;
            _lastPluginQuery = searchQuery;
            _lastPluginMode = searchMode;
        }

        if (currentVersion !== _searchVersion)
            return;

        _publishPluginResults(allItems, restoreSelection);
    }

    function _pluginQueryItems(plugin) {
        var maxPerPlugin = 10;
        var items = [];
        if (plugin.isBuiltIn) {
            var blItems = AppSearchService.getBuiltInLauncherItems(plugin.id, searchQuery);
            var blLimit = Math.min(blItems.length, maxPerPlugin);
            for (var j = 0; j < blLimit; j++) {
                var item = transformBuiltInSearchItem(blItems[j], plugin.id);
                item._preScored = 900 - j;
                items.push(item);
            }
            return items;
        }
        var pItems = getPluginItems(plugin.id, searchQuery, maxPerPlugin);
        for (var k = 0; k < pItems.length; k++) {
            pItems[k]._preScored = 900 - k;
            items.push(pItems[k]);
        }
        return items;
    }

    function _refreshPluginResults(pluginId) {
        if (_pluginPhasePending || _lastPluginQuery !== searchQuery || _lastPluginMode !== searchMode)
            return false;
        if (_lastPluginItems[pluginId] === undefined)
            return false;
        var plugin = getAllVisiblePluginsOrdered().find(entry => entry.id === pluginId);
        if (!plugin)
            return false;
        var fresh = _pluginQueryItems(plugin);
        if (_samePluginItems(_lastPluginItems[pluginId], fresh))
            return true;
        var updated = Object.assign({}, _lastPluginItems);
        updated[pluginId] = fresh;
        _lastPluginItems = updated;
        var allItems = _lastPhase1Items.slice();
        for (var i = 0; i < _lastPluginOrder.length; i++) {
            var items = updated[_lastPluginOrder[i]] || [];
            for (var j = 0; j < items.length; j++)
                allItems.push(items[j]);
        }
        _publishPluginResults(allItems, preserveSelectionAfterUpdate(false));
        return true;
    }

    function _samePluginItems(previous, next) {
        if (!previous || previous.length !== next.length)
            return false;
        for (var i = 0; i < next.length; i++) {
            if (previous[i].id !== next[i].id || previous[i].name !== next[i].name || previous[i].subtitle !== next[i].subtitle)
                return false;
        }
        return true;
    }

    function _publishPluginResults(allItems, restoreSelection) {
        var dynamicDefs = buildDynamicSectionDefs(allItems);
        var scoredItems = Scorer.scoreItems(allItems, searchQuery, getFrecencyForItem);
        var sortAlpha = !searchQuery && SettingsData.sortAppsAlphabetically;
        var newSections = Scorer.groupBySection(scoredItems, dynamicDefs, sortAlpha, searchQuery ? 50 : 500);

        for (var i = 0; i < newSections.length; i++) {
            var sid = newSections[i].id;
            if (collapsedSections[sid] !== undefined)
                newSections[i].collapsed = collapsedSections[sid];
        }

        _applyHighlights(newSections, searchQuery);
        flatModel = Scorer.flattenSections(newSections);
        sections = newSections;

        if (!AppSearchService.isCacheValid() && !searchQuery && !pluginFilter) {
            AppSearchService.setCachedDefaultSections(sections, flatModel);
            _saveDiskCache(sections);
        }

        selectedFlatIndex = restoreSelection(flatModel);
        updateSelectedItem();
        isSearching = false;
        searchCompleted();
    }

    function performFileSearch() {
        if (!active || !DSearchService.dsearchAvailable)
            return;
        var fileQuery = "";
        var effectiveType = fileSearchType || "all";
        var includeFiles = SettingsData.dankLauncherV2IncludeFilesInAll;
        var includeFolders = SettingsData.dankLauncherV2IncludeFoldersInAll;

        if (searchQuery.startsWith("/")) {
            var prefixInfo = Utils.parseFileSearchPrefix(searchQuery);
            fileQuery = prefixInfo ? prefixInfo.query : searchQuery.substring(1).trim();
        } else if (searchMode === "files") {
            fileQuery = searchQuery.trim();
        } else if (searchMode === "all" && (includeFiles || includeFolders)) {
            fileQuery = searchQuery.trim();
            if (includeFiles && !includeFolders)
                effectiveType = "file";
            else if (!includeFiles && includeFolders)
                effectiveType = "dir";
            else
                effectiveType = "all";
        } else {
            return;
        }

        if (fileQuery.length < 2) {
            isFileSearching = false;
            return;
        }

        isFileSearching = true;

        var splitBothTypes = searchMode === "all" && includeFiles && includeFolders && DSearchService.supportsTypeFilter;
        var queryTypes = splitBothTypes ? ["file", "dir"] : [effectiveType];
        var pending = queryTypes.length;
        var aggregatedItems = [];
        const currentVersion = _searchVersion;
        const currentMode = searchMode;

        for (var t = 0; t < queryTypes.length; t++) {
            var queryType = queryTypes[t];
            var params = {
                limit: 20,
                fuzzy: true,
                sort: fileSearchSort || "score",
                desc: true
            };

            if (DSearchService.supportsTypeFilter) {
                params.type = (queryType && queryType !== "all") ? queryType : "all";
            }
            if (fileSearchExt) {
                params.ext = fileSearchExt;
            }
            if (fileSearchFolder) {
                params.folder = fileSearchFolder;
            }

            DSearchService.search(fileQuery, params, function (response) {
                if (!root.active || currentVersion !== root._searchVersion || currentMode !== root.searchMode)
                    return;
                pending--;
                if (!response.error) {
                    var hits = response.result?.hits || [];
                    for (var i = 0; i < hits.length; i++) {
                        var hit = hits[i];
                        var docTypes = hit.locations?.doc_type;
                        var isDir = docTypes ? !!docTypes["dir"] : false;
                        aggregatedItems.push(transformFileResult({
                            path: hit.id || "",
                            score: hit.score || 0,
                            is_dir: isDir
                        }));
                    }
                }
                if (pending > 0)
                    return;

                isFileSearching = false;
                _applyFileSearchResults(aggregatedItems, effectiveType);
            });
        }
    }

    function _applyFileSearchResults(fileItems, effectiveType) {
        var fileSections = [];
        var showType = effectiveType;
        var order = SettingsData.launcherPluginOrder || [];
        var filesOrderIdx = order.indexOf("__files");
        var foldersOrderIdx = order.indexOf("__folders");
        var filesPriority = filesOrderIdx !== -1 ? 2.6 + filesOrderIdx * 0.01 : 4;
        var foldersPriority = foldersOrderIdx !== -1 ? 2.6 + foldersOrderIdx * 0.01 : 4.1;

        if (showType === "all" && DSearchService.supportsTypeFilter) {
            var onlyFiles = [];
            var onlyDirs = [];
            for (var j = 0; j < fileItems.length; j++) {
                if (fileItems[j].data?.is_dir)
                    onlyDirs.push(fileItems[j]);
                else
                    onlyFiles.push(fileItems[j]);
            }
            if (onlyFiles.length > 0) {
                fileSections.push({
                    id: "files",
                    title: I18n.tr("Files"),
                    icon: "insert_drive_file",
                    priority: filesPriority,
                    items: onlyFiles,
                    collapsed: collapsedSections["files"] || false,
                    flatStartIndex: 0
                });
            }
            if (onlyDirs.length > 0) {
                fileSections.push({
                    id: "folders",
                    title: I18n.tr("Folders", "launcher file search section title and filter option"),
                    icon: "folder",
                    priority: foldersPriority,
                    items: onlyDirs,
                    collapsed: collapsedSections["folders"] || false,
                    flatStartIndex: 0
                });
            }
        } else {
            var filesIcon = showType === "dir" ? "folder" : showType === "file" ? "insert_drive_file" : "folder";
            var filesTitle = showType === "dir" ? I18n.tr("Folders") : I18n.tr("Files");
            var singlePriority = showType === "dir" ? foldersPriority : filesPriority;
            if (fileItems.length > 0) {
                fileSections.push({
                    id: "files",
                    title: filesTitle,
                    icon: filesIcon,
                    priority: singlePriority,
                    items: fileItems,
                    collapsed: collapsedSections["files"] || false,
                    flatStartIndex: 0
                });
            }
        }

        var newSections;
        if (searchMode === "files") {
            newSections = fileSections;
        } else {
            var existingNonFile = sections.filter(function (s) {
                return s.id !== "files" && s.id !== "folders";
            });
            newSections = existingNonFile.concat(fileSections);
        }
        newSections.sort(function (a, b) {
            if (a.priority !== b.priority)
                return a.priority - b.priority;
            return a.id.localeCompare(b.id);
        });
        _applyHighlights(newSections, searchQuery);
        flatModel = Scorer.flattenSections(newSections);
        sections = newSections;
        selectedFlatIndex = getFirstItemIndex();
        updateSelectedItem();
    }

    function searchApps(query) {
        var apps = AppSearchService.searchApplications(query);
        var items = [];

        for (var i = 0; i < apps.length; i++) {
            items.push(getOrTransformApp(apps[i]));
        }

        var coreApps = AppSearchService.getCoreApps(query);
        for (var i = 0; i < coreApps.length; i++) {
            items.push(transformCoreApp(coreApps[i]));
        }

        return items;
    }

    function transformApp(app) {
        var appId = app.id || app.execString || app.exec || "";
        var override = SessionData.getAppOverride(appId);
        return Transform.transformApp(app, override, [], I18n.tr("Launch"));
    }

    function transformCoreApp(app) {
        return Transform.transformCoreApp(app, I18n.tr("Open"));
    }

    function transformBuiltInLauncherItem(item, pluginId) {
        return Transform.transformBuiltInLauncherItem(item, pluginId, I18n.tr("Open"));
    }

    function transformBuiltInSearchItem(item, pluginId) {
        if (pluginId === "dms_clipboard_search" || item.type === "clipboard") {
            var transformed = transformClipboardEntry(item.data || item);
            if (item._preScored !== undefined)
                transformed._preScored = item._preScored;
            return transformed;
        }
        return transformBuiltInLauncherItem(item, pluginId);
    }

    function transformFileResult(file) {
        return Transform.transformFileResult(file, I18n.tr("Open"), I18n.tr("Open folder"), I18n.tr("Copy path"), I18n.tr("Open in terminal"), I18n.tr("Open with") + "…");
    }

    function transformClipboardEntry(entry) {
        var copyLabel = I18n.tr("Copy");
        var pasteLabel = I18n.tr("Paste");
        var primaryLabel = SettingsData.clipboardEnterToPaste ? pasteLabel : copyLabel;
        var pasteHintLabel = SettingsData.clipboardEnterToPaste ? I18n.tr("Shift+Enter to copy") : I18n.tr("Shift+Enter to paste");
        return Transform.transformClipboardItem(entry, copyLabel, pasteLabel, primaryLabel, I18n.tr("Image"), I18n.tr("Text"), I18n.tr("Pinned"), pasteHintLabel, "", I18n.tr("Clipboard"));
    }

    function builtInLauncherVisibleInAll(pluginId) {
        return SettingsData.getBuiltInPluginSetting(pluginId, "enabled", true) && SettingsData.getPluginAllowWithoutTrigger(pluginId);
    }

    function clipboardSearchEnabledInAll() {
        return builtInLauncherVisibleInAll("dms_clipboard_search") && ClipboardService.clipboardAvailable;
    }

    function appendSharedAllResults(allItems, query) {
        if (!query || query.length < 2)
            return;
        var settingsItems = _settingsSharedItems(query);
        var clipboardItems = _clipboardSharedItems(query);
        for (var i = 0; i < settingsItems.length; i++)
            allItems.push(settingsItems[i]);
        for (var j = 0; j < clipboardItems.length; j++)
            allItems.push(clipboardItems[j]);
        _lastSettingsItems = settingsItems;
        _lastClipboardItems = clipboardItems;
    }

    function _settingsSharedItems(query) {
        var items = [];
        if (!builtInLauncherVisibleInAll("dms_settings_search"))
            return items;
        var settingsItems = AppSearchService.getBuiltInLauncherItems("dms_settings_search", query);
        var settingsLimit = Math.min(settingsItems.length, 8);
        for (var i = 0; i < settingsLimit; i++) {
            settingsItems[i]._preScored = 890 - i;
            items.push(transformBuiltInSearchItem(settingsItems[i], "dms_settings_search"));
        }
        return items;
    }

    function _clipboardSharedItems(query) {
        var items = [];
        if (!clipboardSearchEnabledInAll())
            return items;
        var clipboardItems = AppSearchService.getBuiltInLauncherItems("dms_clipboard_search", query);
        var clipboardLimit = Math.min(clipboardItems.length, 8);
        for (var j = 0; j < clipboardLimit; j++) {
            clipboardItems[j]._preScored = 840 - j;
            items.push(transformBuiltInSearchItem(clipboardItems[j], "dms_clipboard_search"));
        }
        return items;
    }

    function _refreshClipboardResults() {
        if (searchMode !== "all" || searchQuery.length < 2 || _lastPhase1Query !== searchQuery)
            return false;
        var fresh = _clipboardSharedItems(searchQuery);
        if (_samePluginItems(_lastClipboardItems, fresh))
            return true;
        _lastClipboardItems = fresh;
        var phase1 = _lastAppItems.slice();
        for (var i = 0; i < _lastSettingsItems.length; i++)
            phase1.push(_lastSettingsItems[i]);
        for (var j = 0; j < fresh.length; j++)
            phase1.push(fresh[j]);
        if (_pluginPhasePending) {
            _phase1Items = phase1;
            return true;
        }
        if (_lastPluginQuery !== searchQuery || _lastPluginMode !== searchMode)
            return false;
        var allItems = phase1;
        for (var k = 0; k < _lastPluginOrder.length; k++) {
            var items = _lastPluginItems[_lastPluginOrder[k]] || [];
            for (var m = 0; m < items.length; m++)
                allItems.push(items[m]);
        }
        _publishPluginResults(allItems, preserveSelectionAfterUpdate(false));
        return true;
    }

    function detectTrigger(query) {
        if (!query || query.length === 0)
            return {
                pluginId: null,
                query: query
            };

        var pluginTriggers = PluginService.getAllPluginTriggers();
        for (var trigger in pluginTriggers) {
            if (trigger && query.startsWith(trigger)) {
                return {
                    pluginId: pluginTriggers[trigger],
                    query: query.substring(trigger.length).trim()
                };
            }
        }

        var builtInTriggers = AppSearchService.getBuiltInLauncherTriggers();
        for (var trigger in builtInTriggers) {
            if (trigger && query.startsWith(trigger)) {
                return {
                    pluginId: builtInTriggers[trigger],
                    query: query.substring(trigger.length).trim(),
                    isBuiltIn: true
                };
            }
        }

        return {
            pluginId: null,
            query: query
        };
    }

    function getEmptyTriggerPlugins() {
        var plugins = PluginService.getPluginsWithEmptyTrigger();
        var visible = plugins.filter(function (pluginId) {
            return SettingsData.getPluginAllowWithoutTrigger(pluginId);
        });
        return sortPluginIdsByOrder(visible);
    }

    function getAllLauncherPluginIds() {
        var launchers = PluginService.getLauncherPlugins();
        return Object.keys(launchers);
    }

    function getVisibleLauncherPluginIds() {
        var launchers = PluginService.getLauncherPlugins();
        var visible = Object.keys(launchers).filter(function (pluginId) {
            return SettingsData.getPluginAllowWithoutTrigger(pluginId);
        });
        return sortPluginIdsByOrder(visible);
    }

    function getAllBuiltInLauncherIds() {
        var launchers = AppSearchService.getBuiltInLauncherPlugins();
        return Object.keys(launchers);
    }

    function getVisibleBuiltInLauncherIds() {
        var launchers = AppSearchService.getBuiltInLauncherPlugins();
        var visible = Object.keys(launchers).filter(function (pluginId) {
            return SettingsData.getPluginAllowWithoutTrigger(pluginId);
        });
        return sortPluginIdsByOrder(visible);
    }

    function sortPluginIdsByOrder(pluginIds) {
        return Utils.sortPluginIdsByOrder(pluginIds, SettingsData.launcherPluginOrder || []);
    }

    function getAllVisiblePluginsOrdered() {
        var thirdPartyLaunchers = PluginService.getLauncherPlugins() || {};
        var builtInLaunchers = AppSearchService.getBuiltInLauncherPlugins() || {};
        var all = [];
        for (var id in thirdPartyLaunchers) {
            if (SettingsData.getPluginAllowWithoutTrigger(id))
                all.push({
                    id: id,
                    isBuiltIn: false
                });
        }
        for (var id in builtInLaunchers) {
            if (SettingsData.getPluginAllowWithoutTrigger(id))
                all.push({
                    id: id,
                    isBuiltIn: true
                });
        }
        return Utils.sortPluginsOrdered(all, SettingsData.launcherPluginOrder || []);
    }

    function getEmptyTriggerPluginsOrdered() {
        var thirdParty = PluginService.getPluginsWithEmptyTrigger() || [];
        var builtIn = AppSearchService.getBuiltInLauncherPluginsWithEmptyTrigger() || [];
        var all = [];
        for (var i = 0; i < thirdParty.length; i++) {
            var id = thirdParty[i];
            if (SettingsData.getPluginAllowWithoutTrigger(id))
                all.push({
                    id: id,
                    isBuiltIn: false
                });
        }
        for (var i = 0; i < builtIn.length; i++) {
            var id = builtIn[i];
            if (SettingsData.getPluginAllowWithoutTrigger(id))
                all.push({
                    id: id,
                    isBuiltIn: true
                });
        }
        return Utils.sortPluginsOrdered(all, SettingsData.launcherPluginOrder || []);
    }

    function getPluginBrowseItems() {
        var items = [];
        var browseLabel = I18n.tr("Browse");
        var triggerLabel = I18n.tr("Trigger: %1");
        var noTriggerLabel = I18n.tr("No trigger");

        var launchers = PluginService.getLauncherPlugins();
        for (var pluginId in launchers) {
            var trigger = PluginService.getPluginTrigger(pluginId);
            var isAllowed = SettingsData.getPluginAllowWithoutTrigger(pluginId);
            items.push(Transform.createPluginBrowseItem(pluginId, launchers[pluginId], trigger, false, isAllowed, browseLabel, triggerLabel, noTriggerLabel));
        }

        var builtInLaunchers = AppSearchService.getBuiltInLauncherPlugins();
        for (var pluginId in builtInLaunchers) {
            var trigger = AppSearchService.getBuiltInPluginTrigger(pluginId);
            var isAllowed = SettingsData.getPluginAllowWithoutTrigger(pluginId);
            items.push(Transform.createPluginBrowseItem(pluginId, builtInLaunchers[pluginId], trigger, true, isAllowed, browseLabel, triggerLabel, noTriggerLabel));
        }

        return items;
    }

    function getBuiltInEmptyTriggerLaunchers() {
        var plugins = AppSearchService.getBuiltInLauncherPluginsWithEmptyTrigger();
        var visible = plugins.filter(function (pluginId) {
            return SettingsData.getPluginAllowWithoutTrigger(pluginId);
        });
        return sortPluginIdsByOrder(visible);
    }

    function getPluginItems(pluginId, query, limit) {
        var items = AppSearchService.getPluginItemsForPlugin(pluginId, query);
        var count = limit > 0 && limit < items.length ? limit : items.length;
        var transformed = [];

        for (var i = 0; i < count; i++) {
            transformed.push(transformPluginItem(items[i], pluginId));
        }

        return transformed;
    }

    function getPluginName(pluginId, isBuiltIn) {
        if (isBuiltIn) {
            var plugin = AppSearchService.builtInPlugins[pluginId];
            return plugin ? plugin.name : pluginId;
        }
        var launchers = PluginService.getLauncherPlugins();
        if (launchers[pluginId]) {
            return launchers[pluginId].name || pluginId;
        }
        return pluginId;
    }

    function getPluginMetadata(pluginId) {
        var builtIn = AppSearchService.builtInPlugins[pluginId];
        if (builtIn) {
            return {
                name: builtIn.name || pluginId,
                icon: builtIn.cornerIcon || "extension"
            };
        }
        var launchers = PluginService.getLauncherPlugins();
        if (launchers[pluginId]) {
            var rawIcon = launchers[pluginId].icon || "extension";
            return {
                name: launchers[pluginId].name || pluginId,
                icon: Utils.stripIconPrefix(rawIcon)
            };
        }
        return {
            name: pluginId,
            icon: "extension"
        };
    }

    function buildDynamicSectionDefs(items) {
        var baseDefs = sectionDefinitions.map(function (def) {
            return Object.assign({}, def);
        });
        var pluginSections = {};
        var order = SettingsData.launcherPluginOrder || [];
        var orderMap = {};
        for (var k = 0; k < order.length; k++)
            orderMap[order[k]] = k;
        var unorderedPriority = 2.6 + order.length * 0.01;

        for (var d = 0; d < baseDefs.length; d++) {
            var virtualId = baseDefs[d].id === "settings" ? "dms_settings_search" : baseDefs[d].id === "clipboard" ? "dms_clipboard_search" : "";
            if (virtualId && orderMap[virtualId] !== undefined)
                baseDefs[d].priority = 2.6 + orderMap[virtualId] * 0.01;
        }

        for (var i = 0; i < items.length; i++) {
            var section = items[i].section;
            if (!section || !section.startsWith("plugin_"))
                continue;
            if (pluginSections[section])
                continue;
            var pluginId = section.substring(7);
            var meta = getPluginMetadata(pluginId);
            var viewPref = getPluginViewPref(pluginId);
            var orderIdx = orderMap[pluginId];
            var defaultPriority = AppSearchService.builtInPlugins[pluginId]?.defaultSectionPriority;
            var priority;
            if (orderIdx !== undefined) {
                priority = 2.6 + orderIdx * 0.01;
            } else if (defaultPriority !== undefined) {
                priority = defaultPriority;
            } else {
                priority = unorderedPriority;
                unorderedPriority += 0.01;
            }

            pluginSections[section] = {
                id: section,
                title: meta.name,
                icon: meta.icon,
                priority: priority,
                defaultViewMode: viewPref.mode || "list"
            };

            if (viewPref.mode)
                setPluginViewPreference(section, viewPref.mode, viewPref.enforced);
        }

        for (var sectionId in pluginSections) {
            baseDefs.push(pluginSections[sectionId]);
        }

        baseDefs.sort(function (a, b) {
            if (a.priority !== b.priority)
                return a.priority - b.priority;
            return a.id.localeCompare(b.id);
        });
        return baseDefs;
    }

    function getPluginViewPref(pluginId) {
        var builtIn = AppSearchService.builtInPlugins[pluginId];
        if (builtIn && builtIn.viewMode) {
            return {
                mode: builtIn.viewMode,
                enforced: builtIn.viewModeEnforced === true
            };
        }

        var pref = PluginService.getPluginViewPreference(pluginId);
        if (pref && pref.mode) {
            return pref;
        }

        return {
            mode: "list",
            enforced: false
        };
    }

    function transformPluginItem(item, pluginId) {
        return Transform.transformPluginItem(item, pluginId, I18n.tr("Select", "verb, primary action label for a launcher plugin item"));
    }

    function getFrecencyForItem(item) {
        if (item.type !== "app")
            return null;

        var appId = item.id;
        var usageRanking = AppUsageHistoryData.appUsageRanking || {};

        var idVariants = [appId, appId.replace(".desktop", "")];
        var usageData = null;

        for (var i = 0; i < idVariants.length; i++) {
            if (usageRanking[idVariants[i]]) {
                usageData = usageRanking[idVariants[i]];
                break;
            }
        }

        return {
            usageCount: usageData?.usageCount || 0
        };
    }

    function getFirstItemIndex() {
        return Nav.getFirstItemIndex(flatModel);
    }

    function _getCachedModeData(mode) {
        return _modeSectionsCache[mode] || null;
    }

    function _setCachedModeData(mode, sectionsData, flatModelData) {
        var cache = Object.assign({}, _modeSectionsCache);
        cache[mode] = {
            sections: sectionsData,
            flatModel: flatModelData
        };
        _modeSectionsCache = cache;
    }

    function _clearModeCache() {
        _modeSectionsCache = {};
    }

    function _saveDiskCache(sectionsData) {
        var serializable = [];
        for (var i = 0; i < sectionsData.length; i++) {
            var s = sectionsData[i];
            var items = [];
            var srcItems = s.items || [];
            for (var j = 0; j < srcItems.length; j++) {
                var it = srcItems[j];
                items.push({
                    id: it.id,
                    type: it.type,
                    name: it.name || "",
                    subtitle: it.subtitle || "",
                    icon: it.icon || "",
                    iconType: it.iconType || "image",
                    iconFull: it.iconFull || "",
                    section: it.section || "",
                    isCore: it.isCore || false,
                    isBuiltInLauncher: it.isBuiltInLauncher || false,
                    pluginId: it.pluginId || "",
                    source: it.source || ""
                });
            }
            serializable.push({
                id: s.id,
                title: s.title || "",
                icon: s.icon || "",
                priority: s.priority || 0,
                items: items
            });
        }
        CacheData.saveLauncherCache(serializable);
    }

    function _actionsFromDesktopEntry(appId) {
        if (!appId)
            return [];
        var entry = DesktopEntries.heuristicLookup(appId);
        if (!entry || !entry.actions || entry.actions.length === 0)
            return [];
        var result = [];
        for (var i = 0; i < entry.actions.length; i++) {
            result.push({
                name: entry.actions[i].name,
                icon: "play_arrow",
                actionData: entry.actions[i]
            });
        }
        return result;
    }

    function _diskCacheSectionDef(sectionId) {
        for (var i = 0; i < sectionDefinitions.length; i++) {
            if (sectionDefinitions[i].id === sectionId)
                return sectionDefinitions[i];
        }
        return null;
    }

    function _diskCacheSection(def, items) {
        return {
            id: def.id || "",
            title: def.title || "",
            icon: def.icon || "",
            priority: def.priority || 0,
            items: items,
            collapsed: false,
            flatStartIndex: 0
        };
    }

    function _loadDiskCache() {
        var cached = CacheData.loadLauncherCache();
        if (!cached || !Array.isArray(cached) || cached.length === 0)
            return null;

        var browseItems = getPluginBrowseItems();
        var liveCoreItems = {};
        var liveCoreApps = AppSearchService.getCoreApps("");
        for (var c = 0; c < liveCoreApps.length; c++) {
            var coreItem = transformCoreApp(liveCoreApps[c]);
            liveCoreItems[coreItem.id] = coreItem;
        }

        var sectionsData = [];
        var browseSectionSeen = false;
        for (var i = 0; i < cached.length; i++) {
            var s = cached[i];
            if (s.id === "browse_plugins") {
                browseSectionSeen = true;
                if (browseItems.length > 0)
                    sectionsData.push(_diskCacheSection(_diskCacheSectionDef(s.id) || s, browseItems));
                continue;
            }
            var items = [];
            var srcItems = s.items || [];
            for (var j = 0; j < srcItems.length; j++) {
                var it = srcItems[j];
                if (it.isCore) {
                    if (liveCoreItems[it.id])
                        items.push(liveCoreItems[it.id]);
                    continue;
                }
                if (it.type === "plugin_browse" || it.isBuiltInLauncher || it.pluginId)
                    continue;
                items.push({
                    id: it.id || "",
                    type: it.type || "app",
                    name: it.name || "",
                    subtitle: it.subtitle || "",
                    icon: it.icon || "",
                    iconType: it.iconType || "image",
                    iconFull: it.iconFull || "",
                    section: it.section || "",
                    source: it.source || "",
                    data: {
                        id: it.id
                    },
                    actions: _actionsFromDesktopEntry(it.id),
                    primaryAction: it.type === "app" ? {
                        name: I18n.tr("Launch"),
                        icon: "open_in_new",
                        action: "launch"
                    } : null,
                    _diskCached: true,
                    _hName: "",
                    _hSub: "",
                    _hRich: false,
                    _preScored: undefined
                });
            }
            if (items.length > 0)
                sectionsData.push(_diskCacheSection(s, items));
        }

        if (!browseSectionSeen && browseItems.length > 0) {
            var browseDef = _diskCacheSectionDef("browse_plugins");
            if (browseDef)
                sectionsData.push(_diskCacheSection(browseDef, browseItems));
        }

        if (sectionsData.length === 0)
            return null;

        sectionsData.sort(function (a, b) {
            if (a.priority !== b.priority)
                return a.priority - b.priority;
            return a.id.localeCompare(b.id);
        });
        return sectionsData;
    }

    function updateSelectedItem() {
        if (selectedFlatIndex >= 0 && selectedFlatIndex < flatModel.length) {
            var entry = flatModel[selectedFlatIndex];
            selectedItem = entry.isHeader ? null : entry.item;
        } else {
            selectedItem = null;
        }
    }

    function _applyHighlights(sectionsData, query) {
        if (!query || query.length === 0) {
            for (var i = 0; i < sectionsData.length; i++) {
                var items = sectionsData[i].items;
                for (var j = 0; j < items.length; j++) {
                    var item = items[j];
                    item._hName = item.name || "";
                    item._hSub = item.subtitle || "";
                    item._hRich = false;
                }
            }
            return;
        }

        var lowerQuery = query.toLowerCase();

        for (var i = 0; i < sectionsData.length; i++) {
            var items = sectionsData[i].items;
            for (var j = 0; j < items.length; j++) {
                var item = items[j];
                item._hName = _highlightField(item.name || "", lowerQuery, query.length);
                item._hSub = _highlightField(item.subtitle || "", lowerQuery, query.length);
                item._hRich = true;
            }
        }
    }

    function _highlightField(text, lowerQuery, queryLen) {
        if (!text)
            return "";
        var idx = text.toLowerCase().indexOf(lowerQuery);
        if (idx === -1)
            return _escapeRichText(text);
        var before = text.substring(0, idx);
        var match = text.substring(idx, idx + queryLen);
        var after = text.substring(idx + queryLen);
        return _escapeRichText(before) + '<b>' + _escapeRichText(match) + '</b>' + _escapeRichText(after);
    }

    function _escapeRichText(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");
    }

    function getCurrentSectionViewMode() {
        if (selectedFlatIndex < 0 || selectedFlatIndex >= flatModel.length)
            return "list";
        var entry = flatModel[selectedFlatIndex];
        if (!entry || entry.isHeader)
            return "list";
        return getSectionViewMode(entry.sectionId);
    }

    function getGridColumns(sectionId) {
        return Nav.getGridColumns(getSectionViewMode(sectionId), gridColumns);
    }

    function _cancelPendingSelectionReset() {
        _queryDrivenSearch = false;
        _pluginPhaseForceFirst = false;
    }

    function selectNext() {
        keyboardNavigationActive = true;
        _cancelPendingSelectionReset();
        var newIndex = forceLinearNavigation ? Nav.findNextNonHeaderIndex(flatModel, selectedFlatIndex + 1) : Nav.calculateNextIndex(flatModel, selectedFlatIndex, null, null, gridColumns, getSectionViewMode);
        if (newIndex === -1)
            newIndex = selectedFlatIndex;
        if (newIndex !== selectedFlatIndex) {
            selectedFlatIndex = newIndex;
            updateSelectedItem();
        }
    }

    function selectPrevious() {
        keyboardNavigationActive = true;
        _cancelPendingSelectionReset();
        var newIndex = forceLinearNavigation ? Nav.findPrevNonHeaderIndex(flatModel, selectedFlatIndex - 1) : Nav.calculatePrevIndex(flatModel, selectedFlatIndex, null, null, gridColumns, getSectionViewMode);
        if (newIndex === -1)
            newIndex = selectedFlatIndex;
        if (newIndex !== selectedFlatIndex) {
            selectedFlatIndex = newIndex;
            updateSelectedItem();
        }
    }

    function selectRight() {
        keyboardNavigationActive = true;
        _cancelPendingSelectionReset();
        var newIndex = Nav.calculateRightIndex(flatModel, selectedFlatIndex, getSectionViewMode);
        if (newIndex !== selectedFlatIndex) {
            selectedFlatIndex = newIndex;
            updateSelectedItem();
        }
    }

    function selectLeft() {
        keyboardNavigationActive = true;
        _cancelPendingSelectionReset();
        var newIndex = Nav.calculateLeftIndex(flatModel, selectedFlatIndex, getSectionViewMode);
        if (newIndex !== selectedFlatIndex) {
            selectedFlatIndex = newIndex;
            updateSelectedItem();
        }
    }

    function selectNextSection() {
        keyboardNavigationActive = true;
        _cancelPendingSelectionReset();
        var newIndex = Nav.calculateNextSectionIndex(flatModel, selectedFlatIndex);
        if (newIndex !== selectedFlatIndex) {
            selectedFlatIndex = newIndex;
            updateSelectedItem();
        }
    }

    function selectPreviousSection() {
        keyboardNavigationActive = true;
        _cancelPendingSelectionReset();
        var newIndex = Nav.calculatePrevSectionIndex(flatModel, selectedFlatIndex);
        if (newIndex !== selectedFlatIndex) {
            selectedFlatIndex = newIndex;
            updateSelectedItem();
        }
    }

    function selectPageDown(visibleItems) {
        keyboardNavigationActive = true;
        _cancelPendingSelectionReset();
        var newIndex = Nav.calculatePageDownIndex(flatModel, selectedFlatIndex, visibleItems);
        if (newIndex !== selectedFlatIndex) {
            selectedFlatIndex = newIndex;
            updateSelectedItem();
        }
    }

    function selectPageUp(visibleItems) {
        keyboardNavigationActive = true;
        _cancelPendingSelectionReset();
        var newIndex = Nav.calculatePageUpIndex(flatModel, selectedFlatIndex, visibleItems);
        if (newIndex !== selectedFlatIndex) {
            selectedFlatIndex = newIndex;
            updateSelectedItem();
        }
    }

    function selectIndex(index) {
        keyboardNavigationActive = false;
        if (index >= 0 && index < flatModel.length && !flatModel[index].isHeader) {
            selectedFlatIndex = index;
            updateSelectedItem();
        }
    }

    function toggleSection(sectionId) {
        _clearModeCache();
        var newCollapsed = Object.assign({}, collapsedSections);
        var currentState = newCollapsed[sectionId];

        if (currentState === undefined) {
            for (var i = 0; i < sections.length; i++) {
                if (sections[i].id === sectionId) {
                    currentState = sections[i].collapsed || false;
                    break;
                }
            }
        }

        newCollapsed[sectionId] = !currentState;
        collapsedSections = newCollapsed;

        var newSections = sections.slice();
        for (var i = 0; i < newSections.length; i++) {
            if (newSections[i].id === sectionId) {
                newSections[i] = Object.assign({}, newSections[i], {
                    collapsed: newCollapsed[sectionId]
                });
            }
        }
        flatModel = Scorer.flattenSections(newSections);
        sections = newSections;

        if (selectedFlatIndex >= flatModel.length) {
            selectedFlatIndex = getFirstItemIndex();
        }
        updateSelectedItem();

        if (!newCollapsed[sectionId])
            sectionExpanded(sectionId);
    }

    function executeSelected(newInstance = false) {
        if (_searchPending) {
            _searchPending = false;
            searchDebounce.stop();
            performSearch();
        }
        if (searchMode === "dmenu" && dmenuMultiSelect) {
            confirmDmenuMultiSelection();
            return;
        }
        if (!selectedItem) {
            if (searchMode === "dmenu" && searchQuery) {
                if (dmenuOnlyMatch || dmenuNoCustom)
                    return;
                _sendDmenuFreeText(searchQuery);
                itemExecuted();
            }
            return;
        }
        executeItem(selectedItem, true, newInstance);
    }

    function executeItem(item, isKeyboard = false, newInstance = false) {
        if (!item)
            return;

        if (searchMode !== "dmenu" || !dmenuDisableHistory)
            SessionData.addLauncherHistory(searchQuery, explicitQuerySession);

        if (item.type === "plugin_browse") {
            var browsePluginId = item.data?.pluginId;
            if (!browsePluginId)
                return;
            var browseTrigger = item.data.isBuiltIn ? AppSearchService.getBuiltInPluginTrigger(browsePluginId) : PluginService.getPluginTrigger(browsePluginId);

            if (browseTrigger && browseTrigger.length > 0) {
                searchQueryRequested(browseTrigger);
            } else {
                setMode("plugins", false, undefined, true);
                pluginFilter = browsePluginId;
                performSearch();
            }
            return;
        }

        switch (item.type) {
        case "app":
            if (item.isCore) {
                AppSearchService.executeCoreApp(item.data);
            } else if (item.data?.isAction) {
                launchAppAction(item.data);
            } else {
                launchApp(item.data, newInstance);
            }
            break;
        case "plugin":
            if (item.isBuiltInLauncher) {
                AppSearchService.executeBuiltInLauncherItem(item.data);
            } else {
                AppSearchService.executePluginItem(item.data, item.pluginId);
            }
            break;
        case "setting":
            AppSearchService.executeBuiltInLauncherItem(item.data);
            break;
        case "clipboard":
            var shouldPaste = isKeyboard ? SettingsData.clipboardEnterToPaste : SettingsData.clipboardClickToPaste;
            if (shouldPaste) {
                ClipboardService.pasteEntry(item.data, function () {
                    root.itemExecuted();
                });
            } else {
                ClipboardService.copyEntry(item.data, function () {
                    root.itemExecuted();
                });
            }
            return;
        case "file":
            openFile(item.data?.path);
            break;
        case "dmenu":
            if (item.data.nonSelectable)
                return;
            if (dmenuMultiSelect) {
                _toggleDmenuMultiSelect(item);
                return;
            }
            _sendDmenuRowSelection(item);
            break;
        default:
            return;
        }

        itemExecuted();
    }

    function executeAction(item, action) {
        if (!item || !action)
            return;
        switch (action.action) {
        case "launch":
            executeItem(item);
            break;
        case "open":
            openFile(item.data.path);
            break;
        case "open_folder":
            openFolder(item.data.path);
            break;
        case "open_with":
            openWith(item.data.path);
            break;
        case "copy_path":
            copyToClipboard(item.data.path);
            break;
        case "open_terminal":
            openTerminal(item.data.path);
            break;
        case "copy":
            copyToClipboard(item.name);
            break;
        case "execute":
            executeItem(item);
            break;
        case "clipboard_copy":
            ClipboardService.copyEntry(item.data, function () {
                root.itemExecuted();
            });
            return;
        case "clipboard_paste":
            ClipboardService.pasteEntry(item.data, function () {
                root.itemExecuted();
            });
            return;
        case "launch_dgpu":
            if (item.type === "app" && item.data) {
                launchAppWithNvidia(item.data);
            }
            break;
        case "toggle_all_visibility":
            if (item.type === "plugin_browse" && item.data?.pluginId) {
                var pluginId = item.data.pluginId;
                var currentState = SettingsData.getPluginAllowWithoutTrigger(pluginId);
                SettingsData.setPluginAllowWithoutTrigger(pluginId, !currentState);
                performSearch();
            }
            return;
        default:
            if (item.type === "app" && action.actionData) {
                launchAppAction({
                    parentApp: item.data,
                    actionData: action.actionData
                });
            }
        }

        itemExecuted();
    }

    function _resolveDesktopEntry(app) {
        if (!app)
            return null;
        if (app.command)
            return app;
        var id = app.id || app.execString || app.exec || "";
        if (!id)
            return null;
        return DesktopEntries.heuristicLookup(id);
    }

    function _runningToplevelFor(entry) {
        if (!entry.id)
            return null;
        const toplevels = ToplevelManager.toplevels.values;
        for (let i = 0; i < toplevels.length; i++) {
            const appId = toplevels[i].appId;
            if (!appId)
                continue;
            if (DesktopEntries.heuristicLookup(Paths.moddedAppId(appId))?.id === entry.id)
                return toplevels[i];
        }
        return null;
    }

    function launchApp(app, newInstance = false) {
        var entry = _resolveDesktopEntry(app);
        if (!entry)
            return;
        const running = SettingsData.launcherEnterAction === "focus" && !newInstance ? _runningToplevelFor(entry) : null;
        if (running) {
            CompositorService.activateToplevel(running);
            AppUsageHistoryData.addAppUsage(entry);
            return;
        }
        SessionService.launchDesktopEntry(entry);
        AppUsageHistoryData.addAppUsage(entry);
    }

    function launchAppWithNvidia(app) {
        var entry = _resolveDesktopEntry(app);
        if (!entry)
            return;
        SessionService.launchDesktopEntry(entry, true);
        AppUsageHistoryData.addAppUsage(entry);
    }

    function launchAppAction(actionItem) {
        if (!actionItem || !actionItem.actionData)
            return;
        var entry = _resolveDesktopEntry(actionItem.parentApp);
        if (!entry)
            return;
        SessionService.launchDesktopAction(entry, actionItem.actionData);
        AppUsageHistoryData.addAppUsage(entry);
    }

    function openFile(path) {
        SessionService.openPath(path);
    }

    function openFolder(path) {
        if (!path)
            return;
        SessionService.openPath(path.substring(0, path.lastIndexOf("/")));
    }

    function openWith(path) {
        if (!path)
            return;
        // No mimeType: it would limit the picker to declared handlers, and any app must stay pickable.
        DMSService.appPickerRequested({
            target: path
        });
    }

    function openTerminal(path) {
        if (!path)
            return;
        var terminal = SessionData.resolveTerminal() || "xterm";
        Quickshell.execDetached({
            command: [terminal],
            workingDirectory: path
        });
    }

    function copyToClipboard(text) {
        if (!text)
            return;
        Quickshell.execDetached(["dms", "cl", "copy", text]);
    }
}
