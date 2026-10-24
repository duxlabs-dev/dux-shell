pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import "../DCommon/Common/Shape.js" as Shape
import "../DCommon/Common/Surface.js" as Surface
import "../DCommon/Common/Contrast.js" as Contrast
import "../DCommon/Common/Accents.js" as Accents
import "../DCommon/Common/Tonal.js" as Tonal
import "ContrastFloors.js" as ContrastFloors
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Common as DCommon
import qs.Services
import "StockThemes.js" as StockThemes
import "GSettings.js" as GSettings

Singleton {
    id: root
    readonly property var log: Log.scoped("Theme")

    readonly property string stateDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString()) + "/dms"
    readonly property bool envDisableMatugen: Quickshell.env("DMS_DISABLE_MATUGEN") === "1" || Quickshell.env("DMS_DISABLE_MATUGEN") === "true"
    readonly property string defaultFontFamily: "Google Sans Flex"
    readonly property string defaultMonoFontFamily: "Fira Code"
    readonly property string defaultDisplayFontFamily: "DM Serif Display"

    readonly property real popupDistance: {
        if (typeof SettingsData === "undefined")
            return 4;
        const defaultBar = SettingsData.getPrimaryBarConfig();
        if (!defaultBar)
            return 4;
        const useAuto = defaultBar.popupGapsAuto ?? true;
        const manualValue = defaultBar.popupGapsManual ?? 4;
        const spacing = defaultBar.spacing ?? 4;
        return useAuto ? Math.max(4, spacing) : manualValue;
    }

    property string currentTheme: "purple"
    property string currentThemeCategory: "generic"
    property bool isLightMode: typeof SessionData !== "undefined" ? SessionData.isLightMode : false
    property bool colorsFileLoadFailed: false

    readonly property string dynamic: "dynamic"
    readonly property string custom: "custom"

    readonly property string homeDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.HomeLocation))
    readonly property string configDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation))
    readonly property string shellDir: Paths.strip(Qt.resolvedUrl(".").toString()).replace("/Common/", "")
    readonly property string wallpaperSourceScreen: {
        const screens = Quickshell.screens;
        const target = SettingsData.matugenTargetMonitor;
        return screens.find(screen => screen.name === target)?.name ?? screens[0]?.name ?? "";
    }
    readonly property string wallpaperPath: SessionData.getMonitorWallpaper(Quickshell.screens[0]?.name ?? "")
    readonly property string rawWallpaperPath: SessionData.getMonitorWallpaper(wallpaperSourceScreen)
    readonly property string materialWallpaperSeed: SessionData.getMonitorMaterialWallpaper(wallpaperSourceScreen).seed

    property bool matugenAvailable: false
    property var workerRunning: false
    property var pendingThemeRequest: null

    signal matugenCompleted(string mode, string result)
    property var matugenColors: ({})
    property var _pendingGenerateParams: null
    property int _colorsRetryCount: 0
    property double _lastGenerateMs: 0
    property string _matugenRunKey: ""
    property var _workerStderr: []
    property bool _workerStderrUsage: false
    readonly property int _workerStderrKeep: 8
    readonly property string themeTroubleshootingUrl: "https://duxlabs.dev/docs/dms/application-themes#troubleshooting"

    property bool blurLayersActive: false
    property bool matugenToastSuppressed: false

    signal screenTransitionNeeded
    signal themeGenerationStarting

    readonly property var dank16: {
        const raw = matugenColors?.dank16;
        if (!raw)
            return null;

        const dark = {};
        const light = {};
        const def = {};

        for (let i = 0; i < 16; i++) {
            const key = "color" + i;
            const c = raw[key];
            if (!c)
                continue;
            dark[key] = c.dark;
            light[key] = c.light;
            def[key] = c.default;
        }

        return {
            dark,
            light,
            "default": def
        };
    }
    property var customThemeData: null
    property var customThemeRawData: null
    readonly property var currentThemeVariants: customThemeRawData?.variants || null
    readonly property string currentThemeId: customThemeRawData?.id || ""
    readonly property string currentThemeLabel: {
        if (currentTheme === dynamic)
            return I18n.tr("Dynamic", "dynamic theme name");
        const name = getThemeColors(currentThemeName)?.name || customThemeRawData?.name;
        if (name)
            return name;
        const file = typeof SettingsData !== "undefined" ? SettingsData.customThemeFile : "";
        return file ? file.split("/").pop() : "";
    }

    Component.onCompleted: {
        Proc.runCommand("matugenCheck", ["sh", "-c", "command -v matugen"], (output, code) => {
            matugenAvailable = (code === 0) && !envDisableMatugen;
            generateSystemThemesFromCurrentTheme();
        }, 0);
        if (typeof SessionData !== "undefined") {
            SessionData.isLightModeChanged.connect(root.onLightModeChanged);
        }

        if (typeof SettingsData !== "undefined" && SettingsData.currentThemeName) {
            switchTheme(SettingsData.currentThemeName, false, false);
            const currentIsLight = (typeof SessionData !== "undefined") ? SessionData.isLightMode : false;
            SettingsData.updateCosmicThemeMode(currentIsLight);
        }
    }

    function getMatugenColor(path, fallback) {
        const colorMode = (typeof SessionData !== "undefined" && SessionData.isLightMode) ? "light" : "dark";
        return getMatugenColorForMode(colorMode, path, fallback);
    }

    function getMatugenColorForMode(colorMode, path, fallback) {
        let cur = matugenColors && matugenColors.colors && matugenColors.colors[colorMode];
        for (const part of path.split(".")) {
            if (!cur || typeof cur !== "object" || !(part in cur))
                return fallback;
            cur = cur[part];
        }
        return cur || fallback;
    }

    function extractCurrentTheme(themeName) {
        var name = themeName || "Extracted Theme";
        var dark = {};
        var light = {};

        if (currentTheme === dynamic) {
            dark = buildExtractedDynamicMode("dark", name + " Dark");
            light = buildExtractedDynamicMode("light", name + " Light");
        } else if (currentTheme === custom && customThemeRawData) {
            var rawDark = customThemeRawData.dark || null;
            var rawLight = customThemeRawData.light || null;
            if (rawDark) {
                dark = JSON.parse(JSON.stringify(rawDark));
                if (!dark.name)
                    dark.name = name + " Dark";
            } else if (rawLight) {
                dark = buildExtractedDynamicMode("dark", name + " Dark");
            } else {
                dark = currentThemeData ? JSON.parse(JSON.stringify(currentThemeData)) : {};
                dark.name = name + " Dark";
            }
            if (rawLight) {
                light = JSON.parse(JSON.stringify(rawLight));
                if (!light.name)
                    light.name = name + " Light";
            } else if (rawDark) {
                light = buildExtractedDynamicMode("light", name + " Light");
            } else {
                light = currentThemeData ? JSON.parse(JSON.stringify(currentThemeData)) : {};
                light.name = name + " Light";
            }
        } else {
            var darkTheme = StockThemes.getThemeByName(currentTheme, false);
            var lightTheme = StockThemes.getThemeByName(currentTheme, true);
            dark = darkTheme ? JSON.parse(JSON.stringify(darkTheme)) : {};
            light = lightTheme ? JSON.parse(JSON.stringify(lightTheme)) : {};
            dark.name = name + " Dark";
            light.name = name + " Light";
        }

        return JSON.stringify({
            dark: dark,
            light: light
        }, null, 2);
    }

    function buildExtractedDynamicMode(colorMode, name) {
        return {
            "name": name,
            "primary": getMatugenColorForMode(colorMode, "primary", "#42a5f5"),
            "inversePrimary": getMatugenColorForMode(colorMode, "inverse_primary", getMatugenColorForMode(colorMode === "light" ? "dark" : "light", "primary", "#6750a4")),
            "primaryText": getMatugenColorForMode(colorMode, "on_primary", "#ffffff"),
            "primaryContainer": getMatugenColorForMode(colorMode, "primary_container", "#1976d2"),
            "onPrimaryContainer": getMatugenColorForMode(colorMode, "on_primary_container"),
            "secondary": getMatugenColorForMode(colorMode, "secondary", "#8ab4f8"),
            "secondaryContainer": getMatugenColorForMode(colorMode, "secondary_container"),
            "onSecondaryContainer": getMatugenColorForMode(colorMode, "on_secondary_container"),
            "tertiary": getMatugenColorForMode(colorMode, "tertiary", "#efb8c8"),
            "tertiaryContainer": getMatugenColorForMode(colorMode, "tertiary_container", getMatugenColorForMode(colorMode, "surface_container_high", "#292b2f")),
            "onTertiaryContainer": getMatugenColorForMode(colorMode, "on_tertiary_container"),
            "surface": getMatugenColorForMode(colorMode, "surface", "#1a1c1e"),
            "surfaceText": getMatugenColorForMode(colorMode, "on_background", "#e3e8ef"),
            "surfaceVariant": getMatugenColorForMode(colorMode, "surface_variant", "#44464f"),
            "surfaceVariantText": getMatugenColorForMode(colorMode, "on_surface_variant", "#c4c7c5"),
            "surfaceTint": getMatugenColorForMode(colorMode, "surface_tint", "#8ab4f8"),
            "background": getMatugenColorForMode(colorMode, "background", "#1a1c1e"),
            "backgroundText": getMatugenColorForMode(colorMode, "on_background", "#e3e8ef"),
            "outline": getMatugenColorForMode(colorMode, "outline", "#8e918f"),
            "surfaceContainerLowest": getMatugenColorForMode(colorMode, "surface_container_lowest", "#0e1013"),
            "surfaceContainerLow": getMatugenColorForMode(colorMode, "surface_container_low", "#181a1d"),
            "surfaceContainer": getMatugenColorForMode(colorMode, "surface_container", "#1e2023"),
            "surfaceContainerHigh": getMatugenColorForMode(colorMode, "surface_container_high", "#292b2f"),
            "surfaceContainerHighest": getMatugenColorForMode(colorMode, "surface_container_highest", "#343740"),
            "error": getMatugenColorForMode(colorMode, "error", "#F2B8B5"),
            "errorText": getMatugenColorForMode(colorMode, "on_error"),
            "errorContainer": getMatugenColorForMode(colorMode, "error_container"),
            "errorContainerText": getMatugenColorForMode(colorMode, "on_error_container"),
            "warning": "#FF9800",
            "info": "#2196F3",
            "success": "#4CAF50"
        };
    }

    readonly property var currentThemeData: {
        if (currentTheme === "custom") {
            return customThemeData || StockThemes.getThemeByName("purple", isLightMode);
        } else if (currentTheme === dynamic) {
            return buildExtractedDynamicMode(isLightMode ? "light" : "dark", "Dynamic");
        } else {
            return StockThemes.getThemeByName(currentTheme, isLightMode);
        }
    }

    readonly property var availableMatugenSchemes: {
        const schemes = _matugenSchemeDefs;
        const seen = {};
        for (let i = 0; i < schemes.length; i++) {
            const label = schemes[i].label;
            if (seen[label] === undefined) {
                seen[label] = true;
                continue;
            }
            // duplicate translations otherwise collapse the label-keyed dropdown onto one scheme (#3154)
            schemes[i].label = label + " (" + schemes[i].value.replace("scheme-", "") + ")";
        }
        return schemes;
    }

    readonly property var _matugenSchemeDefs: [({
                "value": "scheme-tonal-spot",
                "spec2025": true,
                "label": I18n.tr("Tonal Spot", "matugen color scheme option"),
                "description": I18n.tr("Balanced palette with focused accents (default).")
            }), ({
                "value": "scheme-vibrant",
                "spec2025": true,
                "label": I18n.tr("Vibrant", "matugen color scheme option"),
                "description": I18n.tr("Lively palette with saturated accents.")
            }), ({
                "value": "scheme-content",
                "label": I18n.tr("Content", "matugen color scheme option"),
                "description": I18n.tr("Derives colors that closely match the underlying image.")
            }), ({
                "value": "scheme-expressive",
                "spec2025": true,
                "label": I18n.tr("Expressive", "matugen color scheme option"),
                "description": I18n.tr("Vibrant palette with playful saturation.")
            }), ({
                "value": "scheme-fidelity",
                "label": I18n.tr("Fidelity", "matugen color scheme option"),
                "description": I18n.tr("High-fidelity palette that preserves source hues.")
            }), ({
                "value": "scheme-fruit-salad",
                "label": I18n.tr("Fruit Salad", "matugen color scheme option"),
                "description": I18n.tr("Colorful mix of bright contrasting accents.")
            }), ({
                "value": "scheme-monochrome",
                "label": I18n.tr("Monochrome", "matugen color scheme option"),
                "description": I18n.tr("Minimal palette built around a single hue.")
            }), ({
                "value": "scheme-neutral",
                "spec2025": true,
                "label": I18n.tr("Neutral", "matugen color scheme option"),
                "description": I18n.tr("Muted palette with subdued, calming tones.")
            }), ({
                "value": "scheme-rainbow",
                "label": I18n.tr("Rainbow", "matugen color scheme option"),
                "description": I18n.tr("Diverse palette spanning the full spectrum.")
            }), ({
                "value": "scheme-smart",
                "label": I18n.tr("Smart", "matugen color scheme option"),
                "description": I18n.tr("Automatically picks the scheme variant based on the wallpaper.")
            })]

    function getMatugenScheme(value) {
        const schemes = availableMatugenSchemes;
        for (var i = 0; i < schemes.length; i++) {
            if (schemes[i].value === value)
                return schemes[i];
        }
        return schemes[0];
    }

    readonly property var availableSourceModes: [({
                "value": "dominant",
                "label": I18n.tr("Dominant", "matugen source color option")
            }), ({
                "value": "colorful",
                "label": I18n.tr("Colorful", "matugen source color option")
            }), ({
                "value": "darkness",
                "label": I18n.tr("Darkest", "matugen source color option")
            }), ({
                "value": "lightness",
                "label": I18n.tr("Lightest", "matugen source color option")
            }), ({
                "value": "saturation",
                "label": I18n.tr("Most Saturated", "matugen source color option")
            }), ({
                "value": "less-saturation",
                "label": I18n.tr("Least Saturated", "matugen source color option")
            }), ({
                "value": "value",
                "label": I18n.tr("Most Vivid", "matugen source color option")
            })]

    function getSourceMode(value) {
        const modes = availableSourceModes;
        for (var i = 0; i < modes.length; i++) {
            if (modes[i].value === value)
                return modes[i];
        }
        return modes[0];
    }

    property color primary: currentThemeData.primary
    property color primaryText: currentThemeData.primaryText
    property color secondary: currentThemeData.secondary
    property color tertiary: currentThemeData.tertiary || currentThemeData.secondary
    property color surface: currentThemeData.surface
    property color surfaceText: currentThemeData.surfaceText
    property color surfaceVariant: currentThemeData.surfaceVariant
    property color surfaceVariantText: currentThemeData.surfaceVariantText
    property color surfaceTint: currentThemeData.surfaceTint
    property color background: currentThemeData.background
    property color backgroundText: currentThemeData.backgroundText
    property color outline: currentThemeData.outline
    property color outlineVariant: currentThemeData.outlineVariant || withAlpha(outline, 0.6)
    property color surfaceContainerLowest: currentThemeData.surfaceContainerLowest || blend(surfaceContainer, surface, 1.2)
    property color surfaceContainerLow: currentThemeData.surfaceContainerLow || blend(surface, surfaceContainer, 0.667)
    property color surfaceContainer: currentThemeData.surfaceContainer
    property color surfaceContainerHigh: currentThemeData.surfaceContainerHigh
    property color surfaceContainerHighest: currentThemeData.surfaceContainerHighest || surfaceContainerHigh
    property color surfaceBright: currentThemeData.surfaceBright || (isLightMode ? surface : surfaceContainerHighest)
    property color surfaceDim: currentThemeData.surfaceDim || (isLightMode ? surfaceContainer : background)
    readonly property color hostSurface: typeof SettingsData === "undefined" ? surface : surfaceRoleColor(SettingsData.hostSurfaceColor, SettingsData.hostSurfaceCustomColor, surface)
    readonly property color cardSurface: typeof SettingsData === "undefined" ? surfaceContainer : surfaceRoleColor(SettingsData.cardSurfaceColor, SettingsData.cardSurfaceCustomColor, surfaceContainer)
    readonly property color chipSurface: typeof SettingsData === "undefined" ? surfaceContainerHigh : surfaceRoleColor(SettingsData.chipSurfaceColor, SettingsData.chipSurfaceCustomColor, surfaceContainerHigh)
    readonly property color chipSurfaceNested: typeof SettingsData === "undefined" ? surfaceContainerHighest : surfaceRoleColor(SettingsData.chipSurfaceNestedColor, SettingsData.chipSurfaceNestedCustomColor, surfaceContainerHighest)
    readonly property real containerSaturation: typeof SettingsData === "undefined" ? 1 : SettingsData.containerSaturation / 100
    readonly property real containerTint: (currentThemeData.containerTint ?? Tonal.defaultTint(surfaceContainer)) * containerSaturation
    property color primaryContainer: currentThemeData.softPrimaryContainer || Tonal.softContainer(primary, surfaceContainer, containerTint)
    property color secondaryContainer: currentThemeData.secondaryContainer || blend(surfaceContainerHigh, secondary, 0.35)
    property color tertiaryContainer: currentThemeData.tertiaryContainer || blend(surfaceContainerHigh, tertiary, 0.35)
    readonly property real selectedContainerTint: currentThemeData.selectedContainerTint ?? 0.2
    readonly property bool themedSelectedContainer: !!currentThemeData.secondaryContainer && Contrast.isTonal(secondaryContainer, onSecondaryContainer) && Contrast.isTonal(secondaryContainer, surfaceText)
    readonly property color selectedContainer: currentThemeData.selectedContainer || (themedSelectedContainer ? secondaryContainer : Contrast.subtleTint(surfaceContainerHigh, primary, surfaceText, selectedContainerTint))
    readonly property color accentOnSelectedContainer: currentThemeData.accentOnSelectedContainer || (Contrast.ratio(primary, selectedContainer) >= 3 ? primary : onSelectedContainer)
    readonly property color accentOnPrimaryContainer: currentThemeData.accentOnPrimaryContainer || (Contrast.ratio(primary, primaryContainer) >= 3 ? primary : onPrimaryContainer)
    readonly property var accents: Accents.derive(primary, isLightMode, currentThemeData.accents ?? null)
    property color inversePrimary: currentThemeData.inversePrimary || wallpaperThemeData(!isLightMode).primary
    property color inverseSurface: currentThemeData.inverseSurface || surfaceText
    property color inverseOnSurface: currentThemeData.inverseOnSurface || surface

    // on<Role> next to a <role> property parses as a signal handler; only Binding elements assign them.
    property color onSurface
    property color onSurfaceVariant
    property color onPrimary
    property color onPrimaryContainer
    property color onSecondaryContainer
    property color onError
    property color onErrorContainer
    property color onTertiaryContainer
    property color onSelectedContainer
    property color onSurface_12: withAlpha(onSurface, 0.12)
    property color onSurface_38: withAlpha(onSurface, 0.38)
    property color onSurfaceVariant_30: withAlpha(onSurfaceVariant, 0.30)
    property color onSurfaceVariant_40
    readonly property list<QtObject> roleBindings: [
        Binding {
            target: root
            property: "onSurfaceVariant_40"
            value: root.withAlpha(root.onSurfaceVariant, 0.4)
        },
        Binding {
            target: root
            property: "onError"
            value: root.currentThemeData.errorText || root.getMatugenColor("on_error", root.surface)
        },
        Binding {
            target: root
            property: "onErrorContainer"
            value: root.currentThemeData.errorContainerText || root.getMatugenColor("on_error_container", root.blend(root.surfaceText, root.error, 0.5))
        },
        Binding {
            target: root
            property: "onSurface"
            value: root.surfaceText
        },
        Binding {
            target: root
            property: "onSurfaceVariant"
            value: root.surfaceVariantText
        },
        Binding {
            target: root
            property: "onPrimary"
            value: root.primaryText
        },
        Binding {
            target: root
            property: "onPrimaryContainer"
            value: {
                const explicit = root.currentThemeData.onPrimaryContainer || root.currentThemeData.primaryContainerText;
                if (!explicit)
                    return Contrast.readableOn(root.primaryContainer, root.onContainerCandidates);
                if (root.currentThemeData.softPrimaryContainer)
                    return explicit;
                return Contrast.readableOn(root.primaryContainer, [Qt.color(explicit)].concat(root.onContainerCandidates));
            }
        },
        Binding {
            target: root
            property: "onSecondaryContainer"
            value: root.currentThemeData.onSecondaryContainer || Contrast.readableOn(root.secondaryContainer, root.onContainerCandidates)
        },
        Binding {
            target: root
            property: "onTertiaryContainer"
            value: root.currentThemeData.onTertiaryContainer || Contrast.readableOn(root.tertiaryContainer, root.onContainerCandidates)
        },
        Binding {
            target: root
            property: "onSelectedContainer"
            value: root.currentThemeData.onSelectedContainer || (root.currentThemeData.selectedContainer ? Contrast.readableOn(root.selectedContainer, root.onContainerCandidates) : root.themedSelectedContainer ? root.onSecondaryContainer : root.surfaceText)
        }
    ]
    readonly property var onContainerCandidates: [surfaceText, surface, contrastLight, contrastDark]
    readonly property real tonalTintAlpha: 0.16

    property color error: currentThemeData.error || "#F2B8B5"
    property color errorContainer: currentThemeData.errorContainer || getMatugenColor("error_container", blend(surfaceContainerHigh, error, 0.35))
    property color warning: currentThemeData.warning || "#FF9800"
    property color info: currentThemeData.info || "#2196F3"
    property color tempWarning: "#ff9933"
    property color tempDanger: "#ff5555"
    property color success: currentThemeData.success || "#4CAF50"

    property color primaryHover: withAlpha(primary, 0.12)
    property color primaryHoverLight: withAlpha(primary, transparentBlurLayers ? 0.12 : 0.08)
    property color primaryPressed: withAlpha(primary, transparentBlurLayers ? 0.24 : 0.16)
    property color primarySelected: withAlpha(primary, 0.3)
    property color primaryBackground: withAlpha(primary, 0.04)

    property color secondaryHover: withAlpha(secondary, 0.08)

    property color surfaceHover: withAlpha(surfaceVariant, 0.08)
    property color surfacePressed: withAlpha(surfaceVariant, 0.12)
    property color surfaceSelected: withAlpha(surfaceVariant, 0.15)
    property color surfaceLight: withAlpha(surfaceVariant, transparentBlurLayers ? 0.3 : 0.1)
    property color surfaceVariantAlpha: withAlpha(surfaceVariant, 0.2)

    readonly property bool foregroundLayers: typeof SettingsData === "undefined" || (SettingsData.blurForegroundLayers ?? true)
    readonly property bool blurForegroundLayers: blurLayersActive && foregroundLayers
    readonly property bool transparentBlurLayers: blurLayersActive && !foregroundLayers
    readonly property real foregroundLayerTransparency: typeof SettingsData === "undefined" ? 1.0 : (SettingsData.foregroundLayerTransparency ?? 1.0)
    readonly property bool notificationForegroundLayers: typeof SettingsData === "undefined" || (SettingsData.notificationForegroundLayers ?? true)
    readonly property color readableSurface: withAlpha(hostSurface, popupTransparency)
    readonly property color readableSurfaceHigh: withAlpha(cardSurface, popupTransparency)
    readonly property color floatingSurface: readableSurface
    readonly property color floatingSurfaceHigh: foregroundColor(cardSurface)
    readonly property bool floatingWindowSynced: typeof SettingsData === "undefined" || (SettingsData.floatingWindowSyncGlobal ?? true)
    readonly property real floatingWindowTransparency: {
        if (typeof SettingsData === "undefined" || floatingWindowSynced)
            return popupTransparency;
        return SettingsData.floatingWindowTransparency ?? 1.0;
    }
    readonly property bool floatingWindowForegroundLayers: floatingWindowSynced ? foregroundLayers : (SettingsData.floatingWindowForegroundLayers ?? true)
    readonly property real floatingWindowForegroundTransparency: {
        if (typeof SettingsData === "undefined" || floatingWindowSynced)
            return foregroundLayerTransparency;
        return SettingsData.floatingWindowForegroundTransparency ?? 1.0;
    }
    readonly property real foregroundAlpha: Surface.foregroundAlpha(foregroundLayers || !blurLayersActive, foregroundLayerTransparency)
    readonly property real floatingWindowForegroundAlpha: Surface.foregroundAlpha(floatingWindowForegroundLayers, floatingWindowForegroundTransparency)

    function isFloatingWindow(item) {
        return Surface.isFloatingWindow(item);
    }

    function accent(name) {
        return accents[name] ?? null;
    }

    function foregroundColor(baseColor, floatingWindow = false) {
        return blendAlpha(baseColor, floatingWindow ? floatingWindowForegroundAlpha : foregroundAlpha);
    }

    readonly property color floatingWindowSurface: withAlpha(hostSurface, floatingWindowTransparency)
    readonly property color floatingWindowSurfaceHigh: foregroundColor(cardSurface, true)
    readonly property color floatingWindowNestedSurface: floatingWindowSurfaceHigh
    readonly property color notepadWindowSurface: withAlpha(hostSurface, notepadTransparency)
    readonly property color nestedSurface: floatingSurfaceHigh
    readonly property color notificationFloatingSurface: notificationForegroundLayers ? readableSurface : withAlpha(readableSurface, 0)
    readonly property color notificationFloatingSurfaceHigh: notificationForegroundLayers ? readableSurfaceHigh : withAlpha(readableSurfaceHigh, 0)
    readonly property color notificationNestedSurface: notificationFloatingSurfaceHigh
    readonly property color notificationChipSurface: notificationForegroundLayers ? chipSurface : withAlpha(onSurface, stateLayerFocus)
    readonly property real blurLayerOutlineOpacity: Math.max(0, Math.min(1, typeof SettingsData === "undefined" ? 0 : (SettingsData.blurLayerOutlineOpacity ?? 0)))
    readonly property real layerOutlineOpacity: blurLayerOutlineOpacity
    readonly property int layerOutlineWidth: layerOutlineOpacity > 0 ? 1 : 0
    readonly property real floatingWindowFieldAlpha: floatingWindowForegroundAlpha
    readonly property color floatingWindowFieldColor: withAlpha(chipSurface, floatingWindowFieldAlpha)
    readonly property real popupFieldAlpha: foregroundAlpha
    readonly property color popupFieldColor: withAlpha(chipSurface, popupFieldAlpha)
    readonly property color popupFieldBorderColor: withAlpha(outline, blurLayersActive ? 0.16 : layerOutlineOpacity)
    readonly property color popupFieldFocusedBorderColor: withAlpha(primary, blurLayersActive ? 0.72 : 1.0)
    readonly property color floatingWindowFieldBorderColor: popupFieldBorderColor
    readonly property color floatingWindowFieldFocusedBorderColor: popupFieldFocusedBorderColor
    property color surfaceTextHover: withAlpha(surfaceText, 0.08)
    property color surfaceTextAlpha: withAlpha(surfaceText, 0.3)

    function surfaceRoleColor(mode, customColor, fallback) {
        switch (mode ?? "default") {
        case "default":
            return fallback;
        case "custom":
            return Qt.color(customColor);
        default:
            return roleColor(mode);
        }
    }

    readonly property real avatarRingWidth: SettingsData.avatarRing === "none" ? 0 : outlineWidth
    readonly property color avatarRingColor: SettingsData.avatarRing === "outline" ? surfaceVariant : roleColor(SettingsData.avatarRing)

    function wallpaperThemeData(light) {
        switch (currentTheme) {
        case "dynamic":
            return buildExtractedDynamicMode(light ? "light" : "dark", "Dynamic");
        case "custom":
            return resolveCustomTheme(customThemeRawData, light ? "light" : "dark");
        default:
            return StockThemes.getThemeByName(currentTheme, light);
        }
    }

    function wallpaperPalette(light = isLightMode) {
        if (light === isLightMode)
            return {
                primary,
                secondary,
                tertiary,
                primaryContainer,
                secondaryContainer,
                tertiaryContainer,
                inversePrimary,
                contrastDark,
                surface
            };
        const data = wallpaperThemeData(light);
        const container = Qt.color(data.surfaceContainer);
        const high = Qt.color(data.surfaceContainerHigh);
        const primaryColor = Qt.color(data.primary);
        const secondaryColor = Qt.color(data.secondary);
        const tertiaryColor = Qt.color(data.tertiary || data.secondary);
        const tint = (data.containerTint ?? Tonal.defaultTint(container)) * containerSaturation;
        return {
            primary: primaryColor,
            secondary: secondaryColor,
            tertiary: tertiaryColor,
            primaryContainer: data.softPrimaryContainer || Tonal.softContainer(primaryColor, container, tint),
            secondaryContainer: data.secondaryContainer || blend(high, secondaryColor, 0.35),
            tertiaryContainer: data.tertiaryContainer || blend(high, tertiaryColor, 0.35),
            inversePrimary: data.inversePrimary || wallpaperThemeData(!light).primary,
            contrastDark,
            surface: data.surface
        };
    }

    function roleColor(mode) {
        switch (mode) {
        case "primary":
        case "pri":
            return primary;
        case "primaryContainer":
            return primaryContainer;
        case "secondary":
        case "sec":
            return secondary;
        case "secondaryContainer":
            return secondaryContainer;
        case "tertiary":
        case "ter":
            return tertiary;
        case "tertiaryContainer":
            return tertiaryContainer;
        case "surfaceText":
            return surfaceText;
        case "surfaceVariant":
            return surfaceVariant;
        case "s":
            return surface;
        case "scll":
            return surfaceContainerLowest;
        case "scl":
            return surfaceContainerLow;
        case "sc":
            return surfaceContainer;
        case "sch":
            return surfaceContainerHigh;
        case "schh":
            return surfaceContainerHighest;
        case "sth":
            return surfaceTextHover;
        case "error":
        case "err":
            return error;
        default:
            return withAlpha(surface, 0);
        }
    }
    property color surfaceTextLight: withAlpha(surfaceText, 0.06)
    property color surfaceTextSecondary: withAlpha(surfaceText, 0.6)
    property color surfaceTextMedium: withAlpha(surfaceText, 0.7)

    property color outlineButton: withAlpha(outline, 0.5)
    property color outlineLight: withAlpha(outline, Math.min(1, layerOutlineOpacity * 0.625))
    property color outlineMedium: withAlpha(outline, layerOutlineOpacity)
    property color outlineStrong: withAlpha(outline, Math.min(1, layerOutlineOpacity * 1.5))
    property color outlineHeavy: withAlpha(outline, 0.2)

    property color errorHover: withAlpha(error, 0.12)
    property color errorPressed: withAlpha(error, 0.16)
    property color errorSelected: withAlpha(error, 0.3)
    property color warningHover: withAlpha(warning, 0.12)

    readonly property color ccTileActiveBg: {
        switch (SettingsData.controlCenterTileColorMode) {
        case "primaryContainer":
            return primaryContainer;
        case "secondary":
            return secondary;
        case "surfaceVariant":
            return surfaceVariant;
        default:
            return primary;
        }
    }

    readonly property color ccPillInactiveBg: transparentBlurLayers ? withAlpha(cardSurface, 0.08) : nestedSurface
    readonly property color ccIconBoxInactiveBg: transparentBlurLayers ? withAlpha(chipSurfaceNested, 0.16) : foregroundColor(chipSurfaceNested)

    readonly property color ccTileActiveText: {
        switch (SettingsData.controlCenterTileColorMode) {
        case "primaryContainer":
            return onPrimaryContainer;
        case "secondary":
            return surfaceText;
        case "surfaceVariant":
            return surfaceText;
        default:
            return primaryText;
        }
    }

    readonly property color buttonBg: {
        switch (SettingsData.buttonColorMode) {
        case "primaryContainer":
            return primaryContainer;
        case "secondary":
            return secondary;
        case "surfaceVariant":
            return surfaceVariant;
        default:
            return primary;
        }
    }

    readonly property color buttonText: {
        switch (SettingsData.buttonColorMode) {
        case "primaryContainer":
            return onPrimaryContainer;
        case "secondary":
            return surfaceText;
        case "surfaceVariant":
            return surfaceText;
        default:
            return primaryText;
        }
    }

    readonly property color buttonHover: {
        switch (SettingsData.buttonColorMode) {
        case "primaryContainer":
            return withAlpha(primary, 0.12);
        case "secondary":
            return withAlpha(surfaceText, 0.12);
        case "surfaceVariant":
            return withAlpha(surfaceText, 0.12);
        default:
            return primaryHover;
        }
    }

    readonly property color buttonPressed: {
        switch (SettingsData.buttonColorMode) {
        case "primaryContainer":
            return withAlpha(primary, 0.16);
        case "secondary":
            return withAlpha(surfaceText, 0.16);
        case "surfaceVariant":
            return withAlpha(surfaceText, 0.16);
        default:
            return primaryPressed;
        }
    }

    property color shadowMedium: Qt.rgba(0, 0, 0, 0.08)
    property color shadowStrong: Qt.rgba(0, 0, 0, 0.3)

    readonly property bool elevationEnabled: typeof SettingsData !== "undefined" && (SettingsData.m3ElevationEnabled ?? true)
    readonly property real elevationBlurMax: typeof SettingsData !== "undefined" && SettingsData.m3ElevationIntensity !== undefined ? Math.min(128, Math.max(32, SettingsData.m3ElevationIntensity * 2)) : 64

    readonly property real _elevMult: typeof SettingsData !== "undefined" && SettingsData.m3ElevationIntensity !== undefined ? SettingsData.m3ElevationIntensity / 12 : 1
    readonly property real _opMult: typeof SettingsData !== "undefined" && SettingsData.m3ElevationOpacity !== undefined ? SettingsData.m3ElevationOpacity / 60 : 1
    function normalizeElevationDirection(direction) {
        switch (direction) {
        case "top":
        case "topLeft":
        case "topRight":
        case "bottom":
        case "bottomLeft":
        case "bottomRight":
        case "left":
        case "right":
        case "autoBar":
            return direction;
        default:
            return "top";
        }
    }

    readonly property string elevationLightDirection: {
        if (typeof SettingsData === "undefined" || !SettingsData.m3ElevationLightDirection)
            return "top";
        switch (SettingsData.m3ElevationLightDirection) {
        case "autoBar":
        case "top":
        case "topLeft":
        case "topRight":
        case "bottom":
            return SettingsData.m3ElevationLightDirection;
        default:
            return "top";
        }
    }
    readonly property real _elevDiagRatio: 0.55
    readonly property string _globalElevationDirForTokens: {
        const normalized = normalizeElevationDirection(elevationLightDirection);
        return normalized === "autoBar" ? "top" : normalized;
    }
    readonly property real _elevDirX: {
        switch (_globalElevationDirForTokens) {
        case "topLeft":
        case "bottomLeft":
        case "left":
            return 1;
        case "topRight":
        case "bottomRight":
        case "right":
            return -1;
        default:
            return 0;
        }
    }
    readonly property real _elevDirY: {
        switch (_globalElevationDirForTokens) {
        case "bottom":
        case "bottomLeft":
        case "bottomRight":
            return -1;
        case "left":
        case "right":
            return 0;
        default:
            return 1;
        }
    }
    readonly property real _elevDirXScale: (_globalElevationDirForTokens === "left" || _globalElevationDirForTokens === "right") ? 1 : _elevDiagRatio

    readonly property var elevationLevel1: ({
            blurPx: 4 * _elevMult,
            offsetX: 1 * _elevMult * _elevDirXScale * _elevDirX,
            offsetY: 1 * _elevMult * _elevDirY,
            spreadPx: 0,
            alpha: 0.2 * _opMult
        })
    readonly property var elevationLevel2: ({
            blurPx: 8 * _elevMult,
            offsetX: 4 * _elevMult * _elevDirXScale * _elevDirX,
            offsetY: 4 * _elevMult * _elevDirY,
            spreadPx: 0,
            alpha: 0.25 * _opMult
        })
    readonly property var elevationLevel3: ({
            blurPx: 12 * _elevMult,
            offsetX: 6 * _elevMult * _elevDirXScale * _elevDirX,
            offsetY: 6 * _elevMult * _elevDirY,
            spreadPx: 0,
            alpha: 0.3 * _opMult
        })
    readonly property var elevationLevel4: ({
            blurPx: 16 * _elevMult,
            offsetX: 8 * _elevMult * _elevDirXScale * _elevDirX,
            offsetY: 8 * _elevMult * _elevDirY,
            spreadPx: 0,
            alpha: 0.3 * _opMult
        })
    readonly property var elevationLevel5: ({
            blurPx: 20 * _elevMult,
            offsetX: 10 * _elevMult * _elevDirXScale * _elevDirX,
            offsetY: 10 * _elevMult * _elevDirY,
            spreadPx: 0,
            alpha: 0.3 * _opMult
        })

    function elevationOffsetMagnitude(level, fallback, direction) {
        if (!level) {
            return fallback !== undefined ? Math.abs(fallback) : 0;
        }
        const yMag = Math.abs(level.offsetY !== undefined ? level.offsetY : 0);
        if (yMag > 0)
            return yMag;
        const xMag = Math.abs(level.offsetX !== undefined ? level.offsetX : 0);
        if (xMag > 0) {
            if (direction === "left" || direction === "right")
                return xMag;
            return xMag / _elevDiagRatio;
        }
        return fallback !== undefined ? Math.abs(fallback) : 0;
    }

    function elevationOffsetXFor(level, direction, fallback) {
        const dir = normalizeElevationDirection(direction || elevationLightDirection);
        const mag = elevationOffsetMagnitude(level, fallback, dir);
        switch (dir) {
        case "topLeft":
        case "bottomLeft":
            return mag * _elevDiagRatio;
        case "topRight":
        case "bottomRight":
            return -mag * _elevDiagRatio;
        case "left":
            return mag;
        case "right":
            return -mag;
        default:
            return 0;
        }
    }

    function elevationOffsetYFor(level, direction, fallback) {
        const dir = normalizeElevationDirection(direction || elevationLightDirection);
        const mag = elevationOffsetMagnitude(level, fallback, dir);
        switch (dir) {
        case "bottom":
        case "bottomLeft":
        case "bottomRight":
            return -mag;
        case "left":
        case "right":
            return 0;
        default:
            return mag;
        }
    }

    function elevationOffsetX(level, fallback) {
        return elevationOffsetXFor(level, elevationLightDirection, fallback);
    }

    function elevationOffsetY(level, fallback) {
        return elevationOffsetYFor(level, elevationLightDirection, fallback);
    }

    function elevationRenderPadding(level, direction, fallbackOffset, extraPadding, minPadding) {
        const dir = direction !== undefined ? direction : elevationLightDirection;
        const blur = (level && level.blurPx !== undefined) ? Math.max(0, level.blurPx) : 0;
        const spread = (level && level.spreadPx !== undefined) ? Math.max(0, level.spreadPx) : 0;
        const fallback = fallbackOffset !== undefined ? fallbackOffset : 0;
        const extra = extraPadding !== undefined ? extraPadding : 8;
        const minPad = minPadding !== undefined ? minPadding : 16;
        const offsetX = Math.abs(elevationOffsetXFor(level, dir, fallback));
        const offsetY = Math.abs(elevationOffsetYFor(level, dir, fallback));
        return Math.max(minPad, blur + spread + Math.max(offsetX, offsetY) + extra);
    }

    function elevationShadowColor(level) {
        const alpha = (level && level.alpha !== undefined) ? level.alpha : 0.3;
        let r = 0;
        let g = 0;
        let b = 0;

        if (typeof SettingsData !== "undefined") {
            const mode = SettingsData.m3ElevationColorMode || "default";
            if (mode === "default") {
                r = 0;
                g = 0;
                b = 0;
            } else if (mode === "text") {
                r = surfaceText.r;
                g = surfaceText.g;
                b = surfaceText.b;
            } else if (mode === "primary") {
                r = primary.r;
                g = primary.g;
                b = primary.b;
            } else if (mode === "surfaceVariant") {
                r = surfaceVariant.r;
                g = surfaceVariant.g;
                b = surfaceVariant.b;
            } else if (mode === "custom" && SettingsData.m3ElevationCustomColor) {
                const c = Qt.color(SettingsData.m3ElevationCustomColor);
                r = c.r;
                g = c.g;
                b = c.b;
            }
        }
        return Qt.rgba(r, g, b, alpha);
    }
    function elevationAmbient(level) {
        const blur = (level && level.blurPx !== undefined) ? Math.max(0, level.blurPx) : 0;
        const alpha = ((level && level.alpha !== undefined) ? level.alpha : 0.3) * 0.5;
        return {
            blurPx: blur * 1.75,
            spreadPx: 1,
            alpha: alpha
        };
    }

    readonly property int currentAnimationBaseDuration: typeof SettingsData !== "undefined" ? SettingsData.animationDuration : 250
    readonly property int currentAnimationSpeed: currentAnimationBaseDuration > 0 ? SettingsData.AnimationSpeed.Custom : SettingsData.AnimationSpeed.None

    readonly property int shorterDuration: Math.round(currentAnimationBaseDuration * 0.2)
    readonly property int shortDuration: Math.round(currentAnimationBaseDuration * 0.3)
    readonly property bool snapListModelChanges: shortDuration <= 0
    readonly property int mediumDuration: Math.round(currentAnimationBaseDuration * 0.6)
    readonly property int longDuration: currentAnimationBaseDuration
    readonly property int extraLongDuration: currentAnimationBaseDuration * 2
    readonly property int standardEasing: Easing.OutCubic
    readonly property int emphasizedEasing: Easing.OutQuart

    readonly property var expressiveCurves: {
        "emphasized": [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1],
        "emphasizedAccel": [0.3, 0, 0.8, 0.15, 1, 1],
        "emphasizedDecel": [0.05, 0.7, 0.1, 1, 1, 1],
        "standard": [0.2, 0, 0, 1, 1, 1],
        "standardAccel": [0.3, 0, 1, 1, 1, 1],
        "standardDecel": [0, 0, 0, 1, 1, 1],
        "expressiveFastSpatial": [0.42, 1.67, 0.21, 0.9, 1, 1],
        "expressiveDefaultSpatial": [0.38, 1.21, 0.22, 1, 1, 1],
        "expressiveSlowSpatial": [0.39, 1.29, 0.35, 0.98, 1, 1],
        "expressiveFastEffects": [0.31, 0.94, 0.34, 1, 1, 1],
        "expressiveEffects": [0.34, 0.8, 0.34, 1, 1, 1],
        "expressiveSlowEffects": [0.34, 0.88, 0.34, 1, 1, 1]
    }

    // Theme is the canonical access point for animation variant state. The
    // aliases below forward to AnimVariants.qml so consumers don't need two
    // imports. ~200 call sites read through Theme.variantEnterCurve /
    // Theme.isConnectedEffect / etc. — do NOT migrate to AnimVariants directly.
    readonly property list<real> variantEnterCurve: AnimVariants.variantEnterCurve
    readonly property list<real> variantExitCurve: AnimVariants.variantExitCurve
    readonly property list<real> variantModalEnterCurve: AnimVariants.variantModalEnterCurve
    readonly property list<real> variantModalExitCurve: AnimVariants.variantModalExitCurve
    readonly property list<real> variantPopoutEnterCurve: AnimVariants.variantPopoutEnterCurve
    readonly property list<real> variantPopoutExitCurve: AnimVariants.variantPopoutExitCurve
    readonly property list<real> variantPopoutResizeCurve: AnimVariants.variantPopoutResizeCurve
    readonly property real variantEnterDurationFactor: AnimVariants.variantEnterDurationFactor
    readonly property real variantExitDurationFactor: AnimVariants.variantExitDurationFactor
    readonly property real variantOpacityDurationScale: AnimVariants.variantOpacityDurationScale
    readonly property bool isDirectionalEffect: AnimVariants.isDirectionalEffect
    readonly property bool isFluidEffect: AnimVariants.isFluidEffect
    readonly property bool isDepthEffect: AnimVariants.isDepthEffect
    readonly property bool isConnectedEffect: AnimVariants.isConnectedEffect
    readonly property real connectedCornerRadius: {
        if (typeof SettingsData === "undefined")
            return 12;
        return FrameTransitionState.effectiveConnectedFrameModeActive ? SettingsData.frameRounding : windowRadius;
    }
    readonly property color connectedSurfaceColor: {
        if (typeof SettingsData === "undefined")
            return withAlpha(hostSurface, popupTransparency);
        return isConnectedEffect ? frameSurfaceColor : withAlpha(hostSurface, popupTransparency);
    }
    readonly property color frameSurfaceColor: typeof SettingsData === "undefined" ? withAlpha(hostSurface, popupTransparency) : withAlpha(SettingsData.frameSurfaceBase, SettingsData.frameSurfaceOpacity)
    readonly property real connectedSurfaceRadius: isConnectedEffect ? connectedCornerRadius : windowRadius
    readonly property bool connectedSurfaceBlurEnabled: (typeof SettingsData === "undefined") ? true : (!isConnectedEffect || SettingsData.frameBlurEnabled)
    readonly property real effectScaleCollapsed: AnimVariants.effectScaleCollapsed
    readonly property real effectAnimOffset: AnimVariants.effectAnimOffset
    function variantDuration(baseDuration, entering) {
        return AnimVariants.variantDuration(baseDuration, entering);
    }
    function variantExitCleanupPadding() {
        return AnimVariants.variantExitCleanupPadding();
    }
    function variantCloseInterval(baseDuration) {
        return AnimVariants.variantCloseInterval(baseDuration);
    }

    readonly property var expressiveDurations: {
        if (typeof SettingsData === "undefined") {
            return {
                "fast": 200,
                "normal": 400,
                "large": 600,
                "extraLarge": 1000,
                "expressiveFastSpatial": 350,
                "expressiveDefaultSpatial": 500,
                "expressiveSlowSpatial": 650,
                "expressiveFastEffects": 150,
                "expressiveEffects": 200,
                "expressiveSlowEffects": 300
            };
        }

        const baseDuration = currentAnimationBaseDuration;
        return {
            "fast": baseDuration * 0.4,
            "normal": baseDuration * 0.8,
            "large": baseDuration * 1.2,
            "extraLarge": baseDuration * 2.0,
            "expressiveFastSpatial": baseDuration * 0.7,
            "expressiveDefaultSpatial": baseDuration,
            "expressiveSlowSpatial": baseDuration * 1.3,
            "expressiveFastEffects": baseDuration * 0.3,
            "expressiveEffects": baseDuration * 0.4,
            "expressiveSlowEffects": baseDuration * 0.6
        };
    }

    // Expressive spatial spring presets ([stiffness, damping], unit mass) tuned to a
    // 500ms reference transition; runtime values scale via springPreset().
    readonly property real morphSettleEpsilon: 0.02
    readonly property real morphLayerEpsilon: 0.002

    readonly property var springSpecs: {
        "expressive": [560, 37],
        "fast": [220, 23],
        "default": [300, 24]
    }

    // Damping multipliers for the user-facing spring bounce setting:
    // crisp settles without overshoot, playful adds visible bounce.
    readonly property var springDampingScales: [1.22, 1.0, 0.82]

    // Must stay under the 16px shadow motion padding every fluid surface reserves.
    readonly property var fluidOvershootLimits: [0, 4, 10]
    readonly property real fluidOvershootLimit: {
        if (typeof SettingsData === "undefined" || springMotionDisabled)
            return 0;
        return fluidOvershootLimits[Math.round(SettingsData.springBounce)] ?? 4;
    }

    function tunedSpring(spec, baseDuration) {
        const f = Math.max(0.05, baseDuration / 500);
        const bounce = typeof SettingsData !== "undefined" && SettingsData.springBounce >= 0 && SettingsData.springBounce < springDampingScales.length ? springDampingScales[Math.round(SettingsData.springBounce)] : 1;
        return {
            "stiffness": spec[0] / (f * f),
            "damping": spec[1] / f * bounce,
            "mass": 1
        };
    }

    function springPreset(name, baseDuration) {
        return tunedSpring(springSpecs[name] ?? springSpecs["default"], baseDuration);
    }

    readonly property bool springMotionDisabled: currentAnimationBaseDuration <= 0

    readonly property int notificationAnimationBaseDuration: typeof SettingsData !== "undefined" ? SettingsData.notificationAnimationDuration : 200

    readonly property int notificationEnterDuration: Math.round(notificationAnimationBaseDuration * 0.875)
    readonly property int notificationExitDuration: Math.round(notificationAnimationBaseDuration * 0.75)
    readonly property int notificationStackShiftDuration: notificationAnimationBaseDuration
    readonly property int notificationStackStaggerDuration: Math.round(notificationAnimationBaseDuration * 0.5)

    readonly property int notificationExpandDuration: {
        const base = notificationAnimationBaseDuration;
        return base === 0 ? 0 : Math.round(base * 1.0);
    }

    readonly property int notificationCollapseDuration: {
        const base = notificationAnimationBaseDuration;
        return base === 0 ? 0 : Math.round(base * 0.85);
    }

    readonly property int notificationInlineExpandDuration: Math.round(notificationAnimationBaseDuration * 0.925)
    readonly property int notificationInlineCollapseDuration: Math.round(notificationAnimationBaseDuration * 0.75)

    readonly property real notificationExpandedIconSizeNormal: avatarSize
    readonly property real notificationExpandedIconSizeCompact: avatarSize
    readonly property real notificationButtonCornerRadius: cornerRadiusFull
    readonly property real notificationHoverRevealMargin: spacingXL
    readonly property real notificationContentSpacing: spacingXS
    readonly property real notificationCardPadding: spacingM
    readonly property real notificationCardPaddingCompact: spacingS

    readonly property real stateLayerHover: 0.08
    readonly property real stateLayerFocus: 0.12
    readonly property real stateLayerPressed: 0.12
    readonly property real stateLayerDrag: 0.16

    readonly property int popoutAnimationDuration: {
        if (typeof SettingsData === "undefined")
            return 150;
        if (SettingsData.syncComponentAnimationSpeeds)
            return Math.min(currentAnimationBaseDuration, 1000);
        return SettingsData.popoutAnimationDuration;
    }

    readonly property int modalAnimationDuration: {
        if (typeof SettingsData === "undefined")
            return 150;
        if (SettingsData.syncComponentAnimationSpeeds)
            return Math.min(currentAnimationBaseDuration, 1000);
        return SettingsData.modalAnimationDuration;
    }

    readonly property real radiusStrength: typeof SettingsData !== "undefined" ? SettingsData.radiusStrength : 50
    readonly property real fixedRadius: typeof SettingsData !== "undefined" && SettingsData.radiusMode === "fixed" ? SettingsData.fixedRadius : -1
    readonly property real shapeScale: fixedRadius >= 0 ? fixedRadius / Shape.corners.m : Shape.scaleForStrength(radiusStrength)
    readonly property real cornerRadius: cornerRadiusM
    readonly property real cornerRadiusXXS: Shape.radius("xxs", shapeScale, fixedRadius)
    readonly property real cornerRadiusXS: Shape.radius("xs", shapeScale, fixedRadius)
    readonly property real cornerRadiusS: Shape.radius("s", shapeScale, fixedRadius)
    readonly property real cornerRadiusM: Shape.radius("m", shapeScale, fixedRadius)
    readonly property real cornerRadiusL: Shape.radius("l", shapeScale, fixedRadius)
    readonly property real cornerRadiusLIncreased: Shape.radius("lIncreased", shapeScale, fixedRadius)
    readonly property real cornerRadiusXL: Shape.radius("xl", shapeScale, fixedRadius)
    readonly property real cornerRadiusXLIncreased: Shape.radius("xlIncreased", shapeScale, fixedRadius)
    readonly property real cornerRadiusXXL: Shape.radius("xxl", shapeScale, fixedRadius)
    readonly property real cornerRadiusFull: fixedRadius >= 0 ? fixedRadius : (shapeScale > 0 ? 9999 : 0)
    readonly property real cornerRadiusSmall: cornerRadiusS
    readonly property real cornerRadiusLarge: cornerRadiusL
    readonly property int compositorRadiusOverride: {
        if (typeof SettingsData === "undefined")
            return -1;
        if (!CompositorService.supportsLayoutConfig)
            return -1;
        const override = SettingsData[CompositorService.configKey + "LayoutRadiusOverride"];
        return override === undefined ? -1 : override;
    }
    readonly property real windowRadius: compositorRadiusOverride >= 0 ? compositorRadiusOverride : cornerRadiusL

    function scaledRadius(radius, limit) {
        return Shape.scaledRadius(radius, limit, shapeScale, fixedRadius);
    }

    function fullRadius(width, height) {
        return Shape.fullRadius(width, height, shapeScale, fixedRadius);
    }

    function buttonRadius(width, height, sizeHeight, pressed, round) {
        return Shape.buttonRadius(width, height, sizeHeight, pressed, round, shapeScale, fixedRadius);
    }

    readonly property real groupedListGap: spacingXXS
    readonly property real groupedListInnerRadius: cornerRadiusXS
    readonly property real groupedListOuterRadius: cornerRadiusL

    property string fontFamily: typeof SettingsData !== "undefined" ? resolvedFontFamily(SettingsData.fontFamily) : DCommon.Fonts.sans

    property string monoFontFamily: typeof SettingsData !== "undefined" ? resolvedMonoFontFamily(SettingsData.monoFontFamily) : DCommon.Fonts.mono
    property string displayFontFamily: typeof SettingsData !== "undefined" ? resolvedDisplayFontFamily(SettingsData.displayFontFamily) : DCommon.Fonts.display

    readonly property var fontChoices: [
        {
            "value": "ui",
            "text": I18n.tr("Default")
        },
        {
            "value": "display",
            "text": I18n.tr("Display", "Display font role option")
        }
    ].concat(DCommon.Fonts.bundledFamilies.map(family => ({
                "value": family,
                "text": family
            })))

    function resolvedFontFamily(family) {
        if (family === defaultFontFamily)
            return DCommon.Fonts.sans;
        return family;
    }

    function resolvedMonoFontFamily(family) {
        if (family === defaultMonoFontFamily)
            return DCommon.Fonts.mono;
        return family;
    }

    function resolvedDisplayFontFamily(family) {
        if (family === defaultDisplayFontFamily)
            return DCommon.Fonts.display;
        return family;
    }

    property int fontWeight: typeof SettingsData !== "undefined" ? SettingsData.fontWeight : Font.Normal
    readonly property int fontWeightMedium: shiftedFontWeight(Font.Medium)
    readonly property int fontWeightBold: shiftedFontWeight(Font.Bold)

    function shiftedFontWeight(weight) {
        return Math.max(Font.Thin, Math.min(Font.Black, weight + fontWeight - Font.Normal));
    }

    property real fontScale: typeof SettingsData !== "undefined" ? SettingsData.fontScale : 1.0

    property real spacingXXS: 2
    property real spacingXS: 4
    property real spacingS: 8
    property real spacingM: 12
    property real spacingL: 16
    property real spacingXL: 24
    readonly property real windowInset: spacingM
    property real fontSizeSmall: Math.round(fontScale * 12)
    property real fontSizeMedium: Math.round(fontScale * 14)
    property real fontSizeLarge: Math.round(fontScale * 16)
    property real fontSizeXLarge: Math.round(fontScale * 20)
    property real fontSizeXXLarge: Math.round(fontScale * 28)
    property real fontSizeDisplay: Math.round(fontScale * 36)
    property real fontSizeDisplayLarge: Math.round(fontScale * 57)
    property real barHeight: 48
    property real iconSize: 24
    property real iconSizeSmall: 16
    property real iconSizeLarge: 32
    readonly property real iconSizeMedium: 20
    readonly property int smallBreakpoint: 480
    readonly property int mediumBreakpoint: 768
    readonly property real iconButtonSize: 40
    readonly property real minimumTouchTargetSize: 48
    readonly property real listItemHeight: 56
    readonly property real listItemTwoLineHeight: 72
    readonly property real avatarSize: 36
    readonly property real sliderTrackHeight: 16
    readonly property real sliderHandleWidth: 4
    readonly property real sliderHandleWidthPressed: 2
    readonly property real sliderHandleHeight: 28
    readonly property real sliderHandleGap: 6
    readonly property real sliderTrackHeightS: 24
    readonly property real sliderHandleHeightS: 36
    readonly property real sliderTrackHeightM: 40
    readonly property real sliderHandleHeightM: 52
    readonly property real sliderTrackHeightL: 56
    readonly property real sliderHandleHeightL: 68
    readonly property real sliderTrackHeightXL: 96
    readonly property real sliderHandleHeightXL: 108
    readonly property real switchTrackWidth: 52
    readonly property real switchTrackHeight: 32
    readonly property real switchOutlineWidth: 2
    readonly property real switchThumbUnselected: 16
    readonly property real switchThumbSelected: 24
    readonly property real switchThumbPressed: 28
    readonly property real sliderStopSize: 4
    readonly property real sliderTickSize: 3
    readonly property real menuItemHeight: 40
    readonly property real outlineWidth: 1
    readonly property real outlineWidthFocused: 2
    readonly property real dividerWidth: 1
    readonly property real focusRingWidth: SettingsData.focusRingEnabled ? SettingsData.focusRingWidth : 0
    readonly property real focusRingOffset: 3
    readonly property color focusRingColor: {
        switch (SettingsData.focusRingColor) {
        case "secondary":
            return secondary;
        case "outline":
            return outline;
        case "surfaceText":
            return surfaceText;
        default:
            return primary;
        }
    }
    readonly property color lockScreenContentColor: "#ffffff"
    readonly property real lockScreenScrimAlpha: 0.4
    readonly property real lockScreenBlur: 0.8
    readonly property int lockScreenBlurMax: 32
    readonly property color screenOffColor: "#000000"
    readonly property real scrimAlpha: 0.55
    readonly property color scrimColor: currentThemeData.scrim || "#000000"
    readonly property real buttonHeightXXS: 28
    readonly property real buttonHeightXS: 32
    readonly property real buttonHeightS: 40
    readonly property real buttonHeightM: 56
    readonly property real buttonMinWidth: 58
    readonly property real pressScale: 0.98
    readonly property real iconEnterScale: 0.6
    readonly property real osdHeight: 60
    readonly property real osdLevelWidth: 264
    readonly property real osdLevelVerticalHeight: 352
    readonly property real osdMediaWidth: 308
    readonly property real dialogMaxWidth: 560
    readonly property real bottomSheetHandleWidth: 36
    readonly property real bottomSheetHandleHeight: 4
    readonly property real popupEnterScale: 0.92
    readonly property real fabEnterScale: 0.2
    readonly property real pendingOpacity: 0.6
    readonly property real spinnerStrokeWidth: 2
    readonly property real tabMinWidth: 64
    readonly property real tabIndicatorHeight: 3
    readonly property real navigationHeight: 64
    readonly property real navigationRailWidth: 96
    readonly property real navigationItemMinWidth: 80
    readonly property real navigationIndicatorWidth: 56
    readonly property real navigationIndicatorHeight: 32
    readonly property real navigationVerticalPadding: 6
    readonly property real tabIndicatorMinWidth: 24
    readonly property real tabIndicatorInset: 2
    readonly property real launcherTileSize: 120
    readonly property real launcherImageRatio: 0.75
    readonly property int launcherMaxVisibleRows: 8
    readonly property real launcherWidthMicro: 500
    readonly property real launcherWidthDefault: 620
    readonly property real launcherWidthWide: 720
    readonly property real launcherWidthLarge: 860
    readonly property real launcherHeightDefault: 600
    readonly property real launcherScreenMargin: 100

    readonly property real fieldDefaultWidth: 200
    readonly property real fieldHeight: Math.round(fontSizeMedium * 3)
    readonly property real fieldHeightLarge: 48
    readonly property real outlinedFieldLabelLineHeight: 16
    readonly property real textFieldSpatialStiffness: 800
    readonly property real textFieldSpatialDampingRatio: 1
    readonly property real textFieldFastEffectsStiffness: 3800
    readonly property real textFieldSlowEffectsStiffness: 800
    readonly property real textEditHeight: Math.round(fontSizeMedium * 8)
    readonly property real tooltipMaxWidth: 500
    readonly property int tooltipDelay: 400
    readonly property real scrollbarThickness: 6
    readonly property real scrollbarGap: spacingXS
    readonly property int scrollbarHideDelay: 1200
    readonly property real menuMaxHeight: 400
    readonly property real clockFaceSize: 250
    readonly property real clockOuterRingRatio: 101 / clockFaceSize
    readonly property real clockInnerRingRatio: 69 / clockFaceSize
    readonly property real clockHandWidth: 2
    readonly property real clockHandleSize: 40
    readonly property real clockCenterSize: 8
    readonly property int clockSwitchDelay: 100
    readonly property real chipIconSize: 18
    readonly property real buttonGroupExpandRatio: 0.15
    readonly property real wallpaperBlur: 0.8
    readonly property int wallpaperBlurMax: 75
    readonly property color contrastDark: "#000000"
    readonly property color contrastLight: "#ffffff"

    property real panelTransparency: 0.85
    property real popupTransparency: {
        if (typeof SettingsData === "undefined")
            return 1.0;
        return SettingsData.popupTransparency !== undefined ? SettingsData.popupTransparency : 1.0;
    }

    function screenTransition() {
        screenTransitionNeeded();
    }

    function switchTheme(themeName, savePrefs = true, enableTransition = true) {
        if (enableTransition) {
            screenTransition();
            themeTransitionTimer.themeName = themeName;
            themeTransitionTimer.savePrefs = savePrefs;
            themeTransitionTimer.restart();
            return;
        }

        if (themeName === dynamic) {
            currentTheme = dynamic;
            if (currentThemeCategory !== "registry")
                currentThemeCategory = dynamic;
        } else if (themeName === custom) {
            currentTheme = custom;
            if (currentThemeCategory !== "registry")
                currentThemeCategory = custom;
            if (typeof SettingsData !== "undefined" && SettingsData.customThemeFile) {
                loadCustomThemeFromFile(SettingsData.customThemeFile);
            }
        } else if (themeName === "" && currentThemeCategory === "registry") {
            // Registry category selected but no theme chosen yet
        } else {
            currentTheme = themeName;
            if (currentThemeCategory !== "registry") {
                currentThemeCategory = "generic";
            }
        }
        if (savePrefs && typeof SettingsData !== "undefined") {
            SettingsData.set("currentThemeCategory", currentThemeCategory);
            SettingsData.set("currentThemeName", currentTheme);
        }

        generateSystemThemesFromCurrentTheme();
    }

    function setLightMode(light, savePrefs = true, enableTransition = false) {
        if (typeof SettingsData !== "undefined" && SettingsData.matugenSmartMode) {
            SettingsData.matugenSmartMode = false;
            SettingsData.saveSettings();
        }

        if (enableTransition) {
            screenTransition();
            lightModeTransitionTimer.lightMode = light;
            lightModeTransitionTimer.savePrefs = savePrefs;
            lightModeTransitionTimer.restart();
            return;
        }

        if (savePrefs && typeof SessionData !== "undefined") {
            SessionData.setLightMode(light);
        }

        if (typeof SettingsData !== "undefined") {
            SettingsData.updateCosmicThemeMode(light);
        }
        generateSystemThemesFromCurrentTheme();
    }

    function toggleLightMode(savePrefs = true) {
        setLightMode(!isLightMode, savePrefs, true);
    }

    function getThemeColors(themeName) {
        if (themeName === "custom" && customThemeData) {
            return customThemeData;
        }
        return StockThemes.getThemeByName(themeName, isLightMode);
    }

    function switchThemeCategory(category, defaultTheme) {
        screenTransition();
        themeCategoryTransitionTimer.category = category;
        themeCategoryTransitionTimer.defaultTheme = defaultTheme;
        themeCategoryTransitionTimer.restart();
    }

    function loadCustomTheme(themeData) {
        customThemeRawData = themeData;
        customThemeData = resolveCustomTheme(themeData, isLightMode ? "light" : "dark");
        generateSystemThemesFromCurrentTheme();
    }

    function resolveCustomTheme(themeData, colorMode) {
        if (!themeData)
            return StockThemes.getThemeByName("purple", colorMode === "light");

        var baseColors = {};
        if (themeData.dark || themeData.light) {
            baseColors = themeData[colorMode] || themeData.dark || themeData.light || {};
        } else {
            baseColors = themeData;
        }

        if (themeData.variants) {
            const themeId = themeData.id || "";

            if (themeData.variants.type === "multi" && themeData.variants.flavors && themeData.variants.accents) {
                const defaults = themeData.variants.defaults || {};
                const modeDefaults = defaults[colorMode] || defaults.dark || {};
                const stored = typeof SettingsData !== "undefined" ? SettingsData.getRegistryThemeMultiVariant(themeId, modeDefaults, colorMode) : modeDefaults;
                var flavorId = stored.flavor || modeDefaults.flavor || "";
                const accentId = stored.accent || modeDefaults.accent || "";
                var flavor = findVariant(themeData.variants.flavors, flavorId);
                if (flavor) {
                    const hasCurrentModeColors = flavor[colorMode] && (flavor[colorMode].primary || flavor[colorMode].surface);
                    if (!hasCurrentModeColors) {
                        flavorId = modeDefaults.flavor || "";
                        flavor = findVariant(themeData.variants.flavors, flavorId);
                    }
                }
                const accent = findAccent(themeData.variants.accents, accentId);
                if (flavor) {
                    const flavorColors = flavor[colorMode] || flavor.dark || flavor.light || {};
                    baseColors = mergeColors(baseColors, flavorColors);
                }
                if (accent && flavor) {
                    const accentColors = accent[flavor.id] || {};
                    baseColors = mergeColors(baseColors, accentColors);
                }
                return baseColors;
            }

            if (themeData.variants.options && themeData.variants.options.length > 0) {
                const selectedVariantId = typeof SettingsData !== "undefined" ? SettingsData.getRegistryThemeVariant(themeId, themeData.variants.default) : themeData.variants.default;
                const variant = findVariant(themeData.variants.options, selectedVariantId);
                if (variant) {
                    const variantColors = variant[colorMode] || variant.dark || variant.light || {};
                    return mergeColors(baseColors, variantColors);
                }
            }
        }

        return baseColors;
    }

    function findVariant(options, variantId) {
        if (!variantId || !options)
            return null;
        for (var i = 0; i < options.length; i++) {
            if (options[i].id === variantId)
                return options[i];
        }
        return options[0] || null;
    }

    function findAccent(accents, accentId) {
        if (!accentId || !accents)
            return null;
        for (var i = 0; i < accents.length; i++) {
            if (accents[i].id === accentId)
                return accents[i];
        }
        return accents[0] || null;
    }

    function mergeColors(base, overlay) {
        var result = JSON.parse(JSON.stringify(base));
        for (var key in overlay) {
            if (overlay[key])
                result[key] = overlay[key];
        }
        return result;
    }

    function loadCustomThemeFromFile(filePath) {
        customThemeFileView.path = Paths.expandTilde(filePath);
    }

    function reloadCustomThemeVariant() {
        if (currentTheme !== "custom" || !customThemeRawData)
            return;
        loadCustomTheme(customThemeRawData);
    }

    property alias availableThemeNames: root._availableThemeNames
    readonly property var _availableThemeNames: StockThemes.getAllThemeNames()
    property string currentThemeName: currentTheme

    property real notepadTransparency: SettingsData.notepadTransparencyOverride >= 0 ? SettingsData.notepadTransparencyOverride : floatingWindowTransparency

    property bool widgetBackgroundHasAlpha: {
        const colorMode = typeof SettingsData !== "undefined" ? SettingsData.widgetBackgroundColor : "default";
        return colorMode === "sth" || colorMode === "custom";
    }

    function safeColor(value, fallback) {
        try {
            if (value === undefined || value === null || value === "")
                return fallback;
            return Qt.color(value);
        } catch (e) {
            return fallback;
        }
    }

    readonly property color widgetBackgroundCustomBaseColor: safeColor(typeof SettingsData !== "undefined" ? SettingsData.widgetBackgroundCustomColor : "#6750A4", primaryContainer)
    readonly property real widgetBackgroundCustomStrength: Math.max(0, Math.min(1, typeof SettingsData !== "undefined" ? (SettingsData.widgetBackgroundCustomStrength ?? 0.4) : 0.4))

    property var widgetBaseBackgroundColor: {
        const colorMode = typeof SettingsData !== "undefined" ? SettingsData.widgetBackgroundColor : "default";
        switch (colorMode) {
        case "default":
            return cardSurface;
        case "s":
            return surface;
        case "sc":
            return surfaceContainer;
        case "sch":
            return surfaceContainerHigh;
        case "primaryContainer":
            return primaryContainer;
        case "secondaryContainer":
            return secondaryContainer;
        case "tertiaryContainer":
            return tertiaryContainer;
        case "custom":
            return blend(surfaceContainerHigh, widgetBackgroundCustomBaseColor, widgetBackgroundCustomStrength);
        case "sth":
        default:
            return surfaceTextHover;
        }
    }

    property color widgetBaseHoverColor: {
        const blended = blend(widgetBaseBackgroundColor, primary, 0.1);
        return withAlpha(blended, Math.max(0.3, blended.a));
    }

    property color widgetIconColor: {
        if (typeof SettingsData === "undefined") {
            return surfaceText;
        }

        switch (SettingsData.widgetColorMode) {
        case "colorful":
            return surfaceText;
        case "default":
        default:
            return surfaceText;
        }
    }

    property color widgetInactiveIconColor: withAlpha(widgetIconColor, 0.6)

    property color widgetTextColor: {
        if (typeof SettingsData === "undefined") {
            return surfaceText;
        }

        switch (SettingsData.widgetColorMode) {
        case "colorful":
            return primary;
        case "default":
        default:
            return surfaceText;
        }
    }

    function barIconSize(barThickness, offset, maximizeIcon, iconScale) {
        const defaultOffset = offset !== undefined ? offset : -6;
        const size = (maximizeIcon ?? false) ? iconSizeLarge : iconSize;
        const s = iconScale !== undefined ? iconScale : 1.0;

        return 2 * Math.round((barThickness / 48) * (size + defaultOffset) * s / 2);
    }

    function barTextSize(barThickness, fontScale, maximizeText) {
        const scale = barThickness / 48;
        const dankBarScale = fontScale !== undefined ? fontScale : 1.0;
        const maximized = maximizeText ?? false;
        if (scale <= 0.75)
            return Math.round((maximized ? fontSizeMedium : fontSizeSmall * 0.9) * dankBarScale);
        if (scale >= 1.25)
            return Math.round((maximized ? fontSizeXLarge : fontSizeMedium) * dankBarScale);
        return Math.round((maximized ? fontSizeLarge : fontSizeSmall) * dankBarScale);
    }

    // !TODO: plugin API only (dms-plugins DankKDEConnect); fold into a parametrized BatteryService ladder and drop from Theme
    function getBatteryIcon(level, isCharging, batteryAvailable) {
        if (!batteryAvailable)
            return "battery_std";

        if (isCharging) {
            if (level >= 90)
                return "battery_charging_full";
            if (level >= 80)
                return "battery_charging_90";
            if (level >= 60)
                return "battery_charging_80";
            if (level >= 50)
                return "battery_charging_60";
            if (level >= 30)
                return "battery_charging_50";
            if (level >= 20)
                return "battery_charging_30";
            return "battery_charging_20";
        } else {
            if (level >= 95)
                return "battery_full";
            if (level >= 85)
                return "battery_6_bar";
            if (level >= 70)
                return "battery_5_bar";
            if (level >= 55)
                return "battery_4_bar";
            if (level >= 40)
                return "battery_3_bar";
            if (level >= 25)
                return "battery_2_bar";
            if (level >= 10)
                return "battery_1_bar";
            return "battery_alert";
        }
    }

    function getPowerProfileIcon(profile) {
        switch (profile) {
        case 0:
            return "battery_saver";
        case 1:
            return "battery_std";
        case 2:
            return "flash_on";
        default:
            return "settings";
        }
    }

    function getPowerProfileLabel(profile) {
        switch (profile) {
        case 0:
            return I18n.tr("Power Saver", "power profile option");
        case 1:
            return I18n.tr("Balanced", "power profile option");
        case 2:
            return I18n.tr("Performance", "power profile option");
        default:
            return I18n.tr("Unknown", "power profile option");
        }
    }

    function onLightModeChanged() {
        if (currentTheme === "custom" && customThemeFileView.path) {
            customThemeFileView.reload();
        }
    }

    function setDesiredTheme(kind, value, isLight, iconTheme, matugenType, stockColors) {
        if (!matugenAvailable) {
            log.warn("matugen not available or disabled - cannot set system theme");
            return;
        }

        if (workerRunning) {
            log.info("Worker already running, queueing request");
            pendingThemeRequest = {
                kind,
                value,
                isLight,
                iconTheme,
                matugenType,
                stockColors
            };
            return;
        }

        const desired = {
            "kind": kind,
            "value": value,
            "mode": (typeof SettingsData !== "undefined" && SettingsData.matugenSmartMode && kind === "image" && !stockColors) ? "smart" : (isLight ? "light" : "dark"),
            "iconTheme": iconTheme || "System Default",
            "matugenType": matugenType || "scheme-tonal-spot",
            "runUserTemplates": (typeof SettingsData !== "undefined") ? SettingsData.runUserMatugenTemplates : true
        };

        const args = [Proc.dmsBin, "matugen", "queue", "--state-dir", stateDir, "--shell-dir", shellDir, "--config-dir", configDir, "--kind", desired.kind, "--value", desired.value, "--mode", desired.mode, "--icon-theme", desired.iconTheme, "--matugen-type", desired.matugenType,];

        if (!desired.runUserTemplates) {
            args.push("--run-user-templates=false");
        }
        if (stockColors) {
            args.push("--stock-colors", JSON.stringify(stockColors));
        }
        if (typeof SettingsData !== "undefined" && SettingsData.syncModeWithPortal) {
            args.push("--sync-mode-with-portal");
        }
        if (typeof SettingsData !== "undefined" && SettingsData.terminalsAlwaysDark) {
            args.push("--terminals-always-dark");
        }
        if (typeof SettingsData !== "undefined" && SettingsData.terminalOpacity < 100) {
            args.push("--terminal-opacity", SettingsData.terminalOpacity.toString());
        }
        if (typeof SettingsData !== "undefined" && SettingsData.terminalPalette !== "default") {
            args.push("--terminal-palette", SettingsData.terminalPalette);
        }
        if (typeof SettingsData !== "undefined" && SettingsData.matugenContrast !== 0) {
            args.push("--contrast", SettingsData.matugenContrast.toString());
        }
        if (typeof SettingsData !== "undefined") {
            args.push(...ContrastFloors.args(SettingsData.contrastOverrides));
        }
        // Only sent when it would change something. A shell newer than the dms
        // binary is a supported setup (DMS_SHELL_DIR / -c), and an older binary
        // exits with "unknown flag: --source-mode" rather than ignoring it, so
        // the default must not put the flag on the command line at all.
        const seedColor = (typeof SettingsData !== "undefined" && !stockColors) ? SettingsData.matugenSeedColor : "";
        if (seedColor) {
            args.push("--seed-color", seedColor);
        } else if (typeof SettingsData !== "undefined" && SettingsData.matugenSourceMode && SettingsData.matugenSourceMode !== "dominant") {
            args.push("--source-mode", SettingsData.matugenSourceMode);
        }
        if (typeof SettingsData !== "undefined" && !stockColors && SettingsData.matugenSpec !== "2021") {
            args.push("--spec", SettingsData.matugenSpec);
        }

        if (typeof SettingsData !== "undefined") {
            const skipTemplates = [];
            if (!SettingsData.runDmsMatugenTemplates) {
                skipTemplates.push("gtk", "nvim", "niri", "qt5ct", "qt6ct", "qtengine", "fcitx5", "firefox", "pywalfox", "zenbrowser", "vesktop", "vencord", "equibop", "ghostty", "kitty", "foot", "alacritty", "wezterm", "dgop", "kcolorscheme", "vscode", "emacs", "zed");
            } else {
                if (!SettingsData.matugenTemplateGtk)
                    skipTemplates.push("gtk");
                if (!SettingsData.matugenTemplateNiri)
                    skipTemplates.push("niri");
                if (!SettingsData.matugenTemplateHyprland)
                    skipTemplates.push("hyprland");
                if (!SettingsData.matugenTemplateMangowc)
                    skipTemplates.push("mangowc");
                if (!SettingsData.matugenTemplateQt5ct)
                    skipTemplates.push("qt5ct");
                if (!SettingsData.matugenTemplateQt6ct)
                    skipTemplates.push("qt6ct");
                if (!SettingsData.matugenTemplateQtengine)
                    skipTemplates.push("qtengine");
                if (!SettingsData.matugenTemplateFcitx5)
                    skipTemplates.push("fcitx5");
                if (!SettingsData.matugenTemplateFirefox)
                    skipTemplates.push("firefox");
                if (!SettingsData.matugenTemplatePywalfox)
                    skipTemplates.push("pywalfox");
                if (!SettingsData.matugenTemplateZenBrowser)
                    skipTemplates.push("zenbrowser");
                if (!SettingsData.matugenTemplateVesktop)
                    skipTemplates.push("vesktop");
                if (!SettingsData.matugenTemplateVencord)
                    skipTemplates.push("vencord");
                if (!SettingsData.matugenTemplateEquibop)
                    skipTemplates.push("equibop");
                if (!SettingsData.matugenTemplateGhostty)
                    skipTemplates.push("ghostty");
                if (!SettingsData.matugenTemplateKitty)
                    skipTemplates.push("kitty");
                if (!SettingsData.matugenTemplateFoot)
                    skipTemplates.push("foot");
                if (!SettingsData.matugenTemplateNeovim)
                    skipTemplates.push("nvim");
                if (!SettingsData.matugenTemplateAlacritty)
                    skipTemplates.push("alacritty");
                if (!SettingsData.matugenTemplateWezterm)
                    skipTemplates.push("wezterm");
                if (!SettingsData.matugenTemplateDgop)
                    skipTemplates.push("dgop");
                if (!SettingsData.matugenTemplateKcolorscheme)
                    skipTemplates.push("kcolorscheme");
                if (!SettingsData.matugenTemplateVscode)
                    skipTemplates.push("vscode");
                if (!SettingsData.matugenTemplateEmacs)
                    skipTemplates.push("emacs");
                if (!SettingsData.matugenTemplateZed)
                    skipTemplates.push("zed");
            }
            if (skipTemplates.length > 0) {
                args.push("--skip-templates", skipTemplates.join(","));
            }
        }

        const runKey = Qt.md5(JSON.stringify(args));
        const startupRun = !_matugenRunKey && typeof SettingsData !== "undefined" && SettingsData.generateThemeAtStartup;
        if (!startupRun && !colorsFileLoadFailed && runKey === CacheData.matugenAppliedKey) {
            log.info("Theme inputs unchanged since the last run, skipping generation");
            return;
        }

        log.info("Setting desired theme -", kind, "mode:", isLight ? "light" : "dark", stockColors ? "(stock colors)" : "(dynamic)");
        themeGenerationStarting();

        log.debug("Starting matugen worker");
        workerRunning = true;
        _matugenRunKey = runKey;
        _lastGenerateMs = Date.now();
        _workerStderr = [];
        _workerStderrUsage = false;
        systemThemeGenerator.command = args;
        systemThemeGenerator.running = true;
    }

    // an older dms rejecting a newer flag prints cobra usage after the error line, which must stay in view
    function _recordWorkerStderr(line) {
        const text = line.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").replace(/^\s*(FATAL|ERROR|WARN|INFO|DEBUG)\s+\S+:\s*/, "").replace(/^Theme generation failed:\s*/, "").trim();
        if (!text || _workerStderrUsage || /^(Backtrace omitted|Run with RUST_BACKTRACE)/.test(text))
            return;
        if (text === "Usage:") {
            _workerStderrUsage = true;
            return;
        }
        _workerStderr = _workerStderr.concat(text).slice(-_workerStderrKeep);
    }

    function _shellQuote(arg) {
        return /^[\w@%+=:,.\/-]+$/.test(arg) ? arg : "'" + arg.replace(/'/g, "'\\''") + "'";
    }

    function _workerReproduceCommand() {
        const args = systemThemeGenerator.command.slice();
        const queueAt = args.indexOf("queue");
        if (queueAt > 0)
            args[queueAt] = "generate";
        return args.map(_shellQuote).join(" ");
    }

    function _reportWorkerFailure(message) {
        const details = _workerStderr.concat(themeTroubleshootingUrl).join("\n");
        if (typeof ToastService !== "undefined")
            ToastService.showError(message, details, _workerReproduceCommand(), "theme-worker");
        log.warn(message);
    }

    function _workerStartFailed() {
        if (!workerRunning || systemThemeGenerator.running)
            return;
        workerRunning = false;
        pendingThemeRequest = null;
        if (CacheData.matugenAppliedKey !== "")
            CacheData.set("matugenAppliedKey", "");
        _reportWorkerFailure(I18n.tr("Theme worker failed to start", "error toast, the dms binary could not be launched"));
        root.matugenCompleted((typeof SessionData !== "undefined" && SessionData.isLightMode) ? "light" : "dark", "error");
    }

    function generateSystemThemesFromCurrentTheme() {
        if (!matugenAvailable)
            return;

        _pendingGenerateParams = true;
        _themeGenerateDebounce.restart();
    }

    function _executeThemeGeneration() {
        if (!_pendingGenerateParams)
            return;
        _pendingGenerateParams = null;

        const isLight = (typeof SessionData !== "undefined" && SessionData.isLightMode);
        const iconTheme = (typeof SettingsData !== "undefined" && SettingsData.iconTheme) ? SettingsData.iconTheme : "System Default";

        if (currentTheme === dynamic) {
            const selectedMatugenType = SettingsData.matugenScheme || "scheme-tonal-spot";
            const source = rawWallpaperPath || SettingsData.matugenSeedColor || materialWallpaperSeed;
            const kind = source.startsWith("#") ? "hex" : "image";
            setDesiredTheme(kind, source, isLight, iconTheme, selectedMatugenType, null);
            return;
        }

        let darkTheme, lightTheme;
        if (currentTheme === "custom") {
            if (customThemeRawData && (customThemeRawData.dark || customThemeRawData.light)) {
                darkTheme = customThemeRawData.dark || customThemeRawData.light;
                lightTheme = customThemeRawData.light || customThemeRawData.dark;

                if (customThemeRawData.variants) {
                    const themeId = customThemeRawData.id || "";

                    if (customThemeRawData.variants.type === "multi" && customThemeRawData.variants.flavors && customThemeRawData.variants.accents) {
                        const defaults = customThemeRawData.variants.defaults || {};
                        const darkDefaults = defaults.dark || {};
                        const lightDefaults = defaults.light || defaults.dark || {};
                        const storedDark = typeof SettingsData !== "undefined" ? SettingsData.getRegistryThemeMultiVariant(themeId, darkDefaults, "dark") : darkDefaults;
                        const storedLight = typeof SettingsData !== "undefined" ? SettingsData.getRegistryThemeMultiVariant(themeId, lightDefaults, "light") : lightDefaults;
                        const darkFlavorId = storedDark.flavor || darkDefaults.flavor || "";
                        const lightFlavorId = storedLight.flavor || lightDefaults.flavor || "";
                        const darkAccentId = storedDark.accent || darkDefaults.accent || "";
                        const lightAccentId = storedLight.accent || lightDefaults.accent || "";
                        const darkFlavor = findVariant(customThemeRawData.variants.flavors, darkFlavorId);
                        const lightFlavor = findVariant(customThemeRawData.variants.flavors, lightFlavorId);
                        const darkAccent = findAccent(customThemeRawData.variants.accents, darkAccentId);
                        const lightAccent = findAccent(customThemeRawData.variants.accents, lightAccentId);
                        if (darkFlavor) {
                            darkTheme = mergeColors(darkTheme, darkFlavor.dark || {});
                            if (darkAccent)
                                darkTheme = mergeColors(darkTheme, darkAccent[darkFlavor.id] || {});
                        }
                        if (lightFlavor) {
                            lightTheme = mergeColors(lightTheme, lightFlavor.light || {});
                            if (lightAccent)
                                lightTheme = mergeColors(lightTheme, lightAccent[lightFlavor.id] || {});
                        }
                    } else if (customThemeRawData.variants.options) {
                        const selectedVariantId = typeof SettingsData !== "undefined" ? SettingsData.getRegistryThemeVariant(themeId, customThemeRawData.variants.default) : customThemeRawData.variants.default;
                        const variant = findVariant(customThemeRawData.variants.options, selectedVariantId);
                        if (variant) {
                            darkTheme = mergeColors(darkTheme, variant.dark || {});
                            lightTheme = mergeColors(lightTheme, variant.light || {});
                        }
                    }
                }
            } else {
                darkTheme = customThemeData;
                lightTheme = customThemeData;
            }
        } else {
            darkTheme = StockThemes.getThemeByName(currentTheme, false);
            lightTheme = StockThemes.getThemeByName(currentTheme, true);
        }

        if (!darkTheme || !darkTheme.primary) {
            log.warn("Theme data not available for:", currentTheme);
            return;
        }

        const stockColors = buildMatugenColorsFromTheme(darkTheme, lightTheme);
        const themeData = isLight ? lightTheme : darkTheme;
        setDesiredTheme("hex", themeData.primary, isLight, iconTheme, themeData.matugen_type, stockColors);
    }

    function buildMatugenColorsFromTheme(darkTheme, lightTheme) {
        const colors = {};
        const isLight = SessionData !== "undefined" && SessionData.isLightMode;

        function addColor(matugenKey, darkVal, lightVal) {
            if (!darkVal && !lightVal)
                return;
            colors[matugenKey] = {
                "dark": {
                    "color": String(darkVal || lightVal)
                },
                "light": {
                    "color": String(lightVal || darkVal)
                },
                "default": {
                    "color": String((isLight && lightVal) ? lightVal : darkVal)
                }
            };
        }

        function get(theme, key, fallback) {
            return theme[key] || fallback;
        }

        function onContainer(theme, container, explicit) {
            if (explicit)
                return explicit;
            if (!container || !theme.surfaceText || !theme.surface)
                return theme.surfaceText;
            return Contrast.readableOn(Qt.color(container), [Qt.color(theme.surfaceText), Qt.color(theme.surface), contrastLight, contrastDark]).toString();
        }

        addColor("primary", darkTheme.primary, lightTheme.primary);
        addColor("on_primary", darkTheme.primaryText, lightTheme.primaryText);
        addColor("primary_container", darkTheme.primaryContainer, lightTheme.primaryContainer);
        addColor("on_primary_container", onContainer(darkTheme, darkTheme.primaryContainer, darkTheme.onPrimaryContainer || darkTheme.primaryContainerText), onContainer(lightTheme, lightTheme.primaryContainer, lightTheme.onPrimaryContainer || lightTheme.primaryContainerText));
        addColor("secondary", darkTheme.secondary, lightTheme.secondary);
        addColor("on_secondary", darkTheme.secondaryText || darkTheme.primaryText, lightTheme.secondaryText || lightTheme.primaryText);
        addColor("secondary_container", darkTheme.secondaryContainer || darkTheme.surfaceContainerHigh, lightTheme.secondaryContainer || lightTheme.surfaceContainerHigh);
        addColor("on_secondary_container", onContainer(darkTheme, darkTheme.secondaryContainer, darkTheme.onSecondaryContainer || darkTheme.secondaryContainerText), onContainer(lightTheme, lightTheme.secondaryContainer, lightTheme.onSecondaryContainer || lightTheme.secondaryContainerText));
        addColor("tertiary", darkTheme.tertiary || darkTheme.secondary, lightTheme.tertiary || lightTheme.secondary);
        addColor("on_tertiary", darkTheme.tertiaryText || darkTheme.secondaryText || darkTheme.primaryText, lightTheme.tertiaryText || lightTheme.secondaryText || lightTheme.primaryText);
        addColor("tertiary_container", darkTheme.tertiaryContainer || darkTheme.secondaryContainer || darkTheme.surfaceContainerHigh, lightTheme.tertiaryContainer || lightTheme.secondaryContainer || lightTheme.surfaceContainerHigh);
        addColor("on_tertiary_container", onContainer(darkTheme, darkTheme.tertiaryContainer, darkTheme.onTertiaryContainer || darkTheme.tertiaryContainerText), onContainer(lightTheme, lightTheme.tertiaryContainer, lightTheme.onTertiaryContainer || lightTheme.tertiaryContainerText));
        addColor("error", darkTheme.error || "#F2B8B5", lightTheme.error || "#B3261E");
        addColor("on_error", darkTheme.errorText || "#601410", lightTheme.errorText || "#FFFFFF");
        addColor("error_container", darkTheme.errorContainer || "#8C1D18", lightTheme.errorContainer || "#F9DEDC");
        addColor("on_error_container", darkTheme.errorContainerText || "#F9DEDC", lightTheme.errorContainerText || "#410E0B");
        addColor("surface", darkTheme.surface, lightTheme.surface);
        addColor("on_surface", darkTheme.surfaceText, lightTheme.surfaceText);
        addColor("surface_variant", darkTheme.surfaceVariant, lightTheme.surfaceVariant);
        addColor("on_surface_variant", darkTheme.surfaceVariantText, lightTheme.surfaceVariantText);
        addColor("surface_tint", darkTheme.surfaceTint, lightTheme.surfaceTint);
        addColor("background", darkTheme.background, lightTheme.background);
        addColor("on_background", darkTheme.backgroundText, lightTheme.backgroundText);
        addColor("outline", darkTheme.outline, lightTheme.outline);
        addColor("outline_variant", darkTheme.outlineVariant || darkTheme.surfaceVariant, lightTheme.outlineVariant || lightTheme.surfaceVariant);
        addColor("surface_container", darkTheme.surfaceContainer, lightTheme.surfaceContainer);
        addColor("surface_container_high", darkTheme.surfaceContainerHigh, lightTheme.surfaceContainerHigh);
        addColor("surface_container_highest", darkTheme.surfaceContainerHighest || darkTheme.surfaceContainerHigh, lightTheme.surfaceContainerHighest || lightTheme.surfaceContainerHigh);
        addColor("surface_container_low", darkTheme.surfaceContainerLow || darkTheme.surface, lightTheme.surfaceContainerLow || lightTheme.surface);
        addColor("surface_container_lowest", darkTheme.surfaceContainerLowest || darkTheme.background, lightTheme.surfaceContainerLowest || lightTheme.background);
        addColor("surface_bright", darkTheme.surfaceBright || darkTheme.surfaceContainerHighest || darkTheme.surfaceContainerHigh, lightTheme.surfaceBright || lightTheme.surface);
        addColor("surface_dim", darkTheme.surfaceDim || darkTheme.background, lightTheme.surfaceDim || lightTheme.surfaceContainer);
        addColor("inverse_surface", darkTheme.inverseSurface || lightTheme.surface, lightTheme.inverseSurface || darkTheme.surface);
        addColor("inverse_on_surface", darkTheme.inverseOnSurface || lightTheme.surfaceText, lightTheme.inverseOnSurface || darkTheme.surfaceText);
        addColor("inverse_primary", darkTheme.inversePrimary || lightTheme.primary, lightTheme.inversePrimary || darkTheme.primary);
        addColor("scrim", darkTheme.scrim || "#000000", lightTheme.scrim || "#000000");
        addColor("shadow", darkTheme.shadow || "#000000", lightTheme.shadow || "#000000");
        addColor("source_color", darkTheme.primary, lightTheme.primary);
        addColor("primary_fixed", darkTheme.primaryFixed || darkTheme.primaryContainer, lightTheme.primaryFixed || lightTheme.primaryContainer);
        addColor("primary_fixed_dim", darkTheme.primaryFixedDim || darkTheme.primary, lightTheme.primaryFixedDim || lightTheme.primary);
        addColor("on_primary_fixed", darkTheme.onPrimaryFixed || darkTheme.primaryText, lightTheme.onPrimaryFixed || lightTheme.primaryText);
        addColor("on_primary_fixed_variant", darkTheme.onPrimaryFixedVariant || darkTheme.primaryText, lightTheme.onPrimaryFixedVariant || lightTheme.primaryText);
        addColor("secondary_fixed", darkTheme.secondaryFixed || darkTheme.secondary, lightTheme.secondaryFixed || lightTheme.secondary);
        addColor("secondary_fixed_dim", darkTheme.secondaryFixedDim || darkTheme.secondary, lightTheme.secondaryFixedDim || lightTheme.secondary);
        addColor("on_secondary_fixed", darkTheme.onSecondaryFixed || darkTheme.primaryText, lightTheme.onSecondaryFixed || lightTheme.primaryText);
        addColor("on_secondary_fixed_variant", darkTheme.onSecondaryFixedVariant || darkTheme.primaryText, lightTheme.onSecondaryFixedVariant || lightTheme.primaryText);
        addColor("tertiary_fixed", darkTheme.tertiaryFixed || darkTheme.tertiary || darkTheme.secondary, lightTheme.tertiaryFixed || lightTheme.tertiary || lightTheme.secondary);
        addColor("tertiary_fixed_dim", darkTheme.tertiaryFixedDim || darkTheme.tertiary || darkTheme.secondary, lightTheme.tertiaryFixedDim || lightTheme.tertiary || lightTheme.secondary);
        addColor("on_tertiary_fixed", darkTheme.onTertiaryFixed || darkTheme.primaryText, lightTheme.onTertiaryFixed || lightTheme.primaryText);
        addColor("on_tertiary_fixed_variant", darkTheme.onTertiaryFixedVariant || darkTheme.primaryText, lightTheme.onTertiaryFixedVariant || lightTheme.primaryText);

        return colors;
    }

    function refreshGtkTheme() {
        const isLight = (typeof SessionData !== "undefined" && SessionData.isLightMode);
        const theme = isLight ? "adw-gtk3" : "adw-gtk3-dark";
        const schema = "org.gnome.desktop.interface";
        const key = "gtk-theme";
        // Same-polarity built-in intermediate: "" resolves to light Adwaita and
        // toolkit-following apps (Chromium without a portal) latch on it.
        const reset = GSettings.setCmd(schema, key, isLight ? "Adwaita" : "HighContrastInverse");
        const apply = GSettings.setCmd(schema, key, theme);

        Proc.runCommand("gtkRefresher", ["sh", "-c", `${reset}; ${apply}`], (output, exitCode) => {
            if (exitCode !== 0) {
                log.warn("Failed to refresh gtk-theme");
            }
        });
    }

    function patchGtk3colors() {
        const isLight = (typeof SessionData !== "undefined" && SessionData.isLightMode);
        Proc.runCommand("gtk3Patcher", ["bash", shellDir + "/scripts/gtk.sh", configDir, "patch", isLight], (output, exitCode) => {
            switch (exitCode) {
            case 0:
                refreshGtkTheme();
                break;
            case 2:
                break;
            default:
                log.warn(`Failed to patch GTK3 colors: ${output}`);
            }
        });
    }

    function applyGtkColors() {
        if (!matugenAvailable) {
            if (typeof ToastService !== "undefined") {
                ToastService.showError(I18n.tr("%1 not available or disabled - cannot apply %2 colors", "error toast, %1 is matugen, %2 is GTK or Qt").arg("matugen").arg("GTK"));
            }
            return;
        }

        const isLight = (typeof SessionData !== "undefined" && SessionData.isLightMode) ? "true" : "false";
        Proc.runCommand("gtkApplier", ["bash", shellDir + "/scripts/gtk.sh", configDir, "apply", isLight], (output, exitCode) => {
            if (exitCode === 0) {
                if (typeof ToastService !== "undefined" && !root.matugenToastSuppressed) {
                    ToastService.showInfo(I18n.tr("GTK colors applied successfully"));
                }
            } else {
                if (typeof ToastService !== "undefined") {
                    ToastService.showError(I18n.tr("Failed to apply %1 colors", "error toast, %1 is GTK or Qt").arg("GTK"));
                }
            }
        });
    }

    function applyQtColors() {
        if (!matugenAvailable) {
            if (typeof ToastService !== "undefined") {
                ToastService.showError(I18n.tr("%1 not available or disabled - cannot apply %2 colors", "error toast, %1 is matugen, %2 is GTK or Qt").arg("matugen").arg("Qt"));
            }
            return;
        }

        const isQtengineActive = SettingsData.qtengineActive;
        let pendingAppliers = isQtengineActive ? 2 : 1;
        let anyApplierSucceeded = false;
        let qtengineFailed = false;

        const finishApplyQtColors = succeeded => {
            anyApplierSucceeded = anyApplierSucceeded || succeeded;
            pendingAppliers -= 1;
            if (pendingAppliers !== 0)
                return;
            if (typeof ToastService === "undefined")
                return;
            if (anyApplierSucceeded && !qtengineFailed) {
                ToastService.showInfo(I18n.tr("Qt colors applied successfully"));
            } else {
                ToastService.showError(I18n.tr("Failed to apply %1 colors").arg("Qt"));
            }
        };

        Proc.runCommand("qtApplier", ["bash", shellDir + "/scripts/qt.sh", configDir], (output, exitCode) => {
            finishApplyQtColors(exitCode === 0);
        });

        if (isQtengineActive) {
            Proc.runCommand("qtengineApplier", [Proc.dmsBin, "matugen", "qtengine", "--config-dir", configDir], (output, exitCode) => {
                qtengineFailed = exitCode !== 0;
                finishApplyQtColors(exitCode === 0);
            });
        }
    }

    function withAlpha(c, a) {
        return DCommon.Style.withAlpha(c, a);
    }

    function blendAlpha(c, a) {
        return DCommon.Style.blendAlpha(c, a);
    }

    function hoverTint(base) {
        const factor = 1.2;
        return isLightMode ? Qt.darker(base, factor) : Qt.lighter(base, factor);
    }

    function blend(c1, c2, r) {
        return Qt.rgba(c1.r * (1 - r) + c2.r * r, c1.g * (1 - r) + c2.g * r, c1.b * (1 - r) + c2.b * r, c1.a * (1 - r) + c2.a * r);
    }

    function luminance(c) {
        if (!c || c.r === undefined)
            return 0;
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
    }

    function isLightColor(c, threshold = 0.5) {
        return luminance(c) > threshold;
    }

    function getFillMode(modeName) {
        switch (modeName) {
        case "Stretch":
            return Image.Stretch;
        case "Fit":
        case "PreserveAspectFit":
            return Image.PreserveAspectFit;
        case "Fill":
        case "PreserveAspectCrop":
            return Image.PreserveAspectCrop;
        case "Tile":
            return Image.Tile;
        case "TileVertically":
            return Image.TileVertically;
        case "TileHorizontally":
            return Image.TileHorizontally;
        case "Pad":
            return Image.Pad;
        default:
            return Image.PreserveAspectCrop;
        }
    }

    // Returns numeric fillMode value for shader use (matches shader calculateUV logic)
    function getShaderFillMode(modeName) {
        switch (modeName) {
        case "Stretch":
            return 0;
        case "Fit":
        case "PreserveAspectFit":
            return 1;
        case "Fill":
        case "PreserveAspectCrop":
            return 2;
        case "Tile":
            return 3;
        case "TileVertically":
            return 4;
        case "TileHorizontally":
            return 5;
        case "Pad":
            return 6;
        case "Scrolling":
            return 7;
        default:
            return 2;
        }
    }

    function snap(value, dpr) {
        const s = dpr || 1;
        return Math.round(value * s) / s;
    }

    // Qt rounds a centred anchor offset to whole pixels, so a box must share its content's parity
    function snapEven(value, dpr) {
        const s = dpr || 1;
        return 2 * Math.round(value * s / 2) / s;
    }

    function px(value, dpr) {
        const s = dpr || 1;
        return Math.round(value * s) / s;
    }

    // the epsilon keeps a value already on the grid from gaining a pixel through float error
    function pxCeil(value, dpr) {
        const s = dpr || 1;
        return Math.ceil(value * s - 0.001) / s;
    }

    function barWidgetThickness(innerPadding, dpr) {
        return snapEven(Math.max(20, 26 + innerPadding * 0.6), dpr);
    }

    function barThickness(innerPadding, dpr) {
        return snapEven(Math.max(barWidgetThickness(innerPadding, dpr) + innerPadding + 4, barHeight - 4 - (8 - innerPadding)), dpr);
    }

    function hairline(dpr) {
        return 1 / (dpr || 1);
    }

    Process {
        id: systemThemeGenerator
        running: false
        stdout: SplitParser {
            onRead: data => log.info("Theme worker:", data)
        }
        stderr: SplitParser {
            onRead: data => {
                log.warn("Theme worker:", data);
                _recordWorkerStderr(data);
            }
        }

        // FailedToStart only flips running, it never emits exited
        onRunningChanged: {
            if (!running)
                Qt.callLater(root._workerStartFailed);
        }

        onExited: exitCode => {
            workerRunning = false;
            const currentMode = (typeof SessionData !== "undefined" && SessionData.isLightMode) ? "light" : "dark";

            switch (exitCode) {
            case 0:
                log.info("Matugen worker completed successfully");
                root.matugenCompleted(currentMode, "success");
                break;
            case 2:
                log.debug("Matugen worker completed with code 2 (no changes needed)");
                root.matugenCompleted(currentMode, "no-changes");
                break;
            default:
                _reportWorkerFailure(I18n.tr("Theme worker failed (%1)", "error toast, %1 is a process exit code").arg(exitCode));
                root.matugenCompleted(currentMode, "error");
            }

            const appliedKey = (exitCode === 0 || exitCode === 2) ? _matugenRunKey : "";
            if (CacheData.matugenAppliedKey !== appliedKey)
                CacheData.set("matugenAppliedKey", appliedKey);

            if (!pendingThemeRequest) {
                if (SettingsData.matugenTemplateGtk)
                    patchGtk3colors();
                return;
            }

            const req = pendingThemeRequest;
            pendingThemeRequest = null;
            log.info("Processing queued theme request");
            setDesiredTheme(req.kind, req.value, req.isLight, req.iconTheme, req.matugenType, req.stockColors);
        }
    }

    FileView {
        id: customThemeFileView
        blockLoading: false
        watchChanges: currentTheme === "custom"

        function parseAndLoadTheme() {
            try {
                var themeData = JSON.parse(customThemeFileView.text());
                loadCustomTheme(themeData);
            } catch (e) {
                ToastService.showError(I18n.tr("Invalid JSON format: %1", "custom theme file error toast, %1 is the error message").arg(e.message));
            }
        }

        onLoaded: {
            parseAndLoadTheme();
        }

        onFileChanged: {
            customThemeFileView.reload();
        }

        onLoadFailed: function (error) {
            if (typeof ToastService !== "undefined") {
                ToastService.showError(I18n.tr("Failed to read theme file: %1", "error toast, %1 is the error message").arg(error));
            }
        }
    }

    FileView {
        id: dynamicColorsFileView
        path: stateDir + "/dms-colors.json"
        blockLoading: false
        watchChanges: true

        function parseAndLoadColors() {
            try {
                const colorsText = dynamicColorsFileView.text();
                if (colorsText) {
                    root.matugenColors = JSON.parse(colorsText);
                    if (typeof SettingsData !== "undefined" && SettingsData.matugenSmartMode && currentTheme === dynamic && root.matugenColors && root.matugenColors.mode && typeof SessionData !== "undefined" && !SessionData.isSwitchingMode) {
                        const resolvedLight = root.matugenColors.mode === "light";
                        if (SessionData.isLightMode !== resolvedLight) {
                            SessionData.setLightMode(resolvedLight, true);
                            SettingsData.updateCosmicThemeMode(resolvedLight);
                        }
                    }
                    if (typeof ToastService !== "undefined") {
                        ToastService.clearWallpaperError();
                    }
                }
            } catch (e) {
                log.error("Failed to parse dynamic colors:", e);
                if (typeof ToastService !== "undefined") {
                    ToastService.wallpaperErrorStatus = "error";
                    ToastService.showError(I18n.tr("Dynamic colors parse error: %1", "error toast, %1 is the error message").arg(e.message));
                }
            }
        }

        onLoaded: {
            _colorsRetryCount = 0;
            if (currentTheme === dynamic)
                colorsFileLoadFailed = false;
            parseAndLoadColors();
        }

        onFileChanged: {
            dynamicColorsFileView.reload();
        }

        onLoadFailed: function (error) {
            if (currentTheme !== dynamic)
                return;

            if (workerRunning) {
                colorsReloadRetry.restart();
                return;
            }

            if (_colorsRetryCount < 3) {
                _colorsRetryCount++;
                colorsReloadRetry.restart();
                return;
            }

            colorsFileLoadFailed = true;
            const stale = Date.now() - _lastGenerateMs > 5000;
            if (matugenAvailable && (rawWallpaperPath || materialWallpaperSeed) && stale) {
                log.debug("Dynamic colors unrecoverable, regenerating");
                generateSystemThemesFromCurrentTheme();
            }
        }

        onPathChanged: {
            colorsFileLoadFailed = false;
        }
    }

    Timer {
        id: colorsReloadRetry
        interval: 150
        repeat: false
        onTriggered: dynamicColorsFileView.reload()
    }

    readonly property bool publishTypography: typeof SettingsData !== "undefined" && SettingsData._hasLoaded
    readonly property string typographyJson: JSON.stringify({
        "fontFamily": fontFamily,
        "monoFontFamily": monoFontFamily,
        "displayFontFamily": displayFontFamily,
        "fontWeight": fontWeight,
        "fontScale": fontScale
    }, null, 2)

    onPublishTypographyChanged: typographyPublishDebounce.restart()
    onTypographyJsonChanged: typographyPublishDebounce.restart()

    FileView {
        id: typographyFileView
        path: root.publishTypography ? root.stateDir + "/dms-typography.json" : ""
        blockLoading: false
        printErrors: false
    }

    Timer {
        id: typographyPublishDebounce
        interval: 250
        repeat: false
        onTriggered: {
            if (!root.publishTypography)
                return;
            typographyFileView.setText(root.typographyJson);
        }
    }

    IpcHandler {
        target: "theme"

        function toggle(): string {
            root.toggleLightMode();
            return root.isLightMode ? "dark" : "light";
        }

        function light(): string {
            root.setLightMode(true, true, true);
            return "light";
        }

        function dark(): string {
            root.setLightMode(false, true, true);
            return "dark";
        }

        function getMode(): string {
            return root.isLightMode ? "light" : "dark";
        }
    }

    Timer {
        id: _themeGenerateDebounce
        interval: 100
        repeat: false
        onTriggered: root._executeThemeGeneration()
    }

    // These timers are for screen transitions, since sometimes QML still beats the niri call
    Timer {
        id: themeTransitionTimer
        interval: 50
        repeat: false
        property string themeName: ""
        property bool savePrefs: true
        onTriggered: root.switchTheme(themeName, savePrefs, false)
    }

    Timer {
        id: lightModeTransitionTimer
        interval: 100
        repeat: false
        property bool lightMode: false
        property bool savePrefs: true
        onTriggered: root.setLightMode(lightMode, savePrefs, false)
    }

    Timer {
        id: themeCategoryTransitionTimer
        interval: 50
        repeat: false
        property string category: ""
        property string defaultTheme: ""
        onTriggered: {
            root.currentThemeCategory = category;
            root.switchTheme(defaultTheme, true, false);
        }
    }
}
