pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import Qt.labs.folderlistmodel
import QtQuick
import "../DCommon/Common/Shape.js" as Shape
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Common.settings
import qs.Services
import "GSettings.js" as GSettings
import "LayoutResolver.js" as LayoutResolver
import "NotificationRuleExpiry.js" as RuleExpiry
import "settings/SettingsSpec.js" as Spec
import "settings/SettingsStore.js" as Store
import "../DCommon/Common/settings/SpecUtil.js" as SpecUtil
import "settings/BarWidgetDefaults.js" as WidgetDefaults
import "settings/DockConfig.js" as DockConfig

Singleton {
    id: root
    readonly property var log: Log.scoped("SettingsData")

    readonly property int settingsConfigVersion: 42

    enum Position {
        Top,
        Bottom,
        Left,
        Right,
        TopCenter,
        BottomCenter,
        LeftCenter,
        RightCenter
    }

    enum AnimationSpeed {
        None,
        Short,
        Medium,
        Long,
        Custom
    }

    enum AnimationEffect {
        Standard,     // 0 — M3: scale-in, rises from below
        Directional,  // 1 — pure large slide, no scale
        Depth,        // 2 — medium slide with deep depth scale pop
        Fluid
    }

    enum SuspendBehavior {
        Suspend,
        Hibernate,
        SuspendThenHibernate
    }

    enum WidgetColorMode {
        Default,
        Colorful
    }

    enum TextRenderType {
        Qt,
        Native,
        Curve
    }

    enum TextRenderQuality {
        Default,
        Low,
        Normal,
        High,
        VeryHigh
    }

    readonly property string _homeUrl: StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string _configUrl: StandardPaths.writableLocation(StandardPaths.ConfigLocation)
    readonly property string _configDir: Paths.strip(_configUrl)
    readonly property string pluginSettingsPath: _configDir + "/dms/plugin_settings.json"
    readonly property bool qtengineActive: Quickshell.env("QT_QPA_PLATFORMTHEME") === "qtengine" || Quickshell.env("QT_QPA_PLATFORMTHEME_QT6") === "qtengine"

    property bool _loading: false
    property bool _pluginSettingsLoading: false
    property bool _parseError: false
    property bool _pluginParseError: false
    property bool _hasLoaded: false
    property bool isReadOnly: false
    property bool unsavedUserChanges: false
    property var pluginSettings: ({})
    property var builtInPluginSettings: Spec.SPEC.builtInPluginSettings.def

    function getBuiltInPluginSetting(pluginId, key, defaultValue) {
        if (!builtInPluginSettings[pluginId])
            return defaultValue;
        return builtInPluginSettings[pluginId][key] !== undefined ? builtInPluginSettings[pluginId][key] : defaultValue;
    }

    function setBuiltInPluginSetting(pluginId, key, value) {
        const updated = JSON.parse(JSON.stringify(builtInPluginSettings));
        if (!updated[pluginId])
            updated[pluginId] = {};
        updated[pluginId][key] = value;
        builtInPluginSettings = updated;
        if (Store.SESSION_BACKED_PLUGIN_IDS.includes(pluginId)) {
            SessionData.setBuiltInPluginState(pluginId, updated[pluginId]);
            return;
        }
        saveSettings();
    }

    property bool clipboardClickToPaste: Spec.SPEC.clipboardClickToPaste.def
    property bool clipboardEnterToPaste: Spec.SPEC.clipboardEnterToPaste.def
    property bool clipboardRememberTypeFilter: Spec.SPEC.clipboardRememberTypeFilter.def
    property bool clipboardUseOverlayLayer: Spec.SPEC.clipboardUseOverlayLayer.def
    property string clipboardSize: Spec.SPEC.clipboardSize.def
    property string clipboardTypeFilter: Spec.SPEC.clipboardTypeFilter.def
    property var clipboardVisibleEntryActions: Spec.SPEC.clipboardVisibleEntryActions.def

    property var launcherPluginVisibility: Spec.SPEC.launcherPluginVisibility.def

    function getPluginAllowWithoutTrigger(pluginId) {
        if (!launcherPluginVisibility[pluginId])
            return true;
        return launcherPluginVisibility[pluginId].allowWithoutTrigger !== false;
    }

    function setPluginAllowWithoutTrigger(pluginId, allow) {
        const updated = JSON.parse(JSON.stringify(launcherPluginVisibility));
        if (!updated[pluginId])
            updated[pluginId] = {};
        updated[pluginId].allowWithoutTrigger = allow;
        launcherPluginVisibility = updated;
        saveSettings();
    }

    property var launcherKeybinds: Spec.SPEC.launcherKeybinds.def
    property var launcherPluginOrder: Spec.SPEC.launcherPluginOrder.def
    onLauncherPluginOrderChanged: saveSettings()

    function setLauncherPluginOrder(order) {
        launcherPluginOrder = order;
    }

    function getOrderedLauncherPlugins(allPlugins) {
        if (!launcherPluginOrder || launcherPluginOrder.length === 0)
            return allPlugins;
        const orderMap = {};
        for (let i = 0; i < launcherPluginOrder.length; i++)
            orderMap[launcherPluginOrder[i]] = i;
        return allPlugins.slice().sort((a, b) => {
            const aOrder = orderMap[a.id] ?? 9999;
            const bOrder = orderMap[b.id] ?? 9999;
            if (aOrder !== bOrder)
                return aOrder - bOrder;
            return a.name.localeCompare(b.name);
        });
    }

    property string currentThemeName: Spec.SPEC.currentThemeName.def
    property string currentThemeCategory: Spec.SPEC.currentThemeCategory.def
    property string customThemeFile: Spec.SPEC.customThemeFile.def
    property var registryThemeVariants: Spec.SPEC.registryThemeVariants.def
    property bool generateThemeAtStartup: Spec.SPEC.generateThemeAtStartup.def
    property string matugenScheme: Spec.SPEC.matugenScheme.def
    property bool matugenSmartMode: Spec.SPEC.matugenSmartMode.def
    property string matugenSourceMode: Spec.SPEC.matugenSourceMode.def
    property real matugenContrast: Spec.SPEC.matugenContrast.def
    property string matugenSeedColor: Spec.SPEC.matugenSeedColor.def
    property string matugenSpec: Spec.SPEC.matugenSpec.def
    property bool runUserMatugenTemplates: Spec.SPEC.runUserMatugenTemplates.def
    property string matugenTargetMonitor: Spec.SPEC.matugenTargetMonitor.def
    property real popupTransparency: Spec.SPEC.popupTransparency.def
    property bool floatingWindowSyncGlobal: Spec.SPEC.floatingWindowSyncGlobal.def
    property bool floatingWindowTitleBars: Spec.SPEC.floatingWindowTitleBars.def
    property real floatingWindowTransparency: Spec.SPEC.floatingWindowTransparency.def
    property bool floatingWindowForegroundLayers: Spec.SPEC.floatingWindowForegroundLayers.def
    property real floatingWindowForegroundTransparency: Spec.SPEC.floatingWindowForegroundTransparency.def
    property var dmsWindowsFloatingSeeded: Spec.SPEC.dmsWindowsFloatingSeeded.def
    property string hostSurfaceColor: Spec.SPEC.hostSurfaceColor.def
    property string hostSurfaceCustomColor: Spec.SPEC.hostSurfaceCustomColor.def
    property string cardSurfaceColor: Spec.SPEC.cardSurfaceColor.def
    property string cardSurfaceCustomColor: Spec.SPEC.cardSurfaceCustomColor.def
    property string chipSurfaceColor: Spec.SPEC.chipSurfaceColor.def
    property string chipSurfaceCustomColor: Spec.SPEC.chipSurfaceCustomColor.def
    property string chipSurfaceNestedColor: Spec.SPEC.chipSurfaceNestedColor.def
    property string chipSurfaceNestedCustomColor: Spec.SPEC.chipSurfaceNestedCustomColor.def
    property string widgetBackgroundColor: Spec.SPEC.widgetBackgroundColor.def
    property string widgetBackgroundCustomColor: Spec.SPEC.widgetBackgroundCustomColor.def
    property real widgetBackgroundCustomStrength: Spec.SPEC.widgetBackgroundCustomStrength.def
    property string widgetColorMode: Spec.SPEC.widgetColorMode.def
    property string controlCenterTileColorMode: Spec.SPEC.controlCenterTileColorMode.def
    property string buttonColorMode: Spec.SPEC.buttonColorMode.def
    property int containerSaturation: Spec.SPEC.containerSaturation.def
    property int radiusStrength: Spec.SPEC.radiusStrength.def
    property string radiusMode: Spec.SPEC.radiusMode.def
    property int fixedRadius: Spec.SPEC.fixedRadius.def
    readonly property real cornerRadius: Shape.radius("m", Shape.scaleForStrength(radiusStrength), radiusMode === "fixed" ? fixedRadius : -1)
    property int niriLayoutGapsOverride: Spec.SPEC.niriLayoutGapsOverride.def
    property int niriLayoutRadiusOverride: Spec.SPEC.niriLayoutRadiusOverride.def
    property int niriLayoutBorderSize: Spec.SPEC.niriLayoutBorderSize.def
    property int hyprlandLayoutGapsOverride: Spec.SPEC.hyprlandLayoutGapsOverride.def
    property int hyprlandLayoutGapsOutOverride: Spec.SPEC.hyprlandLayoutGapsOutOverride.def
    property int hyprlandLayoutRadiusOverride: Spec.SPEC.hyprlandLayoutRadiusOverride.def
    property int hyprlandLayoutBorderSize: Spec.SPEC.hyprlandLayoutBorderSize.def
    property bool hyprlandResizeOnBorder: Spec.SPEC.hyprlandResizeOnBorder.def
    property int hyprlandWindowOpacity: Spec.SPEC.hyprlandWindowOpacity.def
    property int hyprlandBorderGrabArea: Spec.SPEC.hyprlandBorderGrabArea.def
    property string hyprlandBlurVariant: Spec.SPEC.hyprlandBlurVariant.def
    property int hyprlandBlurAcrylicClarity: Spec.SPEC.hyprlandBlurAcrylicClarity.def
    property int hyprlandBlurAuroraIntensity: Spec.SPEC.hyprlandBlurAuroraIntensity.def
    property int hyprlandBlurAuroraSpeed: Spec.SPEC.hyprlandBlurAuroraSpeed.def
    property int hyprlandBlurHazeIntensity: Spec.SPEC.hyprlandBlurHazeIntensity.def
    property int hyprlandBlurHazeIridescence: Spec.SPEC.hyprlandBlurHazeIridescence.def
    property int hyprlandBlurRippleStrength: Spec.SPEC.hyprlandBlurRippleStrength.def
    property int hyprlandBlurWaterStrength: Spec.SPEC.hyprlandBlurWaterStrength.def
    property bool hyprlandGlowEnabled: Spec.SPEC.hyprlandGlowEnabled.def
    property int hyprlandGlowRange: Spec.SPEC.hyprlandGlowRange.def
    property int hyprlandGlowRenderPower: Spec.SPEC.hyprlandGlowRenderPower.def
    property bool hyprlandWobbleEnabled: Spec.SPEC.hyprlandWobbleEnabled.def
    property int hyprlandWobbleIntensity: Spec.SPEC.hyprlandWobbleIntensity.def
    property int hyprlandWobbleStiffness: Spec.SPEC.hyprlandWobbleStiffness.def
    property bool hyprlandMotionBlurEnabled: Spec.SPEC.hyprlandMotionBlurEnabled.def
    property int hyprlandMotionBlurSamples: Spec.SPEC.hyprlandMotionBlurSamples.def
    property bool hyprlandGroupbarBlur: Spec.SPEC.hyprlandGroupbarBlur.def
    property int hyprlandGroupbarTextPadding: Spec.SPEC.hyprlandGroupbarTextPadding.def
    property bool hyprlandGroupbarMiddleClickClose: Spec.SPEC.hyprlandGroupbarMiddleClickClose.def
    property bool hyprlandGroupbarDisableWhenOnly: Spec.SPEC.hyprlandGroupbarDisableWhenOnly.def
    property string hyprlandTilingLayout: Spec.SPEC.hyprlandTilingLayout.def
    property bool hyprlandDwindlePreserveSplit: Spec.SPEC.hyprlandDwindlePreserveSplit.def
    property bool hyprlandDwindleSmartSplit: Spec.SPEC.hyprlandDwindleSmartSplit.def
    property int hyprlandDwindleForceSplit: Spec.SPEC.hyprlandDwindleForceSplit.def
    property string hyprlandMasterOrientation: Spec.SPEC.hyprlandMasterOrientation.def
    property string hyprlandMasterNewStatus: Spec.SPEC.hyprlandMasterNewStatus.def
    property bool hyprlandMasterNewOnTop: Spec.SPEC.hyprlandMasterNewOnTop.def
    property int hyprlandMasterSize: Spec.SPEC.hyprlandMasterSize.def
    property string hyprlandScrollingDirection: Spec.SPEC.hyprlandScrollingDirection.def
    property int hyprlandScrollingColumnWidth: Spec.SPEC.hyprlandScrollingColumnWidth.def
    property bool hyprlandScrollingFullscreenOneColumn: Spec.SPEC.hyprlandScrollingFullscreenOneColumn.def
    property bool hyprlandScrollingFollowFocus: Spec.SPEC.hyprlandScrollingFollowFocus.def
    property int mangoLayoutGapsOverride: Spec.SPEC.mangoLayoutGapsOverride.def
    property int mangoLayoutGapsOutOverride: Spec.SPEC.mangoLayoutGapsOutOverride.def
    property int mangoLayoutRadiusOverride: Spec.SPEC.mangoLayoutRadiusOverride.def
    property int mangoLayoutBorderSize: Spec.SPEC.mangoLayoutBorderSize.def
    property int focusFollowsMouse: Spec.SPEC.focusFollowsMouse.def
    property string mouseAccelProfile: Spec.SPEC.mouseAccelProfile.def
    property real mouseAccelSpeed: Spec.SPEC.mouseAccelSpeed.def
    property bool mouseLeftHanded: Spec.SPEC.mouseLeftHanded.def
    property bool mouseMiddleEmulation: Spec.SPEC.mouseMiddleEmulation.def
    property bool mouseNaturalScroll: Spec.SPEC.mouseNaturalScroll.def
    property real mouseScrollFactor: Spec.SPEC.mouseScrollFactor.def
    property string mouseScrollMethod: Spec.SPEC.mouseScrollMethod.def
    property string touchpadAccelProfile: Spec.SPEC.touchpadAccelProfile.def
    property real touchpadAccelSpeed: Spec.SPEC.touchpadAccelSpeed.def
    property string touchpadClickMethod: Spec.SPEC.touchpadClickMethod.def
    property bool touchpadDisableOnExternalMouse: Spec.SPEC.touchpadDisableOnExternalMouse.def
    property bool touchpadDisableWhileTyping: Spec.SPEC.touchpadDisableWhileTyping.def
    property bool touchpadDragLock: Spec.SPEC.touchpadDragLock.def
    property bool touchpadMiddleEmulation: Spec.SPEC.touchpadMiddleEmulation.def
    property bool touchpadNaturalScroll: Spec.SPEC.touchpadNaturalScroll.def
    property real touchpadScrollFactor: Spec.SPEC.touchpadScrollFactor.def
    property string touchpadScrollMethod: Spec.SPEC.touchpadScrollMethod.def
    property bool touchpadTapAndDrag: Spec.SPEC.touchpadTapAndDrag.def
    property bool touchpadTapToClick: Spec.SPEC.touchpadTapToClick.def

    property string keyboardLayouts: Spec.SPEC.keyboardLayouts.def
    property string keyboardVariants: Spec.SPEC.keyboardVariants.def
    property string keyboardModel: Spec.SPEC.keyboardModel.def
    property string keyboardOptions: Spec.SPEC.keyboardOptions.def
    property string keyboardKeymapFile: Spec.SPEC.keyboardKeymapFile.def
    property string keyboardTrackLayout: Spec.SPEC.keyboardTrackLayout.def
    property int keyboardRepeatDelay: Spec.SPEC.keyboardRepeatDelay.def
    property int keyboardRepeatRate: Spec.SPEC.keyboardRepeatRate.def
    property bool keyboardNumlock: Spec.SPEC.keyboardNumlock.def

    property int firstDayOfWeek: Spec.SPEC.firstDayOfWeek.def
    property bool showWeekNumber: Spec.SPEC.showWeekNumber.def
    property string calendarBackend: Spec.SPEC.calendarBackend.def
    property string defaultTaskCalendarId: Spec.SPEC.defaultTaskCalendarId.def
    property bool audioShowStreamDevices: Spec.SPEC.audioShowStreamDevices.def
    property bool audioMono: Spec.SPEC.audioMono.def
    property string clockFormat: Spec.SPEC.clockFormat.def
    readonly property bool localeUses24Hour: {
        const fmt = Qt.locale().timeFormat(Locale.ShortFormat).replace(/'[^']*'/g, "");
        return !/[aA]/.test(fmt);
    }
    readonly property bool use24HourClock: clockFormat === "24h" ? true : (clockFormat === "12h" ? false : localeUses24Hour)
    property bool showSeconds: Spec.SPEC.showSeconds.def
    property bool padHours12Hour: Spec.SPEC.padHours12Hour.def
    property bool useFahrenheit: Spec.SPEC.useFahrenheit.def
    property string windSpeedUnit: Spec.SPEC.windSpeedUnit.def
    property int animationDuration: Spec.SPEC.animationDuration.def
    property bool syncComponentAnimationSpeeds: Spec.SPEC.syncComponentAnimationSpeeds.def
    onSyncComponentAnimationSpeedsChanged: saveSettings()
    property int popoutAnimationDuration: Spec.SPEC.popoutAnimationDuration.def
    property int modalAnimationDuration: Spec.SPEC.modalAnimationDuration.def
    property bool reduceMotion: Spec.SPEC.reduceMotion.def
    onReduceMotionChanged: saveSettings()
    property int springBounce: Spec.SPEC.springBounce.def
    onSpringBounceChanged: saveSettings()
    property bool enableRippleEffects: Spec.SPEC.enableRippleEffects.def
    onEnableRippleEffectsChanged: saveSettings()
    property bool scrollbarsEnabled: Spec.SPEC.scrollbarsEnabled.def
    onScrollbarsEnabledChanged: saveSettings()
    property int motionEffect: SettingsData.AnimationEffect.Standard
    onMotionEffectChanged: saveSettings()
    property bool m3ElevationEnabled: Spec.SPEC.m3ElevationEnabled.def
    onM3ElevationEnabledChanged: saveSettings()
    property int m3ElevationIntensity: Spec.SPEC.m3ElevationIntensity.def
    onM3ElevationIntensityChanged: saveSettings()
    property int m3ElevationOpacity: Spec.SPEC.m3ElevationOpacity.def
    onM3ElevationOpacityChanged: saveSettings()
    property string m3ElevationColorMode: Spec.SPEC.m3ElevationColorMode.def
    onM3ElevationColorModeChanged: saveSettings()
    property string m3ElevationLightDirection: Spec.SPEC.m3ElevationLightDirection.def
    onM3ElevationLightDirectionChanged: saveSettings()
    property string m3ElevationCustomColor: Spec.SPEC.m3ElevationCustomColor.def
    onM3ElevationCustomColorChanged: saveSettings()
    property bool modalElevationEnabled: Spec.SPEC.modalElevationEnabled.def
    onModalElevationEnabledChanged: saveSettings()
    property bool popoutElevationEnabled: Spec.SPEC.popoutElevationEnabled.def
    onPopoutElevationEnabledChanged: saveSettings()
    property bool barElevationEnabled: Spec.SPEC.barElevationEnabled.def
    onBarElevationEnabledChanged: saveSettings()

    property bool blurEnabled: Spec.SPEC.blurEnabled.def
    onBlurEnabledChanged: saveSettings()
    property int blurStrength: Spec.SPEC.blurStrength.def
    property bool blurBorderSeeded: Spec.SPEC.blurBorderSeeded.def
    onBlurBorderSeededChanged: saveSettings()
    property bool blurForegroundLayers: Spec.SPEC.blurForegroundLayers.def
    onBlurForegroundLayersChanged: saveSettings()
    property real foregroundLayerTransparency: Spec.SPEC.foregroundLayerTransparency.def
    property real blurLayerOutlineOpacity: Spec.SPEC.blurLayerOutlineOpacity.def
    onBlurLayerOutlineOpacityChanged: saveSettings()
    property bool blurBorderEnabled: Spec.SPEC.blurBorderEnabled.def
    onBlurBorderEnabledChanged: saveSettings()
    property string blurBorderColor: Spec.SPEC.blurBorderColor.def
    onBlurBorderColorChanged: saveSettings()
    property string blurBorderCustomColor: Spec.SPEC.blurBorderCustomColor.def
    onBlurBorderCustomColorChanged: saveSettings()
    property real blurBorderOpacity: Spec.SPEC.blurBorderOpacity.def
    onBlurBorderOpacityChanged: saveSettings()
    property bool focusRingEnabled: Spec.SPEC.focusRingEnabled.def
    property real focusRingWidth: Spec.SPEC.focusRingWidth.def
    property string focusRingColor: Spec.SPEC.focusRingColor.def
    property string wallpaperFillMode: Spec.SPEC.wallpaperFillMode.def
    property bool blurredWallpaperLayer: Spec.SPEC.blurredWallpaperLayer.def
    property bool blurWallpaperOnOverview: Spec.SPEC.blurWallpaperOnOverview.def
    property string wallpaperBackgroundColorMode: Spec.SPEC.wallpaperBackgroundColorMode.def
    property string wallpaperBackgroundCustomColor: Spec.SPEC.wallpaperBackgroundCustomColor.def
    readonly property color effectiveWallpaperBackgroundColor: wallpaperBackgroundColorFor(wallpaperBackgroundColorMode)

    property bool nightModeExcludeFullscreen: Spec.SPEC.nightModeExcludeFullscreen.def
    property var nightModeExcludedApps: Spec.SPEC.nightModeExcludedApps.def

    function wallpaperBackgroundColorFor(mode) {
        switch (mode) {
        case "white":
            return "#ffffff";
        case "primary":
            return Theme.primary;
        case "surface":
            return Theme.surfaceContainer;
        case "custom":
            return wallpaperBackgroundCustomColor;
        default:
            return "#000000";
        }
    }

    property bool frameEnabled: Spec.SPEC.frameEnabled.def
    onFrameEnabledChanged: {
        saveSettings();
        if (!_loading)
            updateFrameCompositorLayout();
    }
    property real frameThickness: Spec.SPEC.frameThickness.def
    onFrameThicknessChanged: saveSettings()
    property int barInsetPaddingShared: Spec.SPEC.barInsetPaddingShared.def
    onBarInsetPaddingSharedChanged: saveSettings()
    property bool barInsetPaddingSyncAll: Spec.SPEC.barInsetPaddingSyncAll.def
    onBarInsetPaddingSyncAllChanged: saveSettings()
    property int frameBarInsetPadding: Spec.SPEC.frameBarInsetPadding.def
    onFrameBarInsetPaddingChanged: saveSettings()
    property real frameRounding: Spec.SPEC.frameRounding.def
    onFrameRoundingChanged: saveSettings()
    property var frameScreenPreferences: Spec.SPEC.frameScreenPreferences.def
    onFrameScreenPreferencesChanged: {
        saveSettings();
        if (!_loading)
            Qt.callLater(_reconcileConnectedFrameBarStyles);
    }
    property real frameBarSize: Spec.SPEC.frameBarSize.def
    onFrameBarSizeChanged: saveSettings()
    property bool frameShowOnOverview: Spec.SPEC.frameShowOnOverview.def
    onFrameShowOnOverviewChanged: saveSettings()
    property bool frameBlurEnabled: Spec.SPEC.frameBlurEnabled.def
    onFrameBlurEnabledChanged: saveSettings()
    property bool frameCloseGaps: Spec.SPEC.frameCloseGaps.def
    onFrameCloseGapsChanged: saveSettings()
    property string frameLauncherEmergeSide: Spec.SPEC.frameLauncherEmergeSide.def
    onFrameLauncherEmergeSideChanged: saveSettings()
    property bool frameLauncherArcExtender: Spec.SPEC.frameLauncherArcExtender.def
    onFrameLauncherArcExtenderChanged: saveSettings()
    property bool frameLauncherEdgeHover: Spec.SPEC.frameLauncherEdgeHover.def
    onFrameLauncherEdgeHoverChanged: saveSettings()
    readonly property string frameModalEmergeSide: frameLauncherEmergeSide === "top" ? "bottom" : "top"
    property string frameMode: Spec.SPEC.frameMode.def
    onFrameModeChanged: {
        saveSettings();
        if (!_loading && frameEnabled)
            updateFrameCompositorLayout();
    }
    property var connectedFrameBarStyleBackups: Spec.SPEC.connectedFrameBarStyleBackups.def
    onConnectedFrameBarStyleBackupsChanged: saveSettings()
    readonly property bool connectedFrameModeActive: frameEnabled && frameMode === "connected"
    onConnectedFrameModeActiveChanged: {
        if (_loading)
            return;
        _reconcileConnectedFrameBarStyles();
    }

    readonly property var frameBarConfig: barConfigs.find(bc => bc.enabled !== false && !isIslandBarConfig(bc)) ?? null
    readonly property real frameSurfaceOpacity: barTransparency(frameBarConfig)
    readonly property color frameSurfaceBase: barSurfaceColor(frameBarConfig)

    property string systemTrayIconTintMode: Spec.SPEC.systemTrayIconTintMode.def
    property int systemTrayIconTintSaturation: Spec.SPEC.systemTrayIconTintSaturation.def
    property int systemTrayIconTintStrength: Spec.SPEC.systemTrayIconTintStrength.def

    property int controlCenterColumns: Spec.SPEC.controlCenterColumns.def
    property real controlCenterIconScale: Spec.SPEC.controlCenterIconScale.def
    property var controlCenterWidgets: Spec.SPEC.controlCenterWidgets.def

    property var workspaceNameIcons: Spec.SPEC.workspaceNameIcons.def
    property bool scrollTitleEnabled: Spec.SPEC.scrollTitleEnabled.def
    property bool audioVisualizerEnabled: Spec.SPEC.audioVisualizerEnabled.def
    property int audioWheelScrollAmount: Spec.SPEC.audioWheelScrollAmount.def
    property bool bluetoothMprisEnabled: Spec.SPEC.bluetoothMprisEnabled.def
    property var mediaExcludePlayers: Spec.SPEC.mediaExcludePlayers.def
    property var mediaLyricsProviders: Spec.SPEC.mediaLyricsProviders.def
    property var appIdSubstitutions: Spec.SPEC.appIdSubstitutions.def
    property string centeringMode: Spec.SPEC.centeringMode.def
    property string clockDateFormat: Spec.SPEC.clockDateFormat.def
    property string lockDateFormat: Spec.SPEC.lockDateFormat.def
    property bool greeterRememberLastSession: Spec.SPEC.greeterRememberLastSession.def
    property bool greeterRememberLastUser: Spec.SPEC.greeterRememberLastUser.def
    property bool greeterAutoLogin: Spec.SPEC.greeterAutoLogin.def
    property bool greeterEnableFprint: Spec.SPEC.greeterEnableFprint.def
    property bool greeterEnableU2f: Spec.SPEC.greeterEnableU2f.def

    property string browserPickerViewMode: Spec.SPEC.browserPickerViewMode.def
    property string appPickerViewMode: Spec.SPEC.appPickerViewMode.def
    property bool sortAppsAlphabetically: Spec.SPEC.sortAppsAlphabetically.def
    property int appLauncherGridColumns: Spec.SPEC.appLauncherGridColumns.def
    property bool closeNiriOverviewOnWindowFocus: Spec.SPEC.closeNiriOverviewOnWindowFocus.def
    property bool rememberLastQuery: Spec.SPEC.rememberLastQuery.def
    property bool launcherHistoryEnabled: Spec.SPEC.launcherHistoryEnabled.def
    property string launcherEnterAction: Spec.SPEC.launcherEnterAction.def
    property bool rememberLastMode: Spec.SPEC.rememberLastMode.def
    property var spotlightSectionViewModes: Spec.SPEC.spotlightSectionViewModes.def
    onSpotlightSectionViewModesChanged: saveSettings()
    property var appDrawerSectionViewModes: Spec.SPEC.appDrawerSectionViewModes.def
    onAppDrawerSectionViewModesChanged: saveSettings()
    property bool niriOverviewOverlayEnabled: Spec.SPEC.niriOverviewOverlayEnabled.def
    property string niriOverviewLauncherStyle: Spec.SPEC.niriOverviewLauncherStyle.def
    property string dankLauncherV2Size: Spec.SPEC.dankLauncherV2Size.def
    property bool dankLauncherV2ShowSourceBadges: Spec.SPEC.dankLauncherV2ShowSourceBadges.def
    property bool dankLauncherV2BorderEnabled: Spec.SPEC.dankLauncherV2BorderEnabled.def
    property int dankLauncherV2BorderThickness: Spec.SPEC.dankLauncherV2BorderThickness.def
    property string dankLauncherV2BorderColor: Spec.SPEC.dankLauncherV2BorderColor.def
    property bool dankLauncherV2ShowFooter: Spec.SPEC.dankLauncherV2ShowFooter.def
    property bool dankLauncherV2UnloadOnClose: Spec.SPEC.dankLauncherV2UnloadOnClose.def
    property bool dankLauncherV2IncludeFilesInAll: Spec.SPEC.dankLauncherV2IncludeFilesInAll.def
    property bool dankLauncherV2IncludeFoldersInAll: Spec.SPEC.dankLauncherV2IncludeFoldersInAll.def
    property bool launcherUseOverlayLayer: Spec.SPEC.launcherUseOverlayLayer.def
    property string launcherStyle: Spec.SPEC.launcherStyle.def
    property string avatarRing: Spec.SPEC.avatarRing.def
    property bool spotlightBarShowModeChips: Spec.SPEC.spotlightBarShowModeChips.def
    property bool keybindsFloatingWindow: Spec.SPEC.keybindsFloatingWindow.def
    onKeybindsFloatingWindowChanged: saveSettings()

    property string _legacyWeatherLocation: "New York, NY"
    property string _legacyWeatherCoordinates: "40.7128,-74.0060"
    property string _legacyVpnLastConnected: ""
    readonly property string weatherLocation: SessionData.weatherLocation
    readonly property string weatherCoordinates: SessionData.weatherCoordinates
    property bool useAutoLocation: Spec.SPEC.useAutoLocation.def
    property bool weatherEnabled: Spec.SPEC.weatherEnabled.def

    readonly property var _dashTabsDefault: [
        {
            "id": "overview",
            "enabled": true
        },
        {
            "id": "media",
            "enabled": true
        },
        {
            "id": "wallpaper",
            "enabled": true
        },
        {
            "id": "weather",
            "enabled": true
        },
        {
            "id": "wellbeing",
            "enabled": true
        },
        {
            "id": "notifications",
            "enabled": false
        }
    ]
    property string dashTabPosition: Spec.SPEC.dashTabPosition.def
    property bool dashTabsEvenlySpaced: Spec.SPEC.dashTabsEvenlySpaced.def
    property var dashTabs: Spec.SPEC.dashTabs.def
    onDashTabsChanged: saveSettings()

    readonly property var _dashCardsDefault: [
        {
            "id": "clock",
            "w": 2,
            "h": 1
        },
        {
            "id": "weather",
            "w": 1,
            "h": 1
        },
        {
            "id": "notifications",
            "w": 3,
            "h": 5
        },
        {
            "id": "calendar",
            "w": 3,
            "h": 3
        },
        {
            "id": "media",
            "w": 3,
            "h": 1
        }
    ]
    property var dashCards: Spec.SPEC.dashCards.def
    onDashCardsChanged: saveSettings()
    property var dashOptions: Spec.SPEC.dashOptions.def
    onDashOptionsChanged: saveSettings()
    property bool wellbeingEnabled: Spec.SPEC.wellbeingEnabled.def
    property int wellbeingDailyLimit: Spec.SPEC.wellbeingDailyLimit.def
    property var wellbeingAppLimits: Spec.SPEC.wellbeingAppLimits.def

    function getDashTabs() {
        const stored = Array.isArray(dashTabs) ? dashTabs : [];
        const result = [];
        const seen = {};
        for (var i = 0; i < stored.length; i++) {
            const id = stored[i] && stored[i].id;
            if (typeof id !== "string" || id === "" || seen[id])
                continue;
            seen[id] = true;
            result.push({
                "id": id,
                "enabled": stored[i].enabled !== false
            });
        }
        for (var j = 0; j < _dashTabsDefault.length; j++) {
            if (seen[_dashTabsDefault[j].id])
                continue;
            result.push({
                "id": _dashTabsDefault[j].id,
                "enabled": _dashTabsDefault[j].enabled
            });
        }
        return result;
    }

    function setDashTabOrder(ids) {
        const current = getDashTabs();
        const ordered = [];
        for (var i = 0; i < ids.length; i++) {
            const existing = current.find(t => t.id === ids[i]);
            if (existing)
                ordered.push(existing);
        }
        for (var j = 0; j < current.length; j++) {
            if (ids.indexOf(current[j].id) < 0)
                ordered.push(current[j]);
        }
        dashTabs = ordered;
    }

    function setDashTabEnabled(id, on) {
        const current = getDashTabs();
        if (!current.some(t => t.id === id))
            current.push({
                "id": id,
                "enabled": true
            });
        dashTabs = current.map(t => t.id === id ? {
                "id": t.id,
                "enabled": on
            } : t);
    }

    function resetDashTabs() {
        dashTabs = _dashTabsDefault.map(t => ({
                    "id": t.id,
                    "enabled": t.enabled
                }));
    }

    function resetDashCards() {
        dashCards = _dashCardsDefault.map(c => ({
                    "id": c.id,
                    "w": c.w,
                    "h": c.h
                }));
        const options = Object.assign({}, dashOptions);
        delete options.overview;
        dashOptions = options;
    }

    property string networkPreference: Spec.SPEC.networkPreference.def

    property string iconThemeDark: Spec.SPEC.iconThemeDark.def
    property string iconThemeLight: Spec.SPEC.iconThemeLight.def
    property bool iconThemePerMode: Spec.SPEC.iconThemePerMode.def
    readonly property string iconTheme: resolveIconTheme()
    property var availableIconThemes: Spec.SPEC.availableIconThemes.def
    property string systemDefaultIconTheme: Spec.SPEC.systemDefaultIconTheme.def

    property var cursorSettings: Spec.SPEC.cursorSettings.def
    property var availableCursorThemes: Spec.SPEC.availableCursorThemes.def
    property string systemDefaultCursorTheme: Spec.SPEC.systemDefaultCursorTheme.def

    property string fontFamily: Spec.SPEC.fontFamily.def
    property string monoFontFamily: Spec.SPEC.monoFontFamily.def
    property string displayFontFamily: Spec.SPEC.displayFontFamily.def
    property int fontWeight: Font.Normal
    property real fontScale: Spec.SPEC.fontScale.def
    property int textRenderType: SettingsData.TextRenderType.Qt
    property int textRenderQuality: SettingsData.TextRenderQuality.Default

    property bool notepadUseMonospace: Spec.SPEC.notepadUseMonospace.def
    property string notepadFontFamily: Spec.SPEC.notepadFontFamily.def
    property real notepadFontSize: Spec.SPEC.notepadFontSize.def
    property real notificationSummaryFontSize: Spec.SPEC.notificationSummaryFontSize.def
    property real notificationBodyFontSize: Spec.SPEC.notificationBodyFontSize.def
    property bool notepadShowLineNumbers: Spec.SPEC.notepadShowLineNumbers.def
    property bool notepadAutoSave: Spec.SPEC.notepadAutoSave.def
    property string notepadSlideoutSide: Spec.SPEC.notepadSlideoutSide.def
    property string notepadDefaultMode: Spec.SPEC.notepadDefaultMode.def
    property real notepadTransparencyOverride: Spec.SPEC.notepadTransparencyOverride.def
    property real notepadLastCustomTransparency: Spec.SPEC.notepadLastCustomTransparency.def
    property bool notepadUseCompositorGap: Spec.SPEC.notepadUseCompositorGap.def
    property int notepadEdgeGap: Spec.SPEC.notepadEdgeGap.def

    property string activeCompositor: ""

    // Compositor layout gap when enabled and available, else the manual value.
    readonly property int notepadEffectiveEdgeGap: {
        if (notepadUseCompositorGap) {
            var g = -1;
            switch (activeCompositor) {
            case "niri":
                g = niriLayoutGapsOverride;
                break;
            case "hyprland":
                g = hyprlandLayoutGapsOverride;
                break;
            case "mango":
                g = mangoLayoutGapsOverride;
                break;
            }
            if (g >= 0)
                return g;
        }
        return Math.max(0, notepadEdgeGap);
    }

    onNotepadUseMonospaceChanged: saveSettings()
    onNotepadFontFamilyChanged: saveSettings()
    onNotepadFontSizeChanged: saveSettings()
    onNotepadShowLineNumbersChanged: saveSettings()
    onNotepadAutoSaveChanged: saveSettings()
    onNotepadSlideoutSideChanged: saveSettings()
    onNotepadDefaultModeChanged: saveSettings()
    onNotepadUseCompositorGapChanged: saveSettings()
    onNotepadEdgeGapChanged: saveSettings()
    // onCenteringModeChanged: saveSettings()
    onNotepadTransparencyOverrideChanged: {
        if (notepadTransparencyOverride > 0) {
            notepadLastCustomTransparency = notepadTransparencyOverride;
        }
        saveSettings();
    }
    onNotepadLastCustomTransparencyChanged: saveSettings()

    property bool soundsEnabled: Spec.SPEC.soundsEnabled.def
    property bool useSystemSoundTheme: Spec.SPEC.useSystemSoundTheme.def
    property bool soundNewNotification: Spec.SPEC.soundNewNotification.def
    property bool soundVolumeChanged: Spec.SPEC.soundVolumeChanged.def
    property bool soundPluggedIn: Spec.SPEC.soundPluggedIn.def
    property bool soundLogin: Spec.SPEC.soundLogin.def
    property bool muteSoundsWhenMediaPlaying: Spec.SPEC.muteSoundsWhenMediaPlaying.def

    property int acMonitorTimeout: Spec.SPEC.acMonitorTimeout.def
    property int acLockTimeout: Spec.SPEC.acLockTimeout.def
    property int acSuspendTimeout: Spec.SPEC.acSuspendTimeout.def
    property int acSuspendBehavior: SettingsData.SuspendBehavior.Suspend
    property string acProfileName: Spec.SPEC.acProfileName.def
    property int acPostLockMonitorTimeout: Spec.SPEC.acPostLockMonitorTimeout.def
    property int batteryMonitorTimeout: Spec.SPEC.batteryMonitorTimeout.def
    property int batteryLockTimeout: Spec.SPEC.batteryLockTimeout.def
    property int batterySuspendTimeout: Spec.SPEC.batterySuspendTimeout.def
    property int batterySuspendBehavior: SettingsData.SuspendBehavior.Suspend
    property string batteryProfileName: Spec.SPEC.batteryProfileName.def
    property int batteryPostLockMonitorTimeout: Spec.SPEC.batteryPostLockMonitorTimeout.def
    property int batteryChargeLimit: Spec.SPEC.batteryChargeLimit.def
    property bool batteryNotifyChargeLimit: Spec.SPEC.batteryNotifyChargeLimit.def
    property int batteryCriticalThreshold: Spec.SPEC.batteryCriticalThreshold.def
    property bool batteryCriticalAnimation: Spec.SPEC.batteryCriticalAnimation.def
    property bool batteryNotifyCritical: Spec.SPEC.batteryNotifyCritical.def
    property int batteryLowThreshold: Spec.SPEC.batteryLowThreshold.def
    property bool batteryNotifyLow: Spec.SPEC.batteryNotifyLow.def
    property int batteryChargeLimitNotificationType: Spec.SPEC.batteryChargeLimitNotificationType.def
    property int batteryLowNotificationType: Spec.SPEC.batteryLowNotificationType.def
    property int batteryCriticalNotificationType: Spec.SPEC.batteryCriticalNotificationType.def
    property bool batteryAutoPowerSaver: Spec.SPEC.batteryAutoPowerSaver.def
    property bool lowerDisplayRefreshRateOnBattery: Spec.SPEC.lowerDisplayRefreshRateOnBattery.def
    property bool lockBeforeSuspend: Spec.SPEC.lockBeforeSuspend.def
    property bool keepAwakeBlocksSleep: Spec.SPEC.keepAwakeBlocksSleep.def
    property bool loginctlLockIntegration: Spec.SPEC.loginctlLockIntegration.def
    property bool fadeToLockEnabled: Spec.SPEC.fadeToLockEnabled.def
    property int fadeToLockGracePeriod: Spec.SPEC.fadeToLockGracePeriod.def
    property bool fadeToDpmsEnabled: Spec.SPEC.fadeToDpmsEnabled.def
    property int fadeToDpmsGracePeriod: Spec.SPEC.fadeToDpmsGracePeriod.def
    property string launchPrefix: Spec.SPEC.launchPrefix.def

    property bool syncModeWithPortal: Spec.SPEC.syncModeWithPortal.def
    property bool terminalsAlwaysDark: Spec.SPEC.terminalsAlwaysDark.def
    property int terminalOpacity: Spec.SPEC.terminalOpacity.def
    property string terminalPalette: Spec.SPEC.terminalPalette.def

    property string muxType: Spec.SPEC.muxType.def
    property bool muxUseCustomCommand: Spec.SPEC.muxUseCustomCommand.def
    property string muxCustomCommand: Spec.SPEC.muxCustomCommand.def
    property string muxSessionFilter: Spec.SPEC.muxSessionFilter.def

    property bool runDmsMatugenTemplates: Spec.SPEC.runDmsMatugenTemplates.def
    property bool matugenTemplateGtk: Spec.SPEC.matugenTemplateGtk.def
    property bool matugenTemplateNiri: Spec.SPEC.matugenTemplateNiri.def
    property bool matugenTemplateHyprland: Spec.SPEC.matugenTemplateHyprland.def
    property bool matugenTemplateMangowc: Spec.SPEC.matugenTemplateMangowc.def
    property bool matugenTemplateQt5ct: Spec.SPEC.matugenTemplateQt5ct.def
    property bool matugenTemplateQt6ct: Spec.SPEC.matugenTemplateQt6ct.def
    property bool matugenTemplateFcitx5: Spec.SPEC.matugenTemplateFcitx5.def
    property bool matugenTemplateQtengine: Spec.SPEC.matugenTemplateQtengine.def
    property bool matugenTemplateFirefox: Spec.SPEC.matugenTemplateFirefox.def
    property bool matugenTemplatePywalfox: Spec.SPEC.matugenTemplatePywalfox.def
    property bool matugenTemplateZenBrowser: Spec.SPEC.matugenTemplateZenBrowser.def
    property bool matugenTemplateVesktop: Spec.SPEC.matugenTemplateVesktop.def
    property bool matugenTemplateVencord: Spec.SPEC.matugenTemplateVencord.def
    property bool matugenTemplateEquibop: Spec.SPEC.matugenTemplateEquibop.def
    property bool matugenTemplateGhostty: Spec.SPEC.matugenTemplateGhostty.def
    property bool matugenTemplateKitty: Spec.SPEC.matugenTemplateKitty.def
    property bool matugenTemplateFoot: Spec.SPEC.matugenTemplateFoot.def
    property bool matugenTemplateNeovim: Spec.SPEC.matugenTemplateNeovim.def
    property bool matugenTemplateAlacritty: Spec.SPEC.matugenTemplateAlacritty.def
    property bool matugenTemplateWezterm: Spec.SPEC.matugenTemplateWezterm.def
    property bool matugenTemplateDgop: Spec.SPEC.matugenTemplateDgop.def
    property bool matugenTemplateKcolorscheme: Spec.SPEC.matugenTemplateKcolorscheme.def
    property bool matugenTemplateVscode: Spec.SPEC.matugenTemplateVscode.def
    property bool matugenTemplateEmacs: Spec.SPEC.matugenTemplateEmacs.def
    property bool matugenTemplateZed: Spec.SPEC.matugenTemplateZed.def

    property var matugenTemplateNeovimSettings: Spec.SPEC.matugenTemplateNeovimSettings.def
    property bool matugenTemplateNeovimSetBackground: Spec.SPEC.matugenTemplateNeovimSetBackground.def

    property bool notificationOverlayEnabled: Spec.SPEC.notificationOverlayEnabled.def
    property bool notificationPopupShadowEnabled: Spec.SPEC.notificationPopupShadowEnabled.def
    property bool notificationPopupPrivacyMode: Spec.SPEC.notificationPopupPrivacyMode.def
    property bool notificationPopupBodyInvokesAction: Spec.SPEC.notificationPopupBodyInvokesAction.def
    property bool notificationForegroundLayers: Spec.SPEC.notificationForegroundLayers.def
    property int overviewRows: Spec.SPEC.overviewRows.def
    property int overviewColumns: Spec.SPEC.overviewColumns.def
    property real overviewScale: Spec.SPEC.overviewScale.def

    property bool modalDarkenBackground: Spec.SPEC.modalDarkenBackground.def

    property bool lockScreenShowPowerActions: Spec.SPEC.lockScreenShowPowerActions.def
    property bool lockScreenShowProfileImage: Spec.SPEC.lockScreenShowProfileImage.def
    property bool lockScreenShowWeather: Spec.SPEC.lockScreenShowWeather.def
    property bool lockScreenPowerOffMonitorsOnLock: Spec.SPEC.lockScreenPowerOffMonitorsOnLock.def
    property bool lockAtStartup: Spec.SPEC.lockAtStartup.def

    property bool enableFprint: Spec.SPEC.enableFprint.def
    onEnableFprintChanged: {
        if (enableFprint)
            refreshAuthAvailability();
    }
    property int maxFprintTries: Spec.SPEC.maxFprintTries.def
    readonly property bool fprintdAvailable: Processes.fprintdAvailable
    readonly property bool lockFingerprintCanEnable: Processes.lockFingerprintCanEnable
    readonly property bool lockFingerprintReady: Processes.lockFingerprintReady
    readonly property string lockFingerprintReason: Processes.lockFingerprintReason
    readonly property bool greeterFingerprintCanEnable: Processes.greeterFingerprintCanEnable
    readonly property bool greeterFingerprintReady: Processes.greeterFingerprintReady
    readonly property string greeterFingerprintReason: Processes.greeterFingerprintReason
    readonly property string greeterFingerprintSource: Processes.greeterFingerprintSource
    property bool enableU2f: Spec.SPEC.enableU2f.def
    onEnableU2fChanged: {
        if (enableU2f)
            refreshAuthAvailability();
    }
    property string u2fMode: Spec.SPEC.u2fMode.def
    readonly property bool u2fAvailable: Processes.u2fAvailable
    readonly property bool lockU2fCanEnable: Processes.lockU2fCanEnable
    readonly property bool lockU2fReady: Processes.lockU2fReady
    readonly property string lockU2fReason: Processes.lockU2fReason
    readonly property bool greeterU2fCanEnable: Processes.greeterU2fCanEnable
    readonly property bool greeterU2fReady: Processes.greeterU2fReady
    readonly property string greeterU2fReason: Processes.greeterU2fReason
    readonly property string greeterU2fSource: Processes.greeterU2fSource
    property string lockPamPath: Spec.SPEC.lockPamPath.def
    property bool lockPamInlineFprint: Spec.SPEC.lockPamInlineFprint.def
    property bool lockPamInlineU2f: Spec.SPEC.lockPamInlineU2f.def
    property bool lockPamExternallyManaged: Spec.SPEC.lockPamExternallyManaged.def
    property string lockU2fPamPath: Spec.SPEC.lockU2fPamPath.def
    property string lockScreenSecurityKeyShortcut: Spec.SPEC.lockScreenSecurityKeyShortcut.def
    property bool lockScreenSecurityKeyShortcutEnabled: Spec.SPEC.lockScreenSecurityKeyShortcutEnabled.def
    property bool greeterPamExternallyManaged: Spec.SPEC.greeterPamExternallyManaged.def
    property string lockScreenInactiveColor: Spec.SPEC.lockScreenInactiveColor.def
    property bool lockScreenVideoEnabled: Spec.SPEC.lockScreenVideoEnabled.def
    property string lockScreenVideoPath: Spec.SPEC.lockScreenVideoPath.def
    property bool lockScreenVideoCycling: Spec.SPEC.lockScreenVideoCycling.def
    property string lockScreenWallpaperPath: Spec.SPEC.lockScreenWallpaperPath.def
    property string lockScreenWallpaperFillMode: Spec.SPEC.lockScreenWallpaperFillMode.def
    property string lockScreenFontFamily: Spec.SPEC.lockScreenFontFamily.def

    property int notificationTimeoutLow: Spec.SPEC.notificationTimeoutLow.def
    property int notificationTimeoutNormal: Spec.SPEC.notificationTimeoutNormal.def
    property int notificationTimeoutCritical: Spec.SPEC.notificationTimeoutCritical.def
    property bool notificationIgnoreAppTimeout: Spec.SPEC.notificationIgnoreAppTimeout.def
    property bool notificationCompactMode: Spec.SPEC.notificationCompactMode.def
    property bool notificationShowTimeoutBar: Spec.SPEC.notificationShowTimeoutBar.def
    property bool notificationDedupeEnabled: Spec.SPEC.notificationDedupeEnabled.def
    property int notificationPopupPosition: SettingsData.Position.Top
    property int notificationAnimationDuration: Spec.SPEC.notificationAnimationDuration.def
    property bool notificationHistoryEnabled: Spec.SPEC.notificationHistoryEnabled.def
    property int notificationHistoryMaxCount: Spec.SPEC.notificationHistoryMaxCount.def
    property int notificationHistoryMaxAgeDays: Spec.SPEC.notificationHistoryMaxAgeDays.def
    property bool notificationHistorySaveLow: Spec.SPEC.notificationHistorySaveLow.def
    property bool notificationHistorySaveNormal: Spec.SPEC.notificationHistorySaveNormal.def
    property bool notificationHistorySaveCritical: Spec.SPEC.notificationHistorySaveCritical.def
    property var notificationRules: Spec.SPEC.notificationRules.def
    property bool notificationDndAllowCritical: Spec.SPEC.notificationDndAllowCritical.def
    property bool notificationDndWhileScreenSharing: Spec.SPEC.notificationDndWhileScreenSharing.def
    property bool notificationFocusedMonitor: Spec.SPEC.notificationFocusedMonitor.def
    readonly property var islandBarConfigs: {
        barConfigs;
        return (barConfigs || []).filter(cfg => isIslandBarConfig(cfg));
    }
    readonly property bool dankIslandEnabled: (barConfigs || []).some(cfg => (cfg.enabled ?? false) && hostsIsland(cfg))
    readonly property var enabledIslandBarConfigs: (barConfigs || []).filter(cfg => cfg?.island === true && (cfg.enabled ?? false))
    // Session-only: which bar, island or dot last-used shared shortcuts follow on each screen.
    property var lastUsedBarByScreen: ({})
    // One slot per edge; a dot floats, so it never takes one.
    readonly property int edgeBarConfigCount: (barConfigs || []).filter(cfg => cfg && !isDotBarConfig(cfg)).length
    readonly property var dotBarConfig: (barConfigs || []).find(cfg => isDotBarConfig(cfg)) ?? null
    readonly property var islandDefaults: WidgetDefaults.ISLAND_DEFAULTS
    readonly property var islandWidgetDefaults: WidgetDefaults.DEFAULTS.island

    function islandSettings(bc) {
        if (!bc)
            return {};
        return isIslandBarConfig(bc) ? bc : (islandWidgetEntry(bc) ?? {});
    }

    function islandDefaultsFor(bc) {
        return isIslandBarConfig(bc) ? islandDefaults : islandWidgetDefaults;
    }

    function _isIslandEntry(entry) {
        return (typeof entry === "string" ? entry : entry?.id) === "island";
    }

    // A widget toggled off in the list is still placed, but it owns no screen.
    function _islandWidgetLocation(cfg, enabledOnly) {
        for (const sectionId of ["left", "center", "right"]) {
            const list = cfg?.[sectionId + "Widgets"] ?? [];
            const index = list.findIndex(entry => _isIslandEntry(entry));
            if (index < 0)
                continue;
            if (enabledOnly && list[index]?.enabled === false)
                return null;
            return {
                sectionId,
                index
            };
        }
        return null;
    }

    function islandWidgetSection(cfg) {
        return _islandWidgetLocation(cfg, true)?.sectionId ?? "";
    }

    // Mutates cfg in place, so callers pass a clone; a bare string entry is upgraded to carry settings.
    function _writableIslandSettings(cfg) {
        if (isIslandBarConfig(cfg))
            return cfg;
        const location = _islandWidgetLocation(cfg);
        if (!location)
            return {};
        const list = cfg[location.sectionId + "Widgets"];
        if (typeof list[location.index] === "string")
            list[location.index] = {
                "id": "island",
                "enabled": true
            };
        return list[location.index];
    }

    function setIslandSettings(barId, patch) {
        const config = getBarConfig(barId);
        if (!config)
            return;
        if ("islandRouteDash" in patch) {
            patch = Object.assign({}, patch);
            const settings = islandSettings(config);
            for (const activity of islandDashActivities) {
                const key = islandRouteKey(activity);
                if (patch[key] === undefined && (settings[key] === undefined || settings[key] === null))
                    patch[key] = islandSetting(config, key);
            }
        }
        if (isIslandBarConfig(config)) {
            updateBarConfig(barId, patch);
            return;
        }
        const location = _islandWidgetLocation(config);
        if (!location)
            return;
        updateBarWidget(barId, location.sectionId, location.index, patch);
    }

    function islandSetting(bc, key) {
        const value = islandSettings(bc)[key];
        if (value !== undefined && value !== null)
            return value;
        switch (key) {
        case "islandRouteMedia":
        case "islandRouteWeather":
        case "islandRouteWallpaper":
            return islandSetting(bc, "islandRouteDash");
        }
        return islandDefaultsFor(bc)[key];
    }

    function islandSatelliteTransparency(bc) {
        if (islandSetting(bc, "islandSatelliteFollowInterfaceStyle"))
            return barTransparency(bc);
        return islandSetting(bc, "islandSatelliteTransparency");
    }

    function islandLevelDisplay(bc, key) {
        const value = islandSetting(bc, key);
        return value === "icon" || value === "percentage" || value === "both" ? value : "both";
    }

    function islandClockDisplay(bc) {
        const value = islandSetting(bc, "islandHomeClockDisplay");
        return value === "time" || value === "date" || value === "both" ? value : "both";
    }

    function islandHomeStatusContent(bc) {
        const value = islandSetting(bc, "islandHomeStatusContent");
        return value === "battery" || value === "connectivity" ? value : "battery";
    }

    function islandEdge(bc) {
        return positionToSide(bc?.position ?? SettingsData.Position.Top) || "top";
    }

    function islandVertical(bc) {
        const edge = islandEdge(bc);
        return edge === "left" || edge === "right";
    }

    function islandStripThickness(bc) {
        return LayoutResolver.islandThickness(islandSettings(bc), islandDefaultsFor(bc));
    }
    function islandReserveThickness(bc) {
        return LayoutResolver.islandReserve(islandSettings(bc), islandDefaultsFor(bc));
    }
    readonly property var _islandHomeGroupIds: ["workspaces", "media", "clock", "weather", "status", "volume", "brightness", "notifications", "privacy", "tray"]
    readonly property var _islandHomeLayoutDefault: [
        {
            "id": "workspaces",
            "enabled": false
        },
        {
            "id": "media",
            "enabled": true
        },
        {
            "id": "clock",
            "enabled": true
        },
        {
            "id": "weather",
            "enabled": false
        },
        {
            "id": "status",
            "enabled": false
        },
        {
            "id": "volume",
            "enabled": false
        },
        {
            "id": "brightness",
            "enabled": false
        },
        {
            "id": "notifications",
            "enabled": true
        },
        {
            "id": "privacy",
            "enabled": true
        },
        {
            "id": "tray",
            "enabled": false
        }
    ]
    function getIslandHomeLayout(bc) {
        const layout = islandSettings(bc).islandHomeLayout;
        const stored = Array.isArray(layout) ? layout : [];
        const result = [];
        const seen = {};
        for (const entry of stored) {
            const id = entry && entry.id;
            if (_islandHomeGroupIds.indexOf(id) < 0 || seen[id])
                continue;
            seen[id] = true;
            result.push({
                "id": id,
                "enabled": id === "clock" || entry.enabled !== false
            });
        }
        for (const fallback of _islandHomeLayoutDefault) {
            if (!seen[fallback.id])
                result.push({
                    "id": fallback.id,
                    "enabled": fallback.enabled
                });
        }
        return result;
    }

    function islandHomeGroupEnabled(bc, id) {
        const entry = getIslandHomeLayout(bc).find(g => g.id === id);
        return entry ? entry.enabled : false;
    }

    function setIslandHomeLayoutOrder(barId, ids) {
        const current = getIslandHomeLayout(getBarConfig(barId));
        const ordered = ids.map(id => current.find(g => g.id === id)).filter(g => g);
        for (const entry of current) {
            if (ids.indexOf(entry.id) < 0)
                ordered.push(entry);
        }
        setIslandSettings(barId, {
            islandHomeLayout: ordered
        });
    }

    function setIslandHomeGroupEnabled(barId, id, on) {
        if (id === "clock")
            return;
        setIslandSettings(barId, {
            islandHomeLayout: getIslandHomeLayout(getBarConfig(barId)).map(g => g.id === id ? {
                    "id": g.id,
                    "enabled": on
                } : g)
        });
    }

    property bool osdAlwaysShowValue: Spec.SPEC.osdAlwaysShowValue.def
    property int osdPosition: SettingsData.Position.BottomCenter
    property var osdPositionOverrides: Spec.SPEC.osdPositionOverrides.def
    property bool osdVolumeEnabled: Spec.SPEC.osdVolumeEnabled.def
    property bool osdMediaVolumeEnabled: Spec.SPEC.osdMediaVolumeEnabled.def
    property bool osdMediaPlaybackEnabled: Spec.SPEC.osdMediaPlaybackEnabled.def
    property bool osdBrightnessEnabled: Spec.SPEC.osdBrightnessEnabled.def
    property bool osdIdleInhibitorEnabled: Spec.SPEC.osdIdleInhibitorEnabled.def
    property bool osdMicMuteEnabled: Spec.SPEC.osdMicMuteEnabled.def
    property bool osdMicVolumeEnabled: Spec.SPEC.osdMicVolumeEnabled.def
    property bool osdCapsLockEnabled: Spec.SPEC.osdCapsLockEnabled.def
    property bool osdTouchpadEnabled: Spec.SPEC.osdTouchpadEnabled.def
    property bool osdPowerProfileEnabled: Spec.SPEC.osdPowerProfileEnabled.def
    property bool osdAudioOutputEnabled: Spec.SPEC.osdAudioOutputEnabled.def
    property bool osdWorkspaceEnabled: Spec.SPEC.osdWorkspaceEnabled.def

    property bool powerActionConfirm: Spec.SPEC.powerActionConfirm.def
    property real powerActionHoldDuration: Spec.SPEC.powerActionHoldDuration.def
    property var powerMenuActions: Spec.SPEC.powerMenuActions.def
    property string powerMenuDefaultAction: Spec.SPEC.powerMenuDefaultAction.def
    property bool powerMenuGridLayout: Spec.SPEC.powerMenuGridLayout.def
    property string customPowerActionLock: Spec.SPEC.customPowerActionLock.def
    property string customPowerActionLogout: Spec.SPEC.customPowerActionLogout.def
    property string customPowerActionSuspend: Spec.SPEC.customPowerActionSuspend.def
    property string customPowerActionHibernate: Spec.SPEC.customPowerActionHibernate.def
    property string customPowerActionReboot: Spec.SPEC.customPowerActionReboot.def
    property string customPowerActionPowerOff: Spec.SPEC.customPowerActionPowerOff.def
    property var customPowerButtons: Spec.SPEC.customPowerButtons.def
    property var powerMenuBootEntries: Spec.SPEC.powerMenuBootEntries.def
    property bool powerMenuFirmwareSetup: Spec.SPEC.powerMenuFirmwareSetup.def

    property bool updaterCheckOnStart: Spec.SPEC.updaterCheckOnStart.def
    property bool updaterUseCustomCommand: Spec.SPEC.updaterUseCustomCommand.def
    property string updaterCustomCommand: Spec.SPEC.updaterCustomCommand.def
    property string updaterTerminalAdditionalParams: Spec.SPEC.updaterTerminalAdditionalParams.def
    property int updaterIntervalSeconds: Spec.SPEC.updaterIntervalSeconds.def
    property bool updaterNotify: Spec.SPEC.updaterNotify.def
    property bool updaterPauseOnBattery: Spec.SPEC.updaterPauseOnBattery.def
    property int updaterNotifyMinSeconds: Spec.SPEC.updaterNotifyMinSeconds.def
    property bool updaterIncludeFlatpak: Spec.SPEC.updaterIncludeFlatpak.def
    property bool updaterAllowAUR: Spec.SPEC.updaterAllowAUR.def
    property bool updaterReopenAfterUpgrade: Spec.SPEC.updaterReopenAfterUpgrade.def
    property bool updaterUpgradeInWindow: Spec.SPEC.updaterUpgradeInWindow.def
    property var updaterIgnoredPackages: Spec.SPEC.updaterIgnoredPackages.def

    property string displayNameMode: Spec.SPEC.displayNameMode.def
    onDisplayNameModeChanged: {
        if (!_loading)
            _reconcileConnectedFrameBarStyles();
    }
    property var screenPreferences: Spec.SPEC.screenPreferences.def
    property var showOnLastDisplay: Spec.SPEC.showOnLastDisplay.def
    property var displayProfiles: Spec.SPEC.displayProfiles.def
    property var displayPreviousRefreshModes: Spec.SPEC.displayPreviousRefreshModes.def
    property bool displayProfileAutoSelect: Spec.SPEC.displayProfileAutoSelect.def
    property bool displayShowDisconnected: Spec.SPEC.displayShowDisconnected.def
    property bool displaySnapToEdge: Spec.SPEC.displaySnapToEdge.def
    property var barIpcRevealStates: ({})

    property var dockConfigs: Spec.SPEC.dockConfigs.def
    property var barConfigs: Spec.SPEC.barConfigs.def

    property var desktopWidgetInstances: Spec.SPEC.desktopWidgetInstances.def
    property var desktopWidgetGroups: Spec.SPEC.desktopWidgetGroups.def
    property string desktopContextMenu: Spec.SPEC.desktopContextMenu.def
    property var lockScreenWidgetInstances: Spec.SPEC.lockScreenWidgetInstances.def
    property var greeterWidgetInstances: Spec.SPEC.greeterWidgetInstances.def
    property bool greeterFollowLockScreen: Spec.SPEC.greeterFollowLockScreen.def
    readonly property var widgetInstanceListKeys: ["desktopWidgetInstances", "lockScreenWidgetInstances", "greeterWidgetInstances"]

    // Released greeters still read these three shared keys, so they follow the lock widgets.
    onLockScreenWidgetInstancesChanged: {
        const status = widgetInstanceOfType("lockScreenWidgetInstances", "lockStatus");
        const auth = widgetInstanceOfType("lockScreenWidgetInstances", "lockAuth");
        const power = widgetInstanceOfType("lockScreenWidgetInstances", "lockPower");
        const mirror = (key, value) => {
            if (root[key] !== value)
                set(key, value);
        };
        mirror("lockScreenShowWeather", !!status && status.enabled !== false && (status.config?.showWeather ?? true));
        mirror("lockScreenShowProfileImage", !!auth && (auth.config?.showProfileImage ?? true));
        mirror("lockScreenShowPowerActions", !!power && power.enabled !== false);
        syncGreeterWidgets();
    }

    function widgetInstanceOfType(listKey, widgetType) {
        return (root[listKey] || []).find(inst => inst.widgetType === widgetType) ?? null;
    }

    function lockWidgetInstance(widgetType) {
        return widgetInstanceOfType("lockScreenWidgetInstances", widgetType);
    }

    function syncGreeterWidgets() {
        if (!greeterFollowLockScreen)
            return;
        const next = Spec.greeterWidgetsFromLock(lockScreenWidgetInstances, greeterWidgetInstances);
        if (JSON.stringify(next) === JSON.stringify(greeterWidgetInstances))
            return;
        set("greeterWidgetInstances", next);
    }

    function setGreeterFollowLockScreen(follow) {
        if (follow === greeterFollowLockScreen)
            return;
        if (follow) {
            for (const inst of greeterWidgetInstances || []) {
                if (inst.id.startsWith("gw_"))
                    SessionData.removeDesktopWidgetInstancePositions(inst.id);
            }
            set("greeterFollowLockScreen", true);
            syncGreeterWidgets();
            return;
        }
        const detached = (greeterWidgetInstances || []).map(inst => {
            if (inst.widgetType === "greeterSession")
                return inst;
            const copy = JSON.parse(JSON.stringify(inst));
            copy.id = "gw_" + inst.id;
            SessionData.copyDesktopWidgetInstancePositions(inst.id, copy.id);
            if (inst.widgetType !== "desktopClock" || inst.config?.autoPosition === false)
                return copy;
            copy.config.autoPosition = false;
            SessionData.pinPublishedLockPosition(inst.id, copy.id, inst.config?.syncPositionAcrossScreens ?? false);
            return copy;
        });
        set("greeterWidgetInstances", detached);
        set("greeterFollowLockScreen", false);
    }

    function resetLockScreenWidgets() {
        for (const inst of lockScreenWidgetInstances || [])
            SessionData.removeDesktopWidgetInstancePositions(inst.id);
        for (const inst of Spec.SPEC.lockScreenWidgetInstances.def)
            SessionData.removeDesktopWidgetInstancePositions(inst.id);
        resetToDefault(["lockScreenWidgetInstances"]);
    }

    // Following means the lock layout is the greeter layout, so that is what resets.
    function resetGreeterWidgets() {
        for (const inst of greeterWidgetInstances || []) {
            if (!greeterFollowLockScreen || inst.widgetType === "greeterSession")
                SessionData.removeDesktopWidgetInstancePositions(inst.id);
        }
        if (greeterFollowLockScreen) {
            resetLockScreenWidgets();
            set("greeterWidgetInstances", Spec.greeterWidgetsFromLock(lockScreenWidgetInstances, []));
            return;
        }
        set("greeterWidgetInstances", Spec.greeterWidgetDefaults().map(inst => inst.widgetType === "greeterSession" ? inst : Object.assign(inst, {
                id: "gw_" + inst.id
            })));
    }

    function getDefaultSystemMonitorConfig() {
        return {
            showHeader: true,
            transparency: 0.8,
            colorMode: "primary",
            customColor: "#ffffff",
            showCpu: true,
            showCpuGraph: true,
            showCpuTemp: true,
            showGpuTemp: false,
            gpuPciId: "",
            showMemory: true,
            showMemoryGraph: true,
            showNetwork: true,
            showNetworkGraph: true,
            showDisk: true,
            showTopProcesses: false,
            topProcessCount: 3,
            topProcessSortBy: "cpu",
            layoutMode: "auto",
            graphInterval: 60,
            x: -1,
            y: -1,
            width: 320,
            height: 480,
            displayPreferences: ["all"]
        };
    }

    function widgetInstanceListKey(instanceId) {
        return widgetInstanceListKeys.find(key => (root[key] || []).some(inst => inst.id === instanceId)) ?? "desktopWidgetInstances";
    }

    readonly property var widgetInstanceIdPrefixes: ({
            desktopWidgetInstances: "dw_",
            lockScreenWidgetInstances: "lw_",
            greeterWidgetInstances: "gw_"
        })

    function createDesktopWidgetInstance(widgetType, name, config, listKey = "desktopWidgetInstances") {
        const lockScreen = listKey !== "desktopWidgetInstances";
        const instance = {
            id: widgetInstanceIdPrefixes[listKey] + Date.now() + "_" + Math.random().toString(36).substr(2, 9),
            widgetType: widgetType,
            name: name || widgetType,
            enabled: true,
            config: Object.assign(lockScreen ? {
                syncPositionAcrossScreens: true
            } : {}, config || {})
        };
        const instances = JSON.parse(JSON.stringify(root[listKey] || []));
        instances.push(instance);
        root[listKey] = instances;
        saveSettings();
        return instance;
    }

    function updateDesktopWidgetInstance(instanceId, updates) {
        const listKey = widgetInstanceListKey(instanceId);
        const instances = JSON.parse(JSON.stringify(root[listKey] || []));
        const idx = instances.findIndex(inst => inst.id === instanceId);
        if (idx === -1)
            return;
        Object.assign(instances[idx], updates);
        root[listKey] = instances;
        saveSettings();
    }

    function updateDesktopWidgetInstanceConfig(instanceId, configUpdates) {
        const listKey = widgetInstanceListKey(instanceId);
        const instances = JSON.parse(JSON.stringify(root[listKey] || []));
        const idx = instances.findIndex(inst => inst.id === instanceId);
        if (idx === -1)
            return;
        instances[idx].config = Object.assign({}, instances[idx].config || {}, configUpdates);
        root[listKey] = instances;
        saveSettings();
    }

    function removeDesktopWidgetInstance(instanceId) {
        const listKey = widgetInstanceListKey(instanceId);
        root[listKey] = (root[listKey] || []).filter(inst => inst.id !== instanceId);
        SessionData.removeDesktopWidgetInstancePositions(instanceId);
        saveSettings();
    }

    function duplicateDesktopWidgetInstance(instanceId) {
        const source = getDesktopWidgetInstance(instanceId);
        if (!source)
            return null;
        const instance = createDesktopWidgetInstance(source.widgetType, source.name + " (Copy)", JSON.parse(JSON.stringify(source.config || {})), widgetInstanceListKey(instanceId));
        if (!source.enabled)
            updateDesktopWidgetInstance(instance.id, {
                enabled: false
            });
        return instance;
    }

    function getDesktopWidgetInstance(instanceId) {
        for (const key of widgetInstanceListKeys) {
            const found = (root[key] || []).find(inst => inst.id === instanceId);
            if (found)
                return found;
        }
        return null;
    }

    function moveDesktopWidgetInstanceToGroup(instanceId, groupId, newIndexInGroup) {
        const instances = JSON.parse(JSON.stringify(desktopWidgetInstances || []));
        const groups = desktopWidgetGroups || [];
        const idx = instances.findIndex(inst => inst.id === instanceId);
        if (idx === -1)
            return false;
        const [item] = instances.splice(idx, 1);
        item.group = groupId || null;
        const groupMatches = inst => {
            if (!groupId)
                return !inst.group || !groups.some(g => g.id === inst.group);
            return inst.group === groupId;
        };
        const groupInstances = instances.filter(groupMatches);
        const clamped = Math.max(0, Math.min(newIndexInGroup, groupInstances.length));
        let targetGlobalIdx;
        if (clamped >= groupInstances.length) {
            const last = groupInstances[groupInstances.length - 1];
            targetGlobalIdx = last ? instances.findIndex(inst => inst.id === last.id) + 1 : instances.length;
        } else {
            const targetInstance = groupInstances[clamped];
            targetGlobalIdx = instances.findIndex(inst => inst.id === targetInstance.id);
        }
        instances.splice(targetGlobalIdx, 0, item);
        desktopWidgetInstances = instances;
        saveSettings();
        return true;
    }

    function createDesktopWidgetGroup(name) {
        const id = "dwg_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9);
        const group = {
            id: id,
            name: name,
            collapsed: false
        };
        const groups = JSON.parse(JSON.stringify(desktopWidgetGroups || []));
        groups.push(group);
        desktopWidgetGroups = groups;
        saveSettings();
        return group;
    }

    function updateDesktopWidgetGroup(groupId, updates) {
        const groups = JSON.parse(JSON.stringify(desktopWidgetGroups || []));
        const idx = groups.findIndex(g => g.id === groupId);
        if (idx === -1)
            return;
        Object.assign(groups[idx], updates);
        desktopWidgetGroups = groups;
        saveSettings();
    }

    function removeDesktopWidgetGroup(groupId) {
        const instances = JSON.parse(JSON.stringify(desktopWidgetInstances || []));
        for (let i = 0; i < instances.length; i++) {
            if (instances[i].group === groupId)
                instances[i].group = null;
        }
        desktopWidgetInstances = instances;
        const groups = (desktopWidgetGroups || []).filter(g => g.id !== groupId);
        desktopWidgetGroups = groups;
        saveSettings();
    }

    signal forceDankBarLayoutRefresh
    signal forceDockLayoutRefresh
    signal widgetDataChanged
    signal workspaceIconsUpdated
    signal compositorLayoutRefreshNeeded(bool frame)
    signal blurStrengthRefreshNeeded
    signal compositorInputRefreshNeeded
    signal compositorCursorRefreshNeeded
    signal notificationPopupsInvalidated

    function refreshAuthAvailability() {
        Processes.detectAuthCapabilities();
    }

    function _runStartSequence() {
        Processes.settingsRoot = root;
        const unsaved = _loadSettings();
        initializeListModels();
        return unsaved;
    }

    function applyStoredTheme() {
        if (typeof Theme !== "undefined") {
            Theme.currentThemeCategory = currentThemeCategory;
            Theme.switchTheme(currentThemeName, false, false);
        } else {
            Qt.callLater(function () {
                if (typeof Theme !== "undefined") {
                    Theme.currentThemeCategory = currentThemeCategory;
                    Theme.switchTheme(currentThemeName, false, false);
                }
            });
        }
    }

    function regenSystemThemes() {
        if (typeof Theme !== "undefined") {
            Theme.generateSystemThemesFromCurrentTheme();
        }
    }

    function updateCompositorLayout() {
        compositorLayoutRefreshNeeded(false);
    }

    function updateCompositorInput() {
        compositorInputRefreshNeeded();
    }

    function updateBlurStrength() {
        blurStrengthRefreshNeeded();
    }

    function updateFrameCompositorLayout() {
        compositorLayoutRefreshNeeded(true);
        FrameTransitionState.begin();
    }

    function resolveIconTheme() {
        if (iconThemePerMode && typeof SessionData !== "undefined" && SessionData.isLightMode)
            return iconThemeLight;
        return iconThemeDark;
    }

    function applyStoredIconTheme() {
        updateGtkIconTheme();
        updateQtIconTheme();
        updateCosmicIconTheme();
    }

    function setIconThemeUnmanaged() {
        iconThemePerMode = false;
        iconThemeDark = "System Default";
        iconThemeLight = "System Default";
        SessionData.lastAppliedIconTheme = "";
        SessionData.saveSettings();
        saveSettings();
    }

    function checkIconThemeDrift() {
        if (resolveIconTheme() === "System Default")
            return;
        if (!SessionData.lastAppliedIconTheme)
            return;
        const script = GSettings.getCmd("org.gnome.desktop.interface", "icon-theme");

        Proc.runCommand("iconThemeDriftCheck", ["sh", "-c", script], (output, exitCode) => {
            const platform = (output || "").trim();
            if (!platform)
                return;
            if (platform === SessionData.lastAppliedIconTheme || platform === root.iconThemeDark || platform === root.iconThemeLight)
                return;
            root.setIconThemeUnmanaged();
            ToastService.showWarning(I18n.tr("Icon theme changed outside DMS; switched to System Default", "shown when an external tool overrides the icon theme DMS applied"));
        });
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (!root._loading)
                Qt.callLater(root._reconcileConnectedFrameBarStyles);
        }
    }

    Connections {
        target: typeof SessionData !== "undefined" ? SessionData : null
        function onIsLightModeChanged() {
            if (!SessionData.isSwitchingMode)
                return;
            if (!root.iconThemePerMode)
                return;
            if (root.iconThemeLight === root.iconThemeDark)
                return;
            root.applyStoredIconTheme();
            root.saveSettings();
        }
    }

    function cosmicIntegrationAvailable() {
        const desktop = (Quickshell.env("XDG_CURRENT_DESKTOP") || "").toUpperCase();
        return desktop.includes("COSMIC");
    }

    function updateCosmicIconTheme() {
        if (!cosmicIntegrationAvailable())
            return;
        const resolved = resolveIconTheme();
        let cosmicThemeName = (resolved === "System Default") ? systemDefaultIconTheme : resolved;
        if (!cosmicThemeName || cosmicThemeName === "System Default") {
            const detectScript = GSettings.getCmd("org.gnome.desktop.interface", "icon-theme");

            Proc.runCommand("detectCosmicIconTheme", ["sh", "-c", detectScript], (output, exitCode) => {
                if (exitCode !== 0)
                    return;
                const detected = (output || "").trim();
                if (!detected || detected === "System Default")
                    return;
                const detectedEscaped = detected.replace(/'/g, "'\\''");
                const writeScript = `mkdir -p ${_configDir}/cosmic/com.system76.CosmicTk/v1
                printf '"%s"\\n' '${detectedEscaped}' > ${_configDir}/cosmic/com.system76.CosmicTk/v1/icon_theme 2>/dev/null || true`;
                Quickshell.execDetached(["sh", "-lc", writeScript]);
            });
            return;
        }

        const cosmicThemeNameEscaped = cosmicThemeName.replace(/'/g, "'\\''");
        const script = `mkdir -p ${_configDir}/cosmic/com.system76.CosmicTk/v1
        printf '"%s"\\n' '${cosmicThemeNameEscaped}' > ${_configDir}/cosmic/com.system76.CosmicTk/v1/icon_theme 2>/dev/null || true`;
        Quickshell.execDetached(["sh", "-lc", script]);
    }

    function updateCosmicThemeMode(isLightMode) {
        if (!cosmicIntegrationAvailable())
            return;
        const isDark = isLightMode ? "false" : "true";
        const script = `mkdir -p ${_configDir}/cosmic/com.system76.CosmicTheme.Mode/v1
        printf '%s\\n' ${isDark} > ${_configDir}/cosmic/com.system76.CosmicTheme.Mode/v1/is_dark 2>/dev/null || true`;
        Quickshell.execDetached(["sh", "-lc", script]);
    }

    function updateGtkIconTheme() {
        const resolved = resolveIconTheme();
        const gtkThemeName = (resolved === "System Default") ? systemDefaultIconTheme : resolved;
        if (gtkThemeName === "System Default" || gtkThemeName === "")
            return;
        SessionData.lastAppliedIconTheme = gtkThemeName;
        SessionData.saveSettings();
        if (typeof DMSService !== "undefined" && DMSService.apiVersion >= 3 && typeof PortalService !== "undefined") {
            PortalService.setSystemIconTheme(gtkThemeName);
        }

        const configScript = `mkdir -p ${_configDir}/gtk-3.0 ${_configDir}/gtk-4.0

        for config_dir in ${_configDir}/gtk-3.0 ${_configDir}/gtk-4.0; do
        settings_file="$config_dir/settings.ini"
        [ -f "$settings_file" ] && [ ! -w "$settings_file" ] && continue
        if [ -f "$settings_file" ]; then
        if grep -q "^gtk-icon-theme-name=" "$settings_file"; then
        sed -i 's/^gtk-icon-theme-name=.*/gtk-icon-theme-name=${gtkThemeName}/' "$settings_file"
        else
        if grep -q "\\[Settings\\]" "$settings_file"; then
        sed -i '/\\[Settings\\]/a gtk-icon-theme-name=${gtkThemeName}' "$settings_file"
        else
        echo -e '\\n[Settings]\\ngtk-icon-theme-name=${gtkThemeName}' >> "$settings_file"
        fi
        fi
        else
        echo -e '[Settings]\\ngtk-icon-theme-name=${gtkThemeName}' > "$settings_file"
        fi
        done

        ${GSettings.setCmd("org.gnome.desktop.interface", "icon-theme", gtkThemeName)} || true

        pkill -HUP -f 'gtk' 2>/dev/null || true`;

        Quickshell.execDetached(["sh", "-lc", configScript]);
    }

    function updateQtIconTheme() {
        const resolved = resolveIconTheme();
        const qtThemeName = (resolved === "System Default") ? "" : resolved;
        if (!qtThemeName)
            return;
        const home = _homeUrl.replace("file://", "").replace(/'/g, "'\\''");
        const qtThemeNameEscaped = qtThemeName.replace(/'/g, "'\\''");

        const script = `mkdir -p ${_configDir}/qt5ct ${_configDir}/qt6ct ${_configDir}/environment.d 2>/dev/null || true
        update_qt_icon_theme() {
        local config_file="$1"
        local theme_name="$2"
        if [ -f "$config_file" ]; then
        if grep -q "^\\[Appearance\\]" "$config_file"; then
        if grep -q "^icon_theme=" "$config_file"; then
        sed -i "s/^icon_theme=.*/icon_theme=$theme_name/" "$config_file"
        else
        sed -i "/^\\[Appearance\\]/a icon_theme=$theme_name" "$config_file"
        fi
        else
        printf "\\n[Appearance]\\nicon_theme=%s\\n" "$theme_name" >> "$config_file"
        fi
        else
        printf "[Appearance]\\nicon_theme=%s\\n" "$theme_name" > "$config_file"
        fi
        }
        update_qt_icon_theme ${_configDir}/qt5ct/qt5ct.conf '${qtThemeNameEscaped}'
        update_qt_icon_theme ${_configDir}/qt6ct/qt6ct.conf '${qtThemeNameEscaped}'`;

        Quickshell.execDetached(["sh", "-lc", script]);

        if (!qtengineActive || !runDmsMatugenTemplates || !matugenTemplateQtengine)
            return;
        Proc.runCommand("updateQtengineIconTheme", [Proc.dmsBin, "matugen", "qtengine", "--icon-theme", qtThemeName], () => {});
    }

    function scheduleAuthApply() {
        Qt.callLater(() => {
            Processes.settingsRoot = root;
            Processes.scheduleAuthApply();
        });
    }

    function scheduleGreeterAutoLoginSync() {
        Qt.callLater(() => {
            Processes.settingsRoot = root;
            Processes.scheduleGreeterAutoLoginSync();
        });
    }

    function syncLauncherHistory(who, key) {
        if (who[key])
            return;
        AppUsageHistoryData.clear();
        SessionData.clearLauncherHistory();
    }

    function markGreeterSyncPending(who, key, oldValue) {
        if (!(key in SessionData.greeterSyncBaseline)) {
            var baseline = Object.assign({}, SessionData.greeterSyncBaseline);
            baseline[key] = oldValue;
            SessionData.greeterSyncBaseline = baseline;
        }
        SessionData.greeterSyncPending = true;
        SessionData.saveSettings();
    }

    // Older builds flagged keys the linked slot now serves live; drop them so Apply does not nag forever.
    function pruneGreeterSyncPending() {
        const baseline = SessionData.greeterSyncBaseline || {};
        const keys = Object.keys(baseline);
        const live = keys.filter(key => Spec.SPEC[key]?.onChange === "markGreeterSyncPending");
        if (live.length === keys.length)
            return;
        const pruned = {};
        for (const key of live)
            pruned[key] = baseline[key];
        SessionData.greeterSyncBaseline = pruned;
        if (live.length === 0)
            SessionData.greeterSyncPending = false;
        SessionData.saveSettings();
    }

    function clearGreeterSyncPending() {
        SessionData.greeterSyncBaseline = {};
        SessionData.greeterSyncPending = false;
        SessionData.saveSettings();
    }

    function revertGreeterSyncPending() {
        for (var key in SessionData.greeterSyncBaseline) {
            if (!(key in Spec.SPEC))
                continue;
            root[key] = SessionData.greeterSyncBaseline[key];
        }
        SessionData.greeterSyncBaseline = {};
        SessionData.greeterSyncPending = false;
        SessionData.saveSettings();
        saveSettings();
    }

    readonly property var _hooks: ({
            "applyStoredTheme": applyStoredTheme,
            "regenSystemThemes": regenSystemThemes,
            "updateCompositorLayout": updateCompositorLayout,
            "updateCompositorInput": updateCompositorInput,
            "updateBlurStrength": updateBlurStrength,
            "applyStoredIconTheme": applyStoredIconTheme,
            "updateBarConfigs": updateBarConfigs,
            "updateCompositorCursor": updateCompositorCursor,
            "scheduleAuthApply": scheduleAuthApply,
            "scheduleGreeterAutoLoginSync": scheduleGreeterAutoLoginSync,
            "markGreeterSyncPending": markGreeterSyncPending,
            "syncLauncherHistory": syncLauncherHistory
        })

    function set(key, value) {
        if (key === "cornerRadius") {
            setCornerRadius(value);
            return;
        }
        if (key === "radiusStrength")
            value = Shape.normalizeStrength(value);
        Spec.set(root, key, value, saveSettings, _hooks);
        if (key === "frameEnabled" && value)
            clearIslandBars();
    }

    function hasSetting(key) {
        return key in Spec.SPEC;
    }

    function specDefault(key) {
        return SpecUtil.cloneDef(Spec.SPEC[key]?.def);
    }

    function isDefault(keys) {
        return keys.every(key => !(key in Spec.SPEC) || SpecUtil.isDefault(root[key], Spec.SPEC[key].def));
    }

    function resetToDefault(keys) {
        for (const key of keys) {
            if (key in Spec.SPEC)
                Spec.set(root, key, null, saveSettings, _hooks);
        }
    }

    function osdPositionFor(kind) {
        const override = osdPositionOverrides?.[kind];
        return typeof override === "number" ? override : osdPosition;
    }

    function hasOsdPositionOverride(kind) {
        return typeof osdPositionOverrides?.[kind] === "number";
    }

    function setOsdPosition(kind, position) {
        if (!kind) {
            set("osdPosition", position);
            return;
        }
        if (position === osdPosition) {
            resetOsdPosition(kind);
            return;
        }
        set("osdPositionOverrides", Object.assign({}, osdPositionOverrides, {
            [kind]: position
        }));
    }

    function resetOsdPosition(kind) {
        if (!kind) {
            resetToDefault(["osdPosition"]);
            return;
        }
        if (!hasOsdPositionOverride(kind))
            return;
        const next = Object.assign({}, osdPositionOverrides);
        delete next[kind];
        set("osdPositionOverrides", next);
    }

    function barConfigDefault(field) {
        return Spec.SPEC.barConfigs.def[0][field];
    }

    function dockConfigDefaults() {
        return DockConfig.create("", "");
    }

    // Frame mode hosts bars inside the frame surface, which has nowhere to put an edge island; a dot floats over it.
    function clearIslandBars() {
        if (!islandBarConfigs.some(cfg => !isDotBarConfig(cfg)))
            return;
        const configs = JSON.parse(JSON.stringify(barConfigs));
        for (const cfg of configs)
            delete cfg.island;
        _commitBarConfigs(configs);
    }

    function _loadSettings() {
        const isInitial = !_hasLoaded || _settingsStage === SettingsData.Stage.Partial;
        let unsavedChanges;
        let obj = _getSettingsObjectFromFiles();
        let loadedSettings = JSON.stringify(obj);

        const oldVersion = obj?.configVersion ?? 0;
        if (oldVersion > settingsConfigVersion) {
            newerSettingsBackup.path = `${_configDir}/dms/settings.v${oldVersion}.json`;
            newerSettingsBackup.setText(JSON.stringify(obj, null, 2));
        }
        const legacyPins = oldVersion < 13 ? Store.extractPins(obj) : null;
        const sessionPayload = oldVersion < 15 ? Store.extractSessionPayload(obj) : null;
        const cachePayload = oldVersion < 15 ? Store.extractCachePayload(obj) : null;
        let migrationRan = false;
        if (oldVersion < settingsConfigVersion) {
            const migrated = Store.migrateToVersion(obj, settingsConfigVersion);
            if (migrated) {
                obj = migrated;
                migrationRan = true;
            }
        }
        if (legacyPins) {
            Qt.callLater(() => CacheData.migratePins(legacyPins));
        }
        if (cachePayload) {
            Qt.callLater(() => CacheData.migrateUsageHistories(cachePayload));
        }
        if (sessionPayload) {
            Qt.callLater(() => {
                SessionData.importFromSettings(sessionPayload);
                _mergeSessionState();
            });
        }
        if (obj?.lockScreenActiveMonitor !== undefined) {
            var oldVal = obj.lockScreenActiveMonitor;
            if (oldVal && oldVal !== "all") {
                if (!obj.screenPreferences) {
                    obj.screenPreferences = {};
                }
                if (obj.screenPreferences.lockScreen === undefined) {
                    obj.screenPreferences.lockScreen = [oldVal];
                }
            }
            delete obj.lockScreenActiveMonitor;
        }
        if (obj?.use24HourClock !== undefined && obj?.clockFormat === undefined) {
            obj.clockFormat = obj.use24HourClock ? "24h" : "12h";
            delete obj.use24HourClock;
        }

        const prevFrameEnabled = frameEnabled;
        const prevFrameMode = frameMode;
        unsavedChanges = loadedSettings !== JSON.stringify(obj);
        Store.parse(root, obj);

        // set() enforces this pair, but a hand-edited settings bypass set() entirely.
        if (frameEnabled)
            clearIslandBars();

        if (obj?.directionalAnimationMode === 3 && frameMode !== "connected")
            frameMode = "connected";

        if (obj?.iconTheme !== undefined && obj?.iconThemeDark === undefined)
            iconThemeDark = obj.iconTheme;

        if (obj?.weatherLocation !== undefined)
            _legacyWeatherLocation = obj.weatherLocation;
        if (obj?.weatherCoordinates !== undefined)
            _legacyWeatherCoordinates = obj.weatherCoordinates;
        if (obj?.vpnLastConnected !== undefined && obj.vpnLastConnected !== "") {
            _legacyVpnLastConnected = obj.vpnLastConnected;
            SessionData.vpnLastConnected = _legacyVpnLastConnected;
            SessionData.saveSettings();
        }

        _hasLoaded = true;
        if (!_parseError) {
            _settingsStage = SettingsData.Stage.Ready;
        }

        if (isInitial) {
            _mergeSessionState();
            Qt.callLater(checkIconThemeDrift);
        }
        applyStoredTheme();
        updateCompositorCursor();
        if (!isInitial) {
            // External edits reload under _loading, which skips the per-property transition triggers
            const frameChanged = (frameEnabled !== prevFrameEnabled || (frameEnabled && frameMode !== prevFrameMode));
            if (!_parseError && frameChanged) {
                updateFrameCompositorLayout();
            }
        }

        if (isInitial && _settingsStage === SettingsData.Stage.Ready) {
            loadPluginSettings();
            Qt.callLater(() => _reconcileConnectedFrameBarStyles());
        }
        return unsavedChanges;
    }

    function _mergeSessionState() {
        if (!_hasLoaded || !SessionData._hasLoaded)
            return;
        pruneGreeterSyncPending();

        const pluginState = SessionData.builtInPluginState || {};
        if (Object.keys(pluginState).length > 0) {
            const updated = JSON.parse(JSON.stringify(builtInPluginSettings));
            for (const id in pluginState) {
                updated[id] = pluginState[id];
            }
            builtInPluginSettings = updated;
        }
    }

    Connections {
        target: SessionData

        function onLoaded() {
            root._mergeSessionState();
        }
    }

    function _getCurrentSettings() {
        const setKeys = new Set();
        for (const path of _settingsFilesPaths) {
            const file = _settingsFiles.get(path);
            for (const key in file.settings) {
                setKeys.add(key);
            }
        }
        return Store.toJson(root, setKeys);
    }
    function getCurrentSettingsJson() {
        return JSON.stringify(_getCurrentSettings(), null, 2);
    }

    function _resetPluginSettings() {
        _pluginParseError = false;
        pluginSettings = {};
    }

    function _pluginSettingsErrorCode(error) {
        if (typeof error === "number")
            return error;
        if (error && typeof error === "object") {
            if (typeof error.code === "number")
                return error.code;
            if (typeof error.errno === "number")
                return error.errno;
        }

        const msg = String(error || "").trim();
        if (/^\d+$/.test(msg))
            return Number(msg);

        return -1;
    }

    function _isMissingPluginSettingsError(error) {
        if (_pluginSettingsErrorCode(error) === 2)
            return true;

        const msg = String(error || "").toLowerCase();
        return msg.indexOf("file does not exist") !== -1 || msg.indexOf("no such file") !== -1 || msg.indexOf("enoent") !== -1;
    }

    function loadPluginSettings() {
        try {
            parsePluginSettings(pluginSettingsFile.text());
        } catch (e) {
            const msg = e.message || String(e);
            if (!_isMissingPluginSettingsError(e))
                log.warn("Failed to load plugin_settings.json. Error:", msg);
            _resetPluginSettings();
        }
    }

    function parsePluginSettings(content) {
        _pluginSettingsLoading = true;
        _pluginParseError = false;
        try {
            if (content && content.trim()) {
                pluginSettings = JSON.parse(content);
            } else {
                pluginSettings = {};
            }
        } catch (e) {
            _pluginParseError = true;
            const msg = e.message;
            log.error("Failed to parse plugin_settings.json - file will not be overwritten. Error:", msg);
            Qt.callLater(() => ToastService.showError(I18n.tr("Failed to parse %1").arg("plugin_settings.json"), msg));
            pluginSettings = {};
        } finally {
            _pluginSettingsLoading = false;
        }
    }

    function _splitSettingsByFile(settings) {
        const savedSettings = new Set();
        const splitSettings = {};

        for (let i = _settingsFilesPaths.length - 1; i >= 0; i--) {
            const path = _settingsFilesPaths[i];
            const file = _settingsFiles.get(path);
            const fileSettings = file.getSettings();
            for (const setting in fileSettings) {
                if (!(setting in settings)) {
                    delete fileSettings[setting];
                    continue;
                }
                if (savedSettings.has(setting)) {
                    continue;
                }
                fileSettings[setting] = settings[setting];
                savedSettings.add(setting);
            }
            splitSettings[path] = fileSettings;
        }

        for (const setting in settings) {
            if (!savedSettings.has(setting)) {
                splitSettings[defaultSettingsFile.filePath][setting] = settings[setting];
            }
        }
        return splitSettings;
    }
    function saveSettings() {
        if (_loading || !_hasLoaded)
            return;
        unsavedUserChanges = true;
        settingsSaveDebounce.restart();
    }
    function _saveSettings(userChanges) {
        let reason = null;
        if (_loading) {
            reason = "some files are being loaded";
        } else if (_parseError) {
            reason = "failed to parse settings.";
        }
        if (reason !== null) {
            log.warn("Refusing to save settings, recent changes may be lost: " + reason);
            return;
        }
        const settings = _getCurrentSettings();
        const splitSettings = _splitSettingsByFile(settings);
        for (const path in splitSettings) {
            const fileSettings = splitSettings[path];
            const file = _settingsFiles.get(path);
            file.setSettings(fileSettings, userChanges);
        }
        unsavedUserChanges = _anySettingsFile(file => file.fileUnsavedUserChanges);
    }

    function savePluginSettings() {
        if (_pluginSettingsLoading || _pluginParseError)
            return;
        pluginSettingsFile.setText(JSON.stringify(pluginSettings, null, 2));
    }

    function _connectedFrameBarStyleSnapshot(config) {
        return {
            "shadowIntensity": config?.shadowIntensity ?? 0,
            "squareCorners": config?.squareCorners ?? false,
            "attachToScreenEdge": config?.attachToScreenEdge ?? false,
            "gothCornersEnabled": config?.gothCornersEnabled ?? false,
            "borderEnabled": config?.borderEnabled ?? false
        };
    }

    function barUsesConnectedFrameStyle(config) {
        if (!config || !connectedFrameModeActive)
            return false;
        return Quickshell.screens.some(screen => barConfigCoversScreen(config, screen) && isScreenInPreferences(screen, frameScreenPreferences));
    }

    function _applyConnectedFrameBarStyles(configs) {
        if (!Array.isArray(configs))
            return {
                "configs": configs,
                "changed": false,
                "backups": null
            };

        const backups = connectedFrameBarStyleBackups || {};
        const nextBackups = {};
        let backupsChanged = false;
        let anyChanged = false;
        const zeroed = _connectedFrameBarStyleSnapshot(null);
        const out = configs.map(cfg => {
            if (!cfg?.id)
                return cfg;
            const covered = barUsesConnectedFrameStyle(cfg);
            if (covered) {
                nextBackups[cfg.id] = backups[cfg.id] ?? _connectedFrameBarStyleSnapshot(cfg);
                backupsChanged = backupsChanged || backups[cfg.id] === undefined;
            }
            const target = covered ? zeroed : backups[cfg.id];
            if (!target)
                return cfg;
            const current = _connectedFrameBarStyleSnapshot(cfg);
            if (Object.keys(target).every(key => current[key] === target[key]))
                return cfg;
            anyChanged = true;
            return Object.assign({}, cfg, target);
        });

        const backupsDirty = backupsChanged || Object.keys(nextBackups).length !== Object.keys(backups).length;
        return {
            "configs": anyChanged ? out : configs,
            "changed": anyChanged,
            "backups": backupsDirty ? nextBackups : null
        };
    }

    function effectiveBarConfigForRender(config, usesFrameBarChrome) {
        if (!config || !connectedFrameModeActive || usesFrameBarChrome)
            return config;
        const backup = connectedFrameBarStyleBackups[config.id];
        if (!backup)
            return config;
        return Object.assign({}, config, backup);
    }

    function _reconcileConnectedFrameBarStyles() {
        if (Quickshell.screens.length === 0)
            return;
        const result = _applyConnectedFrameBarStyles(barConfigs);
        if (result.changed)
            barConfigs = result.configs;
        if (result.backups)
            connectedFrameBarStyleBackups = result.backups;
        if (result.changed)
            updateBarConfigs();
    }

    function detectAvailableIconThemes() {
        const xdgDataDirs = Quickshell.env("XDG_DATA_DIRS") || "";
        const localData = Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericDataLocation));
        const homeDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.HomeLocation));

        const dataDirs = xdgDataDirs.trim() !== "" ? xdgDataDirs.split(":").concat([localData]) : ["/usr/share", "/usr/local/share", localData];

        const iconPaths = dataDirs.map(d => d + "/icons").concat([homeDir + "/.icons"]);
        const pathsArg = iconPaths.join(" ");

        const script = `
            echo "SYSDEFAULT:$(${GSettings.getCmd("org.gnome.desktop.interface", "icon-theme")})"
            for dir in ${pathsArg}; do
                [ -d "$dir" ] || continue
                for theme in "$dir"/*/; do
                    [ -d "$theme" ] || continue
                    basename "$theme"
                done
            done | grep -v '^icons$' | grep -v '^default$' | grep -v '^hicolor$' | grep -v '^locolor$' | sort -u
        `;

        Proc.runCommand("detectIconThemes", ["sh", "-c", script], (output, exitCode) => {
            const themes = ["System Default"];
            if (output && output.trim()) {
                const lines = output.trim().split('\n');
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (line.startsWith("SYSDEFAULT:")) {
                        systemDefaultIconTheme = line.substring(11).trim();
                        continue;
                    }
                    if (line)
                        themes.push(line);
                }
            }
            availableIconThemes = themes;
        });
    }

    function detectAvailableCursorThemes() {
        const xdgDataDirs = Quickshell.env("XDG_DATA_DIRS") || "";
        const localData = Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericDataLocation));
        const homeDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.HomeLocation));

        const dataDirs = xdgDataDirs.trim() !== "" ? xdgDataDirs.split(":").concat([localData]) : ["/usr/share", "/usr/local/share", localData];

        const cursorPaths = dataDirs.map(d => d + "/icons").concat([homeDir + "/.icons", homeDir + "/.local/share/icons"]);
        const pathsArg = cursorPaths.join(" ");

        const script = `
            echo "SYSDEFAULT:$(${GSettings.getCmd("org.gnome.desktop.interface", "cursor-theme")})"
            for dir in ${pathsArg}; do
                [ -d "$dir" ] || continue
                for theme in "$dir"/*/; do
                    [ -d "$theme" ] || continue
                    [ -d "$theme/cursors" ] || continue
                    basename "$theme"
                done
            done | grep -v '^icons$' | grep -v '^default$' | sort -u
        `;

        Proc.runCommand("detectCursorThemes", ["sh", "-c", script], (output, exitCode) => {
            const themes = ["System Default"];
            if (output && output.trim()) {
                const lines = output.trim().split('\n');
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (line.startsWith("SYSDEFAULT:")) {
                        systemDefaultCursorTheme = line.substring(11).trim();
                        continue;
                    }
                    if (line)
                        themes.push(line);
                }
            }
            availableCursorThemes = themes;
        });
    }

    function getEffectiveTimeFormat() {
        if (use24HourClock)
            return showSeconds ? "hh:mm:ss" : "hh:mm";
        if (padHours12Hour)
            return showSeconds ? "hh:mm:ss AP" : "hh:mm AP";
        return showSeconds ? "h:mm:ss AP" : "h:mm AP";
    }

    function getEffectiveDateFormat(fallback) {
        if (clockDateFormat && clockDateFormat.length > 0)
            return clockDateFormat;
        return fallback || "ddd d";
    }

    function initializeListModels() {
        const defaultBar = getPrimaryBarConfig();
        if (defaultBar) {
            Lists.init(leftWidgetsModel, centerWidgetsModel, rightWidgetsModel, defaultBar.leftWidgets, defaultBar.centerWidgets, defaultBar.rightWidgets);
        }
    }

    function updateListModel(listModel, order) {
        Lists.update(listModel, order);
        widgetDataChanged();
    }

    function getPopupTriggerPosition(pos, screen, barThickness, widgetWidth, barSpacing, barPosition, barConfig) {
        return ShellLayout.popupTrigger(pos, screen, barThickness, widgetWidth, barSpacing, barPosition, barConfig);
    }

    function getAdjacentBarInfo(screen, barPosition, barConfig, includeAutoHide) {
        return ShellLayout.adjacentInfo(screen, barConfig, includeAutoHide);
    }

    function getBarBounds(screen, barThickness, barPosition, barConfig) {
        return ShellLayout.barBounds(screen, barThickness, barPosition, barConfig);
    }

    function updateBarConfigs() {
        barConfigsChanged();
        saveSettings();
    }

    // Each screen edge can hold one dock, so resolution and reservation are always edge-scoped.
    function dockConfigsForScreen(screen) {
        if (typeof screen === "string")
            screen = Quickshell.screens.find(s => s.name === screen);
        if (!screen)
            return [];
        return DockConfig.resolveAll(dockConfigs, screen, Quickshell.screens, (config, target) => isScreenInPreferences(target, config.screenPreferences)).filter(config => !_barClaimsEdge(screen, config.position));
    }

    function dockConfigForScreenEdge(screen, side) {
        return dockConfigsForScreen(screen).find(config => DockConfig.EDGES[config.position] === side) ?? null;
    }

    function dockConfigForScreen(screen) {
        return dockConfigsForScreen(screen)[0] ?? null;
    }

    function _barClaimsEdge(screen, position) {
        return barConfigs.some(bar => bar.enabled && (bar.visible ?? true) && bar.position === position && barConfigCoversScreen(bar, screen));
    }

    function taskbarInsetForEdge(screen, side) {
        const config = dockConfigForScreenEdge(screen, side);
        if (!config?.enabled || config.mode !== "taskbar")
            return 0;
        const frameInset = !CompositorService.frameWindowVisibleForScreen(screen) ? 0 : !config.useOverlayLayer && CompositorService.usesConnectedFrameChromeForScreen(screen) ? frameEdgeReservation(screen, side) : frameThickness;
        return DockConfig.effectiveThickness(config) + frameInset;
    }

    function dockReservationForEdge(screen, side) {
        const config = dockConfigForScreenEdge(screen, side);
        if (!config?.enabled || config.autoHide || config.smartAutoHide)
            return 0;
        return Math.max(0, DockConfig.effectiveThickness(config) + (config.mode === "taskbar" || (!config.useOverlayLayer && CompositorService.usesConnectedFrameChromeForScreen(screen)) ? 0 : config.margin + config.bottomGap));
    }

    function _screensCoveredBy(preferences) {
        return Quickshell.screens.filter(screen => preferences.includes("all") || isScreenInPreferences(screen, preferences));
    }

    // A dock only clashes with something sharing both a screen and an edge; other edges stay free.
    function dockAssignmentConflict(id, preferences, position) {
        const edge = position ?? getDockConfig(id)?.position ?? SettingsData.Position.Bottom;
        const covered = _screensCoveredBy(preferences);
        for (const other of dockConfigs) {
            if (other.id === id || other.position !== edge || !other.enabled)
                continue;
            if (covered.some(screen => isScreenInPreferences(screen, other.screenPreferences) || other.screenPreferences.includes("all")))
                return other.name;
        }
        for (const bar of barConfigs) {
            if (!bar.enabled || !(bar.visible ?? true) || bar.position !== edge)
                continue;
            if (covered.some(screen => barConfigCoversScreen(bar, screen)))
                return bar.name || bar.id;
        }
        return "";
    }

    // Edges this configuration could still be moved to, with its current edge always offered.
    function dockAvailableEdges(id, preferences) {
        const current = getDockConfig(id)?.position;
        return [SettingsData.Position.Top, SettingsData.Position.Bottom, SettingsData.Position.Left, SettingsData.Position.Right].filter(edge => edge === current || !dockAssignmentConflict(id, preferences, edge));
    }

    function dockConfigForAction(screen, selector) {
        if (selector)
            return getDockConfig(selector) || dockConfigs.find(config => config.name === selector) || null;
        if (typeof screen === "string")
            screen = Quickshell.screens.find(item => item.name === screen);
        const resolved = dockConfigForScreen(screen);
        if (resolved)
            return resolved;
        return dockConfigs.find(config => !config.screenPreferences.includes("all") && screen && isScreenInPreferences(screen, config.screenPreferences)) || dockConfigs.find(config => config.screenPreferences.includes("all")) || dockConfigs[0] || null;
    }

    function getDockConfig(id) {
        return dockConfigs.find(config => config.id === id) ?? null;
    }

    function updateDockConfig(id, updates) {
        const current = getDockConfig(id);
        if (!current)
            return;
        const next = DockConfig.normalize([Object.assign({}, current, updates, {
                id
            })])[0];
        if (!next)
            return;
        dockConfigs = dockConfigs.map(config => config.id === id ? next : config);
        saveSettings();
    }
    // First edge in `order` that no enabled bar or dock already holds on the covered displays.
    function firstFreeEdge(id, preferences, order) {
        return order.find(edge => !dockAssignmentConflict(id, preferences, edge)) ?? -1;
    }

    function firstFreeDockEdge(id, preferences) {
        return firstFreeEdge(id, preferences, [SettingsData.Position.Bottom, SettingsData.Position.Left, SettingsData.Position.Right, SettingsData.Position.Top]);
    }

    // A new dock shows up right away on every display when an edge is free for it.
    function createDockConfig() {
        const id = "dock_" + Date.now();
        let name = I18n.tr("Dock");
        let number = 2;
        while (dockConfigs.some(config => config.name === name))
            name = I18n.tr("Dock %1", "generated dock name, %1 is a number").arg(number++);
        const config = DockConfig.create(id, name);
        const edge = firstFreeDockEdge(id, config.screenPreferences);
        config.enabled = edge >= 0;
        config.position = Math.max(SettingsData.Position.Top, edge);
        dockConfigs = dockConfigs.concat([config]);
        saveSettings();
        return id;
    }
    function removeDockConfig(id) {
        dockConfigs = dockConfigs.filter(config => config.id !== id);
        SessionData.removeDockPins(id);
        saveSettings();
    }
    function updateDockWidget(id, instanceId, updates) {
        const config = getDockConfig(id);
        if (!config)
            return;
        updateDockConfig(id, {
            widgets: config.widgets.map(item => item.id === instanceId ? Object.assign({}, item, updates) : item)
        });
    }

    // Pinning an app to a dock whose Apps row was removed would otherwise pin into nothing.
    function ensureDockApps(id) {
        const config = getDockConfig(id);
        if (!config)
            return;
        const apps = config.widgets.find(item => item.widgetId === "appsDock");
        if (apps && apps.enabled !== false)
            return;
        if (apps) {
            updateDockWidget(id, apps.id, {
                enabled: true
            });
            return;
        }
        updateDockConfig(id, {
            widgets: config.widgets.concat([
                {
                    id: id + "_apps",
                    widgetId: "appsDock",
                    enabled: true
                }
            ])
        });
    }

    function getBarConfig(barId) {
        return barConfigs.find(cfg => cfg.id === barId) || null;
    }

    function barTransparency(config) {
        if (config?.followInterfaceStyle !== false)
            return popupTransparency;
        return config?.transparency ?? 1.0;
    }

    function barWidgetTransparency(config) {
        if (config?.widgetFollowInterfaceStyle !== false)
            return Theme.foregroundAlpha;
        return config?.widgetTransparency ?? 1.0;
    }

    function barSurfaceColor(config) {
        return Theme.surfaceRoleColor(config?.surfaceColor, config?.surfaceCustomColor, Theme.hostSurface);
    }

    function widgetOption(widgetType, data, key) {
        return WidgetDefaults.option(widgetType, data, key);
    }

    function widgetDefaults(widgetType) {
        return WidgetDefaults.DEFAULTS[widgetType] ?? {};
    }

    function barWidgetEntry(barConfig, widgetType) {
        if (!barConfig)
            return null;
        for (const listKey of ["leftWidgets", "centerWidgets", "rightWidgets"]) {
            for (const entry of barConfig[listKey] ?? []) {
                const id = typeof entry === "string" ? entry : (entry.id ?? entry.widgetId);
                if (id !== widgetType)
                    continue;
                return typeof entry === "string" ? {
                    "id": entry
                } : entry;
            }
        }
        return null;
    }

    function addBarWidget(barId, sectionId, widgetId) {
        const config = getBarConfig(barId);
        if (!config)
            return -1;
        const entry = {
            "id": widgetId,
            "enabled": true
        };
        switch (widgetId) {
        case "spacer":
            entry.size = 20;
            break;
        case "gpuTemp":
            entry.selectedGpuIndex = 0;
            entry.pciId = "";
            break;
        case "diskUsage":
            entry.mountPath = "/";
            break;
        }
        const listKey = sectionId + "Widgets";
        const list = (config[listKey] ?? []).slice();
        if (widgetId === "island") {
            if (isIslandBarConfig(config) || islandWidgetBlocked(config) || _islandWidgetLocation(config))
                return -1;
            const configs = JSON.parse(JSON.stringify(barConfigs));
            const target = configs.find(cfg => cfg.id === barId);
            list.push(entry);
            target[listKey] = list;
            _commitIslandOwner(configs, target);
            return list.length - 1;
        }
        list.push(entry);
        const patch = {};
        patch[listKey] = list;
        updateBarConfig(barId, patch);
        return list.length - 1;
    }

    function locateBarWidget(widgetId, preferredBarId) {
        const ordered = barConfigs.slice().sort((a, b) => (b.id === preferredBarId) - (a.id === preferredBarId));
        for (const config of ordered) {
            for (const sectionId of ["left", "center", "right"]) {
                const list = config[sectionId + "Widgets"] ?? [];
                for (let i = 0; i < list.length; i++) {
                    const id = typeof list[i] === "string" ? list[i] : list[i].id;
                    if (id === widgetId)
                        return {
                            "barId": config.id,
                            "section": sectionId,
                            "index": i
                        };
                }
            }
        }
        return null;
    }

    function updateBarWidget(barId, sectionId, index, updates) {
        const config = getBarConfig(barId);
        const listKey = sectionId + "Widgets";
        const list = (config?.[listKey] ?? []).slice();
        if (index < 0 || index >= list.length)
            return;
        const entry = typeof list[index] === "string" ? {
            "id": list[index],
            "enabled": true
        } : Object.assign({}, list[index]);
        Object.assign(entry, updates);
        list[index] = entry;
        const patch = {};
        patch[listKey] = list;
        updateBarConfig(barId, patch);
    }

    function setBarIsland(barId, on, dot) {
        const config = getBarConfig(barId);
        const wantIsland = on === true && dot !== true;
        const wantDot = on === true && dot === true;
        if (!config || ((config.island === true) === wantIsland && (config.dot === true) === wantDot))
            return;
        const updates = {
            island: wantIsland,
            dot: wantDot
        };
        const configs = JSON.parse(JSON.stringify(barConfigs));
        const target = Object.assign(configs.find(cfg => cfg.id === barId), updates);
        if (on !== true) {
            _commitBarConfigs(configs);
            return;
        }
        if (!config.enabled)
            target.enabled = true;
        // A hidden island would draw but leave routing, with no Visibility card and no `bar reveal` to bring it back.
        if (config.visible === false)
            target.visible = true;
        if ((config.screenPreferences ?? []).length === 0)
            target.screenPreferences = ["all"];
        _stashIslandWidget(target);
        if (wantIsland)
            _evictIslandWidgets(configs, target);
        _commitBarConfigs(configs);
    }

    function isBarIpcRevealed(barId) {
        if (!barId)
            return false;
        return !!barIpcRevealStates[barId];
    }

    function setBarIpcReveal(barId, revealed) {
        if (!barId || isIslandBarConfig(getBarConfig(barId)))
            return;
        const nextRevealed = !!revealed;
        if (!!barIpcRevealStates[barId] === nextRevealed)
            return;
        const states = Object.assign({}, barIpcRevealStates);
        if (nextRevealed) {
            states[barId] = true;
        } else {
            delete states[barId];
        }
        barIpcRevealStates = states;
    }

    function toggleBarIpcReveal(barId) {
        const revealed = !isBarIpcRevealed(barId);
        setBarIpcReveal(barId, revealed);
        return revealed;
    }

    function addBarConfig(config) {
        const configs = JSON.parse(JSON.stringify(barConfigs));
        configs.push(config);
        const result = _applyConnectedFrameBarStyles(configs);
        barConfigs = result.configs;
        if (result.backups)
            connectedFrameBarStyleBackups = result.backups;
        updateBarConfigs();
    }

    function updateBarConfig(barId, updates) {
        const configs = JSON.parse(JSON.stringify(barConfigs));
        const index = configs.findIndex(cfg => cfg.id === barId);
        if (index === -1)
            return;
        const positionChanged = updates.position !== undefined && configs[index].position !== updates.position;
        if (updates.autoHide === false || updates.visible === false)
            setBarIpcReveal(barId, false);

        Object.assign(configs[index], updates);
        _commitIslandOwner(configs, configs[index]);

        if (positionChanged) {
            notificationPopupsInvalidated();
        }
    }

    function deleteBarConfig(barId) {
        if (barId === "default")
            return;
        const configs = barConfigs.filter(cfg => cfg.id !== barId);
        barConfigs = configs;
        if (connectedFrameBarStyleBackups?.[barId] !== undefined) {
            const nextBackups = JSON.parse(JSON.stringify(connectedFrameBarStyleBackups || {}));
            delete nextBackups[barId];
            connectedFrameBarStyleBackups = nextBackups;
        }
        setBarIpcReveal(barId, false);
        updateBarConfigs();
    }

    function getBarKindConfigs() {
        return barConfigs.filter(cfg => !isIslandBarConfig(cfg));
    }

    // Style and popup fallbacks never treat the island as "the bar".
    function getPrimaryBarConfig() {
        const bars = getBarKindConfigs();
        if (bars.length > 0)
            return bars[0];
        const fallback = getBarConfig("default");
        return isIslandBarConfig(fallback) ? null : fallback;
    }

    function _sideToPosition(side) {
        return LayoutResolver.edges.indexOf(side);
    }

    function positionToSide(pos) {
        return LayoutResolver.edgeName(pos);
    }

    function barOccupiesSide(screen, side) {
        const position = _sideToPosition(side);
        return position >= 0 && (ShellLayout.forScreen(screen)?.bars.some(input => input.config.position === position) ?? false);
    }

    // Check if a dock occupies the specified screen edge.
    function dockOccupiesSide(screen, side) {
        const config = dockConfigForScreenEdge(screen, side);
        return !!config?.enabled;
    }

    function getScreenModelIndex(screen) {
        return LayoutResolver.screenModelIndex(screen, Quickshell.screens);
    }

    function getScreenDisplayName(screen) {
        if (!screen)
            return "";
        if (displayNameMode === "model" && screen.model) {
            const modelIndex = getScreenModelIndex(screen);
            if (modelIndex >= 0) {
                return screen.model + "-" + modelIndex;
            }
            return screen.model;
        }
        return screen.name;
    }

    function isScreenInPreferences(screen, prefs) {
        return LayoutResolver.screenMatches(screen, prefs, Quickshell.screens, displayNameMode);
    }

    function getFilteredScreens(componentId) {
        var prefs = screenPreferences && screenPreferences[componentId] || ["all"];
        if (componentId === "wallpaper" && Array.isArray(prefs) && prefs.length === 0) {
            return [];
        }
        if (!prefs || prefs.length === 0 || prefs.includes("all") || (typeof prefs[0] === "string" && prefs[0] === "all")) {
            return Quickshell.screens;
        }
        var filtered = Quickshell.screens.filter(screen => isScreenInPreferences(screen, prefs));
        if (filtered.length === 0 && showOnLastDisplay && showOnLastDisplay[componentId] && Quickshell.screens.length === 1) {
            return Quickshell.screens;
        }
        return filtered;
    }

    function barConfigCoversScreen(bc, screen) {
        return ShellLayout.coversScreen(bc, screen);
    }

    function isIslandBarConfig(bc) {
        return !!bc && (bc.island === true || bc.dot === true);
    }

    function islandWidgetEntry(bc) {
        const location = isIslandBarConfig(bc) ? null : _islandWidgetLocation(bc);
        if (!location)
            return null;
        const entry = bc[location.sectionId + "Widgets"][location.index];
        return typeof entry === "string" ? {
            "id": entry
        } : entry;
    }

    function hostsIsland(bc) {
        return isIslandBarConfig(bc) || !!_islandWidgetLocation(bc, true);
    }

    function _sharesScreen(a, b) {
        return Quickshell.screens.some(screen => barConfigCoversScreen(a, screen) && barConfigCoversScreen(b, screen));
    }

    function islandWidgetBlocked(bc) {
        if (!bc)
            return true;
        return (barConfigs || []).some(cfg => cfg.id !== bc.id && cfg.island === true && cfg.enabled !== false && _sharesScreen(cfg, bc));
    }

    // Clones and dots drop the widget for good; an island-layout switch stashes it first.
    function stripIslandWidget(cfg) {
        delete cfg.islandWidgetStash;
        _stripIslandEntries(cfg);
    }

    function _stripIslandEntries(cfg) {
        for (const sectionId of ["left", "center", "right"]) {
            const key = sectionId + "Widgets";
            if (Array.isArray(cfg[key]))
                cfg[key] = cfg[key].filter(entry => !_isIslandEntry(entry));
        }
    }

    // An island-layout bar cannot host the widget, but switching back should not cost the user its placement and settings.
    function _stashIslandWidget(cfg) {
        const location = _islandWidgetLocation(cfg);
        if (location)
            cfg.islandWidgetStash = Object.assign({
                "entry": cfg[location.sectionId + "Widgets"][location.index]
            }, location);
        _stripIslandEntries(cfg);
    }

    // A restore never evicts: while another island holds the screen the stash waits for a later commit to free it.
    function _restoreIslandWidget(cfg, configs) {
        const stash = cfg.islandWidgetStash;
        if (!stash?.entry) {
            delete cfg.islandWidgetStash;
            return;
        }
        if (isIslandBarConfig(cfg) || _islandWidgetLocation(cfg) || _islandScreenTaken(configs, cfg))
            return;
        delete cfg.islandWidgetStash;
        const key = stash.sectionId + "Widgets";
        const list = Array.isArray(cfg[key]) ? cfg[key].slice() : [];
        list.splice(Math.min(stash.index, list.length), 0, stash.entry);
        cfg[key] = list;
    }

    function _islandScreenTaken(configs, bc) {
        return configs.some(cfg => cfg.id !== bc.id && cfg.enabled !== false && (cfg.island === true || _islandWidgetLocation(cfg, true)) && _sharesScreen(cfg, bc));
    }

    function _evictIslandWidgets(configs, owner) {
        for (const cfg of configs) {
            if (cfg.id !== owner.id && cfg.enabled !== false && _islandWidgetLocation(cfg, true) && _sharesScreen(cfg, owner))
                _stashIslandWidget(cfg);
        }
    }

    // Island-relevant writes must go through here, or a freed screen never gets its stashed widget back.
    function _commitBarConfigs(configs) {
        for (const cfg of configs)
            _restoreIslandWidget(cfg, configs);
        const result = _applyConnectedFrameBarStyles(configs);
        barConfigs = result.configs;
        if (result.backups)
            connectedFrameBarStyleBackups = result.backups;
        updateBarConfigs();
    }

    // The bar just written wins its screens: enabling a bar or its island entry evicts the previous host.
    function _commitIslandOwner(configs, cfg) {
        if (cfg.enabled !== false && !isIslandBarConfig(cfg) && _islandWidgetLocation(cfg, true))
            _evictIslandWidgets(configs, cfg);
        _commitBarConfigs(configs);
    }

    function isDotBarConfig(bc) {
        return !!bc && bc.dot === true;
    }

    // The dot is a companion, not a layout: the first enable clones the base bar so it inherits its look.
    function setDotEnabled(enabled, baseId) {
        const existing = dotBarConfig;
        if (existing) {
            if ((existing.enabled ?? false) !== enabled)
                updateBarConfig(existing.id, {
                    enabled
                });
            return;
        }
        if (!enabled)
            return;
        const base = getBarConfig(baseId);
        const source = base && !isDotBarConfig(base) ? base : getBarConfig("default");
        if (!source)
            return;
        const config = Object.assign(JSON.parse(JSON.stringify(source)), {
            id: "dot" + Date.now(),
            name: I18n.tr("Dot", "bar layout: free-floating dot that opens island activities"),
            enabled: true,
            // A hidden or auto-hiding base bar would switch off the dot's OSD and notifications, and bar IPC refuses dot configs.
            visible: true,
            autoHide: false,
            island: false,
            dot: true,
            screenPreferences: ["all"],
            showOnLastDisplay: true,
            followInterfaceStyle: false,
            transparency: barTransparency(source)
        });
        // An inherited "always here" would make the base island and the dot fight by config order.
        delete config.islandSharedRouting;
        stripIslandWidget(config);
        addBarConfig(config);
    }

    function islandFreePlacement(bc) {
        return isDotBarConfig(bc) || (isIslandBarConfig(bc) && islandSetting(bc, "islandFloating") && islandSetting(bc, "islandPlacement") === "free");
    }

    // A hosted island shares its config id with the bar, so last-used cannot tell them apart and would degenerate into always.
    function islandSharedRoutingMode(bc) {
        const mode = islandSetting(bc, "islandSharedRouting");
        if (mode === "always")
            return mode;
        return mode === "last-used" && isIslandBarConfig(bc) ? mode : "normal";
    }

    // Dashboard activities share an IPC close, but choose their destinations independently.
    readonly property var islandDashActivities: ["home", "media", "weather", "wallpaper"]

    function islandRouteKey(activity) {
        switch (activity) {
        case "controlcenter":
            return "islandRouteControlCenter";
        case "notificationcenter":
            return "islandRouteNotificationCenter";
        case "launcher":
            return "islandRouteLauncher";
        case "home":
            return "islandRouteDash";
        case "media":
            return "islandRouteMedia";
        case "weather":
            return "islandRouteWeather";
        case "wallpaper":
            return "islandRouteWallpaper";
        case "clipboard":
            return "islandRouteClipboard";
        case "powermenu":
            return "islandRoutePowerMenu";
        }
        return "";
    }

    function islandActivityRoutingMode(bc, activity) {
        const key = islandRouteKey(activity);
        const override = key ? islandSetting(bc, key) : "follow";
        if (override === "island")
            return "always";
        if (override === "bar")
            return "never";
        return islandSharedRoutingMode(bc);
    }

    function sharedShortcutsFollowLastUsed(screen) {
        return activeIslandConfigsForScreen(screen).some(cfg => islandSharedRoutingMode(cfg) === "last-used");
    }

    function sharedShortcutsOverridden(screen, activity) {
        return activeIslandConfigsForScreen(screen).some(cfg => {
            const mode = islandActivityRoutingMode(cfg, activity);
            return mode === "always" || mode === "last-used";
        });
    }

    function recordBarInteraction(screen, barId) {
        const name = screen?.name;
        if (!name || !barId || lastUsedBarByScreen[name] === barId || !sharedShortcutsFollowLastUsed(screen))
            return;
        lastUsedBarByScreen = Object.assign({}, lastUsedBarByScreen, {
            [name]: barId
        });
    }

    // A satellite carrying the activity's own widget is a standard destination on this screen, same as a bar.
    function islandSatelliteHosts(cfg, activity) {
        const widgetId = activity === "controlcenter" ? "controlCenterButton" : activity === "notificationcenter" ? "notificationButton" : "";
        if (!widgetId || !isIslandBarConfig(cfg) || isDotBarConfig(cfg) || !islandSetting(cfg, "islandSatellitesEnabled"))
            return false;
        return ["leftWidgets", "centerWidgets", "rightWidgets"].some(key => (cfg[key] ?? []).some(entry => (typeof entry === "string" ? entry : entry?.id) === widgetId && (typeof entry === "string" || entry.enabled !== false)));
    }

    function sharedTriggerIslandConfig(screen, activity) {
        const active = activeIslandConfigsForScreen(screen);
        const configs = active.filter(cfg => islandActivityRoutingMode(cfg, activity) !== "never");
        const key = islandRouteKey(activity);
        const pinned = key ? configs.find(cfg => {
            // Saved choices outrank defaults, including legacy dashboard-family pins.
            const settings = islandSettings(cfg);
            const override = settings[key] ?? (islandDashActivities.indexOf(activity) >= 0 ? settings.islandRouteDash : undefined);
            return override === "island";
        }) : null;
        if (pinned)
            return pinned;
        if (configs.some(cfg => islandActivityRoutingMode(cfg, activity) === "last-used")) {
            const lastId = lastUsedBarByScreen[screen?.name];
            const lastIsland = configs.find(cfg => cfg.id === lastId);
            if (lastIsland)
                return lastIsland;
        } else {
            const fixed = configs.find(cfg => islandActivityRoutingMode(cfg, activity) === "always");
            if (fixed)
                return fixed;
        }
        if (getActiveBarEdgesForScreen(screen).length > 0 || active.some(cfg => islandSatelliteHosts(cfg, activity)))
            return null;
        return configs.find(cfg => !isDotBarConfig(cfg)) ?? configs[0] ?? null;
    }
    function islandLauncherHostConfig(screen) {
        const config = sharedTriggerIslandConfig(screen, "launcher");
        if (config || launcherStyle !== "island")
            return config;
        const configs = activeIslandConfigsForScreen(screen).filter(cfg => islandActivityRoutingMode(cfg, "launcher") !== "never");
        return configs.find(cfg => !isDotBarConfig(cfg)) ?? configs[0] ?? null;
    }

    // "Always here" is exclusive per screen, or config order would silently pick the winner.
    function setIslandSharedRouting(barId, mode) {
        const configs = JSON.parse(JSON.stringify(barConfigs));
        const target = configs.find(cfg => cfg.id === barId);
        if (!target || !(isIslandBarConfig(target) || _islandWidgetLocation(target)))
            return;
        _writableIslandSettings(target).islandSharedRouting = mode;
        if (mode === "always") {
            for (const cfg of configs) {
                if (cfg.id !== barId && hostsIsland(cfg) && islandSharedRoutingMode(cfg) === "always" && _sharesScreen(cfg, target))
                    delete _writableIslandSettings(cfg).islandSharedRouting;
            }
        }
        _commitBarConfigs(configs);
    }

    // A hidden bar takes its island with it, so it must not keep swallowing popups and OSDs.
    function activeIslandConfigsForScreen(screen) {
        return ShellLayout.islandConfigs(screen).filter(cfg => cfg.visible !== false);
    }

    function islandConfigForEdge(screen, edge) {
        return ShellLayout.edge(screen, edge)?.island ?? null;
    }

    function dankIslandHandlesNotifications(screen) {
        return activeIslandConfigsForScreen(screen).some(cfg => !islandSetting(cfg, "islandNotificationPopups"));
    }

    function dankIslandHandlesSystemOsd(screen) {
        return activeIslandConfigsForScreen(screen).some(cfg => islandSetting(cfg, "islandSystemOsd"));
    }

    function dankIslandOwnsEdge(screen, edge) {
        return islandConfigForEdge(screen, edge) !== null;
    }

    function dankIslandEdgeOffset(screen, edge) {
        return ShellLayout.edge(screen, edge)?.islandThickness ?? 0;
    }

    function getActiveBarEdgesForScreen(screen) {
        return ShellLayout.barEdges(screen, false);
    }

    readonly property real frameBarContentGap: frameBarInsetPadding < 0 ? frameThickness : frameBarInsetPadding
    readonly property real frameBarContentGapExtra: Math.max(0, frameBarContentGap - frameThickness)

    function frameEdgeReservation(screen, edge) {
        return ShellLayout.frameReservation(screen, edge);
    }

    function frameEdgeInsetForSide(screen, side) {
        if (!frameEnabled)
            return 0;
        return frameEdgeReservation(screen, side);
    }

    function setMatugenScheme(scheme) {
        var normalized = scheme || "scheme-tonal-spot";
        if (matugenScheme === normalized)
            return;
        set("matugenScheme", normalized);
    }

    function setMatugenSmartMode(enabled) {
        if (matugenSmartMode === enabled)
            return;
        set("matugenSmartMode", enabled);
    }

    function setMatugenSourceMode(mode) {
        var normalized = mode || "dominant";
        if (matugenSourceMode === normalized)
            return;
        set("matugenSourceMode", normalized);
    }

    function setMatugenContrast(value) {
        if (matugenContrast === value)
            return;
        set("matugenContrast", value);
    }

    function setMatugenSeedColor(hex) {
        var normalized = /^#[0-9a-f]{6}$/i.test(hex || "") ? hex.toLowerCase() : "";
        if (matugenSeedColor === normalized)
            return;
        set("matugenSeedColor", normalized);
    }

    function setMatugenSpec(spec) {
        var normalized = spec === "2025" || spec === "dms" ? spec : "2021";
        if (matugenSpec === normalized)
            return;
        if (normalized !== "2021") {
            if (matugenContrast < 0)
                set("matugenContrast", 0);
            if (typeof Theme !== "undefined" && !Theme.getMatugenScheme(matugenScheme).spec2025)
                set("matugenScheme", "scheme-tonal-spot");
        }
        set("matugenSpec", normalized);
    }

    function setMatugenTargetMonitor(monitorName) {
        if (matugenTargetMonitor === monitorName)
            return;
        set("matugenTargetMonitor", monitorName);
    }

    function setCornerRadius(radius) {
        set("radiusStrength", Shape.strengthFromRadius(radius));
    }

    function setWeatherLocation(displayName, coordinates) {
        SessionData.setWeatherLocation(displayName, coordinates);
    }

    function setIconThemeForMode(themeName, light) {
        if (light)
            iconThemeLight = themeName;
        else
            iconThemeDark = themeName;
        applyStoredIconTheme();
        saveSettings();
        if (typeof Theme !== "undefined" && Theme.currentTheme === Theme.dynamic)
            Theme.generateSystemThemesFromCurrentTheme();
    }

    function setIconThemePerMode(enabled) {
        iconThemePerMode = enabled;
        applyStoredIconTheme();
        saveSettings();
        if (typeof Theme !== "undefined" && Theme.currentTheme === Theme.dynamic)
            Theme.generateSystemThemesFromCurrentTheme();
    }

    function setCursorTheme(themeName) {
        const updated = JSON.parse(JSON.stringify(cursorSettings));
        if (updated.theme === themeName)
            return;
        updated.theme = themeName;
        cursorSettings = updated;
        saveSettings();
        updateXResources();
        updateCompositorCursor();
    }

    function setCursorSize(size) {
        const updated = JSON.parse(JSON.stringify(cursorSettings));
        if (updated.size === size)
            return;
        updated.size = size;
        cursorSettings = updated;
        saveSettings();
        updateXResources();
        updateCompositorCursor();
    }

    // This solution for xwayland cursor themes is from the xwls discussion:
    // https://github.com/Supreeeme/xwayland-satellite/issues/104
    // no idea if this matters on other compositors but we also set XCURSOR stuff in the launcher
    function updateCompositorCursor() {
        compositorCursorRefreshNeeded();
    }

    function updateXResources() {
        const homeDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.HomeLocation));
        const xresourcesPath = homeDir + "/.Xresources";
        const themeName = cursorSettings.theme === "System Default" ? systemDefaultCursorTheme : cursorSettings.theme;
        const size = cursorSettings.size || 24;

        if (!themeName)
            return;

        const script = `
            xresources_file="${xresourcesPath}"
            [ -f "$xresources_file" ] && [ ! -w "$xresources_file" ] && exit 0
            theme_name="${themeName}"
            cursor_size="${size}"

            current_theme=""
            current_size=""
            if [ -f "$xresources_file" ]; then
                current_theme=$(grep -E '^[[:space:]]*Xcursor\\.theme:' "$xresources_file" 2>/dev/null | sed 's/.*:[[:space:]]*//' | head -1)
                current_size=$(grep -E '^[[:space:]]*Xcursor\\.size:' "$xresources_file" 2>/dev/null | sed 's/.*:[[:space:]]*//' | head -1)
            fi

            [ "$current_theme" = "$theme_name" ] && [ "$current_size" = "$cursor_size" ] && exit 0

            if [ -f "$xresources_file" ]; then
                cp "$xresources_file" "\${xresources_file}.backup$(date +%s)"
            fi

            temp_file="\${xresources_file}.tmp.$$"
            if [ -f "$xresources_file" ]; then
                grep -v '^[[:space:]]*Xcursor\\.theme:' "$xresources_file" | grep -v '^[[:space:]]*Xcursor\\.size:' > "$temp_file" 2>/dev/null || true
            else
                touch "$temp_file"
            fi

            echo "Xcursor.theme: $theme_name" >> "$temp_file"
            echo "Xcursor.size: $cursor_size" >> "$temp_file"
            mv "$temp_file" "$xresources_file"
            xrdb -merge "$xresources_file" 2>/dev/null || true
        `;

        Quickshell.execDetached(["sh", "-c", script]);
    }

    function getCursorEnvironment() {
        const isSystemDefault = cursorSettings.theme === "System Default";
        const isDefaultSize = !cursorSettings.size || cursorSettings.size === 24;
        const themeName = isSystemDefault ? "" : cursorSettings.theme;
        const size = String(cursorSettings.size || 24);
        const env = {};

        // Started from systemd the shell inherits no XCURSOR_SIZE from the compositor
        // XWayland children would size their cursor from the display instead
        if (!isDefaultSize || !Quickshell.env("XCURSOR_SIZE")) {
            env["XCURSOR_SIZE"] = size;
            env["HYPRCURSOR_SIZE"] = size;
        }
        if (themeName) {
            env["XCURSOR_THEME"] = themeName;
            env["HYPRCURSOR_THEME"] = themeName;
        }
        return env;
    }

    function setDankBarLeftWidgets(order) {
        const defaultBar = getPrimaryBarConfig();
        if (defaultBar) {
            updateBarConfig(defaultBar.id, {
                "leftWidgets": order
            });
            updateListModel(leftWidgetsModel, order);
        }
    }

    function setDankBarCenterWidgets(order) {
        const defaultBar = getPrimaryBarConfig();
        if (defaultBar) {
            updateBarConfig(defaultBar.id, {
                "centerWidgets": order
            });
            updateListModel(centerWidgetsModel, order);
        }
    }

    function setDankBarRightWidgets(order) {
        const defaultBar = getPrimaryBarConfig();
        if (defaultBar) {
            updateBarConfig(defaultBar.id, {
                "rightWidgets": order
            });
            updateListModel(rightWidgetsModel, order);
        }
    }

    function setWorkspaceNameIcon(workspaceName, iconData) {
        var iconMap = JSON.parse(JSON.stringify(workspaceNameIcons));
        iconMap[workspaceName] = iconData;
        workspaceNameIcons = iconMap;
        saveSettings();
        workspaceIconsUpdated();
    }

    function removeWorkspaceNameIcon(workspaceName) {
        var iconMap = JSON.parse(JSON.stringify(workspaceNameIcons));
        delete iconMap[workspaceName];
        workspaceNameIcons = iconMap;
        saveSettings();
        workspaceIconsUpdated();
    }

    function getWorkspaceNameIcon(workspaceName) {
        return workspaceNameIcons[workspaceName] || null;
    }

    function addAppIdSubstitution(pattern, replacement, type) {
        var subs = JSON.parse(JSON.stringify(appIdSubstitutions));
        subs.push({
            pattern: pattern,
            replacement: replacement,
            type: type
        });
        appIdSubstitutions = subs;
        saveSettings();
    }

    function updateAppIdSubstitution(index, pattern, replacement, type) {
        var subs = JSON.parse(JSON.stringify(appIdSubstitutions));
        if (index < 0 || index >= subs.length)
            return;
        subs[index] = {
            pattern: pattern,
            replacement: replacement,
            type: type
        };
        appIdSubstitutions = subs;
        saveSettings();
    }

    function removeAppIdSubstitution(index) {
        var subs = JSON.parse(JSON.stringify(appIdSubstitutions));
        if (index < 0 || index >= subs.length)
            return;
        subs.splice(index, 1);
        appIdSubstitutions = subs;
        saveSettings();
    }

    function addAppIdToList(identity: string, appList: list<string>): list<string> {
        identity = identity ?? "";
        appList = appList ?? [];
        if (!identity)
            return appList;

        var normalizedIdentity = Paths.normalizeAppId(identity);
        if (!normalizedIdentity)
            return appList;

        var cleanList = appList.map(id => id ? Paths.normalizeAppId(id) : "").filter(id => id !== "");
        if (cleanList.includes(normalizedIdentity))
            return cleanList;

        cleanList.push(normalizedIdentity);
        return cleanList;
    }

    function removeAppIdFromList(index: int, appList: list<string>): list<string> {
        var moddedList = appList ? appList.slice() : [];
        if (index < 0 || index >= moddedList.length)
            return moddedList;
        moddedList.splice(index, 1);
        return moddedList;
    }

    function addNightModeExcludedApp(identity: string) {
        var newList = addAppIdToList(identity, nightModeExcludedApps);
        nightModeExcludedApps = newList;
        saveSettings();
    }

    function removeNightModeExcludedApp(index: int) {
        var newList = removeAppIdFromList(index, nightModeExcludedApps);
        nightModeExcludedApps = newList;
        saveSettings();
    }

    function addMediaExcludePlayer(identity) {
        var newList = addAppIdToList(identity, mediaExcludePlayers);
        mediaExcludePlayers = newList;
        saveSettings();
    }

    function removeMediaExcludePlayer(index) {
        var newList = removeAppIdFromList(index, mediaExcludePlayers);
        mediaExcludePlayers = newList;
        saveSettings();
    }

    property var pendingNotificationRule: null

    function _newNotificationRule(overrides) {
        return Object.assign({
            enabled: true,
            field: "appName",
            pattern: "",
            matchType: "contains",
            action: "default",
            urgency: "default",
            bypassDnd: false
        }, overrides || {});
    }

    function addNotificationRule(ruleData) {
        var rules = JSON.parse(JSON.stringify(notificationRules || []));
        rules.push(_newNotificationRule(ruleData));
        notificationRules = rules;
        saveSettings();
    }

    function requestNotificationRuleForNotification(appName, desktopEntry) {
        const pattern = desktopEntry || appName || "";
        pendingNotificationRule = _newNotificationRule(pattern ? {
            field: desktopEntry ? "desktopEntry" : "appName",
            pattern: pattern,
            matchType: "exact"
        } : {});
    }

    function _isMuteRule(rule) {
        return (rule.action || "").toString().toLowerCase() === "mute";
    }

    function _isDndBypassRule(rule) {
        return rule.bypassDnd === true;
    }

    // Timed mute rules carry an expiresAt timestamp (ms since epoch); 0 or
    // absent means the mute never expires. Only the mute lapses: a DND bypass
    // or urgency on the same rule stays in force, and
    // pruneExpiredNotificationRules() clears the lapsed mute from the
    // persisted rule. nowMs is optional (defaults to the current time);
    // reactive callers pass NotificationService.notificationRuleNowMs so
    // their bindings refresh as rules expire instead of freezing on a stale
    // Date.now().
    function isNotificationRuleExpired(rule, nowMs) {
        return RuleExpiry.isRuleExpired(rule, nowMs);
    }

    // True while any rule carries an expiry timestamp. Gates the expiry
    // clock and sweeper in NotificationService so they only run when a
    // timed rule can actually expire.
    readonly property bool hasTimedNotificationRules: RuleExpiry.hasTimedRule(notificationRules)

    function _appRuleIndex(rules, appName, desktopEntry, predicate) {
        const app = (appName || "").toString().toLowerCase();
        const desktop = (desktopEntry || "").toString().toLowerCase();
        if (!app && !desktop)
            return -1;
        return rules.findIndex(rule => {
            if (!predicate(rule) || (rule.matchType || "contains").toString().toLowerCase() !== "exact" || (rule.conditions || []).length > 0)
                return false;
            const pattern = (rule.pattern || "").toString().toLowerCase();
            const value = !rule.field || rule.field === "appName" ? app : rule.field === "desktopEntry" ? desktop : "";
            return pattern !== "" && pattern === value;
        });
    }

    function _addAppRule(appName, desktopEntry, overrides) {
        const pattern = desktopEntry || appName || "";
        if (!pattern)
            return;
        var rules = JSON.parse(JSON.stringify(notificationRules || []));
        const rule = _newNotificationRule(Object.assign({
            field: desktopEntry ? "desktopEntry" : "appName",
            pattern: pattern,
            matchType: "exact"
        }, overrides));
        if (!rule.expiresAt)
            delete rule.expiresAt;
        rules.push(rule);
        notificationRules = rules;
        saveSettings();
    }

    function _hasNoAction(rule) {
        return (rule.action || "default").toString().toLowerCase() === "default";
    }

    function _isNoopRule(rule) {
        return _hasNoAction(rule) && (rule.urgency || "default").toString().toLowerCase() === "default" && !_isDndBypassRule(rule);
    }

    // Edits the first enabled matching rule and drops it once it no longer does anything.
    function _updateAppRule(appName, desktopEntry, predicate, changes) {
        var rules = JSON.parse(JSON.stringify(notificationRules || []));
        const index = _appRuleIndex(rules, appName, desktopEntry, rule => rule.enabled !== false && predicate(rule));
        if (index === -1)
            return false;
        const rule = Object.assign(rules[index], changes);
        if (!rule.expiresAt)
            delete rule.expiresAt;
        if (_isNoopRule(rule))
            rules.splice(index, 1);
        notificationRules = rules;
        saveSettings();
        return true;
    }

    function addMuteRuleForApp(appName, desktopEntry, expiresAt) {
        // Re-muting edits the app's existing no-action or mute rule (including an
        // expired one not yet swept) so duplicates never accumulate.
        const changes = {
            action: "mute",
            expiresAt: expiresAt || 0
        };
        if (!_updateAppRule(appName, desktopEntry, rule => _hasNoAction(rule) || _isMuteRule(rule), changes))
            _addAppRule(appName, desktopEntry, changes);
    }

    function isAppMuted(appName, desktopEntry, nowMs) {
        return _appRuleIndex(notificationRules || [], appName, desktopEntry, rule => rule.enabled !== false && _isMuteRule(rule) && !isNotificationRuleExpired(rule, nowMs)) !== -1;
    }

    // ExpiresAt of the active mute rule for an app (ms since epoch),
    // or 0 when the app is not muted or the mute is permanent.
    function muteExpiresAt(appName, desktopEntry, nowMs) {
        const rules = notificationRules || [];
        const index = _appRuleIndex(rules, appName, desktopEntry, rule => rule.enabled !== false && _isMuteRule(rule) && !isNotificationRuleExpired(rule, nowMs));
        return index === -1 ? 0 : (rules[index].expiresAt || 0);
    }

    // Clears lapsed timed mutes from the persisted list so the settings UI
    // stays truthful. Only the mute goes; the rule is dropped once nothing
    // else is left on it. The idle sweep must stay cheap, so nothing is
    // copied unless a rule actually expired.
    function pruneExpiredNotificationRules() {
        const rules = notificationRules || [];
        if (!rules.some(rule => isNotificationRuleExpired(rule)))
            return;
        const kept = [];
        for (const source of rules) {
            if (!isNotificationRuleExpired(source)) {
                kept.push(source);
                continue;
            }
            const rule = Object.assign({}, source, {
                action: "default"
            });
            delete rule.expiresAt;
            if (!_isNoopRule(rule))
                kept.push(rule);
        }
        notificationRules = kept;
        saveSettings();
    }

    function removeMuteRuleForApp(appName, desktopEntry) {
        _updateAppRule(appName, desktopEntry, _isMuteRule, {
            action: "default",
            expiresAt: 0
        });
    }

    function isAppDndBypassed(appName, desktopEntry) {
        return _appRuleIndex(notificationRules || [], appName, desktopEntry, rule => rule.enabled !== false && _isDndBypassRule(rule)) !== -1;
    }

    function setAppDndBypass(appName, desktopEntry, enabled) {
        if (!enabled) {
            _updateAppRule(appName, desktopEntry, _isDndBypassRule, {
                bypassDnd: false
            });
            return;
        }
        if (isAppDndBypassed(appName, desktopEntry))
            return;
        if (!_updateAppRule(appName, desktopEntry, () => true, {
            bypassDnd: true
        }))
            _addAppRule(appName, desktopEntry, {
                bypassDnd: true
            });
    }

    function updateNotificationRule(index, ruleData) {
        var rules = JSON.parse(JSON.stringify(notificationRules || []));
        if (index < 0 || index >= rules.length)
            return;
        var existing = rules[index] || {};
        rules[index] = Object.assign({}, existing, ruleData || {});
        notificationRules = rules;
        saveSettings();
    }

    function updateNotificationRuleField(index, key, value) {
        if (key === undefined || key === null || key === "")
            return;
        var patch = {};
        patch[key] = value;
        updateNotificationRule(index, patch);
    }

    function removeNotificationRule(index) {
        var rules = JSON.parse(JSON.stringify(notificationRules || []));
        if (index < 0 || index >= rules.length)
            return;
        rules.splice(index, 1);
        notificationRules = rules;
        saveSettings();
    }

    function getDefaultNotificationRules() {
        return Spec.SPEC.notificationRules.def;
    }

    function resetNotificationRules() {
        notificationRules = JSON.parse(JSON.stringify(Spec.SPEC.notificationRules.def));
        saveSettings();
    }

    function getDefaultAppIdSubstitutions() {
        return Spec.SPEC.appIdSubstitutions.def;
    }

    function resetAppIdSubstitutions() {
        appIdSubstitutions = JSON.parse(JSON.stringify(Spec.SPEC.appIdSubstitutions.def));
        saveSettings();
    }

    function getRegistryThemeVariant(themeId, defaultVariant) {
        var stored = registryThemeVariants[themeId];
        if (typeof stored === "string")
            return stored || defaultVariant || "";
        return defaultVariant || "";
    }

    function setRegistryThemeVariant(themeId, variantId) {
        var variants = JSON.parse(JSON.stringify(registryThemeVariants));
        variants[themeId] = variantId;
        registryThemeVariants = variants;
        saveSettings();
        if (typeof Theme !== "undefined")
            Theme.reloadCustomThemeVariant();
    }

    function getRegistryThemeMultiVariant(themeId, defaults, mode) {
        var stored = registryThemeVariants[themeId];
        if (!stored || typeof stored !== "object")
            return defaults || {};
        if ((stored.dark && typeof stored.dark === "object") || (stored.light && typeof stored.light === "object")) {
            if (!mode)
                return stored.dark || stored.light || defaults || {};
            var modeData = stored[mode];
            if (modeData && typeof modeData === "object")
                return modeData;
            return defaults || {};
        }
        return stored;
    }

    function setRegistryThemeMultiVariant(themeId, flavor, accent, mode) {
        var variants = JSON.parse(JSON.stringify(registryThemeVariants));
        var existing = variants[themeId];
        var perMode = {};
        if (existing && typeof existing === "object") {
            if ((existing.dark && typeof existing.dark === "object") || (existing.light && typeof existing.light === "object")) {
                perMode = existing;
            } else if (typeof existing.flavor === "string") {
                perMode.dark = {
                    flavor: existing.flavor,
                    accent: existing.accent || ""
                };
            }
        }
        perMode[mode || "dark"] = {
            flavor: flavor,
            accent: accent
        };
        variants[themeId] = perMode;
        registryThemeVariants = variants;
        saveSettings();
        if (typeof Theme !== "undefined")
            Theme.reloadCustomThemeVariant();
    }

    function getPluginSetting(pluginId, key, defaultValue) {
        if (!pluginSettings[pluginId]) {
            return defaultValue;
        }
        return pluginSettings[pluginId][key] !== undefined ? pluginSettings[pluginId][key] : defaultValue;
    }

    function setPluginSetting(pluginId, key, value) {
        const updated = JSON.parse(JSON.stringify(pluginSettings));
        if (!updated[pluginId]) {
            updated[pluginId] = {};
        }
        updated[pluginId][key] = value;
        pluginSettings = updated;
        savePluginSettings();
    }

    function getPluginSettingsForPlugin(pluginId) {
        const settings = pluginSettings[pluginId];
        return settings ? JSON.parse(JSON.stringify(settings)) : {};
    }

    function removeDisplayProfile(compositor, profileId) {
        if (!displayProfiles[compositor] || !displayProfiles[compositor][profileId])
            return;
        const updated = JSON.parse(JSON.stringify(displayProfiles));
        delete updated[compositor][profileId];
        displayProfiles = updated;
        saveSettings();
    }

    function setDisplayPreviousRefreshModes(compositor, modes) {
        if (JSON.stringify(displayPreviousRefreshModes[compositor] || {}) === JSON.stringify(modes || {}))
            return;
        const updated = JSON.parse(JSON.stringify(displayPreviousRefreshModes));
        if (Object.keys(modes || {}).length > 0)
            updated[compositor] = modes;
        else
            delete updated[compositor];
        displayPreviousRefreshModes = updated;
        saveSettings();
    }

    ListModel {
        id: leftWidgetsModel
    }

    ListModel {
        id: centerWidgetsModel
    }

    ListModel {
        id: rightWidgetsModel
    }

    component SettingsFile: QtObject {
        id: settingsFile

        required property string filePath
        property var settings: ({})
        property bool isLoading: false
        property bool hasLoaded: false
        property bool hasParseFailed: false
        property bool fileUnsavedUserChanges: false
        property bool isFileReadOnly: false
        property bool selfWrite: false
        function setSettings(newSettings, userChanges) {
            const newSettingsJson = JSON.stringify(newSettings, null, 2);
            if (JSON.stringify(settings, null, 2) === newSettingsJson) {
                return;
            }

            settings = newSettings;
            fileUnsavedUserChanges = fileUnsavedUserChanges || userChanges;

            selfWrite = true;
            settingsFileView.setText(newSettingsJson);
        }
        function getSettings() {
            return Object.assign({}, settings);
        }

        property Timer timer: Timer {
            id: settingsFileReloadDebounce
            interval: 50
            onTriggered: settingsFileView.reload()
            repeat: false
        }

        property FileView fileView: FileView {
            id: settingsFileView

            path: filePath
            blockLoading: false
            blockWrites: true
            atomicWrites: true
            watchChanges: true
            onFileChanged: {
                if (selfWrite) {
                    selfWrite = false;
                } else {
                    isLoading = true;
                    _loading = true;
                    settingsFileReloadDebounce.restart();
                }
            }
            onLoaded: {
                isLoading = true;
                _loading = true;
                const hadParseFailed = hasParseFailed;
                hasParseFailed = false;
                fileUnsavedUserChanges = false;
                if (unsavedUserChanges) {
                    unsavedUserChanges = _anySettingsFile(file => file.fileUnsavedUserChanges);
                }
                const fileName = filePath?.split("/").pop();
                try {
                    let txt = settingsFileView.text();
                    if (!txt || !txt.trim()) {
                        txt = "{}";
                    }
                    settings = JSON.parse(txt);
                    hasLoaded = true;
                } catch (error) {
                    hasParseFailed = true;
                    _parseError = true;

                    const msg = error.message;
                    log.error(`Failed to reload ${fileName} - file will not be overwritten. Error:`, msg);
                    Qt.callLater(() => ToastService.showError(I18n.tr("Failed to parse %1").arg(fileName), msg));
                } finally {
                    isLoading = false;
                    if (hadParseFailed && !hasParseFailed) {
                        _parseError = _anySettingsFile(file => file.hasParseFailed);
                    }
                    _tryCompleteLoading();
                    _loadSettingsOrStartIfReady();
                }
            }
            onLoadFailed: error => {
                isLoading = false;
                _loading = _anySettingsFile(file => file.isLoading);
                if (error === FileViewError.FileNotFound) {
                    // Fake that the file has been loaded so that it gets created after a save.
                    hasLoaded = true;
                }
                applyStoredTheme();
                _tryCompleteLoading();
                _loadSettingsOrStartIfReady();
            }
            onSaved: {
                isFileReadOnly = false;
                isReadOnly = isReadOnly ? _anySettingsFile(file => file.isFileReadOnly) : false;

                fileUnsavedUserChanges = false;
                if (unsavedUserChanges) {
                    unsavedUserChanges = _anySettingsFile(file => file.fileUnsavedUserChanges);
                }
            }
            onSaveFailed: error => {
                selfWrite = false;
                if (error === FileViewError.PermissionDenied) {
                    isFileReadOnly = true;
                    isReadOnly = true;
                }
                if (fileUnsavedUserChanges) {
                    const fileName = filePath?.split("/").pop() || "unknown";
                    log.warn(`Failed to save ${fileName}`);
                }
            }
        }
    }

    enum Stage {
        Discovering = 0,
        Loading = 1,
        Partial = 2,
        Ready = 3
    }
    property int _settingsStage: SettingsData.Stage.Discovering

    property var _settingsFiles: new Map()
    property var _settingsFilesPaths: ([])
    function _registerSettingsFile(file) {
        const filePath = file.filePath;
        if (_settingsFiles.has(filePath)) {
            return;
        }
        let index;
        if (file === defaultSettingsFile) {
            index = 0;
        } else {
            index = _settingsFilesPaths.findIndex((path, i) => {
                return path > filePath && i > 0;
            });
        }
        _settingsFiles.set(filePath, file);
        if (index >= 0) {
            _settingsFilesPaths.splice(index, 0, filePath);
        } else {
            _settingsFilesPaths.push(filePath);
        }
        _tryCompleteDiscovery();
    }
    function _unregisterSettingsFile(file) {
        _settingsFiles.delete(file.filePath);
        _settingsFilesPaths = _settingsFilesPaths.filter(path => path != file.filePath);
    }
    function _tryCompleteDiscovery() {
        if (_settingsStage !== SettingsData.Stage.Discovering || !_settingsFolderChecked) {
            return;
        }
        let expectedCount = 1;
        if (_settingsFolderExists) {
            expectedCount += settingsFolderLoader.item.count;
        }
        if (_settingsFilesPaths.length == expectedCount) {
            _settingsStage = SettingsData.Stage.Loading;
            _tryCompleteLoading();
            _loadSettingsOrStartIfReady();
        }
    }
    function _tryCompleteLoading() {
        if (_settingsStage !== SettingsData.Stage.Loading) {
            return;
        }
        if (_everySettingsFile(file => file.hasLoaded || file.hasParseFailed)) {
            _settingsStage = _parseError ? SettingsData.Stage.Partial : SettingsData.Stage.Ready;
        }
    }
    function _loadSettingsOrStartIfReady() {
        if (_settingsStage < SettingsData.Stage.Partial || _anySettingsFile(file => file.isLoading)) {
            return;
        }
        let unsaved;
        _loading = true;
        if (!_hasLoaded || _settingsStage === SettingsData.Stage.Partial) {
            unsaved = _runStartSequence();
        } else {
            unsaved = _loadSettings();
        }
        _loading = false;
        if (unsaved) {
            _saveSettings(false);
        }
    }
    function _getSettingsObjectFromFiles() {
        const settingsObject = {};
        for (const path of _settingsFilesPaths) {
            const settingsFile = _settingsFiles.get(path);
            Object.assign(settingsObject, settingsFile.getSettings());
        }
        return settingsObject;
    }

    function _anySettingsFile(predicate) {
        for (const file of _settingsFiles.values()) {
            if (predicate(file)) {
                return true;
            }
        }
        return false;
    }
    function _everySettingsFile(predicate) {
        for (const file of _settingsFiles.values()) {
            if (!predicate(file)) {
                return false;
            }
        }
        return true;
    }

    SettingsFile {
        id: defaultSettingsFile

        filePath: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/dms/settings.json"

        Component.onCompleted: {
            _registerSettingsFile(defaultSettingsFile);
        }
    }

    property bool _settingsFolderExists: false
    property bool _settingsFolderChecked: false
    function _syncSettingsFilesModels() {
        if (!_settingsFolderChecked) {
            settingsFilesModelSyncDebounce.restart();
            return;
        }
        if (!_settingsFolderExists) {
            return;
        }
        const listModel = settingsFilesListModel;
        const folderModel = settingsFolderLoader.item;

        const folderPathsSet = new Set();
        for (let i = 0; i < folderModel.count; i++) {
            const filePath = folderModel.get(i, "filePath");
            folderPathsSet.add(filePath);
            if (!_settingsFiles.has(filePath)) {
                listModel.append({
                    filePath
                });
            }
        }
        for (let i = listModel.count - 1; i >= 0; i--) {
            const filePath = listModel.get(i).filePath;
            if (!folderPathsSet.has(filePath)) {
                listModel.remove(i);
            }
        }
    }
    Timer {
        id: settingsFilesModelSyncDebounce
        interval: 50
        repeat: false
        running: false
        onTriggered: _syncSettingsFilesModels()
    }
    ListModel {
        id: settingsFilesListModel
    }
    Loader {
        id: settingsFolderLoader
        function unloadModel() {
            active = false;
        }
        sourceComponent: FolderListModel {
            id: settingsFolderModel

            property url dir: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/dms/config.d"

            folder: dir
            showDirs: false
            nameFilters: ["*.json"]
            onStatusChanged: {
                // Folder gets reset to the CWD if the directory doesn't exist.
                _settingsFolderExists = folder == dir;
                if (status !== FolderListModel.Ready) {
                    return;
                }
                _settingsFolderChecked = true;
                if (!_settingsFolderExists) {
                    Qt.callLater(() => settingsFolderLoader.unloadModel());
                }

                if (_hasLoaded) {
                    settingsFilesModelSyncDebounce.restart();
                } else {
                    _syncSettingsFilesModels();
                }
                _tryCompleteDiscovery();
            }
        }
    }

    Instantiator {
        id: settingsLoader

        model: settingsFilesListModel
        onObjectAdded: (_, file) => {
            _registerSettingsFile(file);
        }
        onObjectRemoved: (_, file) => {
            _unregisterSettingsFile(file);
            _loadSettingsOrStartIfReady();
        }
        delegate: SettingsFile {
            id: settingsFile
        }
    }

    // Our first save drops the keys a newer shell wrote, so its settings are kept for going back.
    FileView {
        id: newerSettingsBackup

        preload: false
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: pluginSettingsFile

        path: pluginSettingsPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        watchChanges: true
        onLoaded: {
            pluginSettingsFileExists = true;
            parsePluginSettings(pluginSettingsFile.text());
        }
        onLoadFailed: error => {
            const msg = String(error || "");
            const missing = _isMissingPluginSettingsError(error);
            pluginSettingsFileExists = !missing;
            if (!missing)
                log.warn("Failed to load plugin_settings.json. Error:", msg);
            _resetPluginSettings();
        }
    }

    Timer {
        id: settingsSaveDebounce
        interval: 50
        repeat: false
        running: false
        onTriggered: _saveSettings(true)
    }

    property bool pluginSettingsFileExists: false
}
