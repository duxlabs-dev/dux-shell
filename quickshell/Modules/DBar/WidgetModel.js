.pragma library

function normalize(widgets) {
    return (widgets || []).map((widget, index) => {
        if (typeof widget === "string")
            return {
                widgetId: widget,
                id: widget + "_" + index,
                enabled: true
            };

        const entry = Object.assign({}, widget);
        entry.widgetId = widget.id || widget.widgetId;
        entry.id = entry.widgetId + "_" + index;
        entry.enabled = widget.enabled !== false;
        return entry;
    });
}

var componentNames = {
    "launcherButton": "launcherButtonComponent",
    "workspaceSwitcher": "workspaceSwitcherComponent",
    "focusedWindow": "focusedWindowComponent",
    "runningApps": "runningAppsComponent",
    "clock": "clockComponent",
    "music": "mediaComponent",
    "music:activity": "mediaActivityComponent",
    "weather": "weatherComponent",
    "systemTray": "systemTrayComponent",
    "privacyIndicator": "privacyIndicatorComponent",
    "clipboard": "clipboardComponent",
    "cpuUsage": "cpuUsageComponent",
    "memUsage": "memUsageComponent",
    "diskUsage": "diskUsageComponent",
    "cpuTemp": "cpuTempComponent",
    "gpuTemp": "gpuTempComponent",
    "notificationButton": "notificationButtonComponent",
    "battery": "batteryComponent",
    "controlCenterButton": "controlCenterButtonComponent",
    "capsLockIndicator": "capsLockIndicatorComponent",
    "idleInhibitor": "idleInhibitorComponent",
    "spacer": "spacerComponent",
    "separator": "separatorComponent",
    "network_speed_monitor": "networkComponent",
    "keyboard_layout_name": "keyboardLayoutNameComponent",
    "vpn": "vpnComponent",
    "notepadButton": "notepadButtonComponent",
    "colorPicker": "colorPickerComponent",
    "systemUpdate": "systemUpdateComponent",
    "layout": "layoutComponent",
    "powerMenuButton": "powerMenuButtonComponent",
    "appsDock": "appsDockComponent",
    "island": "islandComponent"
};

function builtinComponents(components) {
    const result = {};
    for (const id of Object.keys(componentNames))
        result[id] = components[componentNames[id]];
    return result;
}
