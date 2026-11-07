.pragma library
.import "./SettingsSpec.js" as SpecModule
.import "../../DCommon/Common/settings/SpecUtil.js" as Util
.import "../../DCommon/Common/Shape.js" as Shape
.import "./BarWidgetDefaults.js" as WidgetDefaults
.import "./DockConfig.js" as DockConfig
.import "./DensityPresets.js" as DensityPresets
.import "../GridLayout.js" as GridLayout

var PIN_KEYS = ["brightnessDevicePins", "wifiNetworkPins", "bluetoothDevicePins", "audioInputDevicePins", "audioOutputDevicePins"];

var SESSION_MOVED_KEYS = ["niriOutputSettings", "hyprlandOutputSettings", "activeDisplayProfile", "activeDisplayProfileModes", "desktopWidgetGridSettings", "greeterSyncPending", "greeterSyncBaseline", "lastAppliedIconTheme"];
var CACHE_MOVED_KEYS = ["browserUsageHistory", "filePickerUsageHistory"];
var SESSION_BACKED_PLUGIN_IDS = ["dankNotepadModule"];

// Superseded by desktopWidgetInstances at v4; nothing has written them since
var STALE_WIDGET_KEYS = ["desktopClockEnabled", "desktopClockStyle", "desktopClockTransparency", "desktopClockColorMode", "desktopClockCustomColor", "desktopClockShowDate", "desktopClockShowAnalogNumbers", "desktopClockShowAnalogSeconds", "desktopClockX", "desktopClockY", "desktopClockWidth", "desktopClockHeight", "desktopClockDisplayPreferences", "systemMonitorEnabled", "systemMonitorShowHeader", "systemMonitorTransparency", "systemMonitorColorMode", "systemMonitorCustomColor", "systemMonitorShowCpu", "systemMonitorShowCpuGraph", "systemMonitorShowCpuTemp", "systemMonitorShowGpuTemp", "systemMonitorGpuPciId", "systemMonitorShowMemory", "systemMonitorShowMemoryGraph", "systemMonitorShowNetwork", "systemMonitorShowNetworkGraph", "systemMonitorShowDisk", "systemMonitorShowTopProcesses", "systemMonitorTopProcessCount", "systemMonitorTopProcessSortBy", "systemMonitorGraphInterval", "systemMonitorLayoutMode", "systemMonitorX", "systemMonitorY", "systemMonitorWidth", "systemMonitorHeight", "systemMonitorDisplayPreferences", "systemMonitorVariants", "desktopWidgetPositions"];

var BAR_WIDGET_LIST_KEYS = ["leftWidgets", "centerWidgets", "rightWidgets"];
var CC_HEADER_IDS = ["userCard", "quickActions", "header"];
var CC_ACTION_TILE_IDS = ["settings", "lock", "power"];
var CC_USER_KEYS = ["w", "h", "col", "row", "hostname", "compositor", "uptime", "badge", "background"];
var CC_FULL_HEIGHT_IDS = ["user", "volumeSlider", "inputVolumeSlider", "brightnessSlider"];
// Grid rules as of v41, frozen for that migration.
var CC_V41_GRID_STEP = 0.5;
var CC_V41_DEFAULT_COLUMNS = 8;
var CC_V41_MINIMUM_COLUMNS = 6;
var CC_V41_SLIDER_IDS = ["volumeSlider", "inputVolumeSlider", "brightnessSlider"];
var CC_V41_FOOTER_CELLS = {
    "runningApps": 4,
    "user": 3,
    "volumeSlider": 4,
    "inputVolumeSlider": 4,
    "brightnessSlider": 4
};

var REMOVED_KEYS_V21 = ["showBattery", "showCapsLockIndicator", "showClipboard", "showClock", "showControlCenterButton", "showCpuUsage", "showFocusedWindow", "showLauncherButton", "showMemUsage", "showMusic", "showNotificationButton", "showPrivacyButton", "showSystemTray", "showWeather", "showWorkspaceSwitcher", "hideBrightnessSlider", "updaterHideWidget", "workspaceScrolling", "appLauncherViewMode", "spotlightModalViewMode", "audioDeviceScrollVolumeEnabled", "desktopClockX", "desktopClockY", "desktopClockWidth", "desktopClockHeight", "desktopClockDisplayPreferences", "systemMonitorX", "systemMonitorY", "systemMonitorWidth", "systemMonitorHeight", "systemMonitorDisplayPreferences", "systemMonitorVariants"];

// v18: the shell-wide island settings became per-bar-config island* keys
var ISLAND_KEY_MOVES = {
    dankIslandFloating: "islandFloating",
    dankIslandUseOverlayLayer: "islandUseOverlayLayer",
    dankIslandReserveHeight: "islandReserveThickness",
    dankIslandCompactHeight: "islandCompactThickness",
    dankIslandOuterGap: "islandOuterGap",
    dankIslandHorizontalOffset: "islandAlongOffset",
    dankIslandInteractionMode: "islandInteractionMode",
    dankIslandHoverOpenDelay: "islandHoverOpenDelay",
    dankIslandHoverCloseDelay: "islandHoverCloseDelay",
    dankIslandPalette: "islandPalette",
    dankIslandTransparency: "islandTransparency",
    dankIslandCornerRadius: "islandCornerRadius",
    dankIslandHighContrast: "islandHighContrast",
    dankIslandMediaClockVisible: "islandMediaClockVisible",
    dankIslandNotificationBadgeClearOnOpen: "islandNotificationBadgeClearOnOpen",
    dankIslandNotificationExpand: "islandNotificationExpand",
    dankIslandHomeCompactTight: "islandHomeCompactTight",
    dankIslandHomeClockDisplay: "islandHomeClockDisplay",
    dankIslandHomeVolumeDisplay: "islandHomeVolumeDisplay",
    dankIslandHomeBrightnessDisplay: "islandHomeBrightnessDisplay",
    dankIslandHomeLayout: "islandHomeLayout",
    dankIslandBatteryStyle: "islandBatteryStyle",
    dankIslandSatellitesEnabled: "islandSatellitesEnabled",
    dankIslandSatellitePosition: "islandSatellitePosition",
    dankIslandSatelliteGap: "islandSatelliteGap",
    dankIslandSatelliteBackground: "islandSatelliteBackground",
    dankIslandSatelliteGothCorners: "islandSatelliteGothCorners",
    dankIslandSatelliteTransparency: "islandSatelliteTransparency",
    dankIslandReducedMotion: "islandReducedMotion",
    dankIslandSpringStiffness: "islandSpringStiffness",
    dankIslandSpringDamping: "islandSpringDamping",
    dankIslandSpringMass: "islandSpringMass"
};

function migrateBatteryPillStyle(target) {
    if (!target || typeof target !== "object" || target.batteryPillStyle === undefined)
        return;
    var pill = target.batteryPillStyle === true;
    delete target.batteryPillStyle;
    if (target.batteryStyle !== undefined && target.batteryStyle !== "icon")
        return;
    if (pill)
        target.batteryStyle = "solid";
}

function strengthFromWindowRadius(radius) {
    return Shape.strengthFromRadius((radius ?? Shape.corners.l) * Shape.corners.m / Shape.corners.l);
}

function withoutInstancePositions(instances) {
    if (!Array.isArray(instances))
        return instances;
    return instances.map(function (inst) {
        if (!inst || !inst.positions)
            return inst;
        var copy = Object.assign({}, inst);
        delete copy.positions;
        return copy;
    });
}

function withoutSessionBackedPluginState(pluginSettings) {
    if (!pluginSettings)
        return pluginSettings;
    var copy = Object.assign({}, pluginSettings);
    for (var i = 0; i < SESSION_BACKED_PLUGIN_IDS.length; i++) {
        delete copy[SESSION_BACKED_PLUGIN_IDS[i]];
    }
    return copy;
}

function extractSessionPayload(obj) {
    if (!obj)
        return null;

    var payload = {};
    for (var i = 0; i < SESSION_MOVED_KEYS.length; i++) {
        var key = SESSION_MOVED_KEYS[i];
        if (key in obj)
            payload[key] = obj[key];
    }

    var positions = {};
    var instances = Array.isArray(obj.desktopWidgetInstances) ? obj.desktopWidgetInstances : [];
    for (var i = 0; i < instances.length; i++) {
        var inst = instances[i];
        if (inst && inst.id && inst.positions && Object.keys(inst.positions).length > 0) {
            positions[inst.id] = inst.positions;
        }
    }
    if (Object.keys(positions).length > 0)
        payload.desktopWidgetInstancePositions = positions;

    var pluginState = {};
    for (var i = 0; i < SESSION_BACKED_PLUGIN_IDS.length; i++) {
        var id = SESSION_BACKED_PLUGIN_IDS[i];
        if (obj.builtInPluginSettings && obj.builtInPluginSettings[id]) {
            pluginState[id] = obj.builtInPluginSettings[id];
        }
    }
    if (Object.keys(pluginState).length > 0)
        payload.builtInPluginState = pluginState;

    return Object.keys(payload).length > 0 ? payload : null;
}

function extractCachePayload(obj) {
    if (!obj)
        return null;

    var payload = {};
    for (var i = 0; i < CACHE_MOVED_KEYS.length; i++) {
        var key = CACHE_MOVED_KEYS[i];
        if (obj[key] && Object.keys(obj[key]).length > 0)
            payload[key] = obj[key];
    }
    return Object.keys(payload).length > 0 ? payload : null;
}

function extractPins(obj) {
    if (!obj)
        return null;

    var pins = null;
    for (var i = 0; i < PIN_KEYS.length; i++) {
        var value = obj[PIN_KEYS[i]];
        if (!value || Object.keys(value).length === 0)
            continue;
        if (!pins)
            pins = {};
        pins[PIN_KEYS[i]] = value;
    }
    return pins;
}

function styleDefault(key, style) {
    if (key === "radiusMode" && style === "classic")
        return "fixed";
    return undefined;
}

// Sizes absent from the file load at the saved density's preset, as a reset would; a save omits only that preset.
function densityDefault(key, density, style) {
    var def = styleDefault(key, style) ?? SpecModule.SPEC[key].def;
    if (key === "barConfigs" || key === "dockConfigs") {
        var presets = DensityPresets.values(key === "barConfigs" ? "bar" : "dock", density);
        return def.map(function (config) {
            return Object.assign({}, config, presets);
        });
    }
    var frame = DensityPresets.value("frame", key, density);
    return frame === undefined ? def : frame;
}

function parse(root, jsonObj) {
    jsonObj = migrateToVersion(jsonObj || {}, root.settingsConfigVersion) || jsonObj || {};
    jsonObj.dockConfigs = DockConfig.normalize(jsonObj.dockConfigs, DensityPresets.values("dock", jsonObj.density));
    // the dock pages configure whichever dock is selected, so an empty list leaves them blank
    if (!jsonObj.dockConfigs.length)
        delete jsonObj.dockConfigs;
    var SPEC = SpecModule.SPEC;

    if (!jsonObj)
        return;

    for (var k in SPEC) {
        if (k === "pluginSettings")
            continue;
        // Runtime-only keys are never in the JSON; a reset here would wipe values set by processes on every reload.
        if (SPEC[k].persist === false)
            continue;
        if (!(k in jsonObj))
            assign(root, k, Util.cloneDef(densityDefault(k, jsonObj.density, jsonObj.interfaceStyle)));
    }

    for (var k in jsonObj) {
        if (!SPEC[k])
            continue;
        if (k === "pluginSettings")
            continue;
        var raw = jsonObj[k];
        var spec = SPEC[k];
        var coerce = spec.coerce;
        assign(root, k, coerce ? (coerce(raw) !== undefined ? coerce(raw) : root[k]) : raw);
    }
}

// A QML root throws on an undeclared property; a shared spec key the shell has not declared must not abort the load.
function assign(root, key, value) {
    try {
        root[key] = value;
    } catch (e) {
        console.warn("settings: no SettingsData property for spec key, skipped:", key);
    }
}

function toJson(root, setKeys) {
    var SPEC = SpecModule.SPEC;
    var out = {};
    for (var k in SPEC) {
        if (SPEC[k].persist === false)
            continue;
        if (k === "pluginSettings")
            continue;
        var value = root[k];
        if (value === undefined)
            continue;
        if (k === "desktopWidgetInstances")
            value = withoutInstancePositions(value);
        if (k === "builtInPluginSettings")
            value = withoutSessionBackedPluginState(value);
        if (!setKeys.has(k) && Util.isDefault(value, densityDefault(k, root.density, root.interfaceStyle)))
            continue;
        out[k] = value;
    }
    out.configVersion = root.settingsConfigVersion;
    return out;
}

function migrateToVersion(obj, targetVersion) {
    if (!obj)
        return null;

    // hand-written and nix-generated files carry no version and are authored against the current format
    if (obj.configVersion === undefined)
        return null;
    var settings = JSON.parse(JSON.stringify(obj));
    var currentVersion = settings.configVersion;

    if (currentVersion >= targetVersion) {
        return null;
    }

    if (currentVersion < 2 && targetVersion >= 2) {
        console.info("Migrating settings from version", currentVersion, "to version 2");

        if (settings.barConfigs === undefined) {
            var position = 0;
            if (settings.dankBarAtBottom !== undefined || settings.topBarAtBottom !== undefined) {
                var atBottom = settings.dankBarAtBottom !== undefined ? settings.dankBarAtBottom : settings.topBarAtBottom;
                position = atBottom ? 1 : 0;
            } else if (settings.dankBarPosition !== undefined) {
                position = settings.dankBarPosition;
            }

            var defaultConfig = {
                id: "default",
                name: "Main Bar",
                enabled: true,
                position: position,
                screenPreferences: ["all"],
                showOnLastDisplay: true,
                leftWidgets: settings.dankBarLeftWidgets || ["launcherButton", "workspaceSwitcher", "focusedWindow"],
                centerWidgets: settings.dankBarCenterWidgets || ["music", "clock", "weather"],
                rightWidgets: settings.dankBarRightWidgets || ["systemTray", "clipboard", "cpuUsage", "memUsage", "notificationButton", "battery", "controlCenterButton"],
                spacing: settings.dankBarSpacing !== undefined ? settings.dankBarSpacing : 4,
                innerPadding: settings.dankBarInnerPadding !== undefined ? settings.dankBarInnerPadding : 4,
                bottomGap: settings.dankBarBottomGap !== undefined ? settings.dankBarBottomGap : 0,
                transparency: settings.dankBarTransparency !== undefined ? settings.dankBarTransparency : 1.0,
                widgetTransparency: settings.dankBarWidgetTransparency !== undefined ? settings.dankBarWidgetTransparency : 1.0,
                squareCorners: settings.dankBarSquareCorners !== undefined ? settings.dankBarSquareCorners : false,
                noBackground: settings.dankBarNoBackground !== undefined ? settings.dankBarNoBackground : false,
                gothCornersEnabled: settings.dankBarGothCornersEnabled !== undefined ? settings.dankBarGothCornersEnabled : false,
                gothCornerRadiusOverride: settings.dankBarGothCornerRadiusOverride !== undefined ? settings.dankBarGothCornerRadiusOverride : false,
                gothCornerRadiusValue: settings.dankBarGothCornerRadiusValue !== undefined ? settings.dankBarGothCornerRadiusValue : 12,
                borderEnabled: settings.dankBarBorderEnabled !== undefined ? settings.dankBarBorderEnabled : false,
                borderColor: settings.dankBarBorderColor || "surfaceText",
                borderOpacity: settings.dankBarBorderOpacity !== undefined ? settings.dankBarBorderOpacity : 1.0,
                borderThickness: settings.dankBarBorderThickness !== undefined ? settings.dankBarBorderThickness : 1,
                fontScale: settings.dankBarFontScale !== undefined ? settings.dankBarFontScale : 1.0,
                autoHide: settings.dankBarAutoHide !== undefined ? settings.dankBarAutoHide : false,
                autoHideDelay: settings.dankBarAutoHideDelay !== undefined ? settings.dankBarAutoHideDelay : 250,
                openOnOverview: settings.dankBarOpenOnOverview !== undefined ? settings.dankBarOpenOnOverview : false,
                visible: settings.dankBarVisible !== undefined ? settings.dankBarVisible : true,
                popupGapsAuto: settings.popupGapsAuto !== undefined ? settings.popupGapsAuto : true,
                popupGapsManual: settings.popupGapsManual !== undefined ? settings.popupGapsManual : 4
            };

            settings.barConfigs = [defaultConfig];

            var legacyKeys = ["dankBarLeftWidgets", "dankBarCenterWidgets", "dankBarRightWidgets", "dankBarWidgetOrder", "dankBarAutoHide", "dankBarAutoHideDelay", "dankBarOpenOnOverview", "dankBarVisible", "dankBarSpacing", "dankBarBottomGap", "dankBarInnerPadding", "dankBarPosition", "dankBarSquareCorners", "dankBarNoBackground", "dankBarGothCornersEnabled", "dankBarGothCornerRadiusOverride", "dankBarGothCornerRadiusValue", "dankBarBorderEnabled", "dankBarBorderColor", "dankBarBorderOpacity", "dankBarBorderThickness", "popupGapsAuto", "popupGapsManual", "dankBarAtBottom", "topBarAtBottom", "dankBarTransparency", "dankBarWidgetTransparency"];

            for (var i = 0; i < legacyKeys.length; i++) {
                delete settings[legacyKeys[i]];
            }

            console.info("Migrated single bar settings to barConfigs");
        }

        settings.configVersion = 2;
    }

    if (currentVersion < 3 && targetVersion >= 3) {
        console.info("Migrating settings from version", currentVersion, "to version 3");
        console.info("Per-widget controlCenterButton config now supported via widgetData properties");
        settings.configVersion = 3;
    }

    if (currentVersion < 4 && targetVersion >= 4) {
        console.info("Migrating settings from version", currentVersion, "to version 4");
        console.info("Migrating desktop widgets to unified desktopWidgetInstances");

        var instances = [];

        if (settings.desktopClockEnabled) {
            var clockPositions = {};
            if (settings.desktopClockX !== undefined && settings.desktopClockX >= 0) {
                clockPositions["default"] = {
                    x: settings.desktopClockX,
                    y: settings.desktopClockY,
                    width: settings.desktopClockWidth || 280,
                    height: settings.desktopClockHeight || 180
                };
            }

            instances.push({
                id: "dw_clock_primary",
                widgetType: "desktopClock",
                name: "Desktop Clock",
                enabled: true,
                config: {
                    style: settings.desktopClockStyle || "analog",
                    transparency: settings.desktopClockTransparency !== undefined ? settings.desktopClockTransparency : 0.8,
                    colorMode: settings.desktopClockColorMode || "primary",
                    customColor: settings.desktopClockCustomColor || "#ffffff",
                    showDate: settings.desktopClockShowDate !== false,
                    showAnalogNumbers: settings.desktopClockShowAnalogNumbers || false,
                    showAnalogSeconds: settings.desktopClockShowAnalogSeconds !== false,
                    displayPreferences: settings.desktopClockDisplayPreferences || ["all"]
                },
                positions: clockPositions
            });
        }

        if (settings.systemMonitorEnabled) {
            var sysmonPositions = {};
            if (settings.systemMonitorX !== undefined && settings.systemMonitorX >= 0) {
                sysmonPositions["default"] = {
                    x: settings.systemMonitorX,
                    y: settings.systemMonitorY,
                    width: settings.systemMonitorWidth || 320,
                    height: settings.systemMonitorHeight || 480
                };
            }

            instances.push({
                id: "dw_sysmon_primary",
                widgetType: "systemMonitor",
                name: "System Monitor",
                enabled: true,
                config: {
                    showHeader: settings.systemMonitorShowHeader !== false,
                    transparency: settings.systemMonitorTransparency !== undefined ? settings.systemMonitorTransparency : 0.8,
                    colorMode: settings.systemMonitorColorMode || "primary",
                    customColor: settings.systemMonitorCustomColor || "#ffffff",
                    showCpu: settings.systemMonitorShowCpu !== false,
                    showCpuGraph: settings.systemMonitorShowCpuGraph !== false,
                    showCpuTemp: settings.systemMonitorShowCpuTemp !== false,
                    showGpuTemp: settings.systemMonitorShowGpuTemp || false,
                    gpuPciId: settings.systemMonitorGpuPciId || "",
                    showMemory: settings.systemMonitorShowMemory !== false,
                    showMemoryGraph: settings.systemMonitorShowMemoryGraph !== false,
                    showNetwork: settings.systemMonitorShowNetwork !== false,
                    showNetworkGraph: settings.systemMonitorShowNetworkGraph !== false,
                    showDisk: settings.systemMonitorShowDisk !== false,
                    showTopProcesses: settings.systemMonitorShowTopProcesses || false,
                    topProcessCount: settings.systemMonitorTopProcessCount || 3,
                    topProcessSortBy: settings.systemMonitorTopProcessSortBy || "cpu",
                    layoutMode: settings.systemMonitorLayoutMode || "auto",
                    graphInterval: settings.systemMonitorGraphInterval || 60,
                    displayPreferences: settings.systemMonitorDisplayPreferences || ["all"]
                },
                positions: sysmonPositions
            });
        }

        var variants = settings.systemMonitorVariants || [];
        for (var i = 0; i < variants.length; i++) {
            var v = variants[i];
            instances.push({
                id: v.id,
                widgetType: "systemMonitor",
                name: v.name || ("System Monitor " + (i + 2)),
                enabled: true,
                config: v.config || {},
                positions: v.positions || {}
            });
        }

        settings.desktopWidgetInstances = instances;
        settings.configVersion = 4;
    }

    if (currentVersion < 5 && targetVersion >= 5) {
        console.info("Migrating settings from version", currentVersion, "to version 5");
        console.info("Moving sensitive data (weather location, coordinates) to session.json");

        delete settings.weatherLocation;
        delete settings.weatherCoordinates;

        settings.configVersion = 5;
    }

    if (currentVersion < 6 && targetVersion >= 6) {
        console.info("Migrating settings from version", currentVersion, "to version 6");

        if (settings.barElevationEnabled === undefined) {
            var legacyBars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
            var hadLegacyBarShadowEnabled = false;
            for (var j = 0; j < legacyBars.length; j++) {
                var legacyIntensity = Number(legacyBars[j] && legacyBars[j].shadowIntensity);
                if (!isNaN(legacyIntensity) && legacyIntensity > 0) {
                    hadLegacyBarShadowEnabled = true;
                    break;
                }
            }
            settings.barElevationEnabled = hadLegacyBarShadowEnabled;
        }

        settings.configVersion = 6;
    }

    if (currentVersion < 11 && targetVersion >= 11) {
        settings.configVersion = 11;
    }

    if (currentVersion < 12 && targetVersion >= 12) {
        console.info("Migrating settings from version", currentVersion, "to version 12");
        if (settings.batteryNotificationType !== undefined) {
            settings.batteryChargeLimitNotificationType = settings.batteryNotificationType;
            settings.batteryLowNotificationType = settings.batteryNotificationType;
            settings.batteryCriticalNotificationType = settings.batteryNotificationType;
            delete settings.batteryNotificationType;
        }
        settings.configVersion = 12;
    }

    if (currentVersion < 13 && targetVersion >= 13) {
        console.info("Migrating settings from version", currentVersion, "to version 13");
        console.info("Moving device and network pins to cache.json");

        for (var p = 0; p < PIN_KEYS.length; p++) {
            delete settings[PIN_KEYS[p]];
        }

        settings.configVersion = 13;
    }

    if (currentVersion < 14 && targetVersion >= 14) {
        console.info("Migrating settings from version", currentVersion, "to version 14");
        console.info("Dropping keys that match defaults; settings.json now stores only changed values");

        Util.stripDefaults(settings, SpecModule.SPEC);
        settings.configVersion = 14;
    }

    if (currentVersion < 15 && targetVersion >= 15) {
        console.info("Migrating settings from version", currentVersion, "to version 15");
        console.info("Moving machine-specific state to session.json and usage histories to cache.json");

        var movedKeys = SESSION_MOVED_KEYS.concat(CACHE_MOVED_KEYS, STALE_WIDGET_KEYS);
        for (var i = 0; i < movedKeys.length; i++) {
            delete settings[movedKeys[i]];
        }

        if (Array.isArray(settings.desktopWidgetInstances)) {
            settings.desktopWidgetInstances = withoutInstancePositions(settings.desktopWidgetInstances);
        }
        if (settings.builtInPluginSettings) {
            settings.builtInPluginSettings = withoutSessionBackedPluginState(settings.builtInPluginSettings);
        }

        settings.configVersion = 15;
    }

    if (currentVersion < 16 && targetVersion >= 16) {
        console.info("Migrating settings from version", currentVersion, "to version 16");
        console.info("Moving Niri overview close behavior to the window focus setting");

        if (settings.closeNiriOverviewOnWindowFocus === undefined && settings.spotlightCloseNiriOverview !== undefined) {
            settings.closeNiriOverviewOnWindowFocus = settings.spotlightCloseNiriOverview;
        }
        delete settings.spotlightCloseNiriOverview;

        settings.configVersion = 16;
    }

    if (currentVersion < 17 && targetVersion >= 17) {
        console.info("Migrating settings from version", currentVersion, "to version 17");
        console.info("Converting batteryPillStyle to batteryStyle");

        migrateBatteryPillStyle(settings);
        var bars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
        for (var b = 0; b < bars.length; b++) {
            for (var k = 0; k < BAR_WIDGET_LIST_KEYS.length; k++) {
                var widgets = bars[b] && bars[b][BAR_WIDGET_LIST_KEYS[k]];
                if (!Array.isArray(widgets))
                    continue;
                for (var w = 0; w < widgets.length; w++)
                    migrateBatteryPillStyle(widgets[w]);
            }
        }

        settings.configVersion = 17;
    }

    if (currentVersion < 18 && targetVersion >= 18) {
        console.info("Migrating settings from version", currentVersion, "to version 18");
        console.info("Moving the shell-wide Dank Island onto its bar config as a per-instance mode");

        var islandId = settings.dankIslandBarId;
        var islandBars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
        for (var ib = 0; ib < islandBars.length; ib++) {
            if (!islandBars[ib] || islandBars[ib].id !== islandId)
                continue;
            islandBars[ib].island = true;
            for (var oldKey in ISLAND_KEY_MOVES) {
                if (!(oldKey in settings))
                    continue;
                islandBars[ib][ISLAND_KEY_MOVES[oldKey]] = settings[oldKey];
            }
        }
        for (var dropKey in ISLAND_KEY_MOVES)
            delete settings[dropKey];
        delete settings.dankIslandBarId;
        delete settings.dankIslandSatelliteSwoopRadius;

        settings.configVersion = 18;
    }

    if (currentVersion < 19 && targetVersion >= 19) {
        console.info("Migrating settings from version", currentVersion, "to version 19");
        console.info("Moving global bar widget options onto each widget instance");
        migrateBarWidgetGlobals(settings);
        settings.configVersion = 19;
    }

    if (currentVersion < 20 && targetVersion >= 20) {
        console.info("Migrating settings from version", currentVersion, "to version 20");
        console.info("Marking bars and dock that already match the surface opacity as following the interface style");
        var surfaceOpacity = settings.popupTransparency ?? 1.0;
        var bars19 = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
        for (var i19 = 0; i19 < bars19.length; i19++) {
            if (!bars19[i19] || bars19[i19].followInterfaceStyle !== undefined)
                continue;
            bars19[i19].followInterfaceStyle = (bars19[i19].transparency ?? 1.0) === surfaceOpacity;
        }
        if (settings.dockFollowInterfaceStyle === undefined)
            settings.dockFollowInterfaceStyle = (settings.dockTransparency ?? 1.0) === surfaceOpacity;
        settings.configVersion = 20;
    }

    if (currentVersion < 21 && targetVersion >= 21) {
        console.info("Migrating settings from version", currentVersion, "to version 21");
        console.info("Dropping settings keys that no longer have a consumer");
        for (var i21 = 0; i21 < REMOVED_KEYS_V21.length; i21++)
            delete settings[REMOVED_KEYS_V21[i21]];
        settings.configVersion = 21;
    }

    if (currentVersion < 22 && targetVersion >= 22) {
        const moves = [["waveProgressEnabled", "waveProgress", true], ["mediaWallpaperEnabled", "albumArtBackdrop", true], ["mediaUseAlbumArtAccent", "albumArtAccent", true], ["appleMusicAnimatedArtEnabled", "animatedArt", false]];
        const options = Object.assign({}, settings.dashOptions ?? {});
        const media = Object.assign({}, options.media ?? {});
        for (const [oldKey, key, def] of moves) {
            const value = settings[oldKey];
            delete settings[oldKey];
            if (media[key] !== undefined || typeof value !== "boolean" || value === def)
                continue;
            media[key] = value;
        }
        if (Object.keys(media).length > 0)
            options.media = media;
        if (Object.keys(options).length > 0)
            settings.dashOptions = options;
        settings.configVersion = 22;
    }

    if (currentVersion < 23 && targetVersion >= 23) {
        if (settings.radiusStrength === undefined)
            settings.radiusStrength = strengthFromWindowRadius(settings.cornerRadius);
        delete settings.cornerRadius;
        settings.configVersion = 23;
    }

    if (currentVersion < 24 && targetVersion >= 24) {
        const removed = ["greeterFontFamily", "greeterLockDateFormat", "greeterWallpaperFillMode", "greeterWallpaperPath", "greeterShowWeather"];
        for (const key of removed)
            delete settings[key];
        settings.dockConfigs = DockConfig.migrate(settings);
        for (const key of Object.keys(settings)) {
            if (key === "showDock" || (key !== "dockConfigs" && /^dock[A-Z]/.test(key)))
                delete settings[key];
        }
        if (settings.screenPreferences)
            delete settings.screenPreferences.dock;
        if (settings.showOnLastDisplay)
            delete settings.showOnLastDisplay.dock;
        settings.configVersion = 24;
    }

    if (currentVersion < 25 && targetVersion >= 25) {
        const bars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
        for (const bar of bars) {
            if (!bar)
                continue;
            if (bar.removeWidgetPadding === true)
                bar.widgetPadding = 0;
            delete bar.removeWidgetPadding;
        }
        settings.configVersion = 25;
    }

    if (currentVersion < 26 && targetVersion >= 26) {
        const customSpeed = 4;
        const speedMoves = [["animationSpeed", "customAnimationDuration", "animationDuration", [0, 250, 500, 750], 500], ["popoutAnimationSpeed", "popoutCustomAnimationDuration", "popoutAnimationDuration", [0, 150, 300, 500], 150], ["modalAnimationSpeed", "modalCustomAnimationDuration", "modalAnimationDuration", [0, 150, 300, 500], 150], ["notificationAnimationSpeed", "notificationCustomAnimationDuration", "notificationAnimationDuration", [0, 200, 400, 600], 400]];
        for (const [speedKey, customKey, durationKey, presets, customDefault] of speedMoves) {
            const speed = settings[speedKey];
            const custom = settings[customKey] ?? customDefault;
            delete settings[speedKey];
            delete settings[customKey];
            if (speed === undefined || settings[durationKey] !== undefined)
                continue;
            settings[durationKey] = speed === customSpeed ? custom : (presets[speed] ?? presets[1]);
        }
        settings.configVersion = 26;
    }

    if (currentVersion < 27 && targetVersion >= 27) {
        if (Array.isArray(settings.controlCenterWidgets)) {
            settings.controlCenterWidgets = settings.controlCenterWidgets.map(widget => {
                if (!widget || typeof widget !== "object")
                    return widget;
                const next = Object.assign({}, widget);
                const width = Number(next.width);
                delete next.width;
                const cells = Number.isInteger(next.w) && next.w > 0 ? next.w : Number.isFinite(width) && width > 0 ? Math.max(1, Math.min(4, Math.round(width / 25))) : 2;
                next.w = cells * 2;
                if (next.h === undefined)
                    next.h = 1;
                return next;
            });
        }
        const sheetWidth = Number(settings.controlCenterWidth);
        delete settings.controlCenterWidth;
        const columns = Number(settings.controlCenterColumns);
        if (Number.isFinite(columns) && columns > 0)
            settings.controlCenterColumns = Math.max(3, Math.round(columns)) * 2;
        else if (Number.isFinite(sheetWidth) && sheetWidth > 0)
            settings.controlCenterColumns = Math.max(3, Math.min(6, Math.round(sheetWidth / (550 / 4)))) * 2;
        settings.configVersion = 27;
    }

    if (currentVersion < 28 && targetVersion >= 28) {
        const surfaceOpacity = Number.isFinite(Number(settings.popupTransparency)) ? Number(settings.popupTransparency) : 1.0;
        const bars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
        const frameOpacity = Number(settings.frameOpacity);
        const frameBar = bars.find(bc => bc && bc.enabled !== false && bc.island !== true);
        if (frameBar && Number.isFinite(frameOpacity) && frameOpacity !== surfaceOpacity && frameBar.followInterfaceStyle !== false) {
            frameBar.followInterfaceStyle = false;
            frameBar.transparency = frameOpacity;
        }
        for (const bc of bars) {
            if (!bc || bc.island !== true)
                continue;
            const islandOpacity = Number(bc.islandTransparency);
            if (Number.isFinite(islandOpacity)) {
                bc.transparency = islandOpacity;
                bc.followInterfaceStyle = islandOpacity === surfaceOpacity;
            }
            delete bc.islandTransparency;
            delete bc.islandCornerRadius;
        }
        delete settings.frameColor;
        delete settings.frameOpacity;
        if (settings.blurBorderEnabled === undefined)
            settings.blurBorderEnabled = settings.blurEnabled === true;
        settings.blurBorderSeeded = settings.blurEnabled === true;
        settings.configVersion = 28;
    }

    if (currentVersion < 29 && targetVersion >= 29) {
        console.info("Migrating settings from version", currentVersion, "to version 29");
        console.info("Moving launcher logo options onto each launcher button instance");
        migrateBarWidgetGlobals(settings);
        delete settings.launcherLogoColorInvertOnMode;
        settings.configVersion = 29;
    }

    if (currentVersion < 30 && targetVersion >= 30) {
        if (settings.dmsWindowsFloating === false)
            settings.dmsWindowsFloatingSeeded = ["niri", "hyprland", "mango"];
        delete settings.dmsWindowsFloating;
        settings.configVersion = 30;
    }

    if (currentVersion < 31 && targetVersion >= 31) {
        const glassLayers = settings.blurEnabled === true && settings.blurForegroundLayers === false;
        const foregroundOpacity = Util.percentToUnit(settings.foregroundLayerTransparency) ?? 1.0;
        const followedOpacity = glassLayers ? 0 : foregroundOpacity;
        const bars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
        for (const bc of bars) {
            if (!bc || bc.widgetFollowInterfaceStyle !== undefined)
                continue;
            bc.widgetFollowInterfaceStyle = (bc.widgetTransparency ?? 1.0) === followedOpacity;
        }
        settings.configVersion = 31;
    }

    if (currentVersion < 35 && targetVersion >= 35) {
        if (Array.isArray(settings.controlCenterWidgets))
            settings.controlCenterWidgets = migrateControlCenterHeader(settings.controlCenterWidgets, currentVersion < 33, settings.controlCenterColumns ?? 8);
        settings.configVersion = 35;
    }

    if (currentVersion < 37 && targetVersion >= 37) {
        if (Array.isArray(settings.controlCenterWidgets) && !settings.controlCenterWidgets.some(widget => widget?.id === "edit"))
            settings.controlCenterWidgets = settings.controlCenterWidgets.concat([Object.assign({}, SpecModule.SPEC.controlCenterWidgets.def.find(widget => widget.id === "edit"))]);
        settings.configVersion = 37;
    }

    if (currentVersion < 38 && targetVersion >= 38) {
        migrateLockScreenWidgets(settings);
        settings.configVersion = 38;
    }

    if (currentVersion < 39 && targetVersion >= 39) {
        migrateIslandReducedMotion(settings);
        settings.configVersion = 39;
    }

    if (currentVersion < 40 && targetVersion >= 40) {
        migrateScrollColumnBehavior(settings);
        settings.configVersion = 40;
    }

    if (currentVersion < 41 && targetVersion >= 41) {
        migrateControlCenterFooter(settings);
        settings.configVersion = 41;
    }

    if (currentVersion < 42 && targetVersion >= 42) {
        migrateDockAppsSizing(settings);
        settings.configVersion = 42;
    }

    return settings;
}

// v42: dock apps follow the dock's icon size and magnification instead of their own copies
function migrateDockAppsSizing(settings) {
    if (!Array.isArray(settings.dockConfigs))
        return;
    for (const dock of settings.dockConfigs) {
        for (const widget of Array.isArray(dock?.widgets) ? dock.widgets : []) {
            if (!widget || typeof widget !== "object")
                continue;
            if (widget.appsDockEnlargeOnHover === true && dock.magnification !== true) {
                dock.magnification = true;
                dock.magnificationScale = Math.max(105, Math.min(160, Number(widget.appsDockEnlargePercentage) || 125));
            }
            const percentage = Number(widget.appsDockIconSizePercentage);
            if (percentage > 0 && percentage !== 100)
                dock.iconSize = Math.round((Number(dock.iconSize) || DockConfig.create("", "").iconSize) * percentage / 100);
            delete widget.appsDockEnlargeOnHover;
            delete widget.appsDockEnlargePercentage;
            delete widget.appsDockIconSizePercentage;
        }
    }
}

// v41: footer entries became a grid row under the rest, keeping their order and widths
function migrateControlCenterFooter(settings) {
    delete settings.controlCenterFooterPosition;
    if (!Array.isArray(settings.controlCenterWidgets))
        return;
    const kept = [];
    const starts = [];
    const ends = [];
    for (const widget of settings.controlCenterWidgets) {
        if (!widget || typeof widget !== "object") {
            kept.push(widget);
            continue;
        }
        const moved = Object.assign({}, widget);
        const inFooter = moved.footer === true;
        const atEnd = moved.footerEnd === true;
        const fills = moved.footerFill === true;
        const footerW = Number(moved.footerW);
        // Stale footer keys can sit on any entry.
        for (const key of ["footer", "footerEnd", "footerW", "footerFill"])
            delete moved[key];
        if (!inFooter) {
            kept.push(moved);
            continue;
        }
        const minW = CC_V41_SLIDER_IDS.includes(moved.id) ? 3 : 1;
        const cells = Number.isFinite(footerW) && footerW > 0 ? Math.round(footerW / CC_V41_GRID_STEP) * CC_V41_GRID_STEP : CC_V41_FOOTER_CELLS[moved.id] || 1;
        (atEnd ? ends : starts).push({
            "widget": moved,
            "fill": fills,
            "w": Math.max(minW, fills ? minW : cells)
        });
    }
    settings.controlCenterWidgets = kept;
    const footer = starts.concat(ends);
    if (footer.length === 0)
        return;

    const saved = Number(settings.controlCenterColumns);
    const columns = Number.isFinite(saved) && saved > 0 ? Math.max(CC_V41_MINIMUM_COLUMNS, saved) : CC_V41_DEFAULT_COLUMNS;
    for (const entry of footer)
        entry.w = Math.min(columns, entry.w);
    // Fill entries split the spare width as the strip did.
    const fillers = footer.filter(entry => entry.fill);
    const spare = Math.max(0, columns - footer.reduce((sum, entry) => sum + entry.w, 0));
    if (fillers.length > 0 && spare > 0) {
        const share = Math.floor(spare / fillers.length / CC_V41_GRID_STEP) * CC_V41_GRID_STEP;
        fillers.forEach((entry, i) => entry.w += share + (i === 0 ? spare - share * fillers.length : 0));
    }

    const cards = kept.filter(widget => widget && typeof widget === "object" && !widget.group);
    let row = GridLayout.packCells(cards, cards.map((card, i) => i), columns, null, CC_V41_GRID_STEP, true).rows;
    let col = 0;
    let rowHeight = 1;
    const endWidth = ends.reduce((sum, entry) => sum + entry.w, 0);
    for (const entry of footer) {
        const widget = entry.widget;
        if (!CC_FULL_HEIGHT_IDS.includes(widget.id)) {
            widget.h = 1;
            widget.small = true;
        }
        if (entry === ends[0])
            col = Math.max(col, columns - endWidth);
        if (col + entry.w > columns) {
            col = 0;
            row += rowHeight;
            rowHeight = 1;
        }
        widget.w = entry.w;
        widget.col = col;
        widget.row = row;
        rowHeight = Math.max(rowHeight, Number.isFinite(widget.h) ? widget.h : 1);
        col += entry.w;
        kept.push(widget);
    }
}

// v40: the niri-only "column" scroll behavior became the compositor-neutral "focusWindow"
function migrateScrollColumnBehavior(settings) {
    for (const bar of Array.isArray(settings.barConfigs) ? settings.barConfigs : []) {
        if (!bar || typeof bar !== "object")
            continue;
        for (const key of ["scrollXBehavior", "scrollYBehavior"]) {
            if (bar[key] === "column")
                bar[key] = "focusWindow";
        }
    }
}

// v39: the per-island toggle folded into the global reduceMotion; any bar that had it on turns the global one on
function migrateIslandReducedMotion(settings) {
    for (const bar of Array.isArray(settings.barConfigs) ? settings.barConfigs : []) {
        if (!bar || typeof bar !== "object")
            continue;
        const holders = [bar];
        for (const sectionId of ["leftWidgets", "centerWidgets", "rightWidgets"])
            holders.push(...(Array.isArray(bar[sectionId]) ? bar[sectionId] : []).filter(entry => entry && typeof entry === "object" && entry.id === "island"));
        for (const holder of holders) {
            if (holder.islandReducedMotion === true)
                settings.reduceMotion = true;
            delete holder.islandReducedMotion;
        }
    }
}

var LOCK_WIDGET_MOVED_KEYS = ["lockScreenShowSystemIcons", "lockScreenShowTime", "lockScreenClockStyle", "lockScreenShowDate", "lockScreenShowPasswordField", "lockScreenShowMediaPlayer", "lockScreenNotificationMode"];
var LOCK_WIDGET_GREETER_KEYS = ["lockScreenShowPowerActions", "lockScreenShowProfileImage", "lockScreenShowWeather"];

function migrateLockScreenWidgets(settings) {
    if (Array.isArray(settings.lockScreenWidgetInstances))
        return;
    const present = key => key in settings;
    if (!LOCK_WIDGET_MOVED_KEYS.concat(LOCK_WIDGET_GREETER_KEYS).some(present))
        return;
    const instances = SpecModule.lockWidgetDefaults();
    const byId = id => instances.find(inst => inst.id === id);
    if (present("lockScreenShowTime"))
        byId("lock_clock").enabled = !!settings.lockScreenShowTime;
    if (present("lockScreenClockStyle"))
        byId("lock_clock").config.style = settings.lockScreenClockStyle === "vertical" ? "overlap" : "digital";
    if (present("lockScreenShowDate"))
        byId("lock_date").enabled = !!settings.lockScreenShowDate;
    byId("lock_auth").config.profileVisibility = settings.lockScreenShowProfileImage === false ? "never" : "always";
    byId("lock_auth").config.passwordVisibility = settings.lockScreenShowPasswordField === false ? "typing" : "always";
    if (present("lockScreenNotificationMode")) {
        const mode = Number(settings.lockScreenNotificationMode) || 0;
        byId("lock_notifications").enabled = mode > 0;
        if (mode > 0)
            byId("lock_notifications").config.mode = mode;
    }
    if (present("lockScreenShowSystemIcons"))
        byId("lock_status").enabled = !!settings.lockScreenShowSystemIcons;
    if (present("lockScreenShowMediaPlayer"))
        byId("lock_status").config.showMediaPlayer = !!settings.lockScreenShowMediaPlayer;
    if (present("lockScreenShowWeather"))
        byId("lock_status").config.showWeather = !!settings.lockScreenShowWeather;
    if (present("lockScreenShowPowerActions"))
        byId("lock_power").enabled = !!settings.lockScreenShowPowerActions;
    settings.lockScreenWidgetInstances = instances;
    for (const key of LOCK_WIDGET_MOVED_KEYS)
        delete settings[key];
}

function migrateControlCenterHeader(widgets, fixedHeader, columns) {
    const header = widgets.filter(widget => CC_HEADER_IDS.includes(widget?.id));
    if (!fixedHeader && header.length === 0)
        return widgets;
    const rest = widgets.filter(widget => !CC_HEADER_IDS.includes(widget?.id));
    const actions = header.find(widget => Array.isArray(widget?.actions))?.actions ?? [];
    const wanted = id => !rest.some(widget => widget?.id === id) && actions.find(action => action?.id === id)?.enabled !== false;
    const tiles = CC_ACTION_TILE_IDS.filter(wanted).map(id => ({
                id: id,
                enabled: true,
                w: 1,
                h: 1,
                small: true
            }));
    const footer = rest.some(widget => widget?.id === "runningApps") ? [] : [
        {
            id: "runningApps",
            enabled: true,
            w: 4,
            h: 1,
            footer: true
        }
    ];
    const identity = header.length === 0 ? {} : header.find(widget => widget.id === "userCard" || (widget.id === "header" && widget.showUser !== false));
    if (!identity || rest.some(widget => widget?.id === "user"))
        return tiles.concat(rest, footer);
    const user = {
        id: "user",
        enabled: true,
        w: Math.max(1, columns - tiles.length),
        h: 1
    };
    for (const key of CC_USER_KEYS) {
        if (key in identity)
            user[key] = identity[key];
    }
    return [user].concat(tiles, rest, footer);
}

function migrateBarWidgetGlobals(settings) {
    var bars = Array.isArray(settings.barConfigs) ? settings.barConfigs : [];
    for (var b = 0; b < bars.length; b++) {
        for (var k = 0; k < BAR_WIDGET_LIST_KEYS.length; k++) {
            var widgets = bars[b] && bars[b][BAR_WIDGET_LIST_KEYS[k]];
            if (!Array.isArray(widgets))
                continue;
            for (var w = 0; w < widgets.length; w++) {
                var raw = widgets[w];
                var id = typeof raw === "string" ? raw : (raw && raw.id);
                var map = WidgetDefaults.MIGRATED_GLOBALS[id];
                if (!map)
                    continue;
                var entry = typeof raw === "string" ? {
                    id: raw,
                    enabled: true
                } : raw;
                var copied = false;
                for (var entryKey in map) {
                    var value = settings[map[entryKey]] ?? WidgetDefaults.LEGACY_GLOBAL_DEFAULTS[map[entryKey]];
                    if (entry[entryKey] !== undefined || value === undefined)
                        continue;
                    entry[entryKey] = value;
                    copied = true;
                }
                if (copied)
                    widgets[w] = entry;
            }
        }
    }
    var removed = WidgetDefaults.removedGlobals();
    for (var i = 0; i < removed.length; i++)
        delete settings[removed[i]];
}
