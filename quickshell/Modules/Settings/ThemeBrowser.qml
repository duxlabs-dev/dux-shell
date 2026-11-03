import QtQuick
import Quickshell
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/ThemePalette.js" as ThemePalette

RegistryBrowserWindow {
    id: root

    property var allThemes: []
    property var filteredThemes: []
    property string pendingApplyThemeId: ""
    property string loadError: ""
    property string operationMessage: ""
    property bool operationFailed: false
    property var pendingThemes: ({})
    property int filterIndex: 0

    function updateFilteredThemes() {
        var filtered = [];
        var query = searchQuery ? searchQuery.toLowerCase() : "";

        for (var i = 0; i < allThemes.length; i++) {
            var theme = allThemes[i];
            if (filterIndex === 1 && !theme.installed)
                continue;
            if (filterIndex === 2 && theme.installed)
                continue;

            if (query.length === 0) {
                filtered.push(theme);
                continue;
            }

            var name = theme.name ? theme.name.toLowerCase() : "";
            var description = theme.description ? theme.description.toLowerCase() : "";
            var author = theme.author ? theme.author.toLowerCase() : "";

            if (name.indexOf(query) !== -1 || description.indexOf(query) !== -1 || author.indexOf(query) !== -1)
                filtered.push(theme);
        }

        filteredThemes = filtered;
        selectedIndex = -1;
        keyboardNavigationActive = false;
    }

    function ensureSelectedVisible() {
        if (selectedIndex >= 0)
            themeGrid.revealIndex(selectedIndex);
    }

    function selectNext() {
        if (filteredThemes.length === 0)
            return;
        if (!keyboardNavigationActive) {
            keyboardNavigationActive = true;
            selectedIndex = 0;
            ensureSelectedVisible();
            return;
        }
        selectedIndex = Math.min(selectedIndex + themeGrid.columns, filteredThemes.length - 1);
        ensureSelectedVisible();
    }

    function selectPrevious() {
        if (filteredThemes.length === 0 || !keyboardNavigationActive)
            return;
        const next = selectedIndex - themeGrid.columns;
        if (next < 0) {
            selectedIndex = -1;
            keyboardNavigationActive = false;
            return;
        }
        selectedIndex = next;
        ensureSelectedVisible();
    }

    function selectStep(delta) {
        if (filteredThemes.length === 0 || !keyboardNavigationActive)
            return;
        selectedIndex = Math.max(0, Math.min(selectedIndex + delta, filteredThemes.length - 1));
        ensureSelectedVisible();
    }

    function themeBadges(theme) {
        const badges = PluginService.badgeModel(theme);
        const variants = theme.variants || null;
        const variantCount = variants ? (variants.type === "multi" ? (variants.accents?.length ?? 0) : (variants.options?.length ?? 0)) : 0;
        if (variantCount > 0)
            badges.push({
                label: I18n.tr("%1 variants", "theme browser badge, plural, %1 is a count of theme variants").arg(variantCount),
                icon: "",
                tone: "secondary"
            });
        const wcag = wcagLabel(theme);
        if (wcag)
            badges.push({
                label: wcag,
                icon: "contrast",
                tone: "info"
            });
        return badges;
    }

    function themePalette(theme) {
        return ThemePalette.pick((Theme.isLightMode ? theme.light : theme.dark) ?? theme.dark);
    }

    function themePreviewUrl(theme) {
        const base = "https://raw.githubusercontent.com/duxlabs-dev/dux-plugin-registry/master/themes/" + (theme.sourceDir || theme.id) + "/";
        const variants = theme.variants || null;
        if (!variants)
            return base + "preview.svg";
        let variantId = "";
        if (variants.type === "multi") {
            const mode = Theme.isLightMode ? "light" : "dark";
            const defaults = variants.defaults?.[mode] || variants.defaults?.dark || {};
            variantId = (defaults.flavor || "") + (defaults.accent ? "-" + defaults.accent : "");
        } else {
            variantId = variants.default || (variants.options?.[0]?.id ?? "");
        }
        return variantId ? base + "preview-" + variantId + ".svg" : base + "preview.svg";
    }

    function wcagLabel(theme) {
        const rows = (theme.wcag?.dark?.breakdown ?? []).concat(theme.wcag?.light?.breakdown ?? []);
        let hasAAA = false;
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].level === "AA")
                return "WCAG AA";
            if (rows[i].level === "AAA")
                hasAAA = true;
        }
        return hasAAA ? "WCAG AAA" : "";
    }

    function finishOperation(themeId, message, failed) {
        const pending = Object.assign({}, pendingThemes);
        delete pending[themeId];
        pendingThemes = pending;
        operationMessage = message;
        operationFailed = failed;
    }

    function installTheme(themeId, themeName, applyAfterInstall) {
        if (pendingThemes[themeId])
            return;
        pendingThemes = Object.assign({}, pendingThemes, {
            [themeId]: true
        });
        operationFailed = false;
        operationMessage = I18n.tr("Installing: %1", "installation progress").arg(themeName);
        DMSService.installTheme(themeId, response => {
            if (response.error) {
                finishOperation(themeId, I18n.tr("Install failed: %1", "installation error").arg(response.error), true);
                return;
            }
            finishOperation(themeId, I18n.tr("Installed: %1", "installation success").arg(themeName), false);
            if (applyAfterInstall)
                pendingApplyThemeId = themeId;
            refreshThemes();
        });
    }

    function applyInstalledTheme(themeId, installedThemes) {
        for (var i = 0; i < installedThemes.length; i++) {
            var theme = installedThemes[i];
            if (theme.id === themeId) {
                var sourceDir = theme.sourceDir || theme.id;
                var themePath = Quickshell.env("HOME") + "/.config/dms/themes/" + sourceDir + "/theme.json";
                SettingsData.set("customThemeFile", themePath);
                Theme.switchThemeCategory("registry", "custom");
                Theme.switchTheme("custom", true, true);
                hide();
                return;
            }
        }
    }

    function uninstallTheme(themeId, themeName) {
        if (pendingThemes[themeId])
            return;
        pendingThemes = Object.assign({}, pendingThemes, {
            [themeId]: true
        });
        operationFailed = false;
        operationMessage = I18n.tr("Uninstalling: %1", "uninstallation progress").arg(themeName);
        DMSService.uninstallTheme(themeId, response => {
            if (response.error) {
                finishOperation(themeId, I18n.tr("Uninstall failed: %1", "uninstallation error").arg(response.error), true);
                return;
            }
            finishOperation(themeId, I18n.tr("Uninstalled: %1", "uninstallation success").arg(themeName), false);
            refreshThemes();
        });
    }

    function refreshThemes() {
        isLoading = true;
        loadError = "";
        DMSService.listThemes(response => {
            isLoading = false;
            if (!visible)
                return;
            if (response.error) {
                loadError = response.error;
                return;
            }
            allThemes = response.result || [];
            updateFilteredThemes();
        });
        DMSService.listInstalledThemes(response => {
            if (!response.error)
                return;
            pendingApplyThemeId = "";
            operationFailed = true;
            operationMessage = response.error;
        });
    }

    function checkPendingInstall() {
        if (!PopoutService.pendingThemeInstall || pendingInstallHandled)
            return;
        pendingInstallHandled = true;
        var themeId = PopoutService.pendingThemeInstall;
        PopoutService.pendingThemeInstall = "";
        installConfirm.showWithOptions({
            "title": I18n.tr("Install Theme", "theme installation dialog title"),
            "message": I18n.tr("Install theme '%1' from the DMS registry?", "theme installation confirmation").arg(themeId),
            "confirmText": I18n.tr("Install", "install action button"),
            "cancelText": I18n.tr("Cancel"),
            "onConfirm": () => installTheme(themeId, themeId, true),
            "onCancel": () => hide()
        });
    }

    objectName: "themeBrowser"
    title: I18n.tr("Browse Themes", "theme browser window title")
    headerTitle: I18n.tr("Browse Themes")
    searchPlaceholder: I18n.tr("Search themes...", "theme search placeholder")

    function pendingInstallId() {
        return PopoutService.pendingThemeInstall || "";
    }

    function refresh() {
        refreshThemes();
    }

    function applySearch() {
        updateFilteredThemes();
    }

    function resetContent() {
        allThemes = [];
        filteredThemes = [];
    }

    function activateSelected() {
        if (!keyboardNavigationActive || selectedIndex < 0)
            return false;
        const theme = filteredThemes[selectedIndex];
        if (!theme.installed)
            installTheme(theme.id, theme.name, false);
        return true;
    }

    Connections {
        target: DMSService
        function onThemesListReceived(themes) {
            if (!root.visible)
                return;
            isLoading = false;
            allThemes = themes;
            updateFilteredThemes();
        }
        function onInstalledThemesReceived(themes) {
            if (!pendingApplyThemeId)
                return;
            var themeId = pendingApplyThemeId;
            pendingApplyThemeId = "";
            applyInstalledTheme(themeId, themes);
        }
    }

    aboveSearch: [
        StyledText {
            id: descriptionText
            topPadding: Theme.spacingM
            anchors.left: parent.left
            anchors.right: parent.right
            text: I18n.tr("Install color themes from the DMS theme registry", "theme browser description")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.onSurfaceVariant
            wrapMode: Text.WordWrap
        }
    ]

    belowSearch: [
        Column {
            id: themeFilters
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Theme.spacingS

            DFilterChips {
                width: parent.width
                model: [I18n.tr("All"), I18n.tr("Installed"), I18n.tr("Available")]
                currentIndex: root.filterIndex
                onSelectionChanged: index => {
                    root.filterIndex = index;
                    root.updateFilteredThemes();
                }
            }
            StyledText {
                width: parent.width
                visible: root.operationMessage !== ""
                text: root.operationMessage
                color: root.operationFailed ? Theme.error : Theme.onSurfaceVariant
                wrapMode: Text.Wrap
            }
            StyledText {
                width: parent.width
                visible: root.loadError !== ""
                text: root.loadError
                color: Theme.error
                wrapMode: Text.Wrap
            }
            DButton {
                visible: root.loadError !== ""
                text: I18n.tr("Retry", "retry failed action button")
                iconName: "refresh"
                onClicked: root.refreshThemes()
            }
        }
    ]

    listContent: [
        DGridView {
            id: themeGrid

            property int columns: Math.max(1, Math.floor(width / (Theme.smallBreakpoint / 2 + Theme.spacingXL * 2)))
            readonly property real cardSpacing: Theme.spacingM
            readonly property int previewHeight: Math.round((cellWidth - cardSpacing - Theme.spacingS * 2) * SettingsMetrics.choiceCardPreviewRatio)
            readonly property int infoHeight: Theme.iconButtonSize + Theme.fontSizeSmall * 4 + Theme.spacingS

            anchors.fill: parent
            cellWidth: Math.floor(width / columns)
            cellHeight: previewHeight + infoHeight + Math.round(cardSpacing) + Theme.spacingS * 2 + Theme.spacingM
            model: root.filteredThemes
            clip: true
            visible: !root.isLoading
            cacheBuffer: cellHeight * 2

            delegate: Item {
                id: cardCell

                required property var modelData
                required property int index

                width: themeGrid.cellWidth
                height: themeGrid.cellHeight

                PluginCard {
                    anchors.fill: parent
                    anchors.margins: themeGrid.cardSpacing / 2
                    plugin: cardCell.modelData
                    busy: !!root.pendingThemes[cardCell.modelData.id]
                    fallbackIcon: "palette"
                    previewSource: root.themePreviewUrl(cardCell.modelData)
                    previewFallback: ""
                    badges: root.themeBadges(cardCell.modelData)
                    palette: root.themePalette(cardCell.modelData)
                    allowUninstall: true
                    previewHeight: themeGrid.previewHeight
                    installed: cardCell.modelData.installed || false
                    selected: root.keyboardNavigationActive && cardCell.index === root.selectedIndex
                    onClicked: {
                        root.selectedIndex = cardCell.index;
                        root.keyboardNavigationActive = true;
                        if (!cardCell.modelData.installed)
                            root.installTheme(cardCell.modelData.id, cardCell.modelData.name, false);
                    }
                    onInstallRequested: root.installTheme(cardCell.modelData.id, cardCell.modelData.name, false)
                    onUninstallRequested: root.uninstallTheme(cardCell.modelData.id, cardCell.modelData.name)
                }
            }
        },
        StyledText {
            anchors.centerIn: parent
            text: I18n.tr("No themes found", "empty theme list")
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            visible: !root.isLoading && root.loadError === "" && root.filteredThemes.length === 0
        }
    ]
}
