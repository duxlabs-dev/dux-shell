import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/PluginRanking.js" as PluginRanking

RegistryBrowserWindow {
    id: root

    readonly property var log: Log.scoped("PluginBrowser")
    property var allPlugins: []
    property var filteredPlugins: []
    property var typeFilters: []
    property string categoryFilter: "all"
    property var categoryFilterOptions: []
    property var availableLetters: []
    property string detailPluginId: ""
    property string pendingRevealPluginId: ""
    property string loadError: ""
    property string operationMessage: ""
    property bool operationFailed: false
    property bool operationPending: false
    property var discoverPicks: []
    // Quick filters of this visit: usable (on the running compositor), fresh (new or updated), official.
    property var quickFilters: ({})
    // Set by a click on an author in a plugin's detail: only that author's plugins are listed.
    property string authorFilter: ""
    property var searchSuggestions: []
    property var foundCommands: []
    property var checkedCommands: []
    property var discoverShelves: []

    readonly property var detailPlugin: resolveDetailPlugin(detailPluginId, allPlugins)
    readonly property bool discoverVisible: {
        if (isLoading || loadError !== "" || searchQuery !== "" || typeFilters.length > 0 || authorFilter !== "")
            return false;
        if (discoverPicks.length === 0 && discoverShelves.length === 0)
            return false;
        var mode = normalizedSortMode(SessionData.pluginBrowserSortMode);
        return mode === "default" || mode === "recommended";
    }
    readonly property bool activeCategorySort: normalizedSortMode(SessionData.pluginBrowserSortMode) === "category"
    readonly property bool showCategoryFilters: activeCategorySort && categoryFilterOptions.length > 1
    readonly property bool showLetterIndex: {
        var mode = normalizedSortMode(SessionData.pluginBrowserSortMode);
        return (mode === "name" || mode === "author") && availableLetters.length > 1;
    }

    readonly property var quickFilterOptions: [
        {
            value: "usable",
            label: I18n.tr("Works here", "plugin browser filter chip, plugins that run on the current compositor"),
            icon: "desktop_windows"
        },
        {
            value: "fresh",
            label: I18n.tr("New & updated", "plugin browser filter chip"),
            icon: "fiber_new"
        },
        {
            value: "official",
            label: I18n.tr("Official only", "plugin browser filter chip, first party plugins"),
            icon: "verified"
        }
    ]
    showLoadingSpinner: false

    readonly property var typeFilterOptions: [
        {
            label: I18n.tr("Bar", "plugin browser type filter chip, bar widget plugins"),
            value: "dankbar-widget"
        },
        {
            label: I18n.tr("Control Center", "plugin browser type filter chip"),
            value: "control-center"
        },
        {
            label: I18n.tr("Launcher", "plugin browser type filter chip"),
            value: "launcher"
        },
        {
            label: I18n.tr("Daemon", "plugin browser type filter chip, background plugins"),
            value: "daemon"
        },
        {
            label: I18n.tr("Desktop", "plugin browser type filter chip, desktop widget plugins"),
            value: "desktop-widget"
        },
        {
            label: I18n.tr("Dash tab", "plugin browser type filter chip"),
            value: "dash-tab"
        },
        {
            label: I18n.tr("Dash card", "plugin browser type filter chip"),
            value: "dash-card"
        }
    ]

    readonly property var sortChipOptions: [
        {
            id: "hideInstalled",
            label: I18n.tr("Hide installed", "plugin browser filter chip"),
            toggle: true
        },
        {
            id: "installed",
            label: I18n.tr("Installed first", "plugin browser filter chip"),
            toggle: true
        },
        {
            id: "default",
            label: I18n.tr("Votes", "plugin browser sort option"),
            toggle: false
        },
        {
            id: "recommended",
            label: I18n.tr("For you", "plugin browser sort option, plugins ranked for this user"),
            toggle: false
        },
        {
            id: "name",
            label: I18n.tr("Name", "plugin browser sort option"),
            toggle: false
        },
        {
            id: "author",
            label: I18n.tr("Contributor", "plugin browser sort option"),
            toggle: false
        },
        {
            id: "category",
            label: I18n.tr("Category", "plugin browser sort option"),
            toggle: false
        }
    ]

    function normalizedSortMode(mode) {
        if (mode === "type" || mode === "contributor")
            return "author";
        if (mode === "name" || mode === "author" || mode === "category" || mode === "recommended")
            return mode;
        return "default";
    }

    function rankingCompositor() {
        if (CompositorService.isNiri)
            return "niri";
        if (CompositorService.isHyprland)
            return "hyprland";
        if (CompositorService.isSway)
            return "sway";
        if (CompositorService.isMango)
            return "mangowc";
        if (CompositorService.isLabwc)
            return "labwc";
        if (CompositorService.isMiracle)
            return "miracle-wm";
        return "";
    }

    function recommendationReason(key) {
        switch (key) {
        case "similar":
            return I18n.tr("Like your plugins", "plugin recommendation reason, similar to installed plugins");
        case "featured":
            return I18n.tr("Featured plugin", "plugin recommendation reason");
        case "new":
            return I18n.tr("New", "plugin recommendation reason, recently published");
        case "trending":
            return I18n.tr("Trending", "plugin recommendation reason, gaining votes quickly");
        case "category":
            return I18n.tr("Fits your setup", "plugin recommendation reason, same category as installed plugins");
        default:
            return I18n.tr("Popular", "plugin recommendation reason, many votes");
        }
    }

    function updateDiscover(pool) {
        var now = Date.now();
        var taste = PluginRanking.buildTaste(allPlugins);
        var options = {
            now: now,
            taste: taste,
            compositor: rankingCompositor(),
            limit: 6
        };

        var picks = [];
        var week = PluginRanking.pickOfTheWeek(pool, now);
        if (week)
            picks.push({
                label: I18n.tr("Pick of the week", "plugin browser highlighted plugin"),
                plugin: week
            });
        var day = PluginRanking.pickOfTheDay(pool, now);
        if (day)
            picks.push({
                label: I18n.tr("Pick of the day", "plugin browser highlighted plugin"),
                plugin: day
            });

        options.exclude = picks.map(pick => pick.plugin.id);

        var shelves = [];
        var recommended = PluginRanking.recommend(pool, options);
        if (recommended.length > 0)
            shelves.push({
                label: taste.count > 0 ? I18n.tr("For you", "plugin browser shelf, plugins ranked for this user") : I18n.tr("Popular", "plugin browser shelf"),
                plugins: recommended,
                captions: recommended.map(p => recommendationReason(PluginRanking.reason(p, taste, now)))
            });
        var trending = PluginRanking.trendingNow(pool, options);
        if (trending.length > 0)
            shelves.push({
                label: I18n.tr("Trending", "plugin browser shelf, gaining votes quickly"),
                plugins: trending,
                captions: []
            });
        var arrivals = PluginRanking.newArrivals(pool, options);
        if (arrivals.length > 0)
            shelves.push({
                label: I18n.tr("New", "plugin browser shelf, recently published"),
                plugins: arrivals,
                captions: []
            });

        discoverPicks = picks;
        discoverShelves = shelves;
    }

    function isSortChipSelected(chipId, toggle) {
        if (toggle) {
            if (chipId === "hideInstalled")
                return SessionData.pluginBrowserHideInstalled;
            return SessionData.pluginBrowserInstalledFirst;
        }
        return normalizedSortMode(SessionData.pluginBrowserSortMode) === chipId;
    }

    function comparePluginName(a, b) {
        var nameA = (a.name || "").toLowerCase();
        var nameB = (b.name || "").toLowerCase();
        if (nameA < nameB)
            return -1;
        if (nameA > nameB)
            return 1;
        return 0;
    }

    function pluginReviewed(plugin) {
        return (plugin.status || []).indexOf("reviewed") !== -1;
    }

    function relatedPlugins(plugin) {
        if (!plugin || !plugin.similar || plugin.similar.length === 0)
            return [];

        var related = [];
        for (var i = 0; i < plugin.similar.length; i++) {
            var id = plugin.similar[i];
            var key = "";
            var name = id;
            for (var j = 0; j < allPlugins.length; j++) {
                if (allPlugins[j].id !== id)
                    continue;
                key = detailKeyFor(allPlugins[j]);
                name = allPlugins[j].name || id;
                break;
            }
            related.push({
                key: key,
                name: name
            });
        }
        return related;
    }

    function comparePluginAuthor(a, b) {
        var authorA = (a.author || "").toLowerCase() || "zzz";
        var authorB = (b.author || "").toLowerCase() || "zzz";
        if (authorA < authorB)
            return -1;
        if (authorA > authorB)
            return 1;
        return comparePluginName(a, b);
    }

    function comparePluginCategory(a, b) {
        var catA = (a.category || "").toLowerCase() || "zzz";
        var catB = (b.category || "").toLowerCase() || "zzz";
        if (catA < catB)
            return -1;
        if (catA > catB)
            return 1;
        return comparePluginName(a, b);
    }

    function formatCategoryLabel(categoryKey) {
        if (!categoryKey || categoryKey === "_uncategorized")
            return I18n.tr("Uncategorized", "plugin browser category filter");
        return categoryKey.charAt(0).toUpperCase() + categoryKey.slice(1);
    }

    function sortKeyForPlugin(plugin, mode) {
        if (mode === "author")
            return (plugin.author || "").trim();
        if (mode === "category")
            return formatCategoryLabel((plugin.category || "").toLowerCase() || "_uncategorized");
        return (plugin.name || "").trim();
    }

    function buildCategoryFilterOptions(plugins) {
        var counts = {};
        for (var i = 0; i < plugins.length; i++) {
            var cat = (plugins[i].category || "").toLowerCase();
            if (!cat)
                cat = "_uncategorized";
            counts[cat] = (counts[cat] || 0) + 1;
        }
        var keys = Object.keys(counts).sort();
        var options = [
            {
                key: "all",
                label: I18n.tr("All", "plugin browser category filter"),
                count: plugins.length
            }
        ];
        for (var j = 0; j < keys.length; j++) {
            var key = keys[j];
            options.push({
                key: key,
                label: formatCategoryLabel(key),
                count: counts[key]
            });
        }
        return options;
    }

    function categoryFilterDisplayLabel(option) {
        return option.label + " (" + option.count + ")";
    }

    function categoryFilterLabelForKey(key) {
        for (var i = 0; i < categoryFilterOptions.length; i++) {
            if (categoryFilterOptions[i].key === key)
                return categoryFilterDisplayLabel(categoryFilterOptions[i]);
        }
        return "";
    }

    function categoryFilterKeyForLabel(label) {
        for (var i = 0; i < categoryFilterOptions.length; i++) {
            if (categoryFilterDisplayLabel(categoryFilterOptions[i]) === label)
                return categoryFilterOptions[i].key;
        }
        return "all";
    }

    function categoryFilterDropdownLabels() {
        var labels = [];
        for (var i = 0; i < categoryFilterOptions.length; i++)
            labels.push(categoryFilterDisplayLabel(categoryFilterOptions[i]));
        return labels;
    }

    function updateAvailableLetters(plugins) {
        var mode = normalizedSortMode(SessionData.pluginBrowserSortMode);
        if (mode !== "name" && mode !== "author") {
            availableLetters = [];
            return;
        }
        var letters = {};
        for (var i = 0; i < plugins.length; i++) {
            var key = sortKeyForPlugin(plugins[i], mode);
            if (!key)
                continue;
            var letter = key.charAt(0).toUpperCase();
            if (letter >= "A" && letter <= "Z")
                letters[letter] = true;
        }
        availableLetters = Object.keys(letters).sort();
    }

    function refreshListLayout() {
        if (!pluginGrid)
            return;
        pluginGrid.cancelFlick();
        pluginGrid.positionViewAtBeginning();
        Qt.callLater(() => {
            if (pluginGrid)
                pluginGrid.forceLayout();
        });
    }

    function scrollToLetter(letter) {
        var mode = normalizedSortMode(SessionData.pluginBrowserSortMode);
        for (var i = 0; i < filteredPlugins.length; i++) {
            var key = sortKeyForPlugin(filteredPlugins[i], mode);
            if (key && key.charAt(0).toUpperCase() === letter) {
                pluginGrid.positionViewAtIndex(i, GridView.Beginning);
                return;
            }
        }
    }

    function updateFilteredPlugins() {
        var baseFiltered = [];
        var visiblePlugins = SessionData.showThirdPartyPlugins ? allPlugins : allPlugins.filter(p => p.firstParty || false);
        var plan = PluginRanking.searchPlan(visiblePlugins, searchQuery);

        for (var i = 0; i < allPlugins.length; i++) {
            var plugin = allPlugins[i];
            var isFirstParty = plugin.firstParty || false;

            if (!SessionData.showThirdPartyPlugins && !isFirstParty)
                continue;
            if (typeFilters.length > 0) {
                var hasCapability = typeFilters.some(type => (plugin.capabilities || []).includes(type));
                if (!hasCapability)
                    continue;
            }

            if (PluginRanking.searchRank(plugin, plan) > 0)
                baseFiltered.push(plugin);
        }
        if (authorFilter !== "")
            baseFiltered = PluginRanking.byAuthor(baseFiltered, authorFilter);

        var compositor = rankingCompositor();
        var filterNow = Date.now();
        baseFiltered = baseFiltered.filter(p => PluginRanking.matchesFilters(p, quickFilters, compositor, filterNow));

        updateDiscover(baseFiltered);
        categoryFilterOptions = buildCategoryFilterOptions(baseFiltered);
        if (categoryFilter !== "all") {
            var filterStillValid = false;
            for (var c = 0; c < categoryFilterOptions.length; c++) {
                if (categoryFilterOptions[c].key === categoryFilter) {
                    filterStillValid = true;
                    break;
                }
            }
            if (!filterStillValid)
                categoryFilter = "all";
        }

        var filtered = baseFiltered;
        if (SessionData.pluginBrowserHideInstalled)
            filtered = filtered.filter(p => !(p.installed || false));
        if (activeCategorySort && categoryFilter !== "all") {
            filtered = filtered.filter(p => {
                var cat = (p.category || "").toLowerCase();
                if (!cat)
                    cat = "_uncategorized";
                return cat === categoryFilter;
            });
        }

        var sortMode = normalizedSortMode(SessionData.pluginBrowserSortMode);
        var scores = {};
        if (sortMode === "recommended") {
            var now = Date.now();
            var taste = PluginRanking.buildTaste(allPlugins);
            for (var s = 0; s < filtered.length; s++)
                scores[filtered[s].id] = PluginRanking.score(filtered[s], taste, now);
        }

        filtered.sort((a, b) => {
            if (SessionData.pluginBrowserInstalledFirst) {
                var instA = a.installed || false;
                var instB = b.installed || false;
                if (instA !== instB)
                    return instA ? -1 : 1;
            }
            if (sortMode === "recommended") {
                var scoreA = scores[a.id] || 0;
                var scoreB = scores[b.id] || 0;
                if (scoreA !== scoreB)
                    return scoreB - scoreA;
                return comparePluginName(a, b);
            }
            if (sortMode === "name")
                return comparePluginName(a, b);
            if (sortMode === "author")
                return comparePluginAuthor(a, b);
            if (sortMode === "category")
                return comparePluginCategory(a, b);
            var votesA = a.upvotes || 0;
            var votesB = b.upvotes || 0;
            if (votesA !== votesB)
                return votesB - votesA;
            var verA = root.pluginReviewed(a);
            var verB = root.pluginReviewed(b);
            if (verA !== verB)
                return verA ? -1 : 1;
            return comparePluginName(a, b);
        });

        filteredPlugins = filtered;
        searchSuggestions = filtered.length === 0 && plan.length > 0 ? PluginRanking.closest(visiblePlugins, searchQuery, 4) : [];
        updateAvailableLetters(filtered);
        selectedIndex = -1;
        keyboardNavigationActive = false;
        refreshListLayout();
        revealTimer.restart();
    }

    Timer {
        id: revealTimer
        interval: 0
        onTriggered: {
            if (!root.visible || !root.pendingRevealPluginId || root.isLoading)
                return;
            const index = root.filteredPlugins.findIndex(plugin => plugin.id === root.pendingRevealPluginId);
            if (index < 0)
                return;
            root.selectedIndex = index;
            root.keyboardNavigationActive = true;
            pluginGrid.currentIndex = index;
            pluginGrid.revealIndex(index);
            pluginGrid.forceLayout();
            pluginGrid.currentItem?.focusTarget?.forceActiveFocus(Qt.TabFocusReason);
            root.pendingRevealPluginId = "";
        }
    }

    function detailKeyFor(plugin) {
        if (!plugin)
            return "";
        return plugin.id || plugin.name || "";
    }

    function resolveDetailPlugin(key, plugins) {
        if (!key)
            return null;
        for (var i = 0; i < plugins.length; i++) {
            if (detailKeyFor(plugins[i]) === key)
                return plugins[i];
        }
        return null;
    }

    function openPluginDetail(plugin) {
        var key = detailKeyFor(plugin);
        if (!key)
            return;
        detailPluginId = key;
    }

    function closePluginDetail() {
        detailPluginId = "";
    }

    function showAuthor(author) {
        authorFilter = author || "";
        closePluginDetail();
        updateFilteredPlugins();
    }

    function permissionLabel(id) {
        switch (id) {
        case "settings_read":
            return I18n.tr("Reads its own settings", "plugin permission");
        case "settings_write":
            return I18n.tr("Saves its own settings", "plugin permission");
        case "process":
            return I18n.tr("Runs programs on your computer", "plugin permission");
        case "process_read":
            return I18n.tr("Reads the list of running programs", "plugin permission");
        case "shell_execute":
            return I18n.tr("Runs shell commands", "plugin permission");
        case "network":
            return I18n.tr("Connects to the internet", "plugin permission");
        case "clipboard_read":
            return I18n.tr("Reads the clipboard", "plugin permission");
        case "filesystem_read":
            return I18n.tr("Reads your files", "plugin permission");
        case "filesystem_write":
            return I18n.tr("Writes to your files", "plugin permission");
        case "state_read":
            return I18n.tr("Reads its saved state", "plugin permission");
        case "state_write":
            return I18n.tr("Saves its state", "plugin permission");
        case "audio_read":
            return I18n.tr("Reads audio devices and volume", "plugin permission");
        case "audio_control":
            return I18n.tr("Changes volume and audio devices", "plugin permission");
        case "mpris_control":
            return I18n.tr("Controls media players", "plugin permission");
        default:
            return id;
        }
    }

    function permissionIcon(id) {
        switch (id) {
        case "process":
        case "shell_execute":
            return "terminal";
        case "network":
            return "public";
        case "clipboard_read":
            return "content_paste";
        case "filesystem_read":
        case "filesystem_write":
            return "folder";
        case "audio_read":
        case "audio_control":
            return "volume_up";
        case "mpris_control":
            return "play_circle";
        case "process_read":
            return "list";
        default:
            return "tune";
        }
    }

    function checkDependencies(plugin) {
        var commands = [];
        var deps = plugin ? (plugin.dependencies || []) : [];
        for (var i = 0; i < deps.length; i++)
            commands = commands.concat(PluginRanking.dependencyCommands(deps[i]));
        // shortcut: a registry entry with more than 32 commands only gets the first ones checked; the rest stay unknown.
        commands = commands.slice(0, 32).filter(c => checkedCommands.indexOf(c) < 0);
        if (commands.length === 0)
            return;
        var script = 'for c in "$@"; do command -v "$c" >/dev/null 2>&1 && echo "$c"; done; true';
        Proc.runCommand("plugin-browser-dependencies", ["sh", "-c", script, "sh"].concat(commands), (output, exitCode) => {
            if (exitCode !== 0) {
                root.log.warn("dependency lookup failed", exitCode);
                return;
            }
            var found = String(output || "").split("\n").map(line => line.trim()).filter(line => commands.indexOf(line) >= 0);
            foundCommands = foundCommands.concat(found.filter(c => foundCommands.indexOf(c) < 0));
            checkedCommands = checkedCommands.concat(commands.filter(c => checkedCommands.indexOf(c) < 0));
        }, 0);
    }

    function copyLink(plugin) {
        var url = PluginRanking.shareUrl(plugin);
        if (!url)
            return;
        Quickshell.execDetached([Proc.dmsBin, "cl", "copy", url]);
        ToastService.showInfo(I18n.tr("Link copied", "plugin browser, link copied to clipboard"));
    }

    function linkMarkup(href, label) {
        return `<a href="${String(href).replace(/&/g, "&amp;").replace(/"/g, "&quot;")}" style="text-decoration:none; color:${Theme.primary};">${label}</a>`;
    }

    function authorMarkup(plugin) {
        if (!plugin.author)
            return I18n.tr("by %1", "author attribution").arg(I18n.tr("Unknown", "unknown author"));
        return I18n.tr("by %1", "author attribution").arg(linkMarkup("author:", String(plugin.author).replace(/&/g, "&amp;").replace(/</g, "&lt;")));
    }

    function detailLinksMarkup(plugin) {
        const reportUrl = PluginRanking.issueReportUrl(plugin, {
            "dms": ShellVersionService.shellVersion || DMSService.cliVersion,
            "compositor": rankingCompositor()
        });
        const links = [];
        if (plugin.repo)
            links.push(linkMarkup(plugin.repo, I18n.tr("source", "source code link")));
        if (plugin.issueUrl)
            links.push(linkMarkup(plugin.issueUrl, I18n.tr("discuss", "plugin discussion link")));
        if (reportUrl)
            links.push(linkMarkup(reportUrl, I18n.tr("report a problem", "plugin detail link, opens a prefilled issue")));
        if (PluginRanking.shareUrl(plugin))
            links.push(linkMarkup("copy:", I18n.tr("copy link", "plugin detail link, copies the plugin page address")));
        return links.join(" • ");
    }

    function openDetailLink(plugin, url) {
        if (url === "author:") {
            showAuthor(plugin.author);
            return;
        }
        if (url === "copy:") {
            copyLink(plugin);
            return;
        }
        if (/^https:\/\//.test(url))
            Qt.openUrlExternally(url);
    }

    function formatUpdatedDate(iso) {
        if (!iso)
            return "";
        var date = new Date(iso);
        if (isNaN(date.getTime()))
            return "";
        return date.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }

    function detailMetaBadges(plugin) {
        if (!plugin)
            return [];
        var items = [];
        if (plugin.version)
            items.push({
                label: "v" + plugin.version,
                icon: "sell"
            });
        if (plugin.category)
            items.push({
                label: formatCategoryLabel((plugin.category || "").toLowerCase()),
                icon: "category"
            });
        var updated = formatUpdatedDate(plugin.updated_at);
        if (updated)
            items.push({
                label: updated,
                icon: "history"
            });
        return items;
    }

    function ensureSelectedVisible() {
        if (selectedIndex < 0 || !pluginGrid)
            return;
        pluginGrid.revealIndex(selectedIndex);
    }

    function selectNext() {
        if (detailPluginId !== "" || filteredPlugins.length === 0)
            return;
        if (!keyboardNavigationActive) {
            keyboardNavigationActive = true;
            selectedIndex = 0;
            ensureSelectedVisible();
            return;
        }
        selectedIndex = Math.min(selectedIndex + pluginGrid.columns, filteredPlugins.length - 1);
        ensureSelectedVisible();
    }

    function selectPrevious() {
        if (detailPluginId !== "" || filteredPlugins.length === 0 || !keyboardNavigationActive)
            return;
        var next = selectedIndex - pluginGrid.columns;
        if (next < 0) {
            selectedIndex = -1;
            keyboardNavigationActive = false;
            return;
        }
        selectedIndex = next;
        ensureSelectedVisible();
    }

    function selectStep(delta) {
        if (detailPluginId !== "" || filteredPlugins.length === 0 || !keyboardNavigationActive)
            return;
        selectedIndex = Math.max(0, Math.min(selectedIndex + delta, filteredPlugins.length - 1));
        ensureSelectedVisible();
    }

    function setThirdPartyVisible(show) {
        if (!show) {
            SessionData.setShowThirdPartyPlugins(false);
            updateFilteredPlugins();
            return;
        }
        thirdPartyConfirm.showWithOptions({
            title: I18n.tr("Third-Party Plugin Warning"),
            message: I18n.tr("Third-party plugins are created by the community and are not officially supported by %1.\n\nThese plugins may pose security and privacy risks - install at your own risk.", "third-party plugin warning, %1 is the product name").arg("Dux Shell"),
            confirmText: I18n.tr("I Understand"),
            cancelText: I18n.tr("Cancel"),
            onConfirm: () => {
                SessionData.setShowThirdPartyPlugins(true);
                root.updateFilteredPlugins();
            }
        });
    }

    function installPlugin(pluginId, pluginName, enableAfterInstall) {
        if (PluginService.installingPlugins[pluginId])
            return;
        operationFailed = false;
        operationPending = true;
        operationMessage = I18n.tr("Installing: %1", "installation progress").arg(pluginName);
        PluginService.installFromRegistry(pluginId, pluginName, enableAfterInstall, (success, error) => {
            operationPending = false;
            operationFailed = !success;
            operationMessage = success ? I18n.tr("Installed: %1", "installation success").arg(pluginName) : error;
            if (!success)
                return;
            pendingRevealPluginId = pluginId;
            searchQuery = "";
            typeFilters = [];
            categoryFilter = "all";
            detailPluginId = "";
            SessionData.setPluginBrowserHideInstalled(false);
            refreshPlugins();
        });
    }

    function refreshPlugins() {
        isLoading = true;
        loadError = "";
        DMSService.listPlugins(response => {
            isLoading = false;
            if (!visible)
                return;
            if (response.error) {
                loadError = response.error;
                return;
            }
            allPlugins = response.result || [];
            updateFilteredPlugins();
        });
        if (DMSService.apiVersion >= 8)
            DMSService.listInstalled();
    }

    function checkPendingInstall() {
        if (!PopoutService.pendingPluginInstall || pendingInstallHandled)
            return;
        pendingInstallHandled = true;
        var pluginId = PopoutService.pendingPluginInstall;
        PopoutService.pendingPluginInstall = "";
        installConfirm.showWithOptions({
            "title": I18n.tr("Install Plugin", "plugin installation dialog title"),
            "message": I18n.tr("Install plugin '%1' from the DMS registry?", "plugin installation confirmation").arg(pluginId),
            "confirmText": I18n.tr("Install", "install action button"),
            "cancelText": I18n.tr("Cancel"),
            "onConfirm": () => installPlugin(pluginId, pluginId, true),
            "onCancel": () => hide()
        });
    }

    objectName: "pluginBrowser"
    title: I18n.tr("Browse plugins", "plugin browser window title")
    headerTitle: I18n.tr("Browse plugins")
    searchPlaceholder: I18n.tr("Search plugins...", "plugin search placeholder")

    function pendingInstallId() {
        return PopoutService.pendingPluginInstall || "";
    }

    function refresh() {
        refreshPlugins();
    }

    function applySearch() {
        updateFilteredPlugins();
    }

    function resetContent() {
        allPlugins = [];
        filteredPlugins = [];
        discoverPicks = [];
        discoverShelves = [];
        loadError = "";
        detailPluginId = "";
    }

    function handleEscape() {
        if (detailPluginId !== "") {
            closePluginDetail();
            return;
        }
        hide();
    }

    function activateSelected() {
        if (detailPluginId !== "" || !keyboardNavigationActive || selectedIndex < 0)
            return false;
        openPluginDetail(filteredPlugins[selectedIndex]);
        return true;
    }

    Connections {
        target: DMSService

        function onInstalledPluginsReceived(plugins) {
            if (!root.visible)
                return;
            const selectedPluginId = root.pendingRevealPluginId || root.filteredPlugins[root.selectedIndex]?.id;
            var pluginMap = {};
            for (var i = 0; i < plugins.length; i++) {
                var plugin = plugins[i];
                if (plugin.id)
                    pluginMap[plugin.id] = true;
                if (plugin.name)
                    pluginMap[plugin.name] = true;
            }
            var updated = root.allPlugins.map(p => {
                var isInstalled = pluginMap[p.name] || pluginMap[p.id] || false;
                return Object.assign({}, p, {
                    "installed": isInstalled
                });
            });
            root.allPlugins = updated;
            root.updateFilteredPlugins();
            if (!selectedPluginId)
                return;
            root.pendingRevealPluginId = selectedPluginId;
            revealTimer.restart();
        }
    }

    aboveSearch: [
        SettingsToggleRow {
            id: thirdPartyControl
            anchors.left: parent.left
            anchors.right: parent.right
            text: I18n.tr("Third-party plugins", "community plugin discovery control")
            description: I18n.tr("Discover community plugins. Review their code before installing, and audit changes before updating.", "community plugin safety guidance")
            checked: SessionData.showThirdPartyPlugins
            iconName: "extension"
            onToggled: show => root.setThirdPartyVisible(show)
        },
        DCard {
            id: operationStatus
            readonly property color statusColor: root.operationFailed ? Theme.onErrorContainer : contentColor
            anchors.left: parent.left
            anchors.right: parent.right
            height: visible ? implicitHeight : 0
            implicitHeight: statusContent.implicitHeight + pad * 2
            visible: root.operationMessage !== ""
            tone: "primary"
            pad: Theme.spacingM
            color: root.operationFailed ? Theme.errorContainer : SettingsMetrics.rowColor
            Accessible.name: root.operationMessage

            RowLayout {
                id: statusContent
                anchors.fill: parent
                spacing: Theme.spacingS

                DIcon {
                    name: root.operationFailed ? "error" : root.operationPending ? "downloading" : "check_circle"
                    size: Theme.iconSize
                    color: operationStatus.statusColor
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.operationMessage
                    color: operationStatus.statusColor
                    wrapMode: Text.Wrap
                }
            }
        }
    ]

    belowSearch: [
        Column {
            id: sortControlsRow
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Theme.spacingS

            DFilterChips {
                width: parent.width
                model: root.sortChipOptions.slice(2)
                currentIndex: Math.max(0, model.findIndex(option => option.id === root.normalizedSortMode(SessionData.pluginBrowserSortMode)))
                onSelectionChanged: index => {
                    const mode = model[index].id;
                    if (mode !== "category")
                        root.categoryFilter = "all";
                    SessionData.setPluginBrowserSortMode(mode);
                    root.updateFilteredPlugins();
                }
            }
            DFilterChips {
                width: parent.width
                model: root.sortChipOptions.slice(0, 2).map(option => ({
                            label: option.label,
                            value: option.id
                        })).concat(root.quickFilterOptions)
                multiSelect: true
                selectedValues: [SessionData.pluginBrowserHideInstalled ? "hideInstalled" : "", SessionData.pluginBrowserInstalledFirst ? "installed" : ""].concat(Object.keys(root.quickFilters).filter(key => root.quickFilters[key]))
                onSelectionToggled: (index, selected) => {
                    if (index === 0) {
                        SessionData.setPluginBrowserHideInstalled(selected);
                    } else if (index === 1) {
                        SessionData.setPluginBrowserInstalledFirst(selected);
                    } else {
                        var next = Object.assign({}, root.quickFilters);
                        next[model[index].value] = selected;
                        root.quickFilters = next;
                    }
                    root.updateFilteredPlugins();
                }
            }
            DFilterChips {
                width: parent.width
                model: root.typeFilterOptions
                multiSelect: true
                selectedValues: root.typeFilters
                onSelectionToggled: (index, selected) => {
                    var value = model[index].value;
                    root.typeFilters = selected ? root.typeFilters.concat([value]) : root.typeFilters.filter(type => type !== value);
                    root.updateFilteredPlugins();
                }
            }
            DButton {
                visible: root.authorFilter !== ""
                text: I18n.tr("Plugins by %1", "plugin browser author filter, %1 is the author").arg(root.authorFilter)
                iconName: "close"
                backgroundColor: Theme.primaryContainer
                textColor: Theme.onPrimaryContainer
                tooltipText: I18n.tr("Show every author", "plugin browser, clears the author filter")
                Accessible.name: tooltipText
                onClicked: root.showAuthor("")
            }
        },
        Item {
            id: categoryFiltersRow
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.showCategoryFilters ? Theme.buttonHeightS : 0
            visible: root.showCategoryFilters
            clip: true

            RowLayout {
                anchors.fill: parent
                spacing: Theme.spacingS

                StyledText {
                    id: categoryFilterLabel
                    text: I18n.tr("Filter", "plugin browser category filter label")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onSurfaceVariant
                    Layout.alignment: Qt.AlignVCenter
                }

                DDropdown {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.buttonHeightS
                    backgroundColor: SettingsMetrics.controlSurface
                    compactMode: true
                    dropdownWidth: Math.max(Theme.smallBreakpoint / 2, categoryFiltersRow.width - categoryFilterLabel.implicitWidth - Theme.spacingS * 3)
                    currentValue: root.categoryFilterLabelForKey(root.categoryFilter)
                    options: root.categoryFilterDropdownLabels()
                    onValueChanged: value => {
                        var nextKey = root.categoryFilterKeyForLabel(value);
                        if (nextKey === root.categoryFilter)
                            return;
                        root.categoryFilter = nextKey;
                        root.updateFilteredPlugins();
                    }
                }
            }
        }
    ]

    listContent: [
        DGridView {
            id: pluginGrid

            property int columns: Math.max(1, Math.floor(width / (Theme.smallBreakpoint / 2 + Theme.spacingXL * 2)))
            readonly property real cardSpacing: Theme.spacingM
            readonly property int previewHeight: Math.round((cellWidth - cardSpacing - Theme.spacingS * 2) * SettingsMetrics.choiceCardPreviewRatio)
            readonly property int infoHeight: Theme.iconButtonSize + Theme.fontSizeSmall * 4 + Theme.spacingS

            anchors.fill: parent
            anchors.rightMargin: root.showLetterIndex ? Theme.iconButtonSize : 0
            cellWidth: Math.floor(width / columns)
            cellHeight: previewHeight + infoHeight + Math.round(cardSpacing) + Theme.spacingS * 2 + Theme.spacingM
            model: root.filteredPlugins
            clip: true
            visible: !root.isLoading && root.loadError === ""
            cacheBuffer: cellHeight * 2

            header: Item {
                width: pluginGrid.width
                height: root.discoverVisible ? discover.height + Theme.spacingM : 0
                visible: root.discoverVisible

                PluginDiscover {
                    id: discover
                    x: pluginGrid.cardSpacing / 2
                    width: pluginGrid.cellWidth * pluginGrid.columns - pluginGrid.cardSpacing
                    picks: root.discoverPicks
                    shelves: root.discoverShelves
                    columns: pluginGrid.columns
                    cardSpacing: pluginGrid.cardSpacing
                    onPluginOpened: plugin => root.openPluginDetail(plugin)
                    onInstallRequested: plugin => root.installPlugin(plugin.id, plugin.name, plugin.type === "desktop")
                }
            }

            delegate: Item {
                id: cardCell

                required property var modelData
                required property int index
                readonly property Item focusTarget: pluginCard.focusTarget

                width: pluginGrid.cellWidth
                height: pluginGrid.cellHeight

                PluginCard {
                    id: pluginCard
                    anchors.fill: parent
                    anchors.margins: pluginGrid.cardSpacing / 2
                    plugin: cardCell.modelData
                    busy: !!PluginService.installingPlugins[cardCell.modelData.id]
                    previewHeight: pluginGrid.previewHeight
                    compositor: root.rankingCompositor()
                    installed: cardCell.modelData.installed || false
                    selected: root.keyboardNavigationActive && cardCell.index === root.selectedIndex
                    onClicked: root.openPluginDetail(cardCell.modelData)
                    onInstallRequested: root.installPlugin(cardCell.modelData.id, cardCell.modelData.name, cardCell.modelData.type === "desktop")
                }
            }
        },
        Grid {
            id: loadingGrid
            anchors.fill: pluginGrid
            columns: pluginGrid.columns
            clip: true
            visible: root.isLoading

            SequentialAnimation on opacity {
                running: loadingGrid.visible && Theme.longDuration > 0
                loops: Animation.Infinite
                onRunningChanged: {
                    if (!running)
                        loadingGrid.opacity = 1;
                }

                NumberAnimation {
                    to: 0.45
                    duration: Theme.longDuration
                    easing.type: Theme.standardEasing
                }
                NumberAnimation {
                    to: 1
                    duration: Theme.longDuration
                    easing.type: Theme.standardEasing
                }
            }

            Repeater {
                model: root.isLoading ? pluginGrid.columns * Math.max(1, Math.ceil(pluginGrid.height / pluginGrid.cellHeight)) : 0

                Item {
                    width: pluginGrid.cellWidth
                    height: pluginGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: pluginGrid.cardSpacing / 2
                        radius: Theme.cornerRadiusM
                        color: SettingsMetrics.rowColor
                        border.color: Theme.outlineMedium
                        border.width: Theme.layerOutlineWidth

                        Rectangle {
                            id: ghostPreview
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Theme.spacingS
                            height: pluginGrid.previewHeight
                            radius: Theme.cornerRadiusS
                            color: SettingsMetrics.controlColor
                        }

                        Column {
                            anchors.top: ghostPreview.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.topMargin: Theme.spacingM
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            spacing: Theme.spacingS

                            Repeater {
                                model: [0.55, 0.3, 0.9]

                                Rectangle {
                                    required property real modelData
                                    width: parent.width * modelData
                                    height: Theme.fontSizeSmall
                                    radius: height / 2
                                    color: SettingsMetrics.controlColor
                                }
                            }
                        }
                    }
                }
            }
        },
        DFlickable {
            id: letterIndex
            anchors.right: parent.right
            anchors.top: pluginGrid.top
            anchors.bottom: pluginGrid.bottom
            width: Theme.iconButtonSize
            visible: root.showLetterIndex && !root.isLoading && root.loadError === ""
            contentHeight: letterColumn.implicitHeight
            clip: true

            Column {
                id: letterColumn
                width: parent.width
                Repeater {
                    model: root.availableLetters

                    DButton {
                        required property string modelData
                        width: letterIndex.width
                        minimumWidth: 0
                        horizontalPadding: 0
                        buttonHeight: Theme.buttonHeightXS
                        text: modelData
                        backgroundColor: SettingsMetrics.controlSurface
                        textColor: Theme.onSurfaceVariant
                        onClicked: root.scrollToLetter(modelData)
                    }
                }
            }
        },
        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingS
            visible: !root.isLoading && root.loadError === "" && root.filteredPlugins.length === 0

            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "search_off"
                size: Theme.iconButtonSize
                color: Theme.onSurfaceVariant
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("No plugins found", "empty plugin list")
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.searchSuggestions.length > 0
                text: I18n.tr("Did you mean", "plugin search, introduces plugins with a close name")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingXS
                visible: root.searchSuggestions.length > 0

                Repeater {
                    model: root.searchSuggestions

                    DButton {
                        required property var modelData
                        text: modelData.name || modelData.id
                        iconName: modelData.icon || "extension"
                        backgroundColor: Theme.secondaryContainer
                        textColor: Theme.onSecondaryContainer
                        onClicked: root.openPluginDetail(modelData)
                    }
                }
            }
        },
        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingS
            visible: !root.isLoading && root.loadError !== ""
            width: parent.width

            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "cloud_off"
                size: Theme.iconButtonSize
                color: Theme.onSurfaceVariant
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Couldn't load plugins", "plugin registry fetch error")
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.loadError
                width: parent.width
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.onSurfaceVariant
            }

            DButton {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Retry", "retry failed action button")
                iconName: "refresh"
                backgroundColor: SettingsMetrics.controlSurface
                textColor: Theme.surfaceText
                onClicked: root.refreshPlugins()
            }
        }
    ]

    overlayActive: detailPluginId !== ""

    overlay: Item {
        id: detailPane

        property var plugin: ({})
        property bool heroFallback: false
        readonly property var livePlugin: root.detailPlugin

        onLivePluginChanged: {
            if (!livePlugin)
                return;
            plugin = livePlugin;
        }

        anchors.fill: parent

        Connections {
            target: root
            function onDetailPluginIdChanged() {
                detailPane.heroFallback = false;
                detailFlickable.contentY = 0;
                // Each opened detail looks again, so a program installed meanwhile is found.
                root.foundCommands = [];
                root.checkedCommands = [];
                root.checkDependencies(root.detailPlugin);
            }
            // On the plugin itself, not its id: a detail opened before the list loads is checked once it arrives.
            function onDetailPluginChanged() {
                root.checkDependencies(root.detailPlugin);
            }
        }

        Rectangle {
            id: detailDialog
            anchors.centerIn: parent
            width: Math.min(SettingsMetrics.mediaMaxWidth + PopoutMetrics.contentPadding * 2, parent.width - Theme.spacingL * 2)
            height: Math.min(parent.height - Theme.spacingL * 2, detailHeader.height + detailColumn.height + detailActions.height + PopoutMetrics.contentGap * 2 + PopoutMetrics.contentPadding * 2)
            radius: Theme.windowRadius
            color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
            border.color: Theme.outlineMedium
            border.width: Theme.layerOutlineWidth

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
            }

            Item {
                id: detailHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: PopoutMetrics.contentPadding
                height: Math.max(detailIcon.height, detailCloseButton.height, detailTitleColumn.implicitHeight)

                DIcon {
                    id: detailIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    name: detailPane.plugin.icon || "extension"
                    size: Theme.iconSizeLarge
                    color: Theme.primary
                }

                Column {
                    id: detailTitleColumn
                    anchors.left: detailIcon.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: detailCloseButton.left
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXXS

                    StyledText {
                        width: parent.width
                        text: detailPane.plugin.name || ""
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    StyledText {
                        width: parent.width
                        text: root.authorMarkup(detailPane.plugin)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant
                        linkColor: Theme.primary
                        textFormat: Text.RichText
                        onLinkActivated: url => root.openDetailLink(detailPane.plugin, url)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }

                DActionButton {
                    id: detailCloseButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: Theme.buttonHeightXS
                    iconSize: Theme.iconSizeSmall
                    iconName: "close"
                    backgroundColor: Theme.secondaryContainer
                    iconColor: Theme.onSecondaryContainer
                    Accessible.name: I18n.tr("Close")
                    onClicked: root.closePluginDetail()
                }
            }

            Row {
                id: detailActions
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: PopoutMetrics.contentPadding
                spacing: Theme.spacingS

                DButton {
                    id: detailUpvoteButton
                    visible: !!detailPane.plugin.issueUrl
                    readonly property bool upvoted: !!PluginService.upvotedPlugins[detailPane.plugin.id]
                    text: PluginService.upvoteCount(detailPane.plugin)
                    iconName: "thumb_up"
                    enabled: !PluginService.upvotingPlugins[detailPane.plugin.id]
                    backgroundColor: upvoted ? Theme.primaryContainer : SettingsMetrics.controlSurface
                    textColor: upvoted ? Theme.onPrimaryContainer : Theme.surfaceText
                    tooltipText: upvoted ? I18n.tr("Remove upvote", "plugin upvote button tooltip") : I18n.tr("Upvote on GitHub", "plugin upvote button tooltip")
                    Accessible.name: tooltipText
                    onClicked: PluginService.upvotePlugin(detailPane.plugin)
                }

                DButton {
                    id: detailInstallButton
                    readonly property bool compatible: PluginService.checkPluginCompatibility(detailPane.plugin.requires_dms)
                    text: detailPane.plugin.installed ? I18n.tr("Installed", "adjective, plugin or theme is already installed, button state and filter chip") : compatible ? I18n.tr("Install") : I18n.tr("Requires %1", "version requirement").arg(detailPane.plugin.requires_dms || "")
                    iconName: detailPane.plugin.installed ? "check" : "download"
                    enabled: !detailPane.plugin.installed && compatible && !PluginService.installingPlugins[detailPane.plugin.id]
                    onClicked: root.installPlugin(detailPane.plugin.id, detailPane.plugin.name, detailPane.plugin.type === "desktop")
                }
            }

            DFlickable {
                id: detailFlickable
                anchors.top: detailHeader.bottom
                anchors.bottom: detailActions.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: PopoutMetrics.contentGap
                anchors.bottomMargin: PopoutMetrics.contentGap
                anchors.leftMargin: PopoutMetrics.contentPadding
                anchors.rightMargin: PopoutMetrics.contentPadding
                clip: true
                contentHeight: detailColumn.height
                contentWidth: width

                Column {
                    id: detailColumn
                    width: parent.width
                    spacing: Theme.spacingL

                    Rectangle {
                        width: parent.width
                        height: Math.round(width * SettingsMetrics.choiceCardPreviewRatio)
                        radius: Theme.cornerRadiusM
                        color: SettingsMetrics.rowColor
                        border.color: Theme.outlineMedium
                        border.width: Theme.layerOutlineWidth

                        ClippingRectangle {
                            anchors.fill: parent
                            anchors.margins: Theme.outlineWidth
                            radius: Theme.cornerRadiusM - Theme.outlineWidth
                            color: "transparent"

                            CachingImage {
                                id: heroImage
                                anchors.fill: parent
                                imagePath: detailPane.heroFallback ? PluginService.previewUrl(detailPane.plugin) : PluginService.heroUrl(detailPane.plugin)
                                maxCacheSize: 1600
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                                onStatusChanged: {
                                    if (status !== Image.Error || detailPane.heroFallback)
                                        return;
                                    detailPane.heroFallback = true;
                                }
                            }
                        }

                        DSpinner {
                            anchors.centerIn: parent
                            running: heroImage.status === Image.Loading
                            visible: running
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS
                            visible: heroImage.imagePath.length === 0 || heroImage.status === Image.Error

                            DIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                name: "image_not_supported"
                                size: Theme.iconSizeLarge
                                color: Theme.onSurfaceVariant
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: heroImage.status === Image.Error ? I18n.tr("Screenshot unavailable", "plugin browser screenshot error") : I18n.tr("No screenshot provided", "plugin browser no screenshot")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.onSurfaceVariant
                            }
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.spacingXS

                        Repeater {
                            model: PluginService.badgeModel(detailPane.plugin)

                            PluginBadge {
                                required property var modelData
                                label: modelData.label
                                iconName: modelData.icon
                                tone: PluginService.badgeTone(modelData.tone)
                            }
                        }

                        Repeater {
                            model: root.detailMetaBadges(detailPane.plugin)

                            PluginBadge {
                                required property var modelData
                                label: modelData.label
                                iconName: modelData.icon
                                tone: Theme.outline
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: root.detailLinksMarkup(detailPane.plugin)
                        visible: text !== ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant
                        linkColor: Theme.primary
                        textFormat: Text.RichText
                        wrapMode: Text.WordWrap
                        onLinkActivated: url => root.openDetailLink(detailPane.plugin, url)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                            acceptedButtons: Qt.NoButton
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: detailPane.plugin.description || ""
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                        visible: (detailPane.plugin.description || "").length > 0
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: (detailPane.plugin.capabilities || []).length > 0

                        StyledText {
                            text: I18n.tr("Capabilities", "plugin detail section")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceVariantText
                        }

                        Flow {
                            width: parent.width
                            spacing: Theme.spacingXS

                            Repeater {
                                model: detailPane.plugin.capabilities || []

                                PluginBadge {
                                    required property string modelData
                                    label: modelData
                                    tone: Theme.primary
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: (detailPane.plugin.permissions || []).length > 0

                        StyledText {
                            width: parent.width
                            text: I18n.tr("Declared by the author, not enforced", "plugin detail section, introduces the permission list the plugin declares about itself")
                            wrapMode: Text.WordWrap
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceVariantText
                        }

                        Repeater {
                            model: PluginRanking.sortPermissions(detailPane.plugin.permissions)

                            Row {
                                id: permissionRow
                                required property string modelData
                                readonly property bool sensitive: PluginRanking.permissionIsSensitive(modelData)
                                width: parent.width
                                spacing: Theme.spacingS

                                DIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: root.permissionIcon(permissionRow.modelData)
                                    size: Theme.iconSizeSmall
                                    color: permissionRow.sensitive ? Theme.warning : Theme.surfaceVariantText
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - Theme.iconSizeSmall - Theme.spacingS
                                    text: root.permissionLabel(permissionRow.modelData)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: permissionRow.sensitive ? Theme.surfaceText : Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: (detailPane.plugin.dependencies || []).length > 0

                        StyledText {
                            text: I18n.tr("Needs", "plugin detail section, introduces the programs a plugin depends on")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceVariantText
                        }

                        Flow {
                            width: parent.width
                            spacing: Theme.spacingXS

                            Repeater {
                                model: PluginRanking.dependencyStates(detailPane.plugin.dependencies, root.foundCommands, root.checkedCommands)

                                PluginBadge {
                                    required property var modelData
                                    label: modelData.state === "missing" ? I18n.tr("%1 not found", "plugin dependency missing, %1 is a program name").arg(modelData.name) : modelData.name
                                    iconName: modelData.state === "ok" ? "check_circle" : modelData.state === "missing" ? "warning" : "package_2"
                                    tone: modelData.state === "ok" ? Theme.primary : modelData.state === "missing" ? Theme.warning : Theme.outline
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: root.relatedPlugins(detailPane.plugin).length > 0

                        StyledText {
                            text: I18n.tr("Related: %1", "related plugins").arg("").trim()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceVariantText
                        }

                        Flow {
                            width: parent.width
                            spacing: Theme.spacingXS

                            Repeater {
                                model: root.relatedPlugins(detailPane.plugin)

                                DButton {
                                    required property var modelData
                                    text: modelData.name
                                    iconName: "extension"
                                    buttonHeight: Theme.buttonHeightXS
                                    backgroundColor: Theme.secondaryContainer
                                    textColor: Theme.onSecondaryContainer
                                    enabled: modelData.key !== ""
                                    onClicked: root.detailPluginId = modelData.key
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ConfirmDialogOverlay {
        id: thirdPartyConfirm
        onDialogClosed: root.focusSearch()
    }
}
