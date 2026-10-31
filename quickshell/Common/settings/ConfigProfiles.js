.pragma library
.import "./SettingsStore.js" as SettingsStore
.import "./SessionStore.js" as SessionStore
.import "./SettingsSpec.js" as SettingsSpec
.import "./SessionSpec.js" as SessionSpec
.import "../../DCommon/Common/settings/SpecUtil.js" as SpecUtil

var CATEGORIES = [
    { id: "theme", groups: ["colors", "wallpaper", "dark_mode", "app_theming", "interface_style", "shadows"] },
    { id: "layout", groups: ["bar", "frame", "dock", "desktop_widgets", "control_center", "dashboard", "compositor", "displays"] },
    { id: "appearance", groups: ["fonts_motion", "icons", "cursor"] },
    { id: "other", groups: ["time_weather", "lock_screen", "launcher", "notifications", "osd", "sound_media", "plugins", "general"] }
];

var GROUPS = CATEGORIES.reduce((all, c) => all.concat(c.groups), []);

var PLUGIN_GROUP = "plugins";

// Every persisted settings key and every session key belongs to exactly one list; tests enforce it.
var SETTINGS_MAP = {
    colors: [
        "currentThemeName", "customThemeFile", "registryThemeVariants", "currentThemeCategory", "matugenScheme",
        "matugenSmartMode", "matugenSourceMode", "matugenContrast", "matugenSeedColor", "matugenSpec",
        "generateThemeAtStartup"
    ],
    wallpaper: [
        "wallpaperFillMode", "wallpaperBackgroundColorMode", "wallpaperBackgroundCustomColor",
        "lockScreenWallpaperPath", "lockScreenWallpaperFillMode", "blurredWallpaperLayer", "blurWallpaperOnOverview"
    ],
    app_theming: [
        "runUserMatugenTemplates", "syncModeWithPortal", "terminalsAlwaysDark", "terminalOpacity", "terminalPalette",
        "runDmsMatugenTemplates", "matugenTemplateGtk", "matugenTemplateNiri", "matugenTemplateHyprland",
        "matugenTemplateMangowc", "matugenTemplateQt5ct", "matugenTemplateQt6ct", "matugenTemplateFcitx5",
        "matugenTemplateQtengine", "matugenTemplateFirefox", "matugenTemplatePywalfox", "matugenTemplateZenBrowser",
        "matugenTemplateVesktop", "matugenTemplateVencord", "matugenTemplateEquibop", "matugenTemplateGhostty",
        "matugenTemplateKitty", "matugenTemplateFoot", "matugenTemplateAlacritty", "matugenTemplateNeovim",
        "matugenTemplateWezterm", "matugenTemplateDgop", "matugenTemplateKcolorscheme", "matugenTemplateVscode",
        "matugenTemplateEmacs", "matugenTemplateZed", "matugenTemplateNeovimSettings",
        "matugenTemplateNeovimSetBackground"
    ],
    interface_style: [
        "radiusStrength", "radiusMode", "fixedRadius", "scrollbarsEnabled", "blurBorderEnabled", "blurBorderColor",
        "blurBorderCustomColor", "blurBorderOpacity", "popupTransparency", "floatingWindowSyncGlobal",
        "floatingWindowTitleBars", "floatingWindowTransparency", "floatingWindowForegroundLayers",
        "floatingWindowForegroundTransparency", "hostSurfaceColor", "hostSurfaceCustomColor", "cardSurfaceColor",
        "cardSurfaceCustomColor", "chipSurfaceColor", "chipSurfaceCustomColor", "chipSurfaceNestedColor",
        "chipSurfaceNestedCustomColor", "widgetBackgroundColor", "widgetBackgroundCustomColor",
        "widgetBackgroundCustomStrength", "widgetColorMode", "controlCenterTileColorMode", "buttonColorMode",
        "containerSaturation", "blurEnabled", "blurStrength", "blurForegroundLayers", "foregroundLayerTransparency",
        "blurLayerOutlineOpacity", "focusRingEnabled", "focusRingWidth", "focusRingColor", "controlCenterIconScale",
        "systemTrayIconTintMode", "systemTrayIconTintSaturation", "systemTrayIconTintStrength",
        "dankLauncherV2BorderEnabled", "dankLauncherV2BorderThickness", "dankLauncherV2BorderColor", "avatarRing",
        "modalDarkenBackground", "lockScreenInactiveColor", "notificationForegroundLayers"
    ],
    shadows: [
        "popoutElevationEnabled", "m3ElevationEnabled", "m3ElevationIntensity", "m3ElevationOpacity",
        "m3ElevationColorMode", "m3ElevationLightDirection", "m3ElevationCustomColor", "modalElevationEnabled",
        "barElevationEnabled", "notificationPopupShadowEnabled"
    ],
    bar: [
        "barConfigs", "barInsetPaddingShared", "barInsetPaddingSyncAll", "workspaceNameIcons"
    ],
    frame: [
        "connectedFrameBarStyleBackups", "frameEnabled", "frameThickness", "frameRounding", "frameBarSize",
        "frameShowOnOverview", "frameBlurEnabled", "frameCloseGaps", "frameLauncherEmergeSide",
        "frameLauncherArcExtender", "frameLauncherEdgeHover", "frameMode", "frameBarInsetPadding"
    ],
    dock: [
        "dockConfigs"
    ],
    desktop_widgets: [
        "desktopWidgetInstances", "desktopWidgetGroups", "desktopContextMenu"
    ],
    control_center: [
        "controlCenterWidgets", "controlCenterColumns"
    ],
    dashboard: [
        "dashTabs", "dashCards", "dashTabPosition", "dashTabsEvenlySpaced", "dashOptions"
    ],
    compositor: [
        "niriLayoutGapsOverride", "niriLayoutRadiusOverride", "niriLayoutBorderSize", "hyprlandLayoutGapsOverride",
        "hyprlandLayoutGapsOutOverride", "hyprlandLayoutRadiusOverride", "hyprlandLayoutBorderSize",
        "hyprlandResizeOnBorder", "hyprlandWindowOpacity", "hyprlandBorderGrabArea", "hyprlandBlurVariant",
        "hyprlandBlurAcrylicClarity", "hyprlandBlurAuroraIntensity", "hyprlandBlurAuroraSpeed",
        "hyprlandBlurHazeIntensity", "hyprlandBlurHazeIridescence", "hyprlandBlurRippleStrength",
        "hyprlandBlurWaterStrength", "hyprlandGlowEnabled", "hyprlandGlowRange", "hyprlandGlowRenderPower",
        "hyprlandWobbleEnabled", "hyprlandWobbleIntensity", "hyprlandWobbleStiffness", "hyprlandMotionBlurEnabled",
        "hyprlandMotionBlurSamples", "hyprlandGroupbarBlur", "hyprlandGroupbarTextPadding",
        "hyprlandGroupbarMiddleClickClose", "hyprlandGroupbarDisableWhenOnly", "hyprlandTilingLayout",
        "hyprlandDwindlePreserveSplit", "hyprlandDwindleSmartSplit", "hyprlandDwindleForceSplit",
        "hyprlandMasterOrientation", "hyprlandMasterNewStatus", "hyprlandMasterNewOnTop", "hyprlandMasterSize",
        "hyprlandScrollingDirection", "hyprlandScrollingColumnWidth", "hyprlandScrollingFullscreenOneColumn",
        "hyprlandScrollingFollowFocus", "mangoLayoutGapsOverride", "mangoLayoutGapsOutOverride",
        "mangoLayoutRadiusOverride", "mangoLayoutBorderSize", "closeNiriOverviewOnWindowFocus"
    ],
    displays: [
        "screenPreferences", "showOnLastDisplay", "frameScreenPreferences"
    ],
    fonts_motion: [
        "fontFamily", "monoFontFamily", "displayFontFamily", "fontWeight", "fontScale", "textRenderType",
        "textRenderQuality", "animationDuration", "enableRippleEffects", "popoutAnimationDuration",
        "modalAnimationDuration", "syncComponentAnimationSpeeds", "reduceMotion", "springBounce", "motionEffect",
        "notificationAnimationDuration"
    ],
    icons: [
        "iconThemeDark", "iconThemeLight", "iconThemePerMode"
    ],
    cursor: [
        "cursorSettings"
    ],
    time_weather: [
        "clockFormat", "showSeconds", "padHours12Hour", "useFahrenheit", "lockDateFormat", "useAutoLocation",
        "weatherEnabled", "firstDayOfWeek", "showWeekNumber", "windSpeedUnit", "clockDateFormat"
    ],
    lock_screen: [
        "lockScreenWidgetInstances", "lockScreenShowPowerActions", "lockScreenShowProfileImage",
        "lockScreenShowWeather", "lockScreenFontFamily", "lockScreenVideoEnabled", "lockScreenVideoCycling"
    ],
    launcher: [
        "browserPickerViewMode", "appPickerViewMode", "sortAppsAlphabetically", "appLauncherGridColumns",
        "rememberLastQuery", "rememberLastMode", "spotlightSectionViewModes",
        "appDrawerSectionViewModes", "niriOverviewOverlayEnabled", "niriOverviewLauncherStyle", "dankLauncherV2Size",
        "dankLauncherV2ShowSourceBadges", "dankLauncherV2ShowFooter", "dankLauncherV2UnloadOnClose",
        "dankLauncherV2IncludeFilesInAll", "dankLauncherV2IncludeFoldersInAll", "launcherUseOverlayLayer",
        "launcherStyle", "spotlightBarShowModeChips", "launcherPluginVisibility", "launcherPluginOrder",
        "launcherKeybinds", "launcherEnterAction"
    ],
    notifications: [
        "notificationSummaryFontSize", "notificationBodyFontSize", "notificationOverlayEnabled",
        "notificationPopupPrivacyMode", "notificationPopupBodyInvokesAction", "notificationTimeoutLow",
        "notificationTimeoutNormal", "notificationTimeoutCritical", "notificationIgnoreAppTimeout",
        "notificationCompactMode", "notificationShowTimeoutBar", "notificationDedupeEnabled",
        "notificationPopupPosition", "notificationHistorySaveLow", "notificationHistorySaveNormal",
        "notificationHistorySaveCritical", "notificationRules", "notificationDndAllowCritical",
        "notificationDndWhileScreenSharing", "notificationFocusedMonitor"
    ],
    osd: [
        "osdAlwaysShowValue", "osdPosition", "osdVolumeEnabled", "osdMediaVolumeEnabled", "osdMediaPlaybackEnabled",
        "osdBrightnessEnabled", "osdIdleInhibitorEnabled", "osdMicMuteEnabled", "osdMicVolumeEnabled",
        "osdCapsLockEnabled", "osdTouchpadEnabled", "osdPowerProfileEnabled", "osdAudioOutputEnabled",
        "osdWorkspaceEnabled"
    ],
    sound_media: [
        "audioShowStreamDevices", "audioMono", "scrollTitleEnabled", "audioVisualizerEnabled",
        "audioWheelScrollAmount", "bluetoothMprisEnabled", "mediaLyricsProviders", "soundsEnabled",
        "useSystemSoundTheme", "soundLogin", "soundNewNotification", "soundVolumeChanged", "soundPluggedIn",
        "muteSoundsWhenMediaPlaying"
    ],
    plugins: [
        "builtInPluginSettings"
    ],
    general: [
        "powerActionConfirm", "powerActionHoldDuration", "powerMenuActions", "powerMenuDefaultAction",
        "powerMenuGridLayout", "appIdSubstitutions", "centeringMode", "keybindsFloatingWindow", "wellbeingEnabled",
        "wellbeingDailyLimit", "notepadUseMonospace", "notepadFontFamily", "notepadFontSize",
        "notepadShowLineNumbers", "notepadAutoSave", "notepadSlideoutSide", "notepadDefaultMode",
        "notepadTransparencyOverride", "notepadLastCustomTransparency", "notepadUseCompositorGap", "notepadEdgeGap",
        "muxSessionFilter", "updaterCheckOnStart", "updaterIntervalSeconds", "updaterNotify",
        "updaterPauseOnBattery", "updaterNotifyMinSeconds", "updaterReopenAfterUpgrade", "updaterUpgradeInWindow",
        "clipboardClickToPaste", "clipboardEnterToPaste", "clipboardRememberTypeFilter", "clipboardUseOverlayLayer",
        "clipboardSize", "clipboardTypeFilter", "clipboardVisibleEntryActions"
    ],
    never: [
        "greeterWidgetInstances", "displayNameMode", "greeterRememberLastSession", "greeterRememberLastUser",
        "greeterEnableFprint", "greeterEnableU2f", "dmsWindowsFloatingSeeded", "focusFollowsMouse",
        "mouseAccelProfile", "mouseAccelSpeed", "mouseLeftHanded", "mouseMiddleEmulation", "mouseNaturalScroll",
        "mouseScrollFactor", "mouseScrollMethod", "touchpadAccelProfile", "touchpadAccelSpeed",
        "touchpadClickMethod", "touchpadDisableOnExternalMouse", "touchpadDisableWhileTyping", "touchpadDragLock",
        "touchpadMiddleEmulation", "touchpadNaturalScroll", "touchpadScrollFactor", "touchpadScrollMethod",
        "touchpadTapAndDrag", "touchpadTapToClick", "keyboardLayouts", "keyboardVariants", "keyboardModel",
        "keyboardOptions", "keyboardKeymapFile", "keyboardTrackLayout", "keyboardRepeatDelay", "keyboardRepeatRate",
        "keyboardNumlock", "blurBorderSeeded", "greeterAutoLogin", "greeterFollowLockScreen",
        "greeterPamExternallyManaged", "acMonitorTimeout", "acLockTimeout", "acSuspendTimeout", "acSuspendBehavior",
        "acProfileName", "acPostLockMonitorTimeout", "batteryMonitorTimeout", "batteryLockTimeout",
        "batterySuspendTimeout", "batterySuspendBehavior", "batteryProfileName", "batteryPostLockMonitorTimeout",
        "batteryChargeLimit", "batteryNotifyChargeLimit", "batteryCriticalThreshold", "batteryCriticalAnimation",
        "batteryNotifyCritical", "batteryLowThreshold", "batteryNotifyLow", "batteryChargeLimitNotificationType",
        "batteryLowNotificationType", "batteryCriticalNotificationType", "batteryAutoPowerSaver",
        "lowerDisplayRefreshRateOnBattery", "lockBeforeSuspend", "loginctlLockIntegration", "fadeToLockEnabled",
        "fadeToLockGracePeriod", "fadeToDpmsEnabled", "fadeToDpmsGracePeriod", "lockAtStartup", "enableFprint",
        "maxFprintTries", "enableU2f", "u2fMode", "lockPamPath", "lockScreenSecurityKeyShortcut",
        "lockScreenSecurityKeyShortcutEnabled", "lockPamInlineFprint", "lockPamInlineU2f",
        "lockPamExternallyManaged", "lockU2fPamPath", "displayProfiles", "displayPreviousRefreshModes",
        "displayProfileAutoSelect", "displayShowDisconnected", "displaySnapToEdge", "matugenTargetMonitor",
        "lockScreenPowerOffMonitorsOnLock", "networkPreference", "calendarBackend", "defaultTaskCalendarId",
        "launchPrefix", "muxType", "muxUseCustomCommand", "muxCustomCommand", "updaterUseCustomCommand",
        "updaterCustomCommand", "updaterTerminalAdditionalParams", "updaterIncludeFlatpak", "updaterAllowAUR",
        "lockScreenVideoPath", "customPowerActionLock", "customPowerActionLogout", "customPowerActionSuspend",
        "customPowerActionHibernate", "customPowerActionReboot", "customPowerActionPowerOff", "customPowerButtons",
        "powerMenuBootEntries", "wellbeingAppLimits", "mediaExcludePlayers", "updaterIgnoredPackages",
        "nightModeExcludedApps", "osdPositionOverrides", "nightModeExcludeFullscreen", "launcherHistoryEnabled",
        "notificationHistoryEnabled", "notificationHistoryMaxCount", "notificationHistoryMaxAgeDays"
    ]
};

var SESSION_MAP = {
    wallpaper: [
        "materialWallpapers", "materialWallpaperProfiles", "wallpaperPath", "perMonitorWallpaper",
        "perModeWallpaper", "monitorWallpapers", "monitorWallpaperFillModes", "wallpaperPathLight",
        "wallpaperPathDark", "monitorWallpapersLight", "monitorWallpapersDark", "wallpaperTransition",
        "includedTransitions", "wallpaperCyclingEnabled", "wallpaperCyclingRandom", "wallpaperCyclingRecursive",
        "wallpaperCyclingMode", "wallpaperCyclingInterval", "wallpaperCyclingTime", "wallpaperCyclingFolderPath",
        "monitorCyclingSettings"
    ],
    dark_mode: [
        "isLightMode", "themeModeAutoEnabled", "themeModeAutoMode", "themeModeStartHour", "themeModeStartMinute",
        "themeModeEndHour", "themeModeEndMinute", "themeModeShareGammaSettings"
    ],
    bar: [
        "barPinnedApps", "hiddenTrayIds", "trayItemOrder", "islandFreePositions"
    ],
    dock: [
        "dockPins"
    ],
    desktop_widgets: [
        "desktopWidgetInstancePositions", "desktopWidgetGridSettings"
    ],
    lock_screen: [
        "lockScreenAutoPositions", "lockScreenWidgetGridSettings"
    ],
    never: [
        "weatherLocation", "weatherCoordinates", "greeterAutoPositions", "doNotDisturb", "doNotDisturbUntil",
        "doNotDisturbHeldByScreenShare", "screenShareDndDismissed", "screenShareDismissedIds", "idleInhibited",
        "idleInhibitedUntil", "updaterNotifiedUnix", "updaterNotifiedCount",
        "terminalOverride", "nightModeEnabled", "nightModeTemperature", "nightModeHighTemperature",
        "nightModeAutoEnabled", "nightModeAutoMode", "nightModeStartHour", "nightModeStartMinute",
        "nightModeEndHour", "nightModeEndMinute", "nightModeTransitionMinutes", "displayGamma", "displayContrast",
        "latitude", "longitude", "nightModeUseIPLocation", "nightModeLocationName", "recentColors",
        "showThirdPartyPlugins", "pluginBrowserInstalledFirst", "pluginBrowserSortMode", "lastBrightnessDevice",
        "brightnessExponentialDevices", "brightnessUserSetValues", "brightnessExponentValues",
        "nvidiaGpuTempEnabled", "nonNvidiaGpuTempEnabled", "enabledGpuPciIds", "wifiDeviceOverride", "hiddenApps",
        "appOverrides", "searchAppActions", "vpnLastConnected", "bluetoothAdapterOverride", "lastPlayerIdentity",
        "pinnedPlayerIdentity", "deviceMaxVolumes", "hiddenOutputDeviceNames", "hiddenInputDeviceNames", "locale",
        "timeLocale", "notepadLastMode", "niriOutputSettings", "hyprlandOutputSettings", "activeConfigProfile",
        "activeDisplayProfile", "activeDisplayProfileModes", "builtInPluginState", "greeterSyncPending",
        "greeterSyncBaseline", "lastAppliedIconTheme", "launcherLastMode", "launcherLastFileSearchType",
        "launcherLastQuery", "launcherQueryHistory", "appDrawerLastMode", "niriOverviewLastMode",
        "showConfigReloadToast"
    ]
};

function normalize(groups) {
    return GROUPS.filter(g => (groups || []).includes(g));
}

function keysOf(map, groups) {
    return normalize(groups).reduce((keys, g) => keys.concat(map[g] || []), []);
}

function settingsKeys(groups) {
    return keysOf(SETTINGS_MAP, groups);
}

function sessionKeys(groups) {
    return keysOf(SESSION_MAP, groups);
}

function includesPluginSettings(groups) {
    return (groups || []).includes(PLUGIN_GROUP);
}

function pick(source, keys) {
    const out = {};
    if (!source)
        return out;
    for (const k of keys) {
        if (source[k] !== undefined)
            out[k] = SpecUtil.cloneDef(source[k]);
    }
    return out;
}

function capture(groups, settingsSnapshot, sessionValues, pluginSettings) {
    const gs = normalize(groups);
    if (!gs.length)
        return null;
    const out = {
        groups: gs,
        settings: pick(settingsSnapshot, settingsKeys(gs)),
        session: pick(sessionValues, sessionKeys(gs))
    };
    if (includesPluginSettings(gs))
        out.pluginSettings = SpecUtil.cloneDef(pluginSettings || {});
    return out;
}

function kind(value) {
    return value === null ? "null" : Array.isArray(value) ? "array" : typeof value;
}

function typed(values, spec) {
    for (const k of Object.keys(values)) {
        if (kind(values[k]) !== kind(spec[k].def))
            delete values[k];
    }
    return values;
}

// Values whose JSON kind differs from the spec default are dropped.
function scoped(profile, groups) {
    const gs = groups ? normalize(groups).filter(g => (profile.groups || []).includes(g)) : profile.groups;
    const out = {
        settingsKeys: settingsKeys(gs),
        settings: typed(pick(profile.settings, settingsKeys(gs)), SettingsSpec.SPEC),
        session: typed(pick(profile.session, sessionKeys(gs)), SessionSpec.SPEC)
    };
    if (includesPluginSettings(gs) && profile.pluginSettings)
        out.pluginSettings = SpecUtil.cloneDef(profile.pluginSettings);
    return out;
}

// A settings key missing on either side counts as its default, and a default shows as missing.
function diff(profile, current) {
    const setting = (values, key) => {
        const spec = SettingsSpec.SPEC[key];
        const v = (values || {})[key];
        return spec && v !== undefined && SpecUtil.isDefault(v, spec.def) ? undefined : v;
    };
    const stored = scoped(profile);
    const cur = current || {};
    const result = [];
    for (const group of normalize(profile.groups)) {
        const changes = [];
        const add = (source, key, c, s) => {
            if (SpecUtil.stableStringify(c) !== SpecUtil.stableStringify(s))
                changes.push({ key, source, current: SpecUtil.cloneDef(c), stored: SpecUtil.cloneDef(s) });
        };
        for (const key of SETTINGS_MAP[group] || [])
            add("settings", key, setting(cur.settings, key), setting(stored.settings, key));
        for (const key of SESSION_MAP[group] || []) {
            if (key in stored.session)
                add("session", key, (cur.session || {})[key], stored.session[key]);
        }
        if (group === PLUGIN_GROUP && stored.pluginSettings) {
            for (const id of Object.keys(stored.pluginSettings))
                add("plugins", id, (cur.pluginSettings || {})[id], stored.pluginSettings[id]);
        }
        if (changes.length) {
            changes.sort((a, b) => a.key < b.key ? -1 : a.key > b.key ? 1 : 0);
            result.push({ group, changes });
        }
    }
    return result;
}

function isNewer(profile, settingsVersion, sessionVersion) {
    return (profile.configVersion || 0) > settingsVersion || (profile.sessionConfigVersion || 0) > sessionVersion;
}

// Null when current or newer. A current profile is left alone, so keys it holds for another shell version survive.
// Migration steps that read a key outside the profile's groups see its default.
function migrate(profile, settingsVersion, sessionVersion) {
    if (isNewer(profile, settingsVersion, sessionVersion))
        return null;
    const settingsOld = (profile.configVersion || 0) < settingsVersion;
    const sessionOld = (profile.sessionConfigVersion || 0) < sessionVersion;
    if (!settingsOld && !sessionOld)
        return null;
    const out = SpecUtil.cloneDef(profile);
    const settings = settingsOld ? SettingsStore.migrateToVersion(Object.assign({ configVersion: profile.configVersion || 0 }, profile.settings), settingsVersion) : profile.settings;
    const session = sessionOld ? SessionStore.migrateToVersion(Object.assign({ configVersion: profile.sessionConfigVersion || 0 }, profile.session), sessionVersion, null) : profile.session;
    out.settings = pick(settings, settingsKeys(profile.groups));
    out.session = pick(session, sessionKeys(profile.groups));
    out.configVersion = settingsVersion;
    out.sessionConfigVersion = sessionVersion;
    if (!includesPluginSettings(profile.groups))
        delete out.pluginSettings;
    return out;
}

function rescope(profile, groups, current, settingsVersion, sessionVersion) {
    const gs = normalize(groups);
    if (!gs.length || isNewer(profile, settingsVersion, sessionVersion))
        return null;
    const kept = normalize(profile.groups).filter(g => gs.includes(g));
    const added = gs.filter(g => !kept.includes(g));
    const out = Object.assign({}, profile, {
        groups: gs,
        configVersion: settingsVersion,
        sessionConfigVersion: sessionVersion,
        settings: Object.assign(pick(profile.settings, settingsKeys(kept)), pick(current.settings, settingsKeys(added))),
        session: Object.assign(pick(profile.session, sessionKeys(kept)), pick(current.session, sessionKeys(added)))
    });
    delete out.pluginSettings;
    if (includesPluginSettings(gs))
        out.pluginSettings = SpecUtil.cloneDef(kept.includes(PLUGIN_GROUP) && profile.pluginSettings ? profile.pluginSettings : current.pluginSettings || {});
    return out;
}
