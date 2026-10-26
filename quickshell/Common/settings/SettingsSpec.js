.pragma library
.import "../../DCommon/Common/settings/SharedSettingsSpec.js" as Shared
.import "../../DCommon/Common/settings/SpecUtil.js" as Util
.import "DockConfig.js" as DockConfig

function lockWidgetDefaults() {
    return Shared.lockWidgetDefaults();
}

function greeterWidgetsFromLock(lockInstances, previous) {
    return Shared.greeterWidgetsFromLock(lockInstances, previous);
}

function greeterSessionDefault() {
    return Shared.greeterSessionDefault();
}

function greeterWidgetDefaults() {
    return Shared.greeterWidgetDefaults();
}

var LOCAL_SPEC = {
    dockConfigs: {
        def: [DockConfig.create("dock", "Dock")]
    },
    currentThemeCategory: {
        def: "generic"
    },
    matugenScheme: {
        def: "scheme-tonal-spot",
        onChange: "regenSystemThemes"
    },
    matugenSmartMode: {
        def: false,
        onChange: "regenSystemThemes"
    },
    matugenSourceMode: {
        def: "dominant",
        onChange: "regenSystemThemes"
    },
    matugenContrast: {
        def: 0,
        onChange: "regenSystemThemes"
    },
    matugenSeedColor: {
        def: "",
        onChange: "regenSystemThemes"
    },
    matugenSpec: {
        def: "2021",
        onChange: "regenSystemThemes"
    },
    runUserMatugenTemplates: {
        def: true,
        onChange: "regenSystemThemes"
    },
    matugenTargetMonitor: {
        def: "",
        onChange: "regenSystemThemes"
    },
    generateThemeAtStartup: {
        def: true
    },
    popupTransparency: {
        def: 1.0,
        coerce: Util.percentToUnit
    },
    floatingWindowSyncGlobal: {
        def: true
    },
    floatingWindowTitleBars: {
        def: true
    },
    floatingWindowTransparency: {
        def: 1.0,
        coerce: Util.percentToUnit
    },
    floatingWindowForegroundLayers: {
        def: true
    },
    floatingWindowForegroundTransparency: {
        def: 1.0,
        coerce: Util.percentToUnit
    },
    dmsWindowsFloatingSeeded: {
        def: []
    },
    hostSurfaceColor: {
        def: "default"
    },
    hostSurfaceCustomColor: {
        def: "#6750A4"
    },
    cardSurfaceColor: {
        def: "default"
    },
    cardSurfaceCustomColor: {
        def: "#6750A4"
    },
    chipSurfaceColor: {
        def: "default"
    },
    chipSurfaceCustomColor: {
        def: "#6750A4"
    },
    chipSurfaceNestedColor: {
        def: "default"
    },
    chipSurfaceNestedCustomColor: {
        def: "#6750A4"
    },
    widgetBackgroundColor: {
        def: "default"
    },
    widgetBackgroundCustomColor: {
        def: "#6750A4"
    },
    widgetBackgroundCustomStrength: {
        def: 0.50,
        coerce: Util.percentToUnit
    },
    widgetColorMode: {
        def: "default"
    },
    controlCenterTileColorMode: {
        def: "primary"
    },
    buttonColorMode: {
        def: "primary"
    },
    containerSaturation: {
        def: 100
    },
    niriLayoutGapsOverride: {
        def: -1,
        onChange: "updateCompositorLayout"
    },
    niriLayoutRadiusOverride: {
        def: -1,
        onChange: "updateCompositorLayout"
    },
    niriLayoutBorderSize: {
        def: -1,
        onChange: "updateCompositorLayout"
    },
    hyprlandLayoutGapsOverride: {
        def: -1,
        onChange: "updateCompositorLayout"
    },
    hyprlandLayoutGapsOutOverride: {
        def: -1,
        onChange: "updateCompositorLayout"
    },
    hyprlandLayoutRadiusOverride: {
        def: -1,
        onChange: "updateCompositorLayout"
    },
    hyprlandLayoutBorderSize: {
        def: -1,
        onChange: "updateCompositorLayout"
    },
    hyprlandResizeOnBorder: {
        def: false,
        onChange: "updateCompositorLayout"
    },
    hyprlandWindowOpacity: {
        def: 100,
        onChange: "updateCompositorLayout"
    },
    hyprlandBorderGrabArea: {
        def: 15,
        onChange: "updateCompositorLayout"
    },
    hyprlandBlurVariant: {
        def: "kawase",
        onChange: "updateCompositorLayout"
    },
    hyprlandBlurAcrylicClarity: {
        def: 82,
        onChange: "updateCompositorLayout"
    },
    hyprlandBlurAuroraIntensity: {
        def: 35,
        onChange: "updateCompositorLayout"
    },
    hyprlandBlurAuroraSpeed: {
        def: 1,
        onChange: "updateCompositorLayout"
    },
    hyprlandBlurHazeIntensity: {
        def: 35,
        onChange: "updateCompositorLayout"
    },
    hyprlandBlurHazeIridescence: {
        def: 70,
        onChange: "updateCompositorLayout"
    },
    hyprlandBlurRippleStrength: {
        def: 30,
        onChange: "updateCompositorLayout"
    },
    hyprlandBlurWaterStrength: {
        def: 32,
        onChange: "updateCompositorLayout"
    },
    hyprlandGlowEnabled: {
        def: false,
        onChange: "updateCompositorLayout"
    },
    hyprlandGlowRange: {
        def: 10,
        onChange: "updateCompositorLayout"
    },
    hyprlandGlowRenderPower: {
        def: 3,
        onChange: "updateCompositorLayout"
    },
    hyprlandWobbleEnabled: {
        def: false,
        onChange: "updateCompositorLayout"
    },
    hyprlandWobbleIntensity: {
        def: 20,
        onChange: "updateCompositorLayout"
    },
    hyprlandWobbleStiffness: {
        def: 200,
        onChange: "updateCompositorLayout"
    },
    hyprlandMotionBlurEnabled: {
        def: false,
        onChange: "updateCompositorLayout"
    },
    hyprlandMotionBlurSamples: {
        def: 7,
        onChange: "updateCompositorLayout"
    },
    hyprlandGroupbarBlur: {
        def: false,
        onChange: "updateCompositorLayout"
    },
    hyprlandGroupbarTextPadding: {
        def: 0,
        onChange: "updateCompositorLayout"
    },
    hyprlandGroupbarMiddleClickClose: {
        def: true,
        onChange: "updateCompositorLayout"
    },
    hyprlandGroupbarDisableWhenOnly: {
        def: false,
        onChange: "updateCompositorLayout"
    },
    hyprlandTilingLayout: {
        def: "",
        onChange: "updateCompositorLayout"
    },
    hyprlandDwindlePreserveSplit: {
        def: false,
        onChange: "updateCompositorLayout"
    },
    hyprlandDwindleSmartSplit: {
        def: false,
        onChange: "updateCompositorLayout"
    },
    hyprlandDwindleForceSplit: {
        def: 0,
        onChange: "updateCompositorLayout"
    },
    hyprlandMasterOrientation: {
        def: "left",
        onChange: "updateCompositorLayout"
    },
    hyprlandMasterNewStatus: {
        def: "slave",
        onChange: "updateCompositorLayout"
    },
    hyprlandMasterNewOnTop: {
        def: false,
        onChange: "updateCompositorLayout"
    },
    hyprlandMasterSize: {
        def: 55,
        onChange: "updateCompositorLayout"
    },
    hyprlandScrollingDirection: {
        def: "right",
        onChange: "updateCompositorLayout"
    },
    hyprlandScrollingColumnWidth: {
        def: 50,
        onChange: "updateCompositorLayout"
    },
    hyprlandScrollingFullscreenOneColumn: {
        def: true,
        onChange: "updateCompositorLayout"
    },
    hyprlandScrollingFollowFocus: {
        def: true,
        onChange: "updateCompositorLayout"
    },
    mangoLayoutGapsOverride: {
        def: -1,
        onChange: "updateCompositorLayout"
    },
    mangoLayoutGapsOutOverride: {
        def: -1,
        onChange: "updateCompositorLayout"
    },
    mangoLayoutRadiusOverride: {
        def: -1,
        onChange: "updateCompositorLayout"
    },
    mangoLayoutBorderSize: {
        def: -1,
        onChange: "updateCompositorLayout"
    },
    focusFollowsMouse: {
        def: -1,
        onChange: "updateCompositorInput"
    },
    mouseAccelProfile: {
        def: "default",
        onChange: "updateCompositorInput"
    },
    mouseAccelSpeed: {
        def: 0.0,
        onChange: "updateCompositorInput"
    },
    mouseLeftHanded: {
        def: false,
        onChange: "updateCompositorInput"
    },
    mouseMiddleEmulation: {
        def: false,
        onChange: "updateCompositorInput"
    },
    mouseNaturalScroll: {
        def: false,
        onChange: "updateCompositorInput"
    },
    mouseScrollFactor: {
        def: 1.0,
        onChange: "updateCompositorInput"
    },
    mouseScrollMethod: {
        def: "default",
        onChange: "updateCompositorInput"
    },
    touchpadAccelProfile: {
        def: "default",
        onChange: "updateCompositorInput"
    },
    touchpadAccelSpeed: {
        def: 0.0,
        onChange: "updateCompositorInput"
    },
    touchpadClickMethod: {
        def: "default",
        onChange: "updateCompositorInput"
    },
    touchpadDisableOnExternalMouse: {
        def: false,
        onChange: "updateCompositorInput"
    },
    touchpadDisableWhileTyping: {
        def: true,
        onChange: "updateCompositorInput"
    },
    touchpadDragLock: {
        def: false,
        onChange: "updateCompositorInput"
    },
    touchpadMiddleEmulation: {
        def: false,
        onChange: "updateCompositorInput"
    },
    touchpadNaturalScroll: {
        def: true,
        onChange: "updateCompositorInput"
    },
    touchpadScrollFactor: {
        def: 1.0,
        onChange: "updateCompositorInput"
    },
    touchpadScrollMethod: {
        def: "default",
        onChange: "updateCompositorInput"
    },
    touchpadTapAndDrag: {
        def: true,
        onChange: "updateCompositorInput"
    },
    touchpadTapToClick: {
        def: true,
        onChange: "updateCompositorInput"
    },
    keyboardLayouts: {
        def: "",
        onChange: "updateCompositorInput"
    },
    keyboardVariants: {
        def: "",
        onChange: "updateCompositorInput"
    },
    keyboardModel: {
        def: "",
        onChange: "updateCompositorInput"
    },
    keyboardOptions: {
        def: "",
        onChange: "updateCompositorInput"
    },
    keyboardKeymapFile: {
        def: "",
        onChange: "updateCompositorInput"
    },
    keyboardTrackLayout: {
        def: "",
        onChange: "updateCompositorInput"
    },
    keyboardRepeatDelay: {
        def: 0,
        onChange: "updateCompositorInput"
    },
    keyboardRepeatRate: {
        def: 0,
        onChange: "updateCompositorInput"
    },
    keyboardNumlock: {
        def: false,
        onChange: "updateCompositorInput"
    },
    firstDayOfWeek: {
        def: -1
    },
    showWeekNumber: {
        def: false
    },
    calendarBackend: {
        def: "auto"
    },
    defaultTaskCalendarId: {
        def: ""
    },
    audioShowStreamDevices: {
        def: false
    },
    audioMono: {
        def: false
    },
    windSpeedUnit: {
        def: "kmh"
    },
    syncComponentAnimationSpeeds: {
        def: true
    },
    popoutAnimationDuration: {
        def: 150
    },
    modalAnimationDuration: {
        def: 150
    },
    reduceMotion: {
        def: false
    },
    springBounce: {
        def: 1
    },
    motionEffect: {
        def: 0
    },
    m3ElevationEnabled: {
        def: true
    },
    m3ElevationIntensity: {
        def: 12
    },
    m3ElevationOpacity: {
        def: 30
    },
    m3ElevationColorMode: {
        def: "default"
    },
    m3ElevationLightDirection: {
        def: "top"
    },
    m3ElevationCustomColor: {
        def: "#000000"
    },
    modalElevationEnabled: {
        def: true
    },
    barElevationEnabled: {
        def: true
    },
    blurEnabled: {
        def: false
    },
    blurStrength: {
        def: 0,
        onChange: "updateBlurStrength"
    },
    blurBorderSeeded: {
        def: false
    },
    blurForegroundLayers: {
        def: true
    },
    foregroundLayerTransparency: {
        def: 1.0,
        coerce: Util.percentToUnit
    },
    blurLayerOutlineOpacity: {
        def: 0,
        coerce: Util.percentToUnit
    },
    focusRingEnabled: {
        def: true
    },
    focusRingWidth: {
        def: 1.5
    },
    focusRingColor: {
        def: "primary"
    },
    blurredWallpaperLayer: {
        def: false
    },
    blurWallpaperOnOverview: {
        def: false
    },
    systemTrayIconTintMode: {
        def: "none"
    },
    systemTrayIconTintSaturation: {
        def: 50
    },
    systemTrayIconTintStrength: {
        def: 135
    },
    controlCenterColumns: {
        def: 8
    },
    controlCenterIconScale: {
        def: 1.0
    },
    controlCenterWidgets: {
        def: [
            {
                id: "user",
                enabled: true,
                w: 5,
                h: 1
            },
            {
                id: "settings",
                enabled: true,
                w: 1,
                h: 1,
                small: true
            },
            {
                id: "lock",
                enabled: true,
                w: 1,
                h: 1,
                small: true
            },
            {
                id: "power",
                enabled: true,
                w: 1,
                h: 1,
                small: true
            },
            {
                id: "brightnessSlider",
                enabled: true,
                w: 4,
                h: 1
            },
            {
                id: "volumeSlider",
                enabled: true,
                w: 4,
                h: 1
            },
            {
                id: "wifi",
                enabled: true,
                w: 4,
                h: 1
            },
            {
                id: "bluetooth",
                enabled: true,
                w: 4,
                h: 1
            },
            {
                id: "audioOutput",
                enabled: true,
                w: 4,
                h: 1
            },
            {
                id: "audioInput",
                enabled: true,
                w: 4,
                h: 1
            },
            {
                id: "darkMode",
                enabled: true,
                w: 2,
                h: 1
            },
            {
                id: "nightMode",
                enabled: true,
                w: 2,
                h: 1
            },
            {
                id: "doNotDisturb",
                enabled: true,
                w: 2,
                h: 1
            },
            {
                id: "idleInhibitor",
                enabled: true,
                w: 2,
                h: 1
            },
            {
                id: "battery",
                enabled: true,
                w: 4,
                h: 1
            },
            {
                id: "diskUsage",
                enabled: true,
                w: 4,
                h: 1
            },
            {
                id: "runningApps",
                enabled: true,
                w: 7,
                h: 1,
                small: true
            },
            {
                id: "edit",
                enabled: true,
                w: 1,
                h: 1,
                small: true
            }
        ]
    },
    workspaceNameIcons: {
        def: {}
    },
    scrollTitleEnabled: {
        def: true
    },
    audioVisualizerEnabled: {
        def: true
    },
    audioWheelScrollAmount: {
        def: 5
    },
    bluetoothMprisEnabled: {
        def: false
    },
    mediaExcludePlayers: {
        def: []
    },
    mediaLyricsProviders: {
        def: [
            {
                id: "betterlyrics",
                enabled: true
            },
            {
                id: "unison",
                enabled: true
            },
            {
                id: "lyricsplus",
                enabled: true
            },
            {
                id: "kugou",
                enabled: true
            },
            {
                id: "lrclib",
                enabled: true
            },
            {
                id: "youtubemusic",
                enabled: true
            }
        ]
    },
    appIdSubstitutions: {
        def: [
            {
                pattern: "Spotify",
                replacement: "spotify",
                type: "exact"
            },
            {
                pattern: "beepertexts",
                replacement: "beeper",
                type: "exact"
            },
            {
                pattern: "home assistant desktop",
                replacement: "homeassistant-desktop",
                type: "exact"
            },
            {
                pattern: "com.transmissionbt.transmission",
                replacement: "transmission-gtk",
                type: "contains"
            },
            {
                pattern: "^steam_app_(\\d+)$",
                replacement: "steam_icon_$1",
                type: "regex"
            }
        ]
    },
    centeringMode: {
        def: "index"
    },
    clockDateFormat: {
        def: ""
    },
    greeterAutoLogin: {
        def: false,
        onChange: "scheduleGreeterAutoLoginSync"
    },
    greeterFollowLockScreen: {
        def: true
    },
    greeterPamExternallyManaged: {
        def: false,
        onChange: "markGreeterSyncPending"
    },
    browserPickerViewMode: {
        def: "grid"
    },
    appPickerViewMode: {
        def: "grid"
    },
    sortAppsAlphabetically: {
        def: false
    },
    appLauncherGridColumns: {
        def: 4
    },
    closeNiriOverviewOnWindowFocus: {
        def: true
    },
    rememberLastQuery: {
        def: false
    },
    launcherHistoryEnabled: {
        def: true,
        onChange: "syncLauncherHistory"
    },
    launcherEnterAction: {
        def: "launch"
    },
    rememberLastMode: {
        def: true
    },
    spotlightSectionViewModes: {
        def: {}
    },
    appDrawerSectionViewModes: {
        def: {}
    },
    niriOverviewOverlayEnabled: {
        def: true
    },
    niriOverviewLauncherStyle: {
        def: "full"
    },
    dankLauncherV2Size: {
        def: "compact"
    },
    dankLauncherV2ShowSourceBadges: {
        def: true
    },
    dankLauncherV2BorderEnabled: {
        def: false
    },
    dankLauncherV2BorderThickness: {
        def: 2
    },
    dankLauncherV2BorderColor: {
        def: "primary"
    },
    dankLauncherV2ShowFooter: {
        def: true
    },
    dankLauncherV2UnloadOnClose: {
        def: false
    },
    dankLauncherV2IncludeFilesInAll: {
        def: false
    },
    dankLauncherV2IncludeFoldersInAll: {
        def: false
    },
    launcherUseOverlayLayer: {
        def: false
    },
    launcherStyle: {
        def: "full"
    },
    avatarRing: {
        def: "none"
    },
    spotlightBarShowModeChips: {
        def: false
    },
    keybindsFloatingWindow: {
        def: false
    },
    dashTabPosition: {
        def: "auto"
    },
    dashTabsEvenlySpaced: {
        def: true
    },
    dashTabs: {
        def: [
            {
                id: "overview",
                enabled: true
            },
            {
                id: "media",
                enabled: true
            },
            {
                id: "wallpaper",
                enabled: true
            },
            {
                id: "weather",
                enabled: true
            },
            {
                id: "wellbeing",
                enabled: true
            },
            {
                id: "notifications",
                enabled: false
            }
        ]
    },
    dashCards: {
        def: [
            {
                id: "clock",
                w: 2,
                h: 1
            },
            {
                id: "weather",
                w: 1,
                h: 1
            },
            {
                id: "notifications",
                w: 3,
                h: 5
            },
            {
                id: "calendar",
                w: 3,
                h: 3
            },
            {
                id: "media",
                w: 3,
                h: 1
            }
        ]
    },
    dashOptions: {
        def: {}
    },
    wellbeingEnabled: {
        def: true
    },
    wellbeingDailyLimit: {
        def: 0
    },
    wellbeingAppLimits: {
        def: {}
    },
    networkPreference: {
        def: "auto"
    },
    iconThemeDark: {
        def: "System Default",
        onChange: "applyStoredIconTheme"
    },
    iconThemeLight: {
        def: "System Default",
        onChange: "applyStoredIconTheme"
    },
    iconThemePerMode: {
        def: false,
        onChange: "applyStoredIconTheme"
    },
    availableIconThemes: {
        def: ["System Default"],
        persist: false
    },
    systemDefaultIconTheme: {
        def: "",
        persist: false
    },
    cursorSettings: {
        def: {
            theme: "System Default",
            size: 24,
            niri: {
                hideWhenTyping: false,
                hideAfterInactiveMs: 0
            },
            hyprland: {
                hideOnKeyPress: false,
                hideOnTouch: false,
                inactiveTimeout: 0
            },
            dwl: {
                cursorHideTimeout: 0
            },
            mango: {
                cursorHideTimeout: 0
            }
        },
        onChange: "updateCompositorCursor"
    },
    availableCursorThemes: {
        def: ["System Default"],
        persist: false
    },
    systemDefaultCursorTheme: {
        def: "",
        persist: false
    },
    notepadUseMonospace: {
        def: true
    },
    notepadFontFamily: {
        def: ""
    },
    notepadFontSize: {
        def: 14
    },
    notificationSummaryFontSize: {
        def: 0
    },
    notificationBodyFontSize: {
        def: 0
    },
    notepadShowLineNumbers: {
        def: false
    },
    notepadAutoSave: {
        def: false
    },
    notepadSlideoutSide: {
        def: "right"
    },
    notepadDefaultMode: {
        def: "slideout"
    },
    notepadTransparencyOverride: {
        def: -1
    },
    notepadLastCustomTransparency: {
        def: 0.7
    },
    notepadUseCompositorGap: {
        def: false
    },
    notepadEdgeGap: {
        def: 0
    },
    soundsEnabled: {
        def: true
    },
    useSystemSoundTheme: {
        def: false
    },
    soundLogin: {
        def: false
    },
    soundNewNotification: {
        def: true
    },
    soundVolumeChanged: {
        def: true
    },
    soundPluggedIn: {
        def: true
    },
    muteSoundsWhenMediaPlaying: {
        def: true
    },
    acMonitorTimeout: {
        def: 0
    },
    acLockTimeout: {
        def: 0
    },
    acSuspendTimeout: {
        def: 0
    },
    acSuspendBehavior: {
        def: 0
    },
    acProfileName: {
        def: ""
    },
    acPostLockMonitorTimeout: {
        def: 0
    },
    batteryMonitorTimeout: {
        def: 0
    },
    batteryLockTimeout: {
        def: 0
    },
    batterySuspendTimeout: {
        def: 0
    },
    batterySuspendBehavior: {
        def: 0
    },
    batteryProfileName: {
        def: ""
    },
    batteryPostLockMonitorTimeout: {
        def: 0
    },
    batteryChargeLimit: {
        def: 100
    },
    batteryNotifyChargeLimit: {
        def: false
    },
    batteryCriticalThreshold: {
        def: 10
    },
    batteryCriticalAnimation: {
        def: true
    },
    batteryNotifyCritical: {
        def: true
    },
    batteryLowThreshold: {
        def: 20
    },
    batteryNotifyLow: {
        def: false
    },
    batteryChargeLimitNotificationType: {
        def: 0
    },
    batteryLowNotificationType: {
        def: 0
    },
    batteryCriticalNotificationType: {
        def: 1
    },
    batteryAutoPowerSaver: {
        def: false
    },
    lowerDisplayRefreshRateOnBattery: {
        def: false
    },
    lockBeforeSuspend: {
        def: false
    },
    keepAwakeBlocksSleep: {
        def: false
    },
    loginctlLockIntegration: {
        def: true
    },
    fadeToLockEnabled: {
        def: true
    },
    fadeToLockGracePeriod: {
        def: 5
    },
    fadeToDpmsEnabled: {
        def: true
    },
    fadeToDpmsGracePeriod: {
        def: 5
    },
    launchPrefix: {
        def: ""
    },
    syncModeWithPortal: {
        def: true
    },
    terminalsAlwaysDark: {
        def: false,
        onChange: "regenSystemThemes"
    },
    terminalOpacity: {
        def: 100,
        onChange: "regenSystemThemes"
    },
    terminalPalette: {
        def: "default",
        onChange: "regenSystemThemes"
    },
    muxType: {
        def: "tmux"
    },
    muxUseCustomCommand: {
        def: false
    },
    muxCustomCommand: {
        def: ""
    },
    muxSessionFilter: {
        def: ""
    },
    runDmsMatugenTemplates: {
        def: true
    },
    matugenTemplateGtk: {
        def: true
    },
    matugenTemplateNiri: {
        def: true
    },
    matugenTemplateHyprland: {
        def: true
    },
    matugenTemplateMangowc: {
        def: true
    },
    matugenTemplateQt5ct: {
        def: true
    },
    matugenTemplateQt6ct: {
        def: true
    },
    matugenTemplateFcitx5: {
        def: true
    },
    matugenTemplateQtengine: {
        def: true
    },
    matugenTemplateFirefox: {
        def: true
    },
    matugenTemplatePywalfox: {
        def: true
    },
    matugenTemplateZenBrowser: {
        def: true
    },
    matugenTemplateVesktop: {
        def: true
    },
    matugenTemplateVencord: {
        def: true
    },
    matugenTemplateEquibop: {
        def: true
    },
    matugenTemplateGhostty: {
        def: true
    },
    matugenTemplateKitty: {
        def: true
    },
    matugenTemplateFoot: {
        def: true
    },
    matugenTemplateAlacritty: {
        def: true
    },
    matugenTemplateNeovim: {
        def: false
    },
    matugenTemplateWezterm: {
        def: true
    },
    matugenTemplateDgop: {
        def: true
    },
    matugenTemplateKcolorscheme: {
        def: true
    },
    matugenTemplateVscode: {
        def: true
    },
    matugenTemplateEmacs: {
        def: true
    },
    matugenTemplateZed: {
        def: true
    },
    matugenTemplateNeovimSettings: {
        def: {
            dark: {
                baseTheme: "github_dark",
                harmony: 0.5
            },
            light: {
                baseTheme: "github_light",
                harmony: 0.5
            }
        }
    },
    matugenTemplateNeovimSetBackground: {
        def: true
    },
    notificationOverlayEnabled: {
        def: false
    },
    notificationPopupShadowEnabled: {
        def: true
    },
    notificationPopupPrivacyMode: {
        def: false
    },
    notificationPopupBodyInvokesAction: {
        def: false
    },
    notificationForegroundLayers: {
        def: true
    },
    overviewRows: {
        def: 2,
        persist: false
    },
    overviewColumns: {
        def: 5,
        persist: false
    },
    overviewScale: {
        def: 0.16,
        persist: false
    },
    modalDarkenBackground: {
        def: true
    },
    lockScreenPowerOffMonitorsOnLock: {
        def: false
    },
    lockAtStartup: {
        def: false
    },
    enableFprint: {
        def: false
    },
    maxFprintTries: {
        def: 15
    },
    enableU2f: {
        def: false,
        onChange: "scheduleAuthApply"
    },
    u2fMode: {
        def: "or"
    },
    lockPamPath: {
        def: ""
    },
    lockScreenSecurityKeyShortcut: {
        def: "Ctrl+Q"
    },
    lockScreenSecurityKeyShortcutEnabled: {
        def: false
    },
    lockPamInlineFprint: {
        def: false
    },
    lockPamInlineU2f: {
        def: false
    },
    lockPamExternallyManaged: {
        def: false
    },
    lockU2fPamPath: {
        def: ""
    },
    lockScreenInactiveColor: {
        def: "#000000"
    },
    lockScreenVideoEnabled: {
        def: false
    },
    lockScreenVideoPath: {
        def: ""
    },
    lockScreenVideoCycling: {
        def: false
    },
    notificationTimeoutLow: {
        def: 5000
    },
    notificationTimeoutNormal: {
        def: 5000
    },
    notificationTimeoutCritical: {
        def: 0
    },
    notificationIgnoreAppTimeout: {
        def: false
    },
    notificationCompactMode: {
        def: false
    },
    notificationShowTimeoutBar: {
        def: false
    },
    notificationDedupeEnabled: {
        def: true
    },
    notificationPopupPosition: {
        def: 0
    },
    notificationAnimationDuration: {
        def: 200
    },
    notificationHistoryEnabled: {
        def: true
    },
    notificationHistoryMaxCount: {
        def: 50
    },
    notificationHistoryMaxAgeDays: {
        def: 7
    },
    notificationHistorySaveLow: {
        def: true
    },
    notificationHistorySaveNormal: {
        def: true
    },
    notificationHistorySaveCritical: {
        def: true
    },
    notificationRules: {
        def: []
    },
    notificationDndAllowCritical: {
        def: true
    },
    notificationDndWhileScreenSharing: {
        def: true
    },
    notificationFocusedMonitor: {
        def: false
    },
    osdAlwaysShowValue: {
        def: false
    },
    osdPosition: {
        def: 5
    },
    osdPositionOverrides: {
        def: {}
    },
    osdVolumeEnabled: {
        def: true
    },
    osdMediaVolumeEnabled: {
        def: true
    },
    osdMediaPlaybackEnabled: {
        def: false
    },
    osdBrightnessEnabled: {
        def: true
    },
    osdIdleInhibitorEnabled: {
        def: true
    },
    osdMicMuteEnabled: {
        def: true
    },
    osdMicVolumeEnabled: {
        def: true
    },
    osdCapsLockEnabled: {
        def: true
    },
    osdTouchpadEnabled: {
        def: true
    },
    osdPowerProfileEnabled: {
        def: false
    },
    osdAudioOutputEnabled: {
        def: true
    },
    osdWorkspaceEnabled: {
        def: false
    },
    customPowerActionLock: {
        def: ""
    },
    customPowerActionLogout: {
        def: ""
    },
    customPowerActionSuspend: {
        def: ""
    },
    customPowerActionHibernate: {
        def: ""
    },
    customPowerActionReboot: {
        def: ""
    },
    customPowerActionPowerOff: {
        def: ""
    },
    customPowerButtons: {
        def: []
    },
    powerMenuBootEntries: {
        def: []
    },
    powerMenuFirmwareSetup: {
        def: false
    },
    updaterCheckOnStart: {
        def: false
    },
    updaterUseCustomCommand: {
        def: false
    },
    updaterCustomCommand: {
        def: ""
    },
    updaterTerminalAdditionalParams: {
        def: ""
    },
    updaterIntervalSeconds: {
        def: 86400
    },
    updaterNotify: {
        def: false
    },
    updaterPauseOnBattery: {
        def: false
    },
    // 0 = every time the count grows
    updaterNotifyMinSeconds: {
        def: 86400
    },
    updaterIncludeFlatpak: {
        def: true
    },
    updaterAllowAUR: {
        def: true
    },
    updaterReopenAfterUpgrade: {
        def: true
    },
    updaterUpgradeInWindow: {
        def: false
    },
    updaterIgnoredPackages: {
        def: []
    },
    screenPreferences: {
        def: {}
    },
    showOnLastDisplay: {
        def: {}
    },
    displayProfiles: {
        def: {}
    },
    displayPreviousRefreshModes: {
        def: {}
    },
    displayProfileAutoSelect: {
        def: false
    },
    displayShowDisconnected: {
        def: false
    },
    displaySnapToEdge: {
        def: true
    },
    connectedFrameBarStyleBackups: {
        def: {}
    },
    barConfigs: {
        def: [
            {
                id: "default",
                name: "Main Bar",
                enabled: true,
                position: 0,
                screenPreferences: ["all"],
                showOnLastDisplay: true,
                leftWidgets: ["launcherButton", "workspaceSwitcher", "focusedWindow"],
                centerWidgets: ["music", "clock", "weather"],
                rightWidgets: ["systemTray", "clipboard", "cpuUsage", "memUsage", "notificationButton", "battery", "controlCenterButton"],
                spacing: 4,
                innerPadding: 2,
                barInsetPadding: -1,
                barLengthPadding: 0,
                barLengthMode: "full",
                barLengthPercent: 80,
                bottomGap: 0,
                attachToScreenEdge: false,
                followInterfaceStyle: true,
                transparency: 1.0,
                surfaceColor: "default",
                surfaceCustomColor: "#6750A4",
                widgetFollowInterfaceStyle: true,
                widgetTransparency: 1.0,
                squareCorners: false,
                noBackground: false,
                widgetStyle: "pills",
                maximizeWidgetIcons: false,
                maximizeWidgetText: false,
                widgetPadding: 8,
                batteryColorMode: "theme",
                gothCornersEnabled: false,
                gothCornerRadiusOverride: false,
                gothCornerRadiusValue: 12,
                borderEnabled: false,
                borderColor: "surfaceText",
                borderOpacity: 1.0,
                borderThickness: 1,
                widgetOutlineEnabled: false,
                widgetOutlineColor: "primary",
                widgetOutlineOpacity: 1.0,
                widgetOutlineThickness: 1,
                fontScale: 1.0,
                iconScale: 1.0,
                autoHide: false,
                autoHideStrict: false,
                autoHideDelay: 250,
                showOnWindowsOpen: false,
                openOnOverview: false,
                visible: true,
                popupGapsAuto: true,
                popupGapsManual: 4,
                maximizeDetection: true,
                useOverlayLayer: false,
                scrollEnabled: true,
                scrollXBehavior: "focusWindow",
                scrollYBehavior: "workspace",
                middleClickAction: "none",
                rightClickAction: "none",
                clickActionFollowMouse: false,
                shadowIntensity: 0,
                shadowOpacity: 60,
                shadowColorMode: "default",
                shadowCustomColor: "#000000",
                shadowDirectionMode: "inherit",
                shadowDirection: "top",
                clickThrough: false,
                hoverPopouts: false,
                hoverPopoutDelay: 150
            }
        ],
        onChange: "updateBarConfigs"
    },
    desktopWidgetInstances: {
        def: []
    },
    desktopWidgetGroups: {
        def: []
    },
    desktopContextMenu: {
        def: "auto"
    },
    builtInPluginSettings: {
        def: {}
    },
    clipboardClickToPaste: {
        def: false
    },
    clipboardEnterToPaste: {
        def: false
    },
    clipboardRememberTypeFilter: {
        def: false
    },
    clipboardUseOverlayLayer: {
        def: false
    },
    clipboardSize: {
        def: "compact"
    },
    clipboardTypeFilter: {
        def: "all"
    },
    clipboardVisibleEntryActions: {
        def: ["pin", "edit", "delete"]
    },
    launcherPluginVisibility: {
        def: {}
    },
    launcherPluginOrder: {
        def: []
    },
    launcherKeybinds: {
        def: {}
    },
    frameEnabled: {
        def: false
    },
    frameThickness: {
        def: 16
    },
    frameRounding: {
        def: 23
    },
    frameScreenPreferences: {
        def: ["all"]
    },
    frameBarSize: {
        def: 40
    },
    frameShowOnOverview: {
        def: false
    },
    frameBlurEnabled: {
        def: true
    },
    frameCloseGaps: {
        def: true
    },
    frameLauncherEmergeSide: {
        def: "bottom"
    },
    frameLauncherArcExtender: {
        def: false
    },
    frameLauncherEdgeHover: {
        def: false
    },
    frameMode: {
        def: "connected"
    },
    barInsetPaddingShared: {
        def: -1
    },
    barInsetPaddingSyncAll: {
        def: false
    },
    frameBarInsetPadding: {
        def: -1
    },
    nightModeExcludeFullscreen: {
        def: false
    },
    nightModeExcludedApps: {
        def: []
    }
};

var SPEC = Util.mergeSpec(Shared.SPEC, LOCAL_SPEC);

function getValidKeys() {
    return Object.keys(SPEC).filter(function (k) {
        return SPEC[k].persist !== false;
    }).concat(["configVersion"]);
}

function set(root, key, value, saveFn, hooks) {
    if (!(key in SPEC))
        return;
    if (value === undefined || value === null)
        value = Util.cloneDef(SPEC[key].def);
    var oldValue = root[key];
    root[key] = value;
    var hookName = SPEC[key].onChange;
    if (hookName && hooks && hooks[hookName]) {
        hooks[hookName](root, key, oldValue);
    }
    saveFn();
}
