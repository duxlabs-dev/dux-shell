pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/Format.js" as Format
import "../../Common/IconFolders.js" as IconFolders
import "../../Common/ThemePalette.js" as ThemePalette
import "../../DCommon/Common/MaterialWallpaper.js" as Art
import "../../Common/WallpaperFormats.js" as WallpaperFormats

Column {
    id: root

    property var parentModal: null
    property var cachedIconThemes: SettingsData.availableIconThemes
    readonly property var iconThemeLabels: (cachedIconThemes || []).map(name => IconFolders.label(name))
    property var cachedCursorThemes: SettingsData.availableCursorThemes
    readonly property string pickedIconTheme: SettingsData.iconTheme
    // Dux Icons is built in the theme colors; it has its own options in place of folder recoloring.
    readonly property bool pickedSelfBuiltIcons: IconFolders.isSelf(pickedIconTheme)
    readonly property bool colorAppIcons: IconFolders.colorApps(SettingsData.iconAppStyle)
    readonly property bool tiledAppIcons: IconFolders.tiledApps(SettingsData.iconAppStyle)
    // In the order of IconFolders.shapes().
    readonly property var iconShapeLabels: [I18n.tr("Circle", "icon shape"), I18n.tr("Squircle", "icon shape"), I18n.tr("Rounded square", "icon shape"), I18n.tr("Square", "icon shape"), I18n.tr("Hexagon", "icon shape"), I18n.tr("Cookie", "icon shape, a circle with a scalloped edge"), I18n.tr("Clover", "icon shape, a square with rounded lobes at its corners")]
    readonly property var iconShapeImages: IconFolders.shapes().map(shape => "svg:" + IconFolders.shapeUrl(shape, Theme.primary.toString()))
    readonly property bool selfBuiltIconsMissing: pickedSelfBuiltIcons && iconFolderProbeDone && iconFolderProbe?.code === "no-generator"
    property string iconFolderProbeTheme: ""
    property var iconFolderProbe: null
    property bool iconFolderProbeDone: false
    property bool iconFolderEnabling: false
    // Theme name -> { removable, icons }, from `dms icon-theme list` while this page is open.
    property var iconLibrary: ({})
    property bool iconLibraryOpen: false
    property bool iconInstalling: false
    property bool iconInstallFolder: false
    readonly property var iconThemeImages: (cachedIconThemes || []).map(name => {
        const file = iconLibrary[name]?.icons[0];
        return file ? "svg:" + file : "";
    })
    readonly property var iconThemeGlyphs: iconThemeImages.map(image => image ? "" : "palette")
    // Cursor theme name -> { removable, pointer }, from `dms icon-theme list`.
    property var cursorLibrary: ({})
    property bool cursorLibraryOpen: false
    property bool cursorInstalling: false
    property bool cursorInstallFolder: false
    readonly property var cursorThemeImages: (cachedCursorThemes || []).map(name => cursorLibrary[name]?.pointer ? "svg:" + cursorLibrary[name].pointer : "")
    readonly property var cursorThemeGlyphs: cursorThemeImages.map(image => image ? "" : "arrow_selector_tool")
    // A generation of Dux Icons is a new directory, so its preview files move with every rebuild.
    readonly property string iconGeneration: SettingsData.iconFolderState?.applied ?? ""
    onIconGenerationChanged: loadIconLibrary()
    // Empty while folder recoloring can be turned on for the picked pack.
    readonly property string iconFolderBlocker: {
        if (pickedIconTheme === "System Default")
            return iconFolderProbeText("system-default", "");
        if (!Theme.matugenAvailable)
            return I18n.tr("Install the %1 package for dynamic theming", "matugen installation hint, %1 is the package name").arg("matugen");
        if (!iconFolderProbeDone || iconFolderProbe?.supported)
            return "";
        return iconFolderProbeText(iconFolderProbe?.code ?? "", iconFolderProbe?.reason ?? "");
    }

    // The Go probe's English reason is shown only for a code this shell does not know yet.
    function iconFolderProbeText(code, reason) {
        const unsupported = I18n.tr("%1 is not supported", "folder recolor toggle, %1 is an icon theme name").arg(pickedIconTheme);
        switch (code) {
        case "system-default":
            return I18n.tr("Pick an icon theme first", "folder recolor toggle, disabled while System Default is selected");
        case "not-found":
            return I18n.tr("%1 is not installed", "folder recolor toggle, %1 is an icon theme name").arg(pickedIconTheme);
        case "unreadable":
            return I18n.tr("%1 could not be read", "folder recolor toggle, %1 is an icon theme name").arg(pickedIconTheme);
        case "no-colored-folders":
            return I18n.tr("%1 has no folders that can be recolored", "folder recolor toggle, %1 is an icon theme name").arg(pickedIconTheme);
        case "unsupported-pack":
            return unsupported;
        }
        return reason || unsupported;
    }

    onPickedIconThemeChanged: probeIconFolders(false)

    readonly property bool perMonitor: SessionData.perMonitorWallpaper
    readonly property bool perMode: SessionData.perModeWallpaper
    readonly property string selectedScreen: SettingsUiState.selectedWallpaperScreen || firstScreenName()
    readonly property string currentWallpaper: {
        SessionData.monitorWallpapers;
        return perMonitor ? SessionData.getMonitorWallpaper(selectedScreen) : SessionData.wallpaperPath;
    }
    readonly property var materialTarget: SessionData.materialWallpaperTarget(selectedScreen)
    readonly property var materialEntry: SessionData.materialWallpaperEntry(materialTarget)
    readonly property string materialPreset: Art.resolvePreset(materialEntry.preset, SessionData.materialWallpaperProfiles)
    readonly property bool materialWallpaper: currentWallpaper === ""
    readonly property string pendingWallpaperInstall: PopoutService.pendingWallpaperInstall
    readonly property bool dynamicTheme: Theme.currentTheme === Theme.dynamic
    readonly property var selectedDisplay: Quickshell.screens.find(screen => screen.name === selectedScreen) ?? Quickshell.screens[0]
    readonly property real displayAspectRatio: selectedDisplay ? selectedDisplay.width / selectedDisplay.height : Art.designWidth / Art.designHeight
    readonly property bool hasWallpaper: currentWallpaper !== ""
    readonly property bool wallpaperIsImage: hasWallpaper && !currentWallpaper.startsWith("#")
    readonly property bool cyclingEnabled: {
        SessionData.monitorCyclingSettings;
        return perMonitor ? SessionData.getMonitorCyclingSettings(selectedScreen).enabled : SessionData.wallpaperCyclingEnabled;
    }
    readonly property var themePalette: ThemePalette.pick({
        "primary": Theme.primary,
        "secondary": Theme.secondary,
        "tertiary": Theme.tertiary,
        "primaryContainer": Theme.primaryContainer,
        "info": Theme.info,
        "error": Theme.error,
        "warning": Theme.warning
    })
    readonly property string colorModeStatus: {
        if (SettingsData.matugenSmartMode)
            return I18n.tr("Wallpaper");
        if (!SessionData.themeModeAutoEnabled)
            return I18n.tr("Manual");
        const label = SessionData.themeModeAutoMode === "location" ? I18n.tr("Location") : I18n.tr("Schedule");
        if (!SessionData.themeModeNextTransition)
            return label;
        return label + " · " + Format.formatIsoTime(SessionData.themeModeNextTransition);
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    Component.onCompleted: {
        WallpaperCyclingService.cyclingActive;
        refreshIconThemes();
        SettingsData.detectAvailableCursorThemes();
        if (iconFolderProbeTheme !== pickedIconTheme)
            probeIconFolders(false);
    }

    function loadIconLibrary() {
        Proc.runCommand("iconLibrary", [Proc.dmsBin, "icon-theme", "list", "--state-dir", Theme.stateDir], (output, exitCode) => {
            root.iconLibrary = IconFolders.parseLibrary(output);
            root.cursorLibrary = IconFolders.parseCursorLibrary(output);
        }, 0, undefined, root);
    }

    function refreshIconThemes() {
        SettingsData.detectAvailableIconThemes();
        loadIconLibrary();
    }

    function refreshCursorThemes() {
        SettingsData.detectAvailableCursorThemes();
        loadIconLibrary();
    }

    function iconRefusalText(reply, kind) {
        switch (reply.code) {
        case "no-theme":
            return kind === "cursor" ? I18n.tr("No cursor theme found there", "cursor theme install error, the picked archive or folder holds no theme") : I18n.tr("No icon theme found there", "icon theme install error, the picked archive or folder holds no theme");
        case "in-use":
            return I18n.tr("%1 still uses it", "icon theme remove error, %1 is a list of icon theme names").arg(reply.themes.map(IconFolders.label).join(", "));
        case "not-removable":
            return I18n.tr("Only themes in your own icon folder can be removed", "icon theme remove error");
        }
        return reply.reason;
    }

    function browseIconTheme(folder) {
        iconInstallFolder = folder;
        iconBrowserLoader.active = true;
        if (iconBrowserLoader.item)
            iconBrowserLoader.item.open();
    }

    function browseCursorTheme(folder) {
        cursorInstallFolder = folder;
        cursorBrowserLoader.active = true;
        if (cursorBrowserLoader.item)
            cursorBrowserLoader.item.open();
    }

    function installPack(kind, path, replace) {
        const isCursor = kind === "cursor";
        if (isCursor)
            cursorInstalling = true;
        else
            iconInstalling = true;
        const subcmd = isCursor ? "cursor-theme" : "icon-theme";
        const args = [Proc.dmsBin, subcmd, "install"].concat(replace ? ["--replace"] : [], ["--", path]);
        Proc.runCommand(null, args, (output, exitCode) => {
            if (isCursor)
                root.cursorInstalling = false;
            else
                root.iconInstalling = false;
            const reply = IconFolders.parseReply(output);
            if (exitCode === 0) {
                ToastService.showInfo(I18n.tr("Installed: %1", "theme install toast, %1 is a list of theme names").arg(reply.themes.join(", ")));
                if (isCursor)
                    root.refreshCursorThemes();
                else
                    root.refreshIconThemes();
                return;
            }
            if (reply.code !== "exists") {
                const title = isCursor ? I18n.tr("Cursor theme not installed", "cursor theme install error toast title") : I18n.tr("Icon theme not installed", "icon theme install error toast title");
                ToastService.showError(title, root.iconRefusalText(reply, kind));
                return;
            }
            profileConfirm.showWithOptions({
                "title": isCursor ? I18n.tr("Replace cursor theme", "cursor theme install dialog title") : I18n.tr("Replace icon theme", "icon theme install dialog title"),
                "message": I18n.tr("%1 is already installed. Replace it?", "icon theme install confirmation, %1 is a list of icon theme names").arg(reply.themes.join(", ")),
                "confirmText": I18n.tr("Replace"),
                "cancelText": I18n.tr("Cancel"),
                "danger": true,
                "onConfirm": () => root.installPack(kind, path, true)
            });
        }, 0, Proc.noTimeout, root);
    }

    function confirmRemovePack(kind, name) {
        const isCursor = kind === "cursor";
        profileConfirm.showWithOptions({
            "title": isCursor ? I18n.tr("Remove cursor theme", "cursor theme remove dialog title") : I18n.tr("Remove icon theme", "icon theme remove dialog title"),
            "message": I18n.tr("Remove '%1' from your icon folder?", "icon theme remove confirmation, %1 is an icon theme name").arg(name),
            "confirmText": I18n.tr("Remove"),
            "cancelText": I18n.tr("Cancel"),
            "danger": true,
            "onConfirm": () => root.removePack(kind, name)
        });
    }

    function removePack(kind, name) {
        const isCursor = kind === "cursor";
        const subcmd = isCursor ? "cursor-theme" : "icon-theme";
        const args = [Proc.dmsBin, subcmd, "remove", "--state-dir", Theme.stateDir];
        for (const used of [SettingsData.iconThemeDark, SettingsData.iconThemeLight, SettingsData.systemDefaultIconTheme, SettingsData.cursorSettings?.theme, SettingsData.systemDefaultCursorTheme]) {
            if (used)
                args.push("--in-use", used);
        }
        Proc.runCommand(null, args.concat(["--", name]), (output, exitCode) => {
            if (exitCode === 0) {
                if (isCursor)
                    root.refreshCursorThemes();
                else
                    root.refreshIconThemes();
            } else {
                ToastService.showError(I18n.tr("%1 not removed", "icon theme remove error toast title, %1 is an icon theme name").arg(name), root.iconRefusalText(IconFolders.parseReply(output), kind));
            }
        }, 0, Proc.noTimeout, root);
    }

    function probeIconFolders(enable) {
        const theme = pickedIconTheme;
        iconFolderProbeTheme = theme;
        iconFolderProbe = null;
        iconFolderProbeDone = false;
        iconFolderEnabling = false;
        if (theme === "System Default" || !(enable || SettingsData.iconFolderRecolor || IconFolders.isSelf(theme)))
            return;
        iconFolderEnabling = enable;
        const mode = SessionData.isLightMode ? "light" : "dark";
        Proc.runCommand(null, [Proc.dmsBin, "matugen", "icon-folders", "--icon-theme", theme, "--mode", mode, "--state-dir", Theme.stateDir, "--probe"], (output, exitCode) => {
            if (theme !== root.iconFolderProbeTheme)
                return;
            root.iconFolderProbe = exitCode === 0 ? IconFolders.parseProbe(output) : null;
            root.iconFolderProbeDone = true;
            if (!root.iconFolderEnabling)
                return;
            root.iconFolderEnabling = false;
            if (root.iconFolderProbe?.supported)
                SettingsData.set("iconFolderRecolor", true);
        }, 0, undefined, root);
    }

    function firstScreenName() {
        const screens = Quickshell.screens;
        return screens.length > 0 ? screens[0].name : "";
    }

    function screenNames() {
        const names = [];
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            names.push(SettingsData.getScreenDisplayName(screens[i]));
        return names;
    }

    function screenForDisplayName(value) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (SettingsData.getScreenDisplayName(screens[i]) === value)
                return screens[i].name;
        }
        return "";
    }

    function displayNameForScreen(name) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return SettingsData.getScreenDisplayName(screens[i]);
        }
        return I18n.tr("No displays");
    }

    function openBrowser() {
        wallpaperBrowserLoader.active = true;
        if (wallpaperBrowserLoader.item)
            wallpaperBrowserLoader.item.open();
    }

    function applyWallpaper(path) {
        SessionData.applyWallpaperPick(selectedScreen, path);
    }

    function pickColor() {
        const picker = PopoutService.colorPickerModal;
        if (!picker)
            return;
        picker.selectedColor = currentWallpaper.startsWith("#") ? currentWallpaper : Theme.primary;
        picker.pickerTitle = I18n.tr("Choose Wallpaper Color", "wallpaper color picker title");
        picker.onColorSelectedCallback = function (color) {
            root.applyWallpaper(color.toString());
        };
        picker.show();
    }

    function clearWallpaper() {
        SessionData.setMaterialWallpaper(materialTarget, materialEntry);
    }

    onPendingWallpaperInstallChanged: Qt.callLater(offerPendingInstall)

    function offerPendingInstall() {
        const payload = PopoutService.pendingWallpaperInstall;
        if (!payload)
            return;
        PopoutService.pendingWallpaperInstall = "";
        const layout = Art.parseInstallPayload(payload);
        if (!layout) {
            ToastService.showError(I18n.tr("Invalid wallpaper layout", "material wallpaper import error"));
            return;
        }
        const name = layout.name || Art.profileId("", SessionData.materialWallpaperProfiles);
        profileConfirm.showWithOptions({
            "title": I18n.tr("Install wallpaper", "material wallpaper install dialog title"),
            "message": I18n.tr("Install wallpaper '%1'?", "material wallpaper install confirmation").arg(name),
            "confirmText": I18n.tr("Install", "install action button"),
            "cancelText": I18n.tr("Cancel"),
            "onConfirm": () => root.installLayout(layout, "")
        });
    }

    function installLayout(layout, fallbackName) {
        const id = SessionData.addMaterialWallpaperProfile(layout, fallbackName);
        if (!id) {
            ToastService.showError(I18n.tr("Invalid wallpaper layout", "material wallpaper import error"));
            return;
        }
        SessionData.setMaterialWallpaperPreset(materialTarget, id);
    }

    function importLayoutFile(path) {
        layoutFile.path = "";
        layoutFile.path = path;
    }

    function openLayoutBrowser() {
        layoutBrowserLoader.active = true;
        if (layoutBrowserLoader.item)
            layoutBrowserLoader.item.open();
    }

    function confirmRemoveProfile(id, label) {
        profileConfirm.showWithOptions({
            "title": I18n.tr("Delete"),
            "message": I18n.tr("Delete wallpaper '%1'?", "material wallpaper delete confirmation").arg(label),
            "confirmText": I18n.tr("Delete"),
            "cancelText": I18n.tr("Cancel"),
            "danger": true,
            "onConfirm": () => SessionData.removeMaterialWallpaperProfile(id)
        });
    }

    function selectSeed(seed) {
        if (!SessionData.setMaterialWallpaperSeed(materialTarget, seed))
            return;
        SettingsData.setMatugenSeedColor("");
    }

    function pickSeed() {
        const picker = PopoutService.colorPickerModal;
        if (!picker)
            return;
        picker.selectedColor = materialEntry.seed;
        picker.pickerTitle = I18n.tr("Seed color", "color picker title, the color the dynamic palette is built from");
        picker.onColorSelectedCallback = function (color) {
            root.selectSeed(Theme.withAlpha(color, 1).toString());
        };
        picker.show();
    }

    ConfigInclude {
        id: cursorInclude
        includeKind: "cursor"
        onFixed: SettingsData.updateCompositorCursor()
    }

    function setCursorHideTimeout(value) {
        const updated = JSON.parse(JSON.stringify(SettingsData.cursorSettings));
        if (CompositorService.isNiri) {
            updated.niri = updated.niri || {};
            updated.niri.hideAfterInactiveMs = value;
        } else if (CompositorService.isHyprland) {
            updated.hyprland = updated.hyprland || {};
            updated.hyprland.inactiveTimeout = value;
        } else {
            updated.mango = updated.mango || {};
            updated.mango.cursorHideTimeout = value;
        }
        SettingsData.set("cursorSettings", updated);
    }

    function setHyprlandCursorWarp(mode) {
        const updated = JSON.parse(JSON.stringify(SettingsData.cursorSettings));
        updated.hyprland = updated.hyprland || {};
        updated.hyprland.warpOnMonitorChange = mode;
        SettingsData.set("cursorSettings", updated);
    }

    function warnIfMissingQtTheme() {
        if (Quickshell.env("QT_QPA_PLATFORMTHEME") === "gtk3" || Quickshell.env("QT_QPA_PLATFORMTHEME") === "qt6ct" || Quickshell.env("QT_QPA_PLATFORMTHEME_QT6") === "qt6ct" || SettingsData.qtengineActive || Quickshell.env("QT_QPA_PLATFORMTHEME") === "kde")
            return;
        ToastService.showError(I18n.tr("Missing Environment Variables", "qt theme env error title"), I18n.tr("Set one of these environment variables, then restart the shell:\n%1\n\nOnly %2 requires %3 to be installed.", "qt theme env error body, %1 is a list of variable assignments, %2 and %3 are package names").arg(["QT_QPA_PLATFORMTHEME=gtk3", "QT_QPA_PLATFORMTHEME=qt6ct", "QT_QPA_PLATFORMTHEME=qtengine"].join("\n")).arg("qt6ct").arg("qt6ct-kde"));
    }

    SettingsDeferred {
        SettingsCard {
            tab: "wallpaper"
            tags: ["background", "image", "picture", "light", "dark", "mode", "theme", "color", "palette"]
            settingKey: "wallpaper"
            SettingsDropdownRow {
                tab: "wallpaper"
                tags: ["monitor", "display", "screen"]
                settingKey: "selectedMonitor"
                visible: root.perMonitor
                text: I18n.tr("Display")
                currentValue: root.displayNameForScreen(root.selectedScreen)
                options: root.screenNames()
                onValueChanged: value => SettingsUiState.selectedWallpaperScreen = root.screenForDisplayName(value)
            }

            SettingsRow {
                settingKey: "colorMode"
                tags: ["light", "dark", "mode", "theme", "color", "palette"]
                paddingH: SettingsMetrics.heroPadding
                paddingV: SettingsMetrics.heroPadding
                body: Flow {
                    id: hero

                    readonly property bool stacked: width < SettingsMetrics.wallpaperHeroStackWidth
                    readonly property real thumbWidth: stacked ? width : Math.round(Math.min(width, SettingsMetrics.mediaMaxWidth) * SettingsMetrics.wallpaperHeroSplit)

                    width: parent.width
                    spacing: Theme.spacingL

                    SettingsWallpaperThumb {
                        id: thumb
                        width: hero.thumbWidth
                        path: root.currentWallpaper
                        height: width / root.displayAspectRatio
                        showMaterial: true
                        materialComposition: SessionData.getMonitorMaterialWallpaper(root.selectedScreen)
                        onBrowse: root.openBrowser()
                        onPickColor: root.pickColor()
                        onClear: root.clearWallpaper()
                    }

                    Column {
                        id: side

                        readonly property real navRowHeight: (thumb.height - modeGroup.height - spacing - navGroup.spacing) / 2

                        width: hero.stacked ? hero.width : hero.width - hero.thumbWidth - hero.spacing
                        spacing: Theme.spacingM

                        DButtonGroup {
                            id: modeGroup
                            arrowKeysSelect: false
                            width: parent.width
                            fillWidth: true
                            checkEnabled: false
                            model: [
                                {
                                    "text": I18n.tr("Light", "adjective, wallpaper thumbnail label for light mode"),
                                    "icon": "light_mode"
                                },
                                {
                                    "text": I18n.tr("Dark", "adjective, wallpaper thumbnail label for dark mode"),
                                    "icon": "dark_mode"
                                }
                            ]
                            currentIndex: SessionData.isLightMode ? 0 : 1
                            selectionMode: "single"
                            onSelectionChanged: (index, selected) => {
                                if (!selected)
                                    return;
                                const light = index === 0;
                                if (light === SessionData.isLightMode)
                                    return;
                                Theme.screenTransition();
                                Theme.setLightMode(light);
                            }
                        }

                        SettingsGroup {
                            id: navGroup
                            width: parent.width
                            slotColor: SettingsMetrics.controlColor

                            SettingsNavRow {
                                tab: "wallpaper"
                                tags: ["light", "dark", "mode", "schedule", "location", "automatic"]
                                settingKey: "themeScheduleNav"
                                title: I18n.tr("Dark mode")
                                hint: root.colorModeStatus
                                iconName: "schedule"
                                iconBox: true
                                height: hero.stacked ? implicitHeight : Math.max(implicitHeight, side.navRowHeight)
                                paddingH: Theme.spacingM
                                paddingV: Theme.spacingM
                                onClicked: keyboard => root.parentModal?.navigateTo("theme_schedule", keyboard)
                            }

                            SettingsNavRow {
                                tab: "wallpaper"
                                tags: ["theme", "color", "palette", "matugen", "dynamic", "custom", "registry"]
                                settingKey: "themeNav"
                                title: I18n.tr("Theme & colors")
                                hint: Theme.currentThemeLabel
                                height: hero.stacked ? implicitHeight : Math.max(implicitHeight, side.navRowHeight)
                                paddingH: Theme.spacingM
                                paddingV: Theme.spacingM
                                onClicked: keyboard => root.parentModal?.navigateTo("theme", keyboard)

                                leading: DPaletteSwatch {
                                    width: SettingsMetrics.heroLeadingSize
                                    height: width
                                    primaryColor: root.themePalette.primary
                                    secondaryColor: root.themePalette.secondary
                                    tertiaryColor: root.themePalette.tertiary
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsDeferred {
        SettingsCard {
            tab: "wallpaper"
            tags: ["profile", "setup", "preset", "snapshot", "switch"]
            title: profileGrid.visible ? I18n.tr("Profiles", "settings page for saved setups of DMS settings") : ""
            iconName: "style"
            settingKey: "configProfiles"

            // The first profile is only made on the Profiles page, so browsing here never starts the profile service.
            ProfileGrid {
                id: profileGrid

                width: parent?.width ?? 0
                visible: ConfigProfileService.profiles.length > 1
                columns: Math.max(2, Math.floor(width / SettingsMetrics.previewTileMinWidth))
                cellSpacing: Theme.spacingS
                compact: true
                targetScreen: root.selectedDisplay
                parentModal: root.parentModal
            }

            SettingsNavRow {
                tab: "wallpaper"
                iconName: profileGrid.visible ? "" : "style"
                title: profileGrid.visible ? I18n.tr("Manage profiles", "link row opening the page that creates, edits and deletes config profiles") : I18n.tr("Profiles", "settings page for saved setups of DMS settings")
                onClicked: keyboard => root.parentModal?.navigateTo("profiles", keyboard)
            }
        }
    }

    SettingsDeferred {
        SettingsCard {
            tab: "wallpaper"
            tags: ["background", "image", "picture", "fill", "cycling", "transition", "monitor", "display"]
            title: I18n.tr("Wallpaper")
            settingKey: "wallpaperOptions"

            SettingsRow {
                tab: "wallpaper"
                settingKey: "materialPresets"
                tags: ["material", "shape", "preset", "dank", "bloom", "orbit", "garden", "petal", "dune"]
                visible: root.materialWallpaper
                title: I18n.tr("Material", "wallpaper type")
                subtitle: I18n.tr("Shown while no image or color is set", "Material wallpaper presets description")
                modified: root.materialPreset !== Art.defaultPreset
                onResetRequested: SessionData.setMaterialWallpaperPreset(root.materialTarget, Art.defaultPreset)
                body: MaterialWallpaperPresets {
                    preset: root.materialPreset
                    seed: root.materialEntry.seed
                    aspectRatio: root.displayAspectRatio
                    onSelected: preset => SessionData.setMaterialWallpaperPreset(root.materialTarget, preset)
                    onRemoveRequested: (preset, label) => root.confirmRemoveProfile(preset, label)
                    onImportRequested: root.openLayoutBrowser()
                }

                DButton {
                    visible: Art.hiddenBuiltins(SessionData.materialWallpaperProfiles).length > 0
                    text: I18n.tr("Restore")
                    iconName: "restore"
                    onClicked: SessionData.restoreMaterialWallpaperProfiles()
                }

                DButton {
                    text: I18n.tr("Create")
                    iconName: "open_in_new"
                    tooltipText: Site.wallpaperCreator
                    onClicked: Qt.openUrlExternally(Site.wallpaperCreator)
                }
            }

            SettingsDropdownRow {
                id: fillModeRow

                readonly property var fillModes: ["Stretch", "Fit", "Fill", "Scrolling", "Tile", "TileVertically", "TileHorizontally", "Pad"]
                readonly property var fillModeLabels: [I18n.tr("Stretch", "wallpaper fill mode"), I18n.tr("Fit", "wallpaper fill mode"), I18n.tr("Fill", "wallpaper fill mode"), I18n.tr("Scroll", "wallpaper fill mode"), I18n.tr("Tile", "wallpaper fill mode"), I18n.tr("Tile Vertically", "wallpaper fill mode"), I18n.tr("Tile Horizontally", "wallpaper fill mode"), I18n.tr("Pad", "wallpaper fill mode")]
                // dms picks the animation driver at launch from this setting
                readonly property bool simpleAnimationDriver: Quickshell.env("QSG_USE_SIMPLE_ANIMATION_DRIVER") === "1"
                readonly property bool driverMismatch: (SettingsData.wallpaperFillMode === "Scrolling") !== simpleAnimationDriver

                tab: "wallpaper"
                tags: ["background", "fill", "fit", "stretch", "tile", "scale"]
                settingKey: "wallpaperFillMode"
                resetKeys: root.perMonitor ? [] : ["wallpaperFillMode"]
                text: I18n.tr("Fill mode")
                description: driverMismatch ? I18n.tr("Requires restart") : ""
                visible: root.wallpaperIsImage
                dropdownWidth: 190
                options: fillModeLabels
                optionIcons: ["aspect_ratio", "fit_screen", "zoom_out_map", "swipe", "grid_view", "view_agenda", "view_column", "padding"]
                currentValue: {
                    SessionData.monitorWallpaperFillModes;
                    const mode = root.perMonitor ? SessionData.getMonitorWallpaperFillMode(root.selectedScreen) : SettingsData.wallpaperFillMode;
                    const idx = fillModes.indexOf(mode);
                    return idx >= 0 ? fillModeLabels[idx] : "";
                }
                onValueChanged: value => {
                    const idx = fillModeLabels.indexOf(value);
                    if (idx < 0)
                        return;
                    if (root.perMonitor) {
                        SessionData.setMonitorWallpaperFillMode(root.selectedScreen, fillModes[idx]);
                        return;
                    }
                    SettingsData.set("wallpaperFillMode", fillModes[idx]);
                }
            }

            ColorDropdownRow {
                tab: "wallpaper"
                tags: ["background", "color", "fill", "fit", "custom"]
                settingKey: "wallpaperBackgroundColorMode"
                resetKeys: ["wallpaperBackgroundColorMode", "wallpaperBackgroundCustomColor"]
                text: I18n.tr("Background color")
                visible: root.wallpaperIsImage
                dropdownWidth: 220
                options: [
                    {
                        "value": "black",
                        "previewColor": SettingsData.wallpaperBackgroundColorFor("black"),
                        "label": I18n.tr("Black", "wallpaper background color option")
                    },
                    {
                        "value": "white",
                        "previewColor": SettingsData.wallpaperBackgroundColorFor("white"),
                        "label": I18n.tr("White", "wallpaper background color option")
                    },
                    {
                        "value": "primary",
                        "previewColor": SettingsData.wallpaperBackgroundColorFor("primary"),
                        "label": I18n.tr("Primary")
                    },
                    {
                        "value": "surface",
                        "previewColor": SettingsData.wallpaperBackgroundColorFor("surface"),
                        "label": I18n.tr("Surface Container")
                    },
                    {
                        "value": "custom",
                        "label": I18n.tr("Custom")
                    }
                ]
                currentMode: SettingsData.wallpaperBackgroundColorMode
                customColor: SettingsData.wallpaperBackgroundCustomColor || "#000000"
                pickerTitle: I18n.tr("Background color")
                onModeSelected: mode => SettingsData.set("wallpaperBackgroundColorMode", mode)
                onCustomColorSelected: selectedColor => SettingsData.set("wallpaperBackgroundCustomColor", selectedColor.toString())
            }

            SettingsToggleRow {
                tab: "wallpaper"
                tags: ["per-mode", "light", "dark", "theme"]
                settingKey: "perModeWallpaper"
                text: I18n.tr("Separate light and dark")
                checked: SessionData.perModeWallpaper
                onToggled: toggled => SessionData.setPerModeWallpaper(toggled)
            }

            SettingsToggleRow {
                tab: "wallpaper"
                tags: ["per-monitor", "multi-monitor", "display", "monitor"]
                settingKey: "perMonitorWallpaper"
                text: I18n.tr("Separate per display")
                checked: SessionData.perMonitorWallpaper
                onToggled: toggled => SessionData.setPerMonitorWallpaper(toggled)
            }

            SettingsRow {
                visible: root.perMonitor
                title: I18n.tr("Use default wallpaper", "inherit the global wallpaper on this display")
                DButton {
                    text: I18n.tr("Reset")
                    onClicked: SessionData.setMonitorWallpaper(root.selectedScreen, "")
                }
            }

            SettingsDropdownRow {
                tab: "wallpaper"
                tags: ["matugen", "target", "monitor", "theming", "dynamic", "colors"]
                settingKey: "matugenTargetMonitor"
                visible: root.perMonitor
                text: I18n.tr("Matugen source display")
                description: I18n.tr("Theme colors come from this display's wallpaper", "matugen source display dropdown description")
                currentValue: {
                    if (!SettingsData.matugenTargetMonitor)
                        return root.displayNameForScreen(root.firstScreenName()) + " (" + I18n.tr("Default") + ")";
                    return root.displayNameForScreen(SettingsData.matugenTargetMonitor);
                }
                options: root.screenNames()
                onValueChanged: value => {
                    const screen = root.screenForDisplayName(value);
                    if (screen)
                        SettingsData.setMatugenTargetMonitor(screen);
                }
            }

            SettingsSplitRow {
                tab: "wallpaper"
                tags: ["cycling", "automatic", "rotate", "slideshow", "folder", "interval"]
                settingKey: "wallpaperCyclingEnabled"
                visible: (SessionData.wallpaperPath !== "" || root.perMonitor) && !root.perMode
                title: I18n.tr("Automatic cycling")
                subtitle: SettingsTabs.page("wallpaper_cycling")?.hint ?? ""
                checked: root.cyclingEnabled
                onNavigated: keyboard => root.parentModal?.navigateTo("wallpaper_cycling", keyboard)
                onToggled: toggled => {
                    if (root.perMonitor) {
                        SessionData.setMonitorCyclingEnabled(root.selectedScreen, toggled);
                        return;
                    }
                    SessionData.setWallpaperCyclingEnabled(toggled);
                }
            }

            SettingsDropdownRow {
                tab: "wallpaper"
                tags: ["transition", "effect", "animation", "change"]
                settingKey: "wallpaperTransition"
                resetStore: SessionData
                resetKeys: ["wallpaperTransition"]
                text: I18n.tr("Transition", "noun, wallpaper change animation setting label")

                function getTransitionLabel(t) {
                    switch (t) {
                    case "random":
                        return I18n.tr("Random", "wallpaper transition option");
                    case "none":
                        return I18n.tr("None", "wallpaper transition option");
                    case "fade":
                        return I18n.tr("Fade", "wallpaper transition option");
                    case "wipe":
                        return I18n.tr("Wipe", "wallpaper transition option");
                    case "disc":
                        return I18n.tr("Disc", "wallpaper transition option");
                    case "stripes":
                        return I18n.tr("Stripes", "wallpaper transition option");
                    case "iris bloom":
                        return I18n.tr("Iris Bloom", "wallpaper transition option");
                    case "pixelate":
                        return I18n.tr("Pixelate", "wallpaper transition option");
                    case "portal":
                        return I18n.tr("Portal", "wallpaper transition option");
                    default:
                        return t.charAt(0).toUpperCase() + t.slice(1);
                    }
                }

                currentValue: getTransitionLabel(SessionData.wallpaperTransition)
                options: [I18n.tr("Random", "wallpaper transition option")].concat(SessionData.availableWallpaperTransitions.map(t => getTransitionLabel(t)))
                onValueChanged: value => {
                    const transitionMap = {};
                    transitionMap[I18n.tr("Random", "wallpaper transition option")] = "random";
                    SessionData.availableWallpaperTransitions.forEach(t => {
                        transitionMap[getTransitionLabel(t)] = t;
                    });
                    SessionData.setWallpaperTransition(transitionMap[value] || value.toLowerCase());
                }
            }

            SettingsRow {
                visible: SessionData.wallpaperTransition === "random"
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        text: I18n.tr("Include transitions")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                    }

                    DFilterChips {
                        width: parent.width
                        multiSelect: true
                        model: SessionData.availableWallpaperTransitions.filter(t => t !== "none").map(t => ({
                                    "value": t,
                                    "label": t.replace(/\b\w/g, c => c.toUpperCase())
                                }))
                        selectedValues: SessionData.includedTransitions
                        onSelectionToggled: (index, selected) => {
                            const transition = model[index].value;
                            let included = SessionData.includedTransitions.slice();
                            if (selected && !included.includes(transition))
                                included.push(transition);
                            else if (!selected)
                                included = included.filter(t => t !== transition);
                            SessionData.includedTransitions = included;
                        }
                    }
                }
            }

            SettingsToggleRow {
                tab: "wallpaper"
                tags: ["blur", "overview", "niri"]
                settingKey: "blurWallpaperOnOverview"
                visible: CompositorService.isNiri
                text: I18n.tr("Blur on overview")
                checked: SettingsData.blurWallpaperOnOverview
                onToggled: checked => SettingsData.set("blurWallpaperOnOverview", checked)
            }

            SettingsToggleRow {
                tab: "wallpaper"
                tags: ["wallpaper", "video", "animated", "battery", "power", "pause"]
                settingKey: "pauseVideoWallpaperOnBattery"
                visible: BatteryService.batteryAvailable
                text: I18n.tr("Pause video wallpaper on battery", "Settings toggle: stop video wallpaper playback while running on battery power")
                checked: SettingsData.pauseVideoWallpaperOnBattery
                onToggled: checked => SettingsData.set("pauseVideoWallpaperOnBattery", checked)
            }

            SettingsNavRow {
                tab: "wallpaper"
                tags: ["lock", "screen", "background"]
                iconName: "lock"
                title: I18n.tr("Lock screen")
                hint: SettingsData.lockScreenWallpaperPath ? SettingsData.lockScreenWallpaperPath.split("/").pop() : I18n.tr("Use desktop wallpaper")
                onClicked: keyboard => {
                    SettingsSearchService.navigateToSection("lockScreenWallpaperPath");
                    root.parentModal?.navigateTo("lock_screen", keyboard);
                }
            }

            SettingsNavRow {
                tab: "wallpaper"
                tags: ["folders", "directories", "library"]
                settingKey: "wallpaperFolders"
                iconName: "folder"
                title: I18n.tr("Wallpapers", "wallpaper folders settings row")
                hint: SettingsTabs.page("wallpaper_folders")?.hint ?? ""
                onClicked: keyboard => root.parentModal?.navigateTo("wallpaper_folders", keyboard)
            }
        }
    }

    SettingsDeferred {
        when: root.materialWallpaper

        SettingsCard {
            tab: "wallpaper"
            tags: ["material", "seed", "color", "palette", "hue", "matugen", "dynamic", "theme"]
            title: I18n.tr("Theme color", "Material wallpaper seed card")
            settingKey: "materialSeed"

            SettingsNoteRow {
                visible: !Theme.matugenAvailable
                text: I18n.tr("Install the %1 package for dynamic theming", "matugen installation hint, %1 is the package name").arg("matugen")
            }

            SettingsRow {
                visible: Theme.matugenAvailable && !root.dynamicTheme
                title: I18n.tr("Dynamic theme is off", "Material seed card status")
                subtitle: I18n.tr("Shapes use the %1 theme's colors", "Material seed card status, %1 is a theme name").arg(Theme.currentThemeLabel)
                DButton {
                    text: I18n.tr("Use Dynamic", "switch the shell theme to the dynamic palette")
                    onClicked: Theme.switchTheme(Theme.dynamic)
                }
            }

            SettingsRow {
                visible: root.dynamicTheme && SettingsData.matugenSeedColor !== ""
                title: I18n.tr("A custom seed color overrides this", "Material seed card status")
                subtitle: I18n.tr("Set under Theme & colors, Derived color", "Material seed card status")
                leading: DColorSwatch {
                    width: SettingsMetrics.heroLeadingSize
                    height: width
                    swatchColor: SettingsData.matugenSeedColor
                }
                DButton {
                    text: I18n.tr("Remove override", "clear the custom matugen seed color")
                    onClicked: SettingsData.setMatugenSeedColor("")
                }
            }

            SettingsRow {
                tab: "wallpaper"
                tags: ["seed", "hue", "color", "material", "palette"]
                settingKey: "materialSeedColor"
                visible: root.dynamicTheme
                enabled: Theme.matugenAvailable
                title: I18n.tr("Seed color", "color picker title, the color the dynamic palette is built from")
                subtitle: I18n.tr("The shell palette is built from this color. Shapes take their colors from that palette.", "Material seed picker description")
                modified: root.materialEntry.seed !== Art.defaultSeed
                onResetRequested: root.selectSeed(Art.defaultSeed)
                DActionButton {
                    iconName: "colorize"
                    iconColor: Theme.primary
                    backgroundColor: SettingsMetrics.controlColor
                    enabled: Theme.matugenAvailable
                    Accessible.name: I18n.tr("Custom color")
                    tooltipText: Accessible.name
                    onClicked: root.pickSeed()
                }
                body: MaterialSeedPicker {
                    id: seedPicker
                    seed: root.materialEntry.seed
                    enabled: Theme.matugenAvailable
                    onSeedSelected: seed => root.selectSeed(seed)
                }
            }

            SettingsSliderRow {
                tab: "wallpaper"
                tags: ["hue", "seed", "color", "material", "warm", "cool"]
                settingKey: "materialSeedHue"
                visible: root.dynamicTheme
                enabled: Theme.matugenAvailable
                text: I18n.tr("Hue", "Hue angle in the color picker")
                description: I18n.tr("Fine-tune the seed around the color wheel", "Material seed hue slider description")
                minimum: 0
                maximum: 359
                unit: "°"
                value: Math.round(Art.hueOf(root.materialEntry.seed)) % 360
                onSliderDragFinished: finalValue => root.selectSeed(Art.seedForHue(finalValue, root.materialEntry.seed))
                trackGradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: Art.seedForHue(0)
                    }
                    GradientStop {
                        position: 1 / 12
                        color: Art.seedForHue(30)
                    }
                    GradientStop {
                        position: 2 / 12
                        color: Art.seedForHue(60)
                    }
                    GradientStop {
                        position: 3 / 12
                        color: Art.seedForHue(90)
                    }
                    GradientStop {
                        position: 4 / 12
                        color: Art.seedForHue(120)
                    }
                    GradientStop {
                        position: 5 / 12
                        color: Art.seedForHue(150)
                    }
                    GradientStop {
                        position: 6 / 12
                        color: Art.seedForHue(180)
                    }
                    GradientStop {
                        position: 7 / 12
                        color: Art.seedForHue(210)
                    }
                    GradientStop {
                        position: 8 / 12
                        color: Art.seedForHue(240)
                    }
                    GradientStop {
                        position: 9 / 12
                        color: Art.seedForHue(270)
                    }
                    GradientStop {
                        position: 10 / 12
                        color: Art.seedForHue(300)
                    }
                    GradientStop {
                        position: 11 / 12
                        color: Art.seedForHue(330)
                    }
                    GradientStop {
                        position: 1
                        color: Art.seedForHue(360)
                    }
                }
            }

            SettingsRow {
                visible: root.dynamicTheme && MatugenPreviewService.seedPreviewFailed
                title: I18n.tr("Color previews unavailable", "Material seed card status")
                subtitle: I18n.tr("Swatches show the seed color itself", "Material seed card status")
                DButton {
                    text: I18n.tr("Retry")
                    onClicked: seedPicker.retry()
                }
            }

            SettingsNavRow {
                tab: "wallpaper"
                tags: ["scheme", "palette", "vibrant", "neutral", "expressive", "matugen"]
                settingKey: "paletteStyleNav"
                visible: root.dynamicTheme
                title: I18n.tr("Palette style", "matugen scheme navigation row")
                hint: Theme.getMatugenScheme(SettingsData.matugenScheme).label
                leading: DPaletteSwatch {
                    width: SettingsMetrics.heroLeadingSize
                    height: width
                    primaryColor: root.themePalette.primary
                    secondaryColor: root.themePalette.secondary
                    tertiaryColor: root.themePalette.tertiary
                }
                onClicked: keyboard => {
                    SettingsSearchService.navigateToSection("matugenScheme");
                    root.parentModal?.navigateTo("theme", keyboard);
                }
            }
        }
    }

    SettingsDeferred {
        SettingsCard {
            tab: "wallpaper"
            tags: ["surface", "color", "bar", "popout", "modal", "card", "chip", "tooltip", "background", "elevation"]
            title: I18n.tr("Surfaces")
            settingKey: "surfaceRoles"

            SettingsRow {
                settingKey: "surfaceRolesPreview"
                body: SettingsSurfacePreview {
                    width: parent.width
                }
            }

            SurfaceColorRow {
                tab: "wallpaper"
                tags: ["surface", "color", "host", "bar", "popout", "modal", "window"]
                settingKey: "hostSurfaceColor"
                resetKeys: ["hostSurfaceColor", "hostSurfaceCustomColor"]
                text: I18n.tr("Host")
                defaultColor: Theme.surfaceLadder.host
                currentMode: SettingsData.hostSurfaceColor
                customColor: SettingsData.hostSurfaceCustomColor
                onModeSelected: mode => SettingsData.set("hostSurfaceColor", mode)
                onCustomColorSelected: selectedColor => SettingsData.set("hostSurfaceCustomColor", selectedColor.toString())
            }

            SurfaceColorRow {
                tab: "wallpaper"
                tags: ["surface", "color", "card", "row", "section"]
                settingKey: "cardSurfaceColor"
                resetKeys: ["cardSurfaceColor", "cardSurfaceCustomColor"]
                text: I18n.tr("Cards")
                defaultColor: Theme.surfaceLadder.card
                currentMode: SettingsData.cardSurfaceColor
                customColor: SettingsData.cardSurfaceCustomColor
                onModeSelected: mode => SettingsData.set("cardSurfaceColor", mode)
                onCustomColorSelected: selectedColor => SettingsData.set("cardSurfaceCustomColor", selectedColor.toString())
            }

            SurfaceColorRow {
                tab: "wallpaper"
                tags: ["surface", "color", "chip", "field", "dropdown", "input"]
                settingKey: "chipSurfaceColor"
                resetKeys: ["chipSurfaceColor", "chipSurfaceCustomColor"]
                text: I18n.tr("Chip", "surface role")
                defaultColor: Theme.surfaceLadder.chip
                currentMode: SettingsData.chipSurfaceColor
                customColor: SettingsData.chipSurfaceCustomColor
                onModeSelected: mode => SettingsData.set("chipSurfaceColor", mode)
                onCustomColorSelected: selectedColor => SettingsData.set("chipSurfaceCustomColor", selectedColor.toString())
            }

            SurfaceColorRow {
                tab: "wallpaper"
                tags: ["surface", "color", "nested", "chip", "control"]
                settingKey: "chipSurfaceNestedColor"
                resetKeys: ["chipSurfaceNestedColor", "chipSurfaceNestedCustomColor"]
                text: I18n.tr("Nested chip", "surface role")
                defaultColor: Theme.surfaceLadder.nested
                currentMode: SettingsData.chipSurfaceNestedColor
                customColor: SettingsData.chipSurfaceNestedCustomColor
                onModeSelected: mode => SettingsData.set("chipSurfaceNestedColor", mode)
                onCustomColorSelected: selectedColor => SettingsData.set("chipSurfaceNestedCustomColor", selectedColor.toString())
            }

            SurfaceColorRow {
                tab: "wallpaper"
                tags: ["surface", "color", "tooltip", "hint", "hover", "toast"]
                settingKey: "tooltipSurfaceColor"
                resetKeys: ["tooltipSurfaceColor", "tooltipSurfaceCustomColor"]
                text: I18n.tr("Tooltip", "surface role")
                defaultColor: Theme.roleColor("inverseSurface")
                currentMode: SettingsData.tooltipSurfaceColor
                customColor: SettingsData.tooltipSurfaceCustomColor
                onModeSelected: mode => SettingsData.set("tooltipSurfaceColor", mode)
                onCustomColorSelected: selectedColor => SettingsData.set("tooltipSurfaceCustomColor", selectedColor.toString())
            }
        }
    }

    SettingsDeferred {
        SettingsCard {
            tab: "theme"
            tags: ["icon", "theme", "system"]
            title: I18n.tr("Icons", "settings card title for icon theme and icon options")
            settingKey: "iconTheme"

            SettingsToggleRow {
                tab: "theme"
                tags: ["icon", "theme", "light", "dark", "mode"]
                settingKey: "iconThemePerMode"
                text: I18n.tr("Separate light and dark themes")
                checked: SettingsData.iconThemePerMode
                onToggled: checked => SettingsData.setIconThemePerMode(checked)
            }

            SettingsDropdownRow {
                visible: !SettingsData.iconThemePerMode
                tab: "theme"
                tags: ["icon", "theme", "system"]
                settingKey: "iconTheme"
                resetKeys: ["iconThemeDark"]
                resetByKeys: false
                onResetRequested: SettingsData.setIconThemeForMode(SettingsData.specDefault("iconThemeDark"), false)
                text: I18n.tr("Theme")
                currentValue: SettingsData.iconThemeDark
                enableFuzzySearch: true
                popupWidthOffset: 100
                options: root.iconThemeLabels
                optionValues: root.cachedIconThemes
                optionImages: root.iconThemeImages
                optionIcons: root.iconThemeGlyphs
                onValueChanged: value => {
                    SettingsData.setIconThemeForMode(value, false);
                    root.warnIfMissingQtTheme();
                }
            }

            SettingsDropdownRow {
                visible: SettingsData.iconThemePerMode
                tab: "theme"
                tags: ["icon", "theme", "system", "dark"]
                settingKey: "iconThemeDark"
                resetByKeys: false
                onResetRequested: SettingsData.setIconThemeForMode(SettingsData.specDefault("iconThemeDark"), false)
                text: I18n.tr("Dark mode theme")
                currentValue: SettingsData.iconThemeDark
                enableFuzzySearch: true
                popupWidthOffset: 100
                options: root.iconThemeLabels
                optionValues: root.cachedIconThemes
                optionImages: root.iconThemeImages
                optionIcons: root.iconThemeGlyphs
                onValueChanged: value => {
                    SettingsData.setIconThemeForMode(value, false);
                    root.warnIfMissingQtTheme();
                }
            }

            SettingsDropdownRow {
                visible: SettingsData.iconThemePerMode
                tab: "theme"
                tags: ["icon", "theme", "system", "light"]
                settingKey: "iconThemeLight"
                resetByKeys: false
                onResetRequested: SettingsData.setIconThemeForMode(SettingsData.specDefault("iconThemeLight"), true)
                text: I18n.tr("Light mode theme")
                currentValue: SettingsData.iconThemeLight
                enableFuzzySearch: true
                popupWidthOffset: 100
                options: root.iconThemeLabels
                optionValues: root.cachedIconThemes
                optionImages: root.iconThemeImages
                optionIcons: root.iconThemeGlyphs
                onValueChanged: value => {
                    SettingsData.setIconThemeForMode(value, true);
                    root.warnIfMissingQtTheme();
                }
            }

            SettingsDropdownRow {
                visible: root.pickedSelfBuiltIcons
                tab: "theme"
                tags: ["icon", "shape", "tile", "base", "plate", "badge", "circle", "squircle", "rounded", "square", "hexagon", "cookie", "clover", "dux"]
                settingKey: "iconShape"
                text: I18n.tr("Icon shape", "Dux Icons setting, the outline of the tile behind every icon")
                enabled: !root.selfBuiltIconsMissing
                options: root.iconShapeLabels
                optionValues: IconFolders.shapes()
                optionImages: root.iconShapeImages
                currentValue: SettingsData.iconShape
                onValueChanged: value => SettingsData.set("iconShape", value)
            }

            SettingsDropdownRow {
                visible: root.pickedSelfBuiltIcons
                tab: "theme"
                tags: ["icon", "app", "style", "color", "colour", "tinted", "duotone", "themed", "monochrome", "mono", "gray", "grey", "tint", "dux", "dynamic"]
                settingKey: "iconAppStyle"
                text: I18n.tr("App icon style", "Dux Icons setting, how app icons are colored")
                enabled: !root.selfBuiltIconsMissing
                options: [I18n.tr("Color", "Dux Icons app icon style option, each app keeps its own colors"), I18n.tr("Tinted", "Dux Icons app icon style option, each app's own icon repainted in two tones of its tile color"), I18n.tr("Themed", "Dux Icons app icon style option, every app icon is drawn in tones of the theme color"), I18n.tr("Monochrome", "Dux Icons app icon style option, every app icon is drawn in near-gray tones")]
                optionValues: ["color", "tinted", "themed", "monochrome"]
                currentValue: SettingsData.iconAppStyle
                onValueChanged: value => SettingsData.set("iconAppStyle", value)
            }

            SettingsToggleRow {
                visible: root.pickedSelfBuiltIcons
                tab: "theme"
                tags: ["icon", "gradient", "shade", "shading", "tile", "base", "plate", "badge", "dux"]
                settingKey: "iconGradient"
                text: I18n.tr("Shaded icons", "Dux Icons toggle, fills each icon tile with a soft top-to-bottom gradient")
                enabled: !root.selfBuiltIconsMissing
                checked: SettingsData.iconGradient
                onToggled: checked => SettingsData.set("iconGradient", checked)
            }

            SettingsDropdownRow {
                visible: root.pickedSelfBuiltIcons && root.tiledAppIcons
                tab: "theme"
                tags: ["icon", "tile", "base", "plate", "badge", "color", "colour", "app", "theme", "edge", "match", "ring", "dux"]
                settingKey: "iconTileColor"
                text: I18n.tr("Tile color", "Dux Icons setting, where the color of the tile behind each app icon comes from")
                enabled: !root.selfBuiltIconsMissing
                options: [I18n.tr("Theme", "Dux Icons tile color option, tiles take the theme colors"), I18n.tr("App color", "Dux Icons tile color option, each tile takes a color from its app's icon"), I18n.tr("Edge Match", "Dux Icons tile color option, each tile takes the color of the app icon's own background, and the icon grows to fill it without touching the edge"), I18n.tr("Ring", "Dux Icons tile color option, a neutral tile with a ring in the app's color")]
                optionValues: ["theme", "app", "edge", "ring"]
                currentValue: SettingsData.iconTileColor
                onValueChanged: value => SettingsData.set("iconTileColor", value)
            }

            SettingsDropdownRow {
                visible: root.pickedSelfBuiltIcons && root.tiledAppIcons && ["app", "edge", "ring"].includes(SettingsData.iconTileColor)
                tab: "theme"
                tags: ["icon", "tile", "base", "plate", "badge", "color", "colour", "app", "source", "common", "dux"]
                settingKey: "iconColorSource"
                text: I18n.tr("App color", "Dux Icons setting, how the tile color is picked from an app's icon")
                enabled: !root.selfBuiltIconsMissing
                options: [I18n.tr("Best match", "Dux Icons app color source option, picks the color the way the wallpaper's theme color is picked"), I18n.tr("Most common", "Dux Icons app color source option, picks the color that covers most of the icon")]
                optionValues: ["score", "common"]
                currentValue: SettingsData.iconColorSource
                onValueChanged: value => SettingsData.set("iconColorSource", value)
            }

            SettingsDropdownRow {
                visible: root.pickedSelfBuiltIcons && IconFolders.tileStyled(SettingsData.iconAppStyle, SettingsData.iconTileColor)
                tab: "theme"
                tags: ["icon", "tile", "base", "plate", "badge", "style", "vivid", "muted", "tonal", "app", "dux"]
                settingKey: "iconTileStyle"
                text: I18n.tr("Tile style", "Dux Icons setting, how strong the app's own color is on its tile")
                enabled: !root.selfBuiltIconsMissing
                options: [I18n.tr("Tonal", "Dux Icons tile style option, a soft tone of the app's color"), I18n.tr("Vivid", "Dux Icons tile style option, the app's color as strong as in its icon"), I18n.tr("Muted", "Dux Icons tile style option, a near-gray tint of the app's color")]
                optionValues: ["tonal", "content", "neutral"]
                currentValue: SettingsData.iconTileStyle
                onValueChanged: value => SettingsData.set("iconTileStyle", value)
            }

            // -1 is automatic; each slider commits on release since every change rebuilds the pack.
            SettingsToggleSliderRow {
                visible: root.pickedSelfBuiltIcons
                tab: "theme"
                tags: ["icon", "tile", "base", "plate", "badge", "tone", "light", "dark", "brightness", "dux"]
                settingKey: "iconTileTone"
                text: I18n.tr("Tile tone", "Dux Icons setting, how light the tile behind each icon is")
                enabled: !root.selfBuiltIconsMissing
                checked: SettingsData.iconTileTone >= 0
                value: Math.max(0, SettingsData.iconTileTone)
                minimum: 0
                maximum: 100
                modified: checked
                onToggled: checked => SettingsData.set("iconTileTone", checked ? 50 : -1)
                onSliderDragFinished: finalValue => SettingsData.set("iconTileTone", finalValue)
            }

            SettingsDropdownRow {
                visible: root.pickedSelfBuiltIcons
                tab: "theme"
                tags: ["icon", "file", "files", "folder", "folders", "mime", "type", "color", "colour", "tile", "standard", "base", "papirus", "dux"]
                settingKey: "iconFileStyle"
                text: I18n.tr("Files & folders", "Dux Icons setting, how file and folder icons are drawn")
                enabled: !root.selfBuiltIconsMissing
                options: [I18n.tr("Standard", "Dux Icons files and folders option, files and folders sit on the theme tile like every other icon"), I18n.tr("Color", "Dux Icons files and folders option, colored folders and a color for each file type, like Papirus")]
                optionValues: ["standard", "color"]
                currentValue: SettingsData.iconFileStyle
                onValueChanged: value => SettingsData.set("iconFileStyle", value)
            }

            // Themed and Monochrome repaint the Dux apps like any other app, which takes no tone.
            SettingsToggleSliderRow {
                visible: root.pickedSelfBuiltIcons && root.colorAppIcons
                tab: "theme"
                tags: ["icon", "tile", "base", "plate", "badge", "tone", "dux", "labs", "app", "art", "shade"]
                settingKey: "iconOwnTone"
                text: I18n.tr("Dux app tone", "Dux Icons setting, the shade of Dux Labs app art on its tile")
                enabled: !root.selfBuiltIconsMissing
                checked: SettingsData.iconOwnTone >= 0
                value: Math.max(40, SettingsData.iconOwnTone)
                minimum: 40
                maximum: 98
                modified: checked
                onToggled: checked => SettingsData.set("iconOwnTone", checked ? 70 : -1)
                onSliderDragFinished: finalValue => SettingsData.set("iconOwnTone", finalValue)
            }

            SettingsToggleRow {
                visible: !root.pickedSelfBuiltIcons
                tab: "theme"
                tags: ["icon", "folder", "color", "recolor", "theme", "matugen", "dynamic"]
                settingKey: "iconFolderRecolor"
                text: I18n.tr("Match folder colors to theme", "icon theme toggle, recolors the picked icon pack's folders with the theme colors")
                enabled: SettingsData.iconFolderRecolor || root.iconFolderBlocker === ""
                toggling: root.iconFolderEnabling
                checked: SettingsData.iconFolderRecolor
                onToggled: checked => {
                    if (checked)
                        root.probeIconFolders(true);
                    else
                        SettingsData.set("iconFolderRecolor", false);
                }
            }

            SettingsFoldRow {
                id: iconLibraryRow

                tab: "theme"
                tags: ["icon", "theme", "install", "remove", "delete", "preview", "archive", "manage"]
                settingKey: "iconThemeLibrary"
                title: I18n.tr("Manage themes", "settings row that expands to the installed icon themes")
                subtitle: I18n.tr("Preview, install and remove icon themes", "icon theme manager row description")
                open: root.iconLibraryOpen
                onToggled: root.iconLibraryOpen = !root.iconLibraryOpen

                body: Loader {
                    width: parent.width
                    visible: active
                    active: iconLibraryRow.open

                    sourceComponent: SettingsGroup {
                        slotColor: SettingsMetrics.controlColor

                        Repeater {
                            model: (root.cachedIconThemes || []).filter(name => root.iconLibrary[name] !== undefined)

                            SettingsRow {
                                id: themeRow

                                required property string modelData
                                readonly property var info: root.iconLibrary[modelData]
                                readonly property bool picked: modelData === SettingsData.iconThemeDark || modelData === SettingsData.iconThemeLight

                                title: IconFolders.label(modelData)
                                trailingBadge: picked ? I18n.tr("In use", "icon theme list badge, the theme currently applied") : ""

                                supporting: Row {
                                    spacing: Theme.spacingS

                                    Repeater {
                                        model: themeRow.info?.icons ?? []

                                        DSVGIcon {
                                            required property string modelData

                                            source: modelData
                                            size: Theme.iconSizeLarge
                                        }
                                    }
                                }

                                DActionButton {
                                    anchors.verticalCenter: parent?.verticalCenter
                                    visible: (themeRow.info?.removable ?? false) && !themeRow.picked
                                    iconName: "delete"
                                    tooltipText: I18n.tr("Remove")
                                    onClicked: root.confirmRemovePack("icon", themeRow.modelData)
                                }
                            }
                        }

                        SettingsRow {
                            title: I18n.tr("Install theme", "icon theme manager row title")
                            subtitle: I18n.tr("From an archive or a folder. Nothing inside it is run.", "icon theme install row description")

                            DButton {
                                text: I18n.tr("Archive", "button, picks an archive file to install an icon theme from")
                                iconName: "folder_zip"
                                enabled: !root.iconInstalling
                                onClicked: root.browseIconTheme(false)
                            }

                            DButton {
                                text: I18n.tr("Folder", "button, picks a folder to install an icon theme from")
                                iconName: "folder_open"
                                enabled: !root.iconInstalling
                                onClicked: root.browseIconTheme(true)
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsDeferred {
        when: CompositorService.supportsCursorConfig

        SettingsCard {
            tab: "theme"
            tags: ["cursor", "mouse", "pointer", "theme", "size", "hide", "typing", "touch", "timeout"]
            title: I18n.tr("Cursor", "settings card title for mouse cursor theme")
            settingKey: "cursorTheme"

            IncludeSetupBanner {
                include: cursorInclude
            }

            SettingsDropdownRow {
                tab: "theme"
                tags: ["cursor", "mouse", "pointer", "theme"]
                settingKey: "cursorTheme"
                text: I18n.tr("Theme")
                currentValue: SettingsData.cursorSettings.theme
                enableFuzzySearch: true
                popupWidthOffset: 100
                options: root.cachedCursorThemes
                optionImages: root.cursorThemeImages
                optionIcons: root.cursorThemeGlyphs
                modified: SettingsData.cursorSettings.theme !== SettingsData.specDefault("cursorSettings").theme
                onResetRequested: SettingsData.setCursorTheme(SettingsData.specDefault("cursorSettings").theme)
                onValueChanged: value => SettingsData.setCursorTheme(value)
            }

            SettingsSliderRow {
                tab: "theme"
                tags: ["cursor", "mouse", "pointer", "size"]
                settingKey: "cursorSize"
                text: I18n.tr("Size")
                value: SettingsData.cursorSettings.size
                minimum: 12
                maximum: 128
                unit: "px"
                modified: SettingsData.cursorSettings.size !== SettingsData.specDefault("cursorSettings").size
                onResetRequested: SettingsData.setCursorSize(SettingsData.specDefault("cursorSettings").size)
                onSliderValueChanged: newValue => SettingsData.setCursorSize(newValue)
            }

            SettingsToggleSliderRow {
                readonly property int timeout: {
                    if (CompositorService.isNiri)
                        return SettingsData.cursorSettings.niri?.hideAfterInactiveMs || 0;
                    if (CompositorService.isHyprland)
                        return SettingsData.cursorSettings.hyprland?.inactiveTimeout || 0;
                    return SettingsData.cursorSettings.mango?.cursorHideTimeout || 0;
                }

                tab: "theme"
                tags: ["cursor", "hide", "timeout", "inactive"]
                settingKey: "cursorHideAfterInactive"
                text: I18n.tr("Cursor auto-hide timeout")
                checked: timeout > 0
                value: timeout
                // Timeout 0 means off, so the slider starts above it.
                minimum: CompositorService.isNiri ? 100 : 1
                maximum: CompositorService.isNiri ? 5000 : 10
                unit: CompositorService.isNiri ? "ms" : "s"
                modified: checked
                onResetRequested: root.setCursorHideTimeout(0)
                onToggled: checked => root.setCursorHideTimeout(checked ? (CompositorService.isNiri ? 1000 : 3) : 0)
                onSliderDragFinished: finalValue => root.setCursorHideTimeout(finalValue)
            }

            SettingsToggleRow {
                tab: "theme"
                tags: ["cursor", "hide", "typing", "keyboard"]
                settingKey: "cursorHideWhenTyping"
                text: I18n.tr("Hide cursor when typing")
                visible: CompositorService.isNiri || CompositorService.isHyprland
                modified: checked
                checked: CompositorService.isNiri ? (SettingsData.cursorSettings.niri?.hideWhenTyping || false) : (SettingsData.cursorSettings.hyprland?.hideOnKeyPress || false)
                onToggled: checked => {
                    const updated = JSON.parse(JSON.stringify(SettingsData.cursorSettings));
                    if (CompositorService.isNiri) {
                        updated.niri = updated.niri || {};
                        updated.niri.hideWhenTyping = checked;
                    } else {
                        updated.hyprland = updated.hyprland || {};
                        updated.hyprland.hideOnKeyPress = checked;
                    }
                    SettingsData.set("cursorSettings", updated);
                }
            }

            SettingsToggleRow {
                tab: "theme"
                tags: ["cursor", "hide", "touch"]
                settingKey: "cursorHideOnTouch"
                text: I18n.tr("Hide cursor on touch")
                visible: CompositorService.isHyprland
                modified: checked
                checked: SettingsData.cursorSettings.hyprland?.hideOnTouch || false
                onToggled: checked => {
                    const updated = JSON.parse(JSON.stringify(SettingsData.cursorSettings));
                    updated.hyprland = updated.hyprland || {};
                    updated.hyprland.hideOnTouch = checked;
                    SettingsData.set("cursorSettings", updated);
                }
            }

            SettingsDropdownRow {
                readonly property var modes: [-1, 0, 1, 2]
                tab: "theme"
                tags: ["cursor", "warp", "monitor", "display", "focus", "warp_on_monitor_change"]
                settingKey: "cursorWarpOnMonitorChange"
                text: I18n.tr("Warp on display change", "Hyprland cursor option, move the pointer to the last focused window when focus moves to another display")
                visible: CompositorService.isHyprland && HyprlandService.hyprSupports("cursor:warp_on_monitor_change")
                options: [I18n.tr("Same as workspace change", "Hyprland cursor warp option, follow the workspace change warp setting"), I18n.tr("Off"), I18n.tr("On"), I18n.tr("Force", "Hyprland cursor warp option, warp even when cursor warps are disabled")]
                currentValue: options[Math.max(0, modes.indexOf(SettingsData.cursorSettings.hyprland?.warpOnMonitorChange ?? -1))]
                modified: (SettingsData.cursorSettings.hyprland?.warpOnMonitorChange ?? -1) !== -1
                onResetRequested: root.setHyprlandCursorWarp(-1)
                onValueChanged: value => {
                    const index = options.indexOf(value);
                    if (index < 0)
                        return;
                    root.setHyprlandCursorWarp(modes[index]);
                }
            }

            SettingsFoldRow {
                id: cursorLibraryRow

                tab: "theme"
                tags: ["cursor", "theme", "install", "remove", "delete", "preview", "archive", "manage"]
                settingKey: "cursorThemeLibrary"
                title: I18n.tr("Manage themes", "settings row that expands to the installed cursor themes")
                subtitle: I18n.tr("Preview, install and remove cursor themes", "cursor theme manager row description")
                open: root.cursorLibraryOpen
                onToggled: root.cursorLibraryOpen = !root.cursorLibraryOpen

                body: Loader {
                    width: parent.width
                    visible: active
                    active: cursorLibraryRow.open

                    sourceComponent: SettingsGroup {
                        slotColor: SettingsMetrics.controlColor

                        Repeater {
                            model: (root.cachedCursorThemes || []).filter(name => root.cursorLibrary[name] !== undefined)

                            SettingsRow {
                                id: cursorRow

                                required property string modelData
                                readonly property var info: root.cursorLibrary[modelData]
                                readonly property string activeCursor: SettingsData.cursorSettings?.theme === "System Default" ? SettingsData.systemDefaultCursorTheme : (SettingsData.cursorSettings?.theme ?? "")
                                readonly property bool picked: modelData === activeCursor

                                title: cursorRow.modelData
                                trailingBadge: picked ? I18n.tr("In use", "cursor theme list badge, the theme currently applied") : ""

                                supporting: Row {
                                    spacing: Theme.spacingS

                                    Repeater {
                                        model: cursorRow.info?.cursors ?? []

                                        DSVGIcon {
                                            required property string modelData

                                            source: modelData
                                            size: Theme.iconSizeLarge
                                        }
                                    }

                                    DIcon {
                                        name: "arrow_selector_tool"
                                        size: Theme.iconSizeMedium
                                        color: Theme.surfaceVariantText
                                        visible: (cursorRow.info?.cursors?.length ?? 0) === 0
                                    }
                                }

                                DActionButton {
                                    anchors.verticalCenter: parent?.verticalCenter
                                    visible: (cursorRow.info?.removable ?? false) && !cursorRow.picked
                                    iconName: "delete"
                                    tooltipText: I18n.tr("Remove")
                                    onClicked: root.confirmRemovePack("cursor", cursorRow.modelData)
                                }
                            }
                        }

                        SettingsRow {
                            title: I18n.tr("Install theme", "cursor theme manager row title")
                            subtitle: I18n.tr("From an archive or a folder. Nothing inside it is run.", "icon theme install row description")

                            DButton {
                                text: I18n.tr("Archive", "button, picks an archive file to install a cursor theme from")
                                iconName: "folder_zip"
                                enabled: !root.cursorInstalling
                                onClicked: root.browseCursorTheme(false)
                            }

                            DButton {
                                text: I18n.tr("Folder", "button, picks a folder to install a cursor theme from")
                                iconName: "folder_open"
                                enabled: !root.cursorInstalling
                                onClicked: root.browseCursorTheme(true)
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsDeferred {
        SettingsCard {
            tab: "theme"
            tags: ["font", "fonts", "family", "text", "typography", "monospace"]
            title: I18n.tr("Typography", "settings card title for font options")
            settingKey: "typography"
            iconName: "text_fields"

            SettingsRow {
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        width: parent.width
                        text: "Aa Bb Cc 123"
                        font.family: Theme.resolvedFontFamily(SettingsData.fontFamily)
                        font.pixelSize: Theme.fontSizeXXLarge
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: "Display Aa Bb Cc"
                        fontToken: "display"
                        font.pixelSize: Theme.fontSizeXLarge
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.tr("The quick brown fox jumps over the lazy dog")
                        font.family: Theme.resolvedFontFamily(SettingsData.fontFamily)
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: "monospace { code: 0x1F; }"
                        font.family: Theme.resolvedMonoFontFamily(SettingsData.monoFontFamily)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                    }
                }
            }

            SettingsFontDropdownRow {
                tab: "theme"
                tags: ["font", "fonts", "family", "normal", "text"]
                settingKey: "fontFamily"
                text: I18n.tr("Family", "font family dropdown label")
                maxPopupHeight: 400
                currentFont: SettingsData.fontFamily
                onFontSelected: family => SettingsData.set("fontFamily", family || Theme.defaultFontFamily)
            }

            SettingsSliderRow {
                tab: "theme"
                tags: ["font", "weight", "bold", "light"]
                settingKey: "fontWeight"
                text: I18n.tr("Weight", "font weight slider label")
                minimum: Font.Thin
                maximum: Font.Black
                step: 100
                showStops: true
                unit: ""
                value: SettingsData.fontWeight
                onSliderValueChanged: newValue => SettingsData.set("fontWeight", newValue)
            }

            SettingsSliderRow {
                tab: "theme"
                tags: ["font", "scale", "size", "zoom"]
                settingKey: "fontScale"
                text: I18n.tr("Scale", "noun, font scale slider and display scale setting label")
                minimum: 75
                maximum: 150
                value: Math.round(SettingsData.fontScale * 100)
                onSliderValueChanged: newValue => SettingsData.set("fontScale", newValue / 100)
            }
            SettingsFontDropdownRow {
                tab: "theme"
                tags: ["font", "monospace", "code", "terminal", "process"]
                settingKey: "monoFontFamily"
                text: I18n.tr("Monospace family")
                maxPopupHeight: 400
                defaultFamily: Theme.defaultMonoFontFamily
                currentFont: SettingsData.monoFontFamily
                onFontSelected: family => SettingsData.set("monoFontFamily", family || Theme.defaultMonoFontFamily)
            }

            SettingsFontDropdownRow {
                tab: "theme"
                tags: ["font", "display", "stylistic", "serif", "title", "headline"]
                settingKey: "displayFontFamily"
                text: I18n.tr("Display family")
                maxPopupHeight: 400
                defaultFamily: Theme.defaultDisplayFontFamily
                currentFont: SettingsData.displayFontFamily
                onFontSelected: family => SettingsData.set("displayFontFamily", family || Theme.defaultDisplayFontFamily)
            }
        }
    }

    readonly property Component advancedContent: Column {
        width: parent?.width ?? 0
        spacing: SettingsMetrics.cardGap

        SettingsCard {
            tab: "wallpaper"
            tags: ["blur", "layer", "external", "disable", "swww", "hyprpaper", "swaybg"]
            title: I18n.tr("Wallpaper layer", "settings card title for how the wallpaper surface is drawn")
            settingKey: "wallpaperAdvanced"

            SettingsToggleRow {
                tab: "wallpaper"
                tags: ["disable", "external", "management", "swww", "hyprpaper", "swaybg"]
                settingKey: "disableWallpapers"
                text: I18n.tr("Use external manager")
                description: I18n.tr("DMS stops drawing wallpapers on every display", "use external wallpaper manager toggle description")
                checked: {
                    const prefs = SettingsData.screenPreferences?.wallpaper;
                    return Array.isArray(prefs) && prefs.length === 0;
                }
                onToggled: checked => {
                    const prefs = Object.assign({}, SettingsData.screenPreferences || {});
                    prefs.wallpaper = checked ? [] : ["all"];
                    SettingsData.set("screenPreferences", prefs);
                }
            }

            SettingsToggleRow {
                tab: "wallpaper"
                tags: ["blur", "duplicate", "layer", "compositor", "niri", "blurwallpaper"]
                settingKey: "blurredWallpaperLayer"
                visible: CompositorService.isNiri
                text: I18n.tr("Blur layer")
                description: I18n.tr("Layer namespace %1, needs a niri blur rule", "blur layer toggle description, %1 is the layer namespace").arg("dms:blurwallpaper")
                checked: SettingsData.blurredWallpaperLayer
                onToggled: checked => SettingsData.set("blurredWallpaperLayer", checked)
            }
        }

        SettingsCard {
            tab: "theme"
            tags: ["text", "render", "rendering", "quality"]
            title: I18n.tr("Text rendering", "settings card title for the text renderer options")
            settingKey: "textRendering"

            SettingsButtonGroupRow {
                tab: "theme"
                tags: ["text", "render", "rendering", "type", "native", "qt", "curve", "freetype", "distance-field", "rasterizer"]
                settingKey: "textRenderType"
                text: I18n.tr("Renderer", "text rendering engine setting label")
                model: [I18n.tr("Native", "adjective, text renderer option, native platform rendering"), "Qt", I18n.tr("Curve", "noun, text renderer option, qt curve rendering")]
                currentIndex: {
                    switch (SettingsData.textRenderType) {
                    case SettingsData.TextRenderType.Qt:
                        return 1;
                    case SettingsData.TextRenderType.Curve:
                        return 2;
                    default:
                        return 0;
                    }
                }
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    switch (index) {
                    case 1:
                        SettingsData.set("textRenderType", SettingsData.TextRenderType.Qt);
                        break;
                    case 2:
                        SettingsData.set("textRenderType", SettingsData.TextRenderType.Curve);
                        break;
                    default:
                        SettingsData.set("textRenderType", SettingsData.TextRenderType.Native);
                        break;
                    }
                }
            }

            SettingsDropdownRow {
                id: renderQualityRow
                tab: "theme"
                tags: ["text", "render", "quality", "level"]
                settingKey: "textRenderQuality"
                text: I18n.tr("Quality", "text render quality dropdown label")
                options: [I18n.tr("Default"), I18n.tr("Low", "quality level option"), I18n.tr("Normal", "quality level option"), I18n.tr("High", "quality level option"), I18n.tr("Very High", "quality level option")]
                currentValue: options[SettingsData.textRenderQuality] ?? options[0]
                onValueChanged: value => {
                    const index = renderQualityRow.options.indexOf(value);
                    if (index < 0)
                        return;
                    SettingsData.set("textRenderQuality", index);
                }
            }
        }

        SettingsCard {
            tab: "theme"
            tags: ["render", "control", "cache", "startup", "performance"]
            title: I18n.tr("Performance")
            settingKey: "shellPerformance"
            visible: "renderControl" in Quickshell

            SettingsToggleRow {
                // dms turns this off for the runtime at launch
                readonly property bool launchedEnabled: Quickshell.env("QS_DISABLE_RENDER_CONTROL") === null

                visible: "renderControl" in Quickshell
                tab: "theme"
                tags: ["render", "control", "damage", "gpu", "vram", "memory", "performance"]
                settingKey: "renderControlEnabled"
                text: I18n.tr("Render control", "toggle for the shell's own render loop")
                description: checked !== launchedEnabled ? I18n.tr("Requires restart") : I18n.tr("Redraws only what changed on screen", "render control toggle description")
                checked: SettingsData.renderControlEnabled
                onToggled: checked => SettingsData.set("renderControlEnabled", checked)
            }

            SettingsToggleRow {
                // dms turns this off for the runtime at launch
                readonly property bool launchedEnabled: Quickshell.env("QS_DISABLE_DISK_CACHE") === null

                visible: "renderControl" in Quickshell
                tab: "theme"
                tags: ["cache", "qml", "startup", "start", "disk", "performance"]
                settingKey: "qmlCacheEnabled"
                text: I18n.tr("Startup cache", "toggle for the compiled interface cache")
                description: checked !== launchedEnabled ? I18n.tr("Requires restart") : I18n.tr("Reuses the compiled interface from the last start", "startup cache toggle description")
                checked: SettingsData.qmlCacheEnabled
                onToggled: checked => SettingsData.set("qmlCacheEnabled", checked)
            }
        }
    }

    ConfirmModal {
        id: profileConfirm
    }

    FileView {
        id: layoutFile
        blockLoading: false
        onLoaded: {
            try {
                root.installLayout(JSON.parse(text()), Paths.strip(path).split("/").pop().replace(/\.json$/i, ""));
            } catch (error) {
                ToastService.showError(I18n.tr("Invalid JSON format: %1", "custom theme file error toast, %1 is the error message").arg(error.message));
            }
        }
        onLoadFailed: error => ToastService.showError(I18n.tr("Invalid wallpaper layout", "material wallpaper import error"))
    }

    LazyLoader {
        id: iconBrowserLoader
        active: false

        FileBrowserModal {
            parentModal: root.parentModal
            browserTitle: I18n.tr("Install icon theme", "icon theme file browser title")
            bucket: "iconTheme"
            mode: root.iconInstallFolder ? "openFolder" : "open"
            filters: root.iconInstallFolder ? [] : ["*.tar.gz", "*.tgz", "*.tar.xz", "*.txz", "*.tar.zst", "*.tar", "*.zip"]
            onAccepted: paths => root.installPack("icon", paths[0], false)
        }
    }

    LazyLoader {
        id: cursorBrowserLoader
        active: false

        FileBrowserModal {
            parentModal: root.parentModal
            browserTitle: I18n.tr("Install cursor theme", "cursor theme file browser title")
            bucket: "cursorTheme"
            mode: root.cursorInstallFolder ? "openFolder" : "open"
            filters: root.cursorInstallFolder ? [] : ["*.tar.gz", "*.tgz", "*.tar.xz", "*.txz", "*.tar.zst", "*.tar", "*.zip"]
            onAccepted: paths => root.installPack("cursor", paths[0], false)
        }
    }

    LazyLoader {
        id: layoutBrowserLoader
        active: false

        FileBrowserModal {
            parentModal: root.parentModal
            browserTitle: I18n.tr("Import")
            bucket: "wallpaper"
            showHiddenFiles: true
            filters: ["*.json"]
            onAccepted: paths => root.importLayoutFile(paths[0])
        }
    }

    LazyLoader {
        id: wallpaperBrowserLoader
        active: false

        FileBrowserModal {
            parentModal: root.parentModal
            browserTitle: I18n.tr("Select Wallpaper", "wallpaper file browser title")
            bucket: "wallpaper"
            showHiddenFiles: true
            startPath: root.currentWallpaper
            filters: WallpaperFormats.nameFilters(true)
            onAccepted: paths => root.applyWallpaper(paths[0])
        }
    }
}
