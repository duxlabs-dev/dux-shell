pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../../Common/QmlUtils.js" as QmlUtils
import qs.Modals.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var parentModal: null
    property bool _pluginBrowserShowQueued: false

    property string searchQuery: ""
    property string filterOverride: ""
    readonly property var filterKeys: ["all", "enabled", "disabled", "updates"]
    readonly property int filterIndex: filterKeys.indexOf(filterOverride || CacheData.pluginViewFilter)
    property string actionError: ""
    readonly property bool checkingUpdates: DMSService.checkingPluginUpdates
    readonly property var sortKeys: ["name", "author", "modified"]
    readonly property int sortIndex: sortKeys.indexOf(CacheData.pluginViewSort.by)
    readonly property bool descending: CacheData.pluginViewSort.descending
    property var uninstalling: ({})
    property var uninstallErrors: ({})
    property var updateErrors: ({})
    property string updatingPluginId: ""
    readonly property string pendingRevealPluginId: PluginService.pendingSettingsRevealPluginId
    readonly property var sortOptions: [I18n.tr("Name"), I18n.tr("Author", "installed plugins sort option, plugin author"), I18n.tr("Last modified", "plugin directory modification time")]
    readonly property var filterOptions: [I18n.tr("All"), I18n.tr("Enabled"), I18n.tr("Disabled"), I18n.tr("Update available", "plugin row badge")]

    FontMetrics {
        id: pluginTitleMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
    }

    FontMetrics {
        id: pluginDescriptionMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    readonly property var filteredPlugins: plugins.filter(row => {
        const loaded = PluginService.loadedPlugins[row.pluginId] !== undefined;
        if (filterIndex === 1 && !loaded)
            return false;
        if (filterIndex === 2 && loaded)
            return false;
        if (filterIndex === 3 && !hasUpdate(row))
            return false;
        const plugin = PluginService.availablePlugins[row.pluginId];
        return [row.text, row.hint, plugin?.author, row.pluginId].join(" ").toLowerCase().includes(searchQuery.trim().toLowerCase());
    }).sort((a, b) => {
        let comparison = 0;
        switch (sortIndex) {
        case 1:
            comparison = (PluginService.availablePlugins[a.pluginId]?.author || "").localeCompare(PluginService.availablePlugins[b.pluginId]?.author || "");
            break;
        case 2:
            comparison = modifiedAt(a) - modifiedAt(b);
            break;
        default:
            comparison = a.text.localeCompare(b.text);
        }
        if (comparison !== 0)
            return descending ? -comparison : comparison;
        return a.text.localeCompare(b.text) || a.pluginId.localeCompare(b.pluginId);
    })

    readonly property var plugins: SettingsTabs.pluginHubRows
    readonly property var updateCheckErrors: (DMSService.installedPlugins || []).filter(plugin => plugin.updateError).reduce((errors, plugin) => {
        errors[plugin.id] = plugin.updateError;
        return errors;
    }, {})
    readonly property var pluginsWithUpdates: (DMSService.installedPlugins || []).filter(plugin => plugin.hasUpdate === true)
    readonly property var incompatiblePlugins: {
        PluginService.loadedPlugins;
        ShellVersionService.semverVersion;
        return PluginService.getIncompatiblePlugins();
    }

    width: parent?.width ?? 0
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true
    spacing: Theme.spacingL

    onPendingRevealPluginIdChanged: revealTimer.restart()
    onVisibleChanged: {
        if (!visible)
            filterOverride = "";
    }

    Component.onCompleted: {
        revealTimer.restart();
        if (DMSService.dmsAvailable && DMSService.apiVersion >= 8)
            DMSService.listInstalled();
        if (PopoutService.pendingPluginInstall)
            Qt.callLater(showPluginBrowser);
    }

    function revealPlugin(pluginId) {
        PluginService.pendingSettingsRevealPluginId = pluginId;
        revealTimer.restart();
    }

    function setFilter(index) {
        if (index < 0 || index >= filterKeys.length)
            return;
        CacheData.set("pluginViewFilter", filterKeys[index]);
        filterOverride = "";
    }

    Timer {
        id: revealTimer
        interval: 0
        onTriggered: {
            if (!root.visible || !root.pendingRevealPluginId || pluginBrowserLoader.item?.visible)
                return;
            if (!PluginService.availablePlugins[root.pendingRevealPluginId])
                return;
            root.searchQuery = "";
            root.filterOverride = "all";
            const key = "installedPlugin:" + root.pendingRevealPluginId;
            const entry = SettingsSearchService.registeredCards[key];
            if (!entry)
                return;
            SettingsSearchService.navigateToSection(key);
            entry.item.focusTarget.forceActiveFocus(Qt.TabFocusReason);
            PluginService.pendingSettingsRevealPluginId = "";
        }
    }

    function requestUpdate(row) {
        if (updatingPluginId || pluginUpdatesDialogItem.isUpdating || uninstalling[row.pluginId])
            return;
        const plugin = DMSService.installedPlugins.find(plugin => plugin.id === row.pluginId || plugin.name === row.text);
        confirmUpdates([plugin || {
                id: row.pluginId,
                name: row.text
            }]);
    }

    function confirmUpdates(plugins) {
        if (!plugins.length || updatingPluginId || pluginUpdatesDialogItem.isUpdating || Object.keys(uninstalling).length)
            return;
        const single = plugins.length === 1;
        updateConfirm.showWithOptions({
            title: single ? I18n.tr("Update %1?", "plugin update confirmation").arg(plugins[0].name) : I18n.tr("Update All"),
            message: I18n.tr("Plugin updates can change the code running in your session. Review the changes before updating.", "plugin update audit reminder"),
            reviewUrl: single ? plugins[0].diffUrl || plugins[0].repo || "" : "",
            confirmText: single ? I18n.tr("Update") : I18n.tr("Update All"),
            onConfirm: () => {
                if (single) {
                    updatePlugin({
                        pluginId: plugins[0].id,
                        text: plugins[0].name
                    });
                    return;
                }
                pluginUpdatesDialogItem.updatePlugins(plugins);
            }
        });
    }

    ConfirmDialogOverlay {
        id: updateConfirm
        parent: root.parentModal?.modalFocusScope ?? root.parent
    }

    function updatePlugin(row) {
        if (updatingPluginId || pluginUpdatesDialogItem.isUpdating || uninstalling[row.pluginId])
            return;
        const id = row.pluginId;
        updatingPluginId = id;
        updateErrors = Object.assign({}, updateErrors, {
            [id]: ""
        });
        PluginService.updatePlugin(id, response => {
            updatingPluginId = "";
            if (response.error) {
                updateErrors = Object.assign({}, updateErrors, {
                    [id]: response.error
                });
                revealPlugin(id);
                return;
            }
            pluginUpdatesDialogItem.updatesList = pluginUpdatesDialogItem.updatesList.filter(plugin => plugin.id !== id);
            revealPlugin(id);
        });
    }

    function setSort(index) {
        if (index < 0 || index >= sortKeys.length)
            return;
        CacheData.set("pluginViewSort", {
            by: sortKeys[index],
            descending: index === sortIndex ? descending : index === 2
        });
    }

    function modifiedAt(row) {
        const directory = PluginService.availablePlugins[row.pluginId]?.pluginDirectory;
        return PluginService.directoryModifiedTimes[directory] || 0;
    }

    function checkUpdates() {
        if (!DMSService.dmsAvailable || DMSService.apiVersion < 8)
            return;
        actionError = "";
        DMSService.listInstalled(undefined, true);
    }

    function requestUninstall(row) {
        if (uninstalling[row.pluginId] || updatingPluginId || pluginUpdatesDialogItem.isUpdating)
            return;
        uninstallConfirm.showWithOptions({
            title: I18n.tr("Uninstall"),
            message: I18n.tr("Uninstall %1?", "plugin removal confirmation").arg(row.text),
            confirmText: I18n.tr("Uninstall"),
            confirmColor: Theme.error,
            onConfirm: () => uninstall(row)
        });
    }

    function uninstall(row) {
        const id = row.pluginId;
        const wasEnabled = PluginService.isPluginLoaded(id);
        const repo = DMSService.installedPlugins.find(entry => entry.id === id)?.repo ?? "";
        uninstalling = Object.assign({}, uninstalling, {
            [id]: true
        });
        uninstallErrors = Object.assign({}, uninstallErrors, {
            [id]: ""
        });
        DMSService.uninstall(id, response => {
            const pending = Object.assign({}, uninstalling);
            delete pending[id];
            uninstalling = pending;
            if (response.error) {
                uninstallErrors = Object.assign({}, uninstallErrors, {
                    [id]: response.error
                });
                return;
            }
            PluginService.scanPlugins();
            PluginService.noteUninstalled(id, row.text, wasEnabled, repo);
        });
    }

    ConfirmDialogOverlay {
        id: uninstallConfirm
        parent: root.parentModal?.modalFocusScope ?? root.parent
    }

    function showPluginBrowser() {
        pluginBrowserLoader.active = true;
        if (pluginBrowserLoader.item) {
            pluginBrowserLoader.item.show();
            return;
        }
        _pluginBrowserShowQueued = true;
    }

    function hasUpdate(row) {
        return pluginsWithUpdates.some(plugin => plugin.id === row.pluginId || plugin.name === row.text);
    }

    function setEnabled(row, enabled) {
        actionError = "";
        if (enabled) {
            PluginService.enablePlugin(row.pluginId, ok => {
                if (ok)
                    return;
                const error = PluginService.pluginLoadErrors[row.pluginId];
                actionError = error ? [error.title, error.details].filter(Boolean).join("\n") : I18n.tr("Failed to enable plugin: %1").arg(row.text);
            });
            return;
        }
        if (!PluginService.disablePlugin(row.pluginId))
            actionError = I18n.tr("Failed to disable plugin: %1").arg(row.text);
    }

    Connections {
        target: PluginService

        function onRegistryInstallFinished(pluginId, success) {
            if (success || PluginService.availablePlugins[pluginId])
                root.revealPlugin(pluginId);
        }

        function onPluginListUpdated() {
            revealTimer.restart();
        }
    }

    Connections {
        target: PopoutService

        function onPendingPluginInstallChanged() {
            if (PopoutService.pendingPluginInstall)
                root.showPluginBrowser();
        }
    }

    Connections {
        target: pluginBrowserLoader.item
        function onVisibleChanged() {
            if (!pluginBrowserLoader.item.visible)
                revealTimer.restart();
        }
    }

    Connections {
        target: pluginBrowserLoader

        function onItemChanged() {
            if (!root._pluginBrowserShowQueued || !pluginBrowserLoader.item)
                return;
            root._pluginBrowserShowQueued = false;
            pluginBrowserLoader.item.show();
        }
    }

    LazyLoader {
        id: pluginBrowserLoader
        active: false

        PluginBrowser {
            id: pluginBrowserItem

            Component.onCompleted: {
                pluginBrowserItem.parentModal = root.parentModal;
            }
        }
    }

    PluginUpdatesDialog {
        id: pluginUpdatesDialogItem
        width: parent.width
        operationsBlocked: Object.keys(root.uninstalling).length > 0 || root.updatingPluginId !== ""
        onUpdatesRequested: plugins => root.confirmUpdates(plugins)
        onPluginUpdated: pluginId => root.revealPlugin(pluginId)
    }

    SettingsCard {
        settingKey: "pluginManagerUnavailable"
        visible: !DMSService.dmsAvailable

        SettingsRow {
            iconName: "warning"
            title: I18n.tr("Plugin manager unavailable")
            subtitle: I18n.tr("The %1 environment variable is not set or the socket is unavailable. Automated plugin management requires it.", "plugin manager unavailable notice, %1 is an environment variable").arg("DMS_SOCKET")
        }
    }

    SettingsCard {
        settingKey: "pluginsIncompatible"
        visible: root.incompatiblePlugins.length > 0

        SettingsRow {
            iconName: "error"
            title: I18n.tr("Incompatible plugins loaded")
            subtitle: I18n.tr("Some plugins require a newer version of DMS:") + " " + root.incompatiblePlugins.map(plugin => plugin.name + " (" + plugin.requires_dms + ")").join(", ")
            subtitleColor: Theme.error
        }
    }

    RowLayout {
        width: parent.width
        spacing: Theme.spacingS
        visible: root.plugins.length > 0

        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            spacing: Theme.spacingS

            DButton {
                text: root.pluginsWithUpdates.length ? I18n.tr("Update All") + " (" + root.pluginsWithUpdates.length + ")" : I18n.tr("Check for updates")
                iconName: root.pluginsWithUpdates.length ? "download" : "refresh"
                busy: root.checkingUpdates || pluginUpdatesDialogItem.isUpdating
                backgroundColor: Theme.secondaryContainer
                textColor: Theme.onSecondaryContainer
                maximumWidth: parent.width
                wrapText: true
                enabled: DMSService.dmsAvailable && !pluginUpdatesDialogItem.isUpdating && !root.updatingPluginId && Object.keys(root.uninstalling).length === 0
                Accessible.description: root.checkingUpdates ? I18n.tr("Checking for updates...") : ""
                onClicked: {
                    if (root.checkingUpdates)
                        return;
                    if (root.pluginsWithUpdates.length) {
                        pluginUpdatesDialogItem.show(root.pluginsWithUpdates);
                        return;
                    }
                    root.checkUpdates();
                }
            }
            DIconButton {
                iconName: "refresh"
                widthMode: "narrow"
                tooltipText: I18n.tr("Check for updates")
                visible: root.pluginsWithUpdates.length > 0
                enabled: DMSService.dmsAvailable && !root.checkingUpdates && !pluginUpdatesDialogItem.isUpdating && !root.updatingPluginId
                onClicked: root.checkUpdates()
            }
        }

        DButton {
            text: I18n.tr("Manage Registries", "plugin registry management")
            buttonHeight: Theme.buttonHeightXS
            horizontalPadding: Theme.spacingS
            backgroundColor: "transparent"
            textColor: Theme.primary
            maximumWidth: root.width / 2
            wrapText: true
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: (Theme.buttonHeightS - Theme.buttonHeightXS) / 2
            onClicked: keyboard => root.parentModal?.navigateTo("plugins_manage", keyboard)
        }
    }

    StyledText {
        width: parent.width
        visible: text !== ""
        text: [root.actionError, DMSService.pluginUpdateCheckError].filter(Boolean).join("\n")
        color: Theme.error
        wrapMode: Text.Wrap
    }

    DCard {
        color: SettingsMetrics.rowColor
        width: parent.width
        implicitHeight: undoRow.implicitHeight + pad * 2
        visible: PluginService.lastUninstalledPlugin !== null && DMSService.dmsAvailable
        pad: Theme.spacingS

        RowLayout {
            id: undoRow
            width: parent.width
            spacing: Theme.spacingM

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingS
                text: I18n.tr("%1 uninstalled", "plugin removed notice, %1 is the plugin name").arg(PluginService.lastUninstalledPlugin?.name ?? "")
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            DButton {
                text: I18n.tr("Undo", "reinstall the plugin that was just uninstalled")
                buttonHeight: Theme.buttonHeightXS
                horizontalPadding: Theme.spacingS
                backgroundColor: "transparent"
                textColor: Theme.primary
                onClicked: PluginService.undoUninstall()
            }
        }
    }

    DCard {
        id: storeCard
        color: SettingsMetrics.rowColor
        width: parent.width
        implicitHeight: storeContent.implicitHeight + pad * 2
        visible: root.plugins.length === 0
        pad: Theme.spacingL

        ColumnLayout {
            id: storeContent
            width: parent.width
            spacing: Theme.spacingM

            DIcon {
                name: "store"
                size: Theme.iconSizeLarge
                color: storeCard.accentColor
            }
            StyledText {
                Layout.fillWidth: true
                text: I18n.tr("Explore Plugins")
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Theme.fontWeightMedium
                color: storeCard.contentColor
                wrapMode: Text.Wrap
            }
            StyledText {
                Layout.fillWidth: true
                text: I18n.tr("Extend %1 with powerful plugins for widgets, launchers, and more", "plugins hub description, %1 is the product name").arg("Dux Shell")
                color: storeCard.mutedColor
                wrapMode: Text.Wrap
            }
            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                spacing: Theme.spacingS

                DButton {
                    text: I18n.tr("Browse")
                    iconName: "store"
                    backgroundColor: Theme.primary
                    textColor: Theme.onPrimary
                    maximumWidth: parent.width
                    wrapText: true
                    enabled: DMSService.dmsAvailable
                    onClicked: root.showPluginBrowser()
                }
                DButton {
                    text: I18n.tr("Manage Registries", "plugin registry management")
                    backgroundColor: "transparent"
                    textColor: storeCard.accentColor
                    maximumWidth: parent.width
                    wrapText: true
                    onClicked: keyboard => root.parentModal?.navigateTo("plugins_manage", keyboard)
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS
        visible: root.plugins.length > 0

        DSearchField {
            width: parent.width
            text: root.searchQuery
            placeholderText: I18n.tr("Search plugins...", "plugin search placeholder")
            // matches MAX_QUERY_LENGTH in PluginRanking.js
            maximumLength: 100
            onTextEdited: root.searchQuery = text
        }
        Flow {
            width: parent.width
            spacing: Theme.spacingS

            DSplitButton {
                id: filterButton
                text: I18n.tr("Filter") + ": " + root.filterOptions[root.filterIndex]
                iconName: "filter_list"
                size: "xs"
                variant: root.filterIndex > 0 ? "tonal" : "outlined"
                maximumWidth: parent.width
                expanded: filterMenu.menuVisible
                tooltipText: root.filterOptions[(root.filterIndex + 1) % root.filterKeys.length]
                menuTooltipText: I18n.tr("Filter")
                onClicked: root.setFilter((root.filterIndex + 1) % root.filterKeys.length)
                onMenuClicked: {
                    filterMenu.currentValue = root.filterOptions[root.filterIndex];
                    filterMenu.openDropdownMenu();
                }

                DDropdown {
                    id: filterMenu
                    showTrigger: false
                    popupAnchorItem: filterButton.trailingButton
                    focusReturnTarget: filterButton.trailingButton
                    alignPopupRight: !I18n.isRtl
                    popupWidth: Math.min(root.width, Theme.smallBreakpoint / 2)
                    options: root.filterOptions
                    onValueChanged: value => root.setFilter(options.indexOf(value))
                }
            }
            DSplitButton {
                id: sortButton
                text: I18n.tr("Sort by") + ": " + root.sortOptions[root.sortIndex]
                iconName: root.descending ? "arrow_downward" : "arrow_upward"
                size: "xs"
                variant: "tonal"
                maximumWidth: parent.width
                expanded: sortMenu.menuVisible
                tooltipText: root.sortOptions[(root.sortIndex + 1) % root.sortKeys.length]
                menuTooltipText: I18n.tr("Sort by")
                Accessible.description: [root.sortOptions[root.sortIndex], root.descending ? I18n.tr("Descending") : I18n.tr("Ascending")].join(" · ")
                onClicked: root.setSort((root.sortIndex + 1) % root.sortKeys.length)
                onMenuClicked: {
                    sortMenu.currentValue = root.sortOptions[root.sortIndex];
                    sortMenu.openDropdownMenu();
                }

                DDropdown {
                    id: sortMenu
                    showTrigger: false
                    popupAnchorItem: sortButton.trailingButton
                    focusReturnTarget: sortButton.trailingButton
                    alignPopupRight: !I18n.isRtl
                    popupWidth: Math.min(root.width, Theme.smallBreakpoint / 2)
                    options: root.sortOptions.concat([I18n.tr("Ascending"), I18n.tr("Descending")])
                    optionIcons: ["sort_by_alpha", "person", "schedule", root.descending ? "arrow_upward" : "check", root.descending ? "check" : "arrow_downward"]
                    onValueChanged: value => {
                        const index = options.indexOf(value);
                        if (index < 0)
                            return;
                        if (index < root.sortKeys.length) {
                            root.setSort(index);
                            return;
                        }
                        CacheData.set("pluginViewSort", {
                            by: root.sortKeys[root.sortIndex],
                            descending: index === root.sortKeys.length + 1
                        });
                    }
                }
            }
        }
    }

    StyledText {
        width: parent.width
        visible: root.plugins.length > 0 && root.filteredPlugins.length === 0
        text: I18n.tr("No plugins found", "empty plugin list")
        color: Theme.onSurfaceVariant
        wrapMode: Text.Wrap
    }

    GridLayout {
        id: installedGrid
        width: parent.width
        columns: width >= Theme.mediumBreakpoint ? 3 : width >= Theme.smallBreakpoint ? 2 : 1
        columnSpacing: Theme.spacingM
        rowSpacing: Theme.spacingM

        Repeater {
            model: root.filteredPlugins

            DCard {
                id: installedCard
                required property var modelData
                readonly property bool loaded: PluginService.loadedPlugins[modelData.pluginId] !== undefined
                readonly property var plugin: PluginService.availablePlugins[modelData.pluginId] || ({})
                readonly property var loadError: PluginService.pluginLoadErrors[modelData.pluginId]
                readonly property bool compatible: PluginService.checkPluginCompatibility(plugin.requires_dms)
                readonly property string problem: root.uninstallErrors[modelData.pluginId] || root.updateErrors[modelData.pluginId] || root.updateCheckErrors[modelData.pluginId] || (loadError ? [loadError.title, loadError.details].filter(Boolean).join("\n") : !compatible ? I18n.tr("Requires %1", "version requirement").arg(plugin.requires_dms) : "")
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: (installedGrid.width - installedGrid.columnSpacing * (installedGrid.columns - 1)) / installedGrid.columns
                Layout.fillHeight: true
                implicitHeight: cardContent.implicitHeight + pad * 2
                pad: Theme.spacingL
                radius: Theme.cornerRadiusM
                readonly property string highlightKey: "installedPlugin:" + modelData.pluginId
                color: SettingsSearchService.highlightSection === highlightKey ? Theme.blend(SettingsMetrics.rowColor, Theme.primary, SettingsMetrics.highlightBlend) : SettingsMetrics.rowColor
                clickable: true
                Accessible.name: modelData.text
                onClicked: keyboard => root.parentModal?.navigateTo(modelData.id, keyboard)

                Timer {
                    interval: 0
                    running: true
                    onTriggered: {
                        const flickable = QmlUtils.findParentFlickable(installedCard.parent);
                        if (!flickable)
                            return;
                        SettingsSearchService.registerCard(installedCard.highlightKey, installedCard, flickable);
                        revealTimer.restart();
                    }
                }
                Component.onDestruction: SettingsSearchService.unregisterCard(highlightKey, installedCard)

                ColumnLayout {
                    id: cardContent
                    anchors.fill: parent
                    spacing: Theme.spacingS

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.minimumHeight: Math.ceil(pluginTitleMetrics.height) * 2 + Theme.spacingXXS + pluginMetadata.implicitHeight
                        Layout.maximumHeight: Layout.minimumHeight
                        spacing: Theme.spacingS
                        DIcon {
                            id: pluginIcon
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: Math.max(0, (pluginTitle.implicitHeight - height) / 2)
                            name: installedCard.modelData.icon
                            size: Theme.iconSize
                            color: Theme.primary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: Math.max(0, (pluginIcon.height - pluginTitle.implicitHeight) / 2)
                            spacing: Theme.spacingXXS

                            StyledText {
                                id: pluginTitle
                                Layout.fillWidth: true
                                text: installedCard.modelData.text
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightMedium
                                color: Theme.onSurface
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignTop
                            }
                            Item {
                                id: pluginMetadata
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                implicitHeight: Math.max(Theme.spacingL, Math.ceil(pluginDescriptionMetrics.height), versionBadge.implicitHeight)

                                DBadge {
                                    id: versionBadge
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    text: installedCard.plugin.version || ""
                                    visible: text !== ""
                                    maximumWidth: parent.width
                                    color: installedCard.chipColor
                                    textColor: Theme.onSurfaceVariant
                                    Accessible.name: I18n.tr("Version %1", "accessible name of plugin version badge, %1 is the version number").arg(text)
                                }

                                StyledText {
                                    anchors.left: versionBadge.visible ? versionBadge.right : parent.left
                                    anchors.leftMargin: versionBadge.visible ? Theme.spacingXS : 0
                                    anchors.baseline: versionBadge.visible ? versionBadge.baseline : undefined
                                    width: Math.max(0, parent.width - (versionBadge.visible ? versionBadge.width + Theme.spacingXS : 0))
                                    visible: root.sortKeys[root.sortIndex] === "author"
                                    text: I18n.tr("by %1", "author attribution").arg(installedCard.plugin.author || I18n.tr("Unknown", "unknown author"))
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.onSurfaceVariant
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        DToggle {
                            Layout.alignment: Qt.AlignTop
                            enabled: !root.updatingPluginId && !pluginUpdatesDialogItem.isUpdating && !root.uninstalling[installedCard.modelData.pluginId]
                            checked: installedCard.loaded
                            Accessible.name: installedCard.modelData.text
                            onToggled: value => root.setEnabled(installedCard.modelData, value)
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumHeight: Math.ceil(pluginDescriptionMetrics.height) * 2
                        Layout.maximumHeight: Layout.minimumHeight
                        text: installedCard.modelData.hint
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        color: Theme.onSurfaceVariant
                        font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignTop
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: installedCard.problem !== "" || !!root.uninstalling[installedCard.modelData.pluginId]
                        spacing: Theme.spacingS
                        DActionButton {
                            visible: installedCard.problem !== ""
                            buttonSize: Theme.buttonHeightXS
                            iconName: "error"
                            iconColor: Theme.error
                            tooltipText: installedCard.problem
                            onClicked: root.actionError = installedCard.modelData.text + ": " + installedCard.problem
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.uninstalling[installedCard.modelData.pluginId] ? I18n.tr("Uninstalling: %1", "uninstallation progress").arg(installedCard.modelData.text) : installedCard.problem
                            color: installedCard.problem ? Theme.error : Theme.onSurfaceVariant
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            Accessible.description: installedCard.problem
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: Math.max(settingsButton.implicitHeight, cardActions.implicitHeight)

                        DIconButton {
                            id: settingsButton
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "settings"
                            variant: "tonal"
                            Accessible.name: I18n.tr("Settings")
                            onClicked: keyboard => root.parentModal?.navigateTo(installedCard.modelData.id, keyboard)
                        }
                        Row {
                            id: cardActions
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS

                            DIconButton {
                                iconName: "download"
                                variant: "tonal"
                                tooltipText: root.updatingPluginId === installedCard.modelData.pluginId ? I18n.tr("Updating...", "plugin update button tooltip while the update runs") : I18n.tr("Update available", "plugin row badge")
                                visible: root.hasUpdate(installedCard.modelData) || root.updatingPluginId === installedCard.modelData.pluginId
                                enabled: DMSService.dmsAvailable && !root.checkingUpdates && !pluginUpdatesDialogItem.isUpdating && !root.updatingPluginId && !root.uninstalling[installedCard.modelData.pluginId]
                                onClicked: root.requestUpdate(installedCard.modelData)
                            }
                            DIconButton {
                                iconName: "delete"
                                Accessible.name: I18n.tr("Uninstall")
                                visible: installedCard.plugin.source !== "system"
                                enabled: DMSService.dmsAvailable && !pluginUpdatesDialogItem.isUpdating && !root.updatingPluginId && !root.uninstalling[installedCard.modelData.pluginId]
                                onClicked: root.requestUninstall(installedCard.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsFabBar {
        shown: root.plugins.length > 0 && DMSService.dmsAvailable

        DFab {
            text: I18n.tr("Browse")
            iconName: "store"
            onClicked: root.showPluginBrowser()
        }
    }
}
