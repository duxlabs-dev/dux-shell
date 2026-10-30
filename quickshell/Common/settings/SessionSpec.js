.pragma library
.import "../../DCommon/Common/settings/SharedSessionSpec.js" as Shared
.import "../../DCommon/Common/settings/SpecUtil.js" as Util

var LOCAL_SPEC = {
    doNotDisturb: {
        def: false
    },
    doNotDisturbUntil: {
        def: 0
    },
    doNotDisturbHeldByScreenShare: {
        def: false
    },
    screenShareDndDismissed: {
        def: false
    },
    screenShareDismissedIds: {
        def: []
    },
    idleInhibited: {
        def: false
    },
    idleInhibitedUntil: {
        def: 0
    },
    updaterNotifiedUnix: {
        def: 0
    },
    updaterNotifiedCount: {
        def: 0
    },
    repoMoveNoticeVersion: {
        def: ""
    },
    terminalOverride: {
        def: ""
    },
    wallpaperPathLight: {
        def: ""
    },
    wallpaperPathDark: {
        def: ""
    },
    monitorWallpapersLight: {
        def: {}
    },
    monitorWallpapersDark: {
        def: {}
    },
    wallpaperTransition: {
        def: "fade"
    },
    includedTransitions: {
        def: ["fade", "wipe", "disc", "stripes", "iris bloom", "pixelate", "portal"]
    },
    wallpaperCyclingEnabled: {
        def: false
    },
    wallpaperCyclingRandom: {
        def: false
    },
    wallpaperCyclingRecursive: {
        def: false
    },
    wallpaperCyclingMode: {
        def: "interval"
    },
    wallpaperCyclingInterval: {
        def: 300
    },
    wallpaperCyclingTime: {
        def: "06:00"
    },
    wallpaperCyclingFolderPath: {
        def: ""
    },
    monitorCyclingSettings: {
        def: {}
    },
    nightModeEnabled: {
        def: false
    },
    nightModeTemperature: {
        def: 4500
    },
    nightModeHighTemperature: {
        def: 6500
    },
    nightModeAutoEnabled: {
        def: false
    },
    nightModeAutoMode: {
        def: "time"
    },
    nightModeStartHour: {
        def: 18
    },
    nightModeStartMinute: {
        def: 0
    },
    nightModeEndHour: {
        def: 6
    },
    nightModeEndMinute: {
        def: 0
    },
    nightModeTransitionMinutes: {
        def: 60
    },
    displayGamma: {
        def: 1.0
    },
    displayContrast: {
        def: 1.0
    },
    latitude: {
        def: 0.0
    },
    longitude: {
        def: 0.0
    },
    nightModeUseIPLocation: {
        def: false
    },
    nightModeLocationName: {
        def: ""
    },
    themeModeAutoEnabled: {
        def: false
    },
    themeModeAutoMode: {
        def: "time"
    },
    themeModeStartHour: {
        def: 18
    },
    themeModeStartMinute: {
        def: 0
    },
    themeModeEndHour: {
        def: 6
    },
    themeModeEndMinute: {
        def: 0
    },
    themeModeShareGammaSettings: {
        def: true
    },
    dockPins: {
        def: {}
    },
    barPinnedApps: {
        def: []
    },
    hiddenTrayIds: {
        def: []
    },
    trayItemOrder: {
        def: []
    },
    recentColors: {
        def: []
    },
    showThirdPartyPlugins: {
        def: false
    },
    pluginBrowserInstalledFirst: {
        def: false
    },
    pluginBrowserSortMode: {
        def: "default"
    },
    lastBrightnessDevice: {
        def: ""
    },
    brightnessExponentialDevices: {
        def: {}
    },
    brightnessUserSetValues: {
        def: {}
    },
    brightnessExponentValues: {
        def: {}
    },
    nvidiaGpuTempEnabled: {
        def: false
    },
    nonNvidiaGpuTempEnabled: {
        def: false
    },
    enabledGpuPciIds: {
        def: []
    },
    wifiDeviceOverride: {
        def: ""
    },
    hiddenApps: {
        def: []
    },
    appOverrides: {
        def: {}
    },
    searchAppActions: {
        def: true
    },
    vpnLastConnected: {
        def: ""
    },
    bluetoothAdapterOverride: {
        def: ""
    },
    lastPlayerIdentity: {
        def: ""
    },
    pinnedPlayerIdentity: {
        def: ""
    },
    deviceMaxVolumes: {
        def: {}
    },
    hiddenOutputDeviceNames: {
        def: []
    },
    hiddenInputDeviceNames: {
        def: []
    },
    locale: {
        def: "",
        onChange: "updateLocale"
    },
    timeLocale: {
        def: ""
    },
    notepadLastMode: {
        def: ""
    },
    niriOutputSettings: {
        def: {}
    },
    hyprlandOutputSettings: {
        def: {}
    },
    activeDisplayProfile: {
        def: {}
    },
    activeDisplayProfileModes: {
        def: {}
    },
    desktopWidgetGridSettings: {
        def: {}
    },
    lockScreenWidgetGridSettings: {
        def: {}
    },
    islandFreePositions: {
        def: {}
    },
    builtInPluginState: {
        def: {}
    },
    greeterSyncPending: {
        def: false
    },
    greeterSyncBaseline: {
        def: {}
    },
    lastAppliedIconTheme: {
        def: ""
    },
    launcherLastMode: {
        def: "all"
    },
    launcherLastFileSearchType: {
        def: "all"
    },
    launcherLastQuery: {
        def: ""
    },
    launcherQueryHistory: {
        def: []
    },
    appDrawerLastMode: {
        def: "apps"
    },
    niriOverviewLastMode: {
        def: "apps"
    },
    showConfigReloadToast: {
        def: true
    }
};

var SPEC = Util.mergeSpec(Shared.SPEC, LOCAL_SPEC);

function getValidKeys() {
    return Object.keys(SPEC).concat(["configVersion"]);
}

function set(root, key, value, saveFn, hooks) {
    if (!(key in SPEC))
        return;
    root[key] = value;
    var hookName = SPEC[key].onChange;
    if (hookName && hooks && hooks[hookName]) {
        hooks[hookName](root);
    }
    saveFn();
}
