import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/KeyUtils.js" as KeyUtils
import "../../Common/LauncherKeybinds.js" as LauncherKeybinds

Item {
    id: root

    property var parentModal: null
    readonly property string defaultLauncherAction: "spawn dms ipc call spotlight toggle"
    readonly property string spotlightBarAction: "spawn dms ipc call spotlight-bar toggle"
    readonly property int keybindDataVersion: KeybindsService._dataVersion
    readonly property bool keybindsAvailable: KeybindsService.available
    readonly property string defaultLauncherKeybindSearch: "spotlight toggle"
    readonly property string spotlightBarKeybindSearch: "spotlight-bar"
    readonly property bool spotlightIgnoresRows: SettingsData.launcherStyle === "spotlight" && !SettingsData.connectedFrameModeActive
    // The niri overview launcher still uses size and footer when it is set to the full style.
    readonly property bool spotlightIgnoresSize: spotlightIgnoresRows && !(CompositorService.isNiri && SettingsData.niriOverviewOverlayEnabled && SettingsData.niriOverviewLauncherStyle !== "spotlight")
    readonly property var builtInPluginIds: ["dms_settings", "dms_notepad", "dms_sysmon", "dms_colorpicker", "dms_settings_search", "dms_clipboard_search", "dms_power", "dms_vpn", "dms_qr_generator"]

    function openKeybindsSearch(query) {
        if (!root.parentModal)
            return;
        if (typeof root.parentModal.showKeybindsSearch === "function") {
            root.parentModal.showKeybindsSearch(query);
        } else {
            root.parentModal.navigateTo("keybinds");
        }
    }

    function keysLabel(actionId) {
        void (keybindDataVersion);
        if (!keybindsAvailable)
            return I18n.tr("Manual config");
        const keys = KeybindsService.keysForAction(actionId);
        if (!keys || keys.length === 0)
            return I18n.tr("Not bound");
        return keys.join(", ");
    }

    function lastLaunchedText(lastUsed) {
        if (!lastUsed)
            return I18n.tr("Never used");
        const date = new Date(lastUsed);
        const diffMs = Date.now() - date.getTime();
        const diffMins = Math.floor(diffMs / (1000 * 60));
        const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
        const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
        if (diffMins < 1)
            return I18n.tr("Last launched just now");
        if (diffMins < 60)
            return diffMins === 1 ? I18n.tr("Last launched %1 minute ago", "singular, app usage list in launcher settings, %1 is 1").arg(diffMins) : I18n.tr("Last launched %1 minutes ago", "plural, app usage list in launcher settings, %1 is a count").arg(diffMins);
        if (diffHours < 24)
            return diffHours === 1 ? I18n.tr("Last launched %1 hour ago", "singular, app usage list in launcher settings, %1 is 1").arg(diffHours) : I18n.tr("Last launched %1 hours ago", "plural, app usage list in launcher settings, %1 is a count").arg(diffHours);
        if (diffDays < 7)
            return diffDays === 1 ? I18n.tr("Last launched %1 day ago", "singular, app usage list in launcher settings, %1 is 1").arg(diffDays) : I18n.tr("Last launched %1 days ago", "plural, app usage list in launcher settings, %1 is a count").arg(diffDays);
        return I18n.tr("Last launched %1", "app usage list in launcher settings, %1 is a localized date").arg(date.toLocaleDateString());
    }

    readonly property var launcherActionLabels: ({
            nextMode: I18n.tr("Next category", "launcher shortcut that switches to the next mode tab"),
            previousMode: I18n.tr("Previous category", "launcher shortcut that switches to the previous mode tab"),
            modeAll: I18n.tr("All"),
            modeApps: I18n.tr("Apps", "launcher mode tab, short for applications"),
            modeFiles: I18n.tr("Files"),
            modePlugins: I18n.tr("Plugins")
        })

    function setLauncherKeybind(actionId, combos) {
        const updated = Object.assign({}, SettingsData.launcherKeybinds);
        if (combos)
            updated[actionId] = combos;
        else
            delete updated[actionId];
        SettingsData.set("launcherKeybinds", updated);
    }

    Component.onCompleted: {
        KeybindsService.addRef();
        if (KeybindsService.available)
            KeybindsService.loadBinds(false);
    }

    Component.onDestruction: KeybindsService.removeRef()

    SettingsPage {
        id: mainColumn

        SettingsCard {
            width: parent.width
            iconName: "search"
            title: I18n.tr("Default action")
            settingKey: "launcherStyle"

            SettingsButtonGroupRow {
                readonly property bool islandOffered: SettingsData.dankIslandEnabled || SettingsData.launcherStyle === "island"
                readonly property bool spotlightOffered: !SettingsData.connectedFrameModeActive

                settingKey: "launcherStyleSelector"
                tags: ["launcher", "style", "default", "spotlight", "full", "minimal", "island", "dankisland"]
                resetKeys: ["launcherStyle"]
                text: I18n.tr("Opens", "verb, row label, which launcher style the shortcut opens")
                model: [I18n.tr("Full", "adjective, full size launcher style option")].concat(spotlightOffered ? [I18n.tr("Spotlight", "launcher style option, small centered search bar")] : []).concat(islandOffered ? [I18n.tr("Island")] : [])
                values: ["full"].concat(spotlightOffered ? ["spotlight"] : []).concat(islandOffered ? ["island"] : [])
                value: SettingsData.launcherStyle
                fallbackValue: "full"
                onValueSelected: value => SettingsData.set("launcherStyle", value)
            }

            SettingsRow {
                iconName: "keyboard"
                title: I18n.tr("Shortcut", "noun, keyboard shortcut row in launcher settings")
                subtitle: root.keybindsAvailable ? "" : I18n.tr("Bind the %1 IPC action in your compositor config.", "launcher shortcut hint, %1 is the ipc target name").arg("spotlight")
                trailingBadge: root.keysLabel(root.defaultLauncherAction)
                trailingBadgeColor: Theme.primary
                showChevron: root.keybindsAvailable
                clickable: root.keybindsAvailable
                onClicked: root.openKeybindsSearch(root.defaultLauncherKeybindSearch)
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "overview_key"
            title: I18n.tr("Overview")
            settingKey: "launcherNiriOverview"
            tags: ["launcher", "niri", "overview", "overlay"]
            visible: CompositorService.isNiri

            SettingsToggleRow {
                settingKey: "niriOverviewOverlayEnabled"
                tags: ["launcher", "niri", "overview", "overlay", "enable"]
                text: I18n.tr("Overlay")
                description: I18n.tr("Typing in the overview opens the launcher")
                checked: SettingsData.niriOverviewOverlayEnabled
                onToggled: checked => SettingsData.set("niriOverviewOverlayEnabled", checked)
            }

            SettingsButtonGroupRow {
                visible: SettingsData.niriOverviewOverlayEnabled
                settingKey: "niriOverviewLauncherStyle"
                tags: ["launcher", "niri", "overview", "overlay", "style", "spotlight", "full"]
                text: I18n.tr("Opens")
                model: [I18n.tr("Full"), I18n.tr("Spotlight")]
                currentIndex: SettingsData.niriOverviewLauncherStyle === "spotlight" ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("niriOverviewLauncherStyle", index === 1 ? "spotlight" : "full");
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "tune"
            title: I18n.tr("Appearance")
            settingKey: "dankLauncherV2Appearance"
            tags: ["launcher", "size", "grid", "columns", "footer", "badges", "darken"]

            SettingsButtonGroupRow {
                readonly property var sizes: ["micro", "compact", "medium", "large"]

                enabled: !root.spotlightIgnoresSize
                settingKey: "dankLauncherV2Size"
                tags: ["launcher", "size", "micro", "compact", "medium", "large"]
                text: I18n.tr("Size")
                model: ["1", "2", "3", "4"]
                currentIndex: {
                    const index = sizes.indexOf(SettingsData.dankLauncherV2Size);
                    return index >= 0 ? index : 2;
                }
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("dankLauncherV2Size", sizes[index]);
                }
            }

            SettingsSliderRow {
                settingKey: "appLauncherGridColumns"
                tags: ["launcher", "grid", "columns", "layout"]
                text: I18n.tr("Grid columns")
                unit: ""
                minimum: 2
                maximum: 8
                value: SettingsData.appLauncherGridColumns
                onSliderValueChanged: newValue => SettingsData.set("appLauncherGridColumns", newValue)
            }

            SettingsToggleRow {
                settingKey: "dankLauncherV2ShowFooter"
                tags: ["launcher", "footer", "hints", "shortcuts", "modes", "filters"]
                text: I18n.tr("Show footer")
                checked: SettingsData.dankLauncherV2ShowFooter
                enabled: SettingsData.dankLauncherV2Size !== "micro" && !root.spotlightIgnoresSize
                onToggled: checked => SettingsData.set("dankLauncherV2ShowFooter", checked)
            }

            SettingsToggleRow {
                settingKey: "dankLauncherV2ShowSourceBadges"
                tags: ["launcher", "appearance", "badge", "source", "flatpak", "snap", "appimage", "nix"]
                text: I18n.tr("Show package source badges")
                checked: SettingsData.dankLauncherV2ShowSourceBadges
                onToggled: checked => SettingsData.set("dankLauncherV2ShowSourceBadges", checked)
            }

            SettingsControlledBy {
                visible: SettingsData.frameEnabled
                parentModal: root.parentModal
                section: "frameBorder"
                settingLabel: I18n.tr("Darken modal background")
                reason: I18n.tr("Disabled by Frame Mode")
            }

            SettingsToggleRow {
                enabled: !SettingsData.frameEnabled
                settingKey: "modalDarkenBackground"
                tags: ["modal", "darken", "background", "overlay", "launcher"]
                text: I18n.tr("Darken modal background")
                checked: SettingsData.modalDarkenBackground
                onToggled: checked => SettingsData.set("modalDarkenBackground", checked)
            }
        }

        SettingsControlledBy {
            visible: SettingsData.connectedFrameModeActive && !SettingsData.launcherUseOverlayLayer
            parentModal: root.parentModal
            section: "frameBorder"
            settingLabel: I18n.tr("Border")
            reason: I18n.tr("Managed by Frame in Connected Mode")
        }

        SettingsToggleCard {
            width: parent.width
            visible: !SettingsData.connectedFrameModeActive || SettingsData.launcherUseOverlayLayer
            enabled: !root.spotlightIgnoresRows
            iconName: "border_style"
            title: I18n.tr("Border")
            settingKey: "dankLauncherV2BorderEnabled"
            tags: ["launcher", "border", "outline"]
            checked: SettingsData.dankLauncherV2BorderEnabled
            onToggled: checked => SettingsData.set("dankLauncherV2BorderEnabled", checked)

            SettingsSliderRow {
                settingKey: "dankLauncherV2BorderThickness"
                tags: ["launcher", "border", "thickness"]
                text: I18n.tr("Thickness")
                minimum: 1
                maximum: 6
                value: SettingsData.dankLauncherV2BorderThickness
                unit: "px"
                onSliderValueChanged: newValue => SettingsData.set("dankLauncherV2BorderThickness", newValue)
            }

            SettingsButtonGroupRow {
                readonly property var colors: ["primary", "secondary", "outline", "surfaceText"]

                settingKey: "dankLauncherV2BorderColor"
                tags: ["launcher", "border", "color"]
                text: I18n.tr("Color")
                model: [I18n.tr("Primary", "primary color"), I18n.tr("Secondary", "secondary color"), I18n.tr("Outline", "outline color"), I18n.tr("Text", "text color")]
                currentIndex: Math.max(0, colors.indexOf(SettingsData.dankLauncherV2BorderColor))
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("dankLauncherV2BorderColor", colors[index]);
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "search"
            title: I18n.tr("Search", "launcher settings section title, noun")
            settingKey: "searchOptions"

            SettingsToggleRow {
                settingKey: "searchAppActions"
                tags: ["launcher", "search", "actions", "shortcuts", "desktop"]
                text: I18n.tr("App actions")
                description: I18n.tr("Search also matches actions apps provide, like New Window", "launcher app actions search toggle description")
                checked: SessionData.searchAppActions
                onToggled: checked => SessionData.setSearchAppActions(checked)
            }

            SettingsToggleRow {
                settingKey: "rememberLastMode"
                tags: ["launcher", "remember", "last", "mode", "tab"]
                text: I18n.tr("Remember last mode")
                checked: SettingsData.rememberLastMode
                onToggled: checked => SettingsData.set("rememberLastMode", checked)
            }

            SettingsToggleRow {
                settingKey: "launcherHistoryEnabled"
                tags: ["launcher", "history", "privacy", "usage", "recent", "persist", "save"]
                text: I18n.tr("History")
                description: I18n.tr("Record app usage and past queries. Turning this off clears what is stored.", "launcher history toggle description")
                checked: SettingsData.launcherHistoryEnabled
                onToggled: checked => SettingsData.set("launcherHistoryEnabled", checked)
            }

            SettingsButtonGroupRow {
                settingKey: "launcherEnterAction"
                tags: ["launcher", "default", "action", "focus", "running", "window", "instance", "launch"]
                text: I18n.tr("Default action")
                model: [I18n.tr("Launch"), I18n.tr("Focus")]
                currentIndex: SettingsData.launcherEnterAction === "focus" ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("launcherEnterAction", index === 1 ? "focus" : "launch");
                }
            }

            SettingsToggleRow {
                settingKey: "rememberLastQuery"
                tags: ["launcher", "remember", "last", "search", "query"]
                text: I18n.tr("Remember last query")
                checked: SettingsData.rememberLastQuery
                onToggled: checked => SettingsData.set("rememberLastQuery", checked)
            }

            SettingsToggleRow {
                settingKey: "sortAppsAlphabetically"
                tags: ["launcher", "sort", "alphabetically", "apps", "order", "usage", "frequency"]
                text: I18n.tr("Sort alphabetically")
                checked: SettingsData.sortAppsAlphabetically
                onToggled: checked => SettingsData.set("sortAppsAlphabetically", checked)
            }

            SettingsToggleRow {
                settingKey: "dankLauncherV2IncludeFilesInAll"
                tags: ["launcher", "files", "dsearch", "all", "results", "indexed"]
                text: I18n.tr("Include files in All tab")
                checked: SettingsData.dankLauncherV2IncludeFilesInAll
                onToggled: checked => SettingsData.set("dankLauncherV2IncludeFilesInAll", checked)
            }

            SettingsToggleRow {
                settingKey: "dankLauncherV2IncludeFoldersInAll"
                tags: ["launcher", "folders", "dirs", "dsearch", "all", "results", "indexed"]
                text: I18n.tr("Include folders in All tab")
                checked: SettingsData.dankLauncherV2IncludeFoldersInAll
                onToggled: checked => SettingsData.set("dankLauncherV2IncludeFoldersInAll", checked)
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "keyboard"
            title: I18n.tr("Keyboard shortcuts")
            settingKey: "launcherKeybinds"
            tags: ["launcher", "keybind", "shortcut", "keyboard", "mode", "category", "tab"]

            Repeater {
                model: LauncherKeybinds.ACTIONS

                SettingsRow {
                    id: keybindRow

                    required property var modelData
                    readonly property var combos: LauncherKeybinds.combosFor(modelData, SettingsData.launcherKeybinds)

                    title: root.launcherActionLabels[modelData.id]
                    subtitle: keyCapture.capturing ? I18n.tr("Hold Ctrl, Alt or Super and press a key. Esc cancels.", "launcher shortcut key combination capture hint") : ""
                    modified: SettingsData.launcherKeybinds[modelData.id] !== undefined
                    resetByKeys: false
                    onResetRequested: root.setLauncherKeybind(modelData.id, null)

                    DButton {
                        id: keyCapture

                        property bool capturing: false

                        anchors.verticalCenter: parent.verticalCenter
                        text: capturing ? I18n.tr("Press key...") : (keybindRow.combos.join(", ") || I18n.tr("Not bound"))
                        backgroundColor: capturing ? Theme.selectedContainer : SettingsMetrics.controlColor
                        textColor: Theme.surfaceText
                        onClicked: {
                            capturing = !capturing;
                            if (capturing)
                                forceActiveFocus();
                        }
                        onActiveFocusChanged: {
                            if (!activeFocus)
                                capturing = false;
                        }

                        Keys.onPressed: event => captureKey(event)
                        // Specific Tab handlers stop Qt focus traversal while capturing.
                        Keys.onTabPressed: event => captureKey(event)
                        Keys.onBacktabPressed: event => captureKey(event)

                        function captureKey(event) {
                            event.accepted = capturing;
                            if (!capturing || KeyUtils.isModifierKey(event.key))
                                return;
                            if (event.key === Qt.Key_Escape) {
                                capturing = false;
                                return;
                            }
                            // Unmodified keys belong to the search field.
                            if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
                                return;
                            const chord = LauncherKeybinds.chordFromEvent(event);
                            if (!chord)
                                return;
                            root.setLauncherKeybind(keybindRow.modelData.id, [chord]);
                            capturing = false;
                        }
                    }
                }
            }
        }

        SettingsCard {
            id: hiddenAppsCard
            width: parent.width
            iconName: "visibility_off"
            title: I18n.tr("Hidden apps")
            settingKey: "hiddenApps"

            property var hiddenAppsModel: {
                SessionData.hiddenApps;
                const apps = [];
                const allApps = AppSearchService.applications || [];
                for (const hiddenId of SessionData.hiddenApps) {
                    const app = allApps.find(a => (a.id || a.execString || a.exec) === hiddenId);
                    if (app) {
                        apps.push({
                            id: hiddenId,
                            name: app.name || hiddenId,
                            icon: app.icon || "",
                            comment: app.comment || ""
                        });
                    } else {
                        apps.push({
                            id: hiddenId,
                            name: hiddenId,
                            icon: "",
                            comment: ""
                        });
                    }
                }
                return apps.sort((a, b) => a.name.localeCompare(b.name));
            }

            SettingsRow {
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Right-click an app in the launcher and choose 'Hide App'")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            Repeater {
                model: hiddenAppsCard.hiddenAppsModel

                SettingsRow {
                    id: hiddenAppRow

                    required property var modelData

                    title: modelData.name
                    subtitle: modelData.comment || modelData.id
                    leading: AppIconRenderer {
                        width: Theme.iconSize
                        height: Theme.iconSize
                        iconValue: hiddenAppRow.modelData.icon || "application-x-executable"
                        iconSize: Theme.iconSize
                        fallbackText: (hiddenAppRow.modelData.name || "?").charAt(0).toUpperCase()
                    }

                    DActionButton {
                        iconName: "visibility"
                        Accessible.name: I18n.tr("Show")
                        iconColor: Theme.primary
                        onClicked: SessionData.showApp(hiddenAppRow.modelData.id)
                    }
                }
            }

            SettingsRow {
                visible: hiddenAppsCard.hiddenAppsModel.length === 0
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("No hidden apps.")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        SettingsCard {
            id: appOverridesCard
            width: parent.width
            iconName: "edit"
            title: I18n.tr("App customizations")
            settingKey: "appOverrides"

            property var overridesModel: {
                SessionData.appOverrides;
                const items = [];
                const allApps = AppSearchService.applications || [];
                for (const appId in SessionData.appOverrides) {
                    const override = SessionData.appOverrides[appId];
                    const app = allApps.find(a => (a.id || a.execString || a.exec) === appId);
                    items.push({
                        id: appId,
                        name: override.name || app?.name || appId,
                        originalName: app?.name || appId,
                        icon: override.icon || app?.icon || "",
                        hasOverride: true
                    });
                }
                return items.sort((a, b) => a.name.localeCompare(b.name));
            }

            SettingsRow {
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Right-click an app in the launcher and choose 'Edit App'")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            Repeater {
                model: appOverridesCard.overridesModel

                SettingsRow {
                    id: overrideRow

                    required property var modelData

                    title: modelData.name
                    subtitle: modelData.originalName !== modelData.name ? modelData.originalName : modelData.id
                    leading: AppIconRenderer {
                        width: Theme.iconSize
                        height: Theme.iconSize
                        iconValue: overrideRow.modelData.icon || "application-x-executable"
                        iconSize: Theme.iconSize
                        fallbackText: (overrideRow.modelData.name || "?").charAt(0).toUpperCase()
                    }

                    DActionButton {
                        iconName: "delete"
                        tooltipText: I18n.tr("Reset to default")
                        iconColor: Theme.error
                        onClicked: SessionData.clearAppOverride(overrideRow.modelData.id)
                    }
                }
            }

            SettingsRow {
                visible: appOverridesCard.overridesModel.length === 0
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("No app customizations.")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "apps"
            title: I18n.tr("Built-in apps", "launcher settings card, DMS tools listed with the installed apps")
            settingKey: "launcherBuiltInApps"
            tags: ["launcher", "apps", "builtin", "settings", "notepad", "system monitor", "color picker"]

            Repeater {
                model: root.builtInPluginIds.filter(id => AppSearchService.builtInPlugins[id]?.isLauncher !== true)

                SettingsToggleRow {
                    required property string modelData
                    readonly property var plugin: AppSearchService.builtInPlugins[modelData]

                    iconName: plugin?.cornerIcon ?? "extension"
                    text: plugin?.name ?? modelData
                    checked: SettingsData.getBuiltInPluginSetting(modelData, "enabled", true)
                    onToggled: checked => SettingsData.setBuiltInPluginSetting(modelData, "enabled", checked)
                }
            }
        }

        SettingsCard {
            id: pluginVisibilityCard
            width: parent.width
            iconName: "filter_list"
            title: I18n.tr("Plugin visibility")
            settingKey: "pluginVisibility"

            property var allLauncherPlugins: {
                SettingsData.launcherPluginOrder;
                SettingsData.dankLauncherV2IncludeFilesInAll;
                SettingsData.dankLauncherV2IncludeFoldersInAll;
                var plugins = [];
                var builtIn = AppSearchService.getBuiltInLauncherPlugins() || {};
                for (var pluginId in builtIn) {
                    var plugin = builtIn[pluginId];
                    plugins.push({
                        id: pluginId,
                        name: plugin.name || pluginId,
                        icon: plugin.cornerIcon || "extension",
                        iconType: "material",
                        isBuiltIn: true,
                        isVirtual: false,
                        trigger: AppSearchService.getBuiltInPluginTrigger(pluginId) || ""
                    });
                }
                var thirdParty = PluginService.getLauncherPlugins() || {};
                for (var pluginId in thirdParty) {
                    var plugin = thirdParty[pluginId];
                    var rawIcon = plugin.icon || "extension";
                    plugins.push({
                        id: pluginId,
                        name: plugin.name || pluginId,
                        icon: rawIcon.startsWith("material:") ? rawIcon.substring(9) : rawIcon.startsWith("unicode:") ? rawIcon.substring(8) : rawIcon,
                        iconType: rawIcon.startsWith("unicode:") ? "unicode" : "material",
                        isBuiltIn: false,
                        isVirtual: false,
                        trigger: PluginService.getPluginTrigger(pluginId) || ""
                    });
                }
                if (SettingsData.dankLauncherV2IncludeFilesInAll) {
                    plugins.push({
                        id: "__files",
                        name: I18n.tr("Files"),
                        icon: "insert_drive_file",
                        iconType: "material",
                        isBuiltIn: false,
                        isVirtual: true,
                        trigger: "/"
                    });
                }
                if (SettingsData.dankLauncherV2IncludeFoldersInAll) {
                    plugins.push({
                        id: "__folders",
                        name: I18n.tr("Folders"),
                        icon: "folder",
                        iconType: "material",
                        isBuiltIn: false,
                        isVirtual: true,
                        trigger: "/"
                    });
                }
                return SettingsData.getOrderedLauncherPlugins(plugins);
            }

            SettingsRow {
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Plugins shown in All mode without a trigger. Drag to reorder")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            SettingsReorderList {
                id: pluginList

                model: pluginVisibilityCard.allLauncherPlugins
                onReordered: indices => SettingsData.setLauncherPluginOrder(indices.map(i => pluginVisibilityCard.allLauncherPlugins[i].id))

                delegate: SettingsReorderRow {
                    id: pluginRow

                    required property var modelData

                    reorderList: pluginList
                    title: modelData.name
                    subtitle: modelData.trigger ? I18n.tr("Trigger: %1", "launcher plugin subtitle, %1 is the trigger prefix text").arg(modelData.trigger) : I18n.tr("No trigger")
                    iconName: modelData.iconType !== "unicode" ? modelData.icon : ""
                    textIcon: modelData.iconType === "unicode" ? modelData.icon : ""

                    DBadge {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: pluginRow.modelData.isBuiltIn
                        text: I18n.tr("Built-in", "badge on launcher plugins that ship with DMS")
                        color: Theme.primaryHover
                        textColor: Theme.primary
                    }

                    DToggle {
                        anchors.verticalCenter: parent.verticalCenter
                        hideText: true
                        checked: {
                            switch (pluginRow.modelData.id) {
                            case "__files":
                                return SettingsData.dankLauncherV2IncludeFilesInAll;
                            case "__folders":
                                return SettingsData.dankLauncherV2IncludeFoldersInAll;
                            default:
                                return SettingsData.getPluginAllowWithoutTrigger(pluginRow.modelData.id);
                            }
                        }
                        onToggled: isChecked => {
                            switch (pluginRow.modelData.id) {
                            case "__files":
                                SettingsData.set("dankLauncherV2IncludeFilesInAll", isChecked);
                                return;
                            case "__folders":
                                SettingsData.set("dankLauncherV2IncludeFoldersInAll", isChecked);
                                return;
                            default:
                                SettingsData.setPluginAllowWithoutTrigger(pluginRow.modelData.id, isChecked);
                            }
                        }
                    }
                }
            }

            SettingsRow {
                visible: pluginVisibilityCard.allLauncherPlugins.length === 0
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("No launcher plugins installed.")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "extension"
            title: I18n.tr("Built-in plugins")
            settingKey: "launcherBuiltInPlugins"
            tags: ["launcher", "plugins", "trigger", "builtin", "power", "vpn", "qr", "clipboard", "search"]

            Repeater {
                model: root.builtInPluginIds.filter(id => AppSearchService.builtInPlugins[id]?.isLauncher === true)

                SettingsRow {
                    id: builtInRow

                    required property string modelData
                    readonly property var plugin: AppSearchService.builtInPlugins[modelData]

                    iconName: plugin?.cornerIcon ?? "extension"
                    title: plugin?.name ?? modelData

                    DTextField {
                        outlined: true
                        leftIconName: "keyboard"
                        labelText: I18n.tr("Trigger", "noun, launcher plugin trigger prefix text field label")
                        width: Theme.fontSizeMedium * 6 + Theme.iconButtonSize
                        anchors.verticalCenter: parent.verticalCenter
                        onTextEdited: SettingsData.setBuiltInPluginSetting(builtInRow.modelData, "trigger", text)
                        Component.onCompleted: text = SettingsData.getBuiltInPluginSetting(builtInRow.modelData, "trigger", builtInRow.plugin?.defaultTrigger ?? "")
                    }

                    DToggle {
                        hideText: true
                        anchors.verticalCenter: parent.verticalCenter
                        checked: SettingsData.getBuiltInPluginSetting(builtInRow.modelData, "enabled", true)
                        onToggled: checked => SettingsData.setBuiltInPluginSetting(builtInRow.modelData, "enabled", checked)
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "horizontal_split"
            title: I18n.tr("Spotlight bar")
            settingKey: "spotlightBar"
            tags: ["launcher", "spotlight", "bar", "shortcut", "chips"]

            SettingsRow {
                iconName: "keyboard"
                title: I18n.tr("Shortcut")
                subtitle: root.keybindsAvailable ? "" : I18n.tr("Bind the %1 IPC action in your compositor config.").arg("spotlight-bar")
                trailingBadge: root.keysLabel(root.spotlightBarAction)
                trailingBadgeColor: Theme.primary
                showChevron: root.keybindsAvailable
                clickable: root.keybindsAvailable
                onClicked: root.openKeybindsSearch(root.spotlightBarKeybindSearch)
            }

            SettingsToggleRow {
                settingKey: "spotlightBarShowModeChips"
                tags: ["launcher", "spotlight", "bar", "chips", "tabs", "modes", "filters"]
                text: I18n.tr("Show mode chips")
                checked: SettingsData.spotlightBarShowModeChips
                onToggled: checked => SettingsData.set("spotlightBarShowModeChips", checked)
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "rocket_launch"
            title: I18n.tr("Launching", "launcher settings card about how apps are launched")
            settingKey: "launcherLaunching"
            tags: ["launcher", "prefix", "terminal", "uwsm"]

            SettingsTextFieldRow {
                settingKey: "launchPrefix"
                tags: ["launcher", "prefix", "uwsm", "command", "launch"]
                text: I18n.tr("Launch prefix")
                description: I18n.tr("Added in front of every app launch command", "launcher launch prefix field description")
                leftIconName: "terminal"
                placeholderText: I18n.tr("Enter launch prefix (e.g., 'uwsm-app')")
                value: SettingsData.launchPrefix
                onValueEdited: value => SettingsData.set("launchPrefix", value)
            }

            TerminalPickerRow {}
        }

        SettingsCard {
            id: recentAppsCard
            width: parent.width
            iconName: "history"
            title: I18n.tr("Recently used apps")
            settingKey: "recentApps"
            visible: SettingsData.launcherHistoryEnabled
            collapsible: true
            expanded: false

            property var rankedAppsModel: {
                var ranking = AppUsageHistoryData.appUsageRanking;
                if (!ranking)
                    return [];
                var apps = [];
                for (var appId in ranking) {
                    var appData = ranking[appId];
                    apps.push({
                        "id": appId,
                        "name": appData.name,
                        "exec": appData.exec,
                        "icon": appData.icon,
                        "comment": appData.comment,
                        "usageCount": appData.usageCount,
                        "lastUsed": appData.lastUsed
                    });
                }
                apps.sort(function (a, b) {
                    if (a.usageCount !== b.usageCount)
                        return b.usageCount - a.usageCount;
                    return a.name.localeCompare(b.name);
                });
                return apps.slice(0, 20);
            }

            SettingsRow {
                body: Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    StyledText {
                        width: parent.width - clearAllButton.width - Theme.spacingM
                        text: I18n.tr("Apps are ordered by usage frequency, then last used, then alphabetically.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DActionButton {
                        id: clearAllButton
                        iconName: "delete_sweep"
                        tooltipText: I18n.tr("Clear All")
                        iconSize: Theme.iconSizeMedium
                        iconColor: Theme.error
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: AppUsageHistoryData.clear()
                    }
                }
            }

            Repeater {
                model: recentAppsCard.rankedAppsModel

                SettingsRow {
                    id: rankedAppRow

                    required property var modelData
                    required property int index

                    title: modelData.name || I18n.tr("Unknown App")
                    subtitle: root.lastLaunchedText(modelData.lastUsed)
                    leading: [
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.iconSize
                            text: (rankedAppRow.index + 1).toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: Theme.primary
                        },
                        AppIconRenderer {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.iconSize
                            height: Theme.iconSize
                            iconValue: rankedAppRow.modelData.icon || "application-x-executable"
                            iconSize: Theme.iconSize
                            fallbackText: (rankedAppRow.modelData.name || "?").charAt(0).toUpperCase()
                        }
                    ]

                    DActionButton {
                        iconName: "close"
                        Accessible.name: I18n.tr("Remove")
                        iconColor: Theme.error
                        onClicked: {
                            const currentRanking = Object.assign({}, AppUsageHistoryData.appUsageRanking || {});
                            delete currentRanking[rankedAppRow.modelData.id];
                            AppUsageHistoryData.appUsageRanking = currentRanking;
                            AppUsageHistoryData.saveSettings();
                        }
                    }
                }
            }

            SettingsRow {
                visible: recentAppsCard.rankedAppsModel.length === 0
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("No apps have been launched yet.")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        SettingsCard {
            width: parent.width
            title: I18n.tr("Advanced")
            settingKey: "launcherAdvanced"
            tags: ["launcher", "advanced", "overlay", "layer", "unload", "memory"]
            collapsible: true
            expanded: false

            SettingsToggleRow {
                settingKey: "launcherUseOverlayLayer"
                tags: ["launcher", "fullscreen", "overlay", "layer"]
                text: I18n.tr("Use overlay layer")
                checked: SettingsData.launcherUseOverlayLayer
                onToggled: checked => SettingsData.set("launcherUseOverlayLayer", checked)
            }

            SettingsToggleRow {
                enabled: !root.spotlightIgnoresRows
                settingKey: "dankLauncherV2UnloadOnClose"
                tags: ["launcher", "unload", "close", "memory", "vram"]
                text: I18n.tr("Unload on close")
                description: I18n.tr("Frees the launcher when closed and rebuilds it on open", "launcher unload on close toggle description")
                checked: SettingsData.dankLauncherV2UnloadOnClose
                onToggled: checked => SettingsData.set("dankLauncherV2UnloadOnClose", checked)
            }
        }
    }
}
