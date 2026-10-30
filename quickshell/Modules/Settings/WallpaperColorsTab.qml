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
import "../../Common/ThemePalette.js" as ThemePalette
import "../../DCommon/Common/MaterialWallpaper.js" as Art

Column {
    id: root

    property var parentModal: null
    property var cachedIconThemes: SettingsData.availableIconThemes
    property var cachedCursorThemes: SettingsData.availableCursorThemes

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
        SettingsData.detectAvailableIconThemes();
        SettingsData.detectAvailableCursorThemes();
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
        if (perMonitor) {
            SessionData.setMonitorWallpaper(selectedScreen, path);
            SessionData.setMonitorCyclingFolderPath(selectedScreen, "");
            return;
        }
        SessionData.setWallpaper(path);
        SessionData.wallpaperCyclingFolderPath = "";
        SessionData.saveSettings();
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
            "confirmColor": Theme.error,
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

    SettingsCard {
        tab: "wallpaper"
        tags: ["background", "image", "picture", "light", "dark", "mode", "theme", "color", "palette"]
        title: I18n.tr("Appearance")
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

        SettingsToggleRow {
            tab: "wallpaper"
            tags: ["blur", "overview", "niri"]
            settingKey: "blurWallpaperOnOverview"
            visible: CompositorService.isNiri
            text: I18n.tr("Blur on overview")
            checked: SettingsData.blurWallpaperOnOverview
            onToggled: checked => SettingsData.set("blurWallpaperOnOverview", checked)
        }
    }

    SettingsCard {
        tab: "wallpaper"
        tags: ["material", "seed", "color", "palette", "hue", "matugen", "dynamic", "theme"]
        title: I18n.tr("Theme color", "Material wallpaper seed card")
        settingKey: "materialSeed"
        visible: root.materialWallpaper

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
            defaultColor: Theme.roleColor("s")
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
            defaultColor: Theme.roleColor("sc")
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
            defaultColor: Theme.roleColor("sch")
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
            defaultColor: Theme.roleColor("schh")
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
            enabled: !SettingsData.iconThemePerMode
            tab: "theme"
            tags: ["icon", "theme", "system"]
            settingKey: "iconTheme"
            resetKeys: ["iconThemeDark"]
            resetByKeys: false
            onResetRequested: SettingsData.setIconThemeForMode(SettingsData.specDefault("iconThemeDark"), false)
            text: I18n.tr("Theme")
            description: I18n.tr("Requires restart")
            currentValue: SettingsData.iconThemeDark
            enableFuzzySearch: true
            popupWidthOffset: 100
            maxPopupHeight: 236
            options: root.cachedIconThemes
            onValueChanged: value => {
                SettingsData.setIconThemeForMode(value, false);
                root.warnIfMissingQtTheme();
            }
        }

        SettingsDropdownRow {
            enabled: SettingsData.iconThemePerMode
            tab: "theme"
            tags: ["icon", "theme", "system", "dark"]
            settingKey: "iconThemeDark"
            resetByKeys: false
            onResetRequested: SettingsData.setIconThemeForMode(SettingsData.specDefault("iconThemeDark"), false)
            text: I18n.tr("Dark mode theme")
            description: I18n.tr("Requires restart")
            currentValue: SettingsData.iconThemeDark
            enableFuzzySearch: true
            popupWidthOffset: 100
            maxPopupHeight: 236
            options: root.cachedIconThemes
            onValueChanged: value => {
                SettingsData.setIconThemeForMode(value, false);
                root.warnIfMissingQtTheme();
            }
        }

        SettingsDropdownRow {
            enabled: SettingsData.iconThemePerMode
            tab: "theme"
            tags: ["icon", "theme", "system", "light"]
            settingKey: "iconThemeLight"
            resetByKeys: false
            onResetRequested: SettingsData.setIconThemeForMode(SettingsData.specDefault("iconThemeLight"), true)
            text: I18n.tr("Light mode theme")
            description: I18n.tr("Requires restart")
            currentValue: SettingsData.iconThemeLight
            enableFuzzySearch: true
            popupWidthOffset: 100
            maxPopupHeight: 236
            options: root.cachedIconThemes
            onValueChanged: value => {
                SettingsData.setIconThemeForMode(value, true);
                root.warnIfMissingQtTheme();
            }
        }
    }

    Loader {
        width: parent.width
        active: CompositorService.isAqueous
        sourceComponent: AqueousAppearanceSettings {
            cursor: true
            settingKey: "aqueousCursor"
            title: I18n.tr("Aqueous cursor", "Aqueous compositor cursor synchronization settings")
            visible: CompositorService.isAqueous
        }
    }

    SettingsCard {
        tab: "theme"
        tags: ["cursor", "mouse", "pointer", "theme", "size", "hide", "typing", "touch", "timeout"]
        title: I18n.tr("Cursor", "settings card title for mouse cursor theme")
        settingKey: "cursorTheme"
        visible: CompositorService.supportsCursorConfig

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
            maxPopupHeight: 236
            options: root.cachedCursorThemes
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

        SettingsSliderRow {
            tab: "theme"
            tags: ["cursor", "hide", "timeout", "inactive"]
            settingKey: "cursorHideAfterInactive"
            text: I18n.tr("Cursor auto-hide timeout")
            minimumLabel: I18n.tr("Off")
            visible: CompositorService.supportsCursorConfig
            value: {
                if (CompositorService.isNiri)
                    return SettingsData.cursorSettings.niri?.hideAfterInactiveMs || 0;
                if (CompositorService.isHyprland)
                    return SettingsData.cursorSettings.hyprland?.inactiveTimeout || 0;
                return SettingsData.cursorSettings.mango?.cursorHideTimeout || 0;
            }
            minimum: 0
            maximum: CompositorService.isNiri ? 5000 : 10
            unit: CompositorService.isNiri ? "ms" : "s"
            modified: value !== 0
            onResetRequested: root.setCursorHideTimeout(0)
            onSliderValueChanged: newValue => root.setCursorHideTimeout(newValue)
        }
    }

    SettingsCard {
        tab: "wallpaper"
        tags: ["blur", "layer", "external", "disable", "swww", "hyprpaper", "swaybg"]
        title: I18n.tr("Advanced")
        settingKey: "wallpaperAdvanced"
        collapsible: true
        expanded: false

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
            filters: ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif", "*.webp", "*.jxl", "*.avif", "*.heif", "*.exr", "*.svg"]
            onAccepted: paths => root.applyWallpaper(paths[0])
        }
    }
}
