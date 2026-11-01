pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import "../Common/settings/SettingsSpec.js" as Spec

Singleton {
    id: root

    property var registeredWidgets: ({})
    property var registeredWidgetsList: []
    property bool editing: false
    property string libraryScreen: ""
    property string optionsScreen: ""
    property string optionsInstanceId: ""

    signal registryChanged

    onEditingChanged: {
        if (editing)
            return;
        libraryScreen = "";
        optionsScreen = "";
        optionsInstanceId = "";
    }

    function startEditing(screen, openLibrary) {
        libraryScreen = openLibrary ? (screen?.name ?? "") : "";
        editing = true;
    }

    function editOptions(screen, instanceId) {
        optionsScreen = screen?.name ?? "";
        optionsInstanceId = instanceId;
        startEditing(screen, false);
    }

    Component.onCompleted: {
        registerBuiltins();
        registerLockBuiltins();
        Qt.callLater(syncPluginWidgets);
    }

    Connections {
        target: PluginService
        function onPluginLoaded(pluginId) {
            if (PluginService.pluginDesktopComponents[pluginId] !== undefined)
                syncPluginWidgets();
        }
        function onPluginUnloaded(pluginId) {
            syncPluginWidgets();
        }
        function onPluginListUpdated() {
            syncPluginWidgets();
        }
    }

    function registerBuiltins() {
        registerWidget({
            id: "desktopClock",
            name: I18n.tr("Clock"),
            icon: "schedule",
            description: I18n.tr("Analog, digital, stacked, expressive, or overlapping clock", "Desktop clock widget description"),
            type: "builtin",
            component: "qs.Modules.BuiltinDesktopPlugins.DesktopClockWidget",
            settingsComponent: "qs.Modules.Settings.DesktopWidgetSettings.ClockSettings",
            greeter: true,
            defaultConfig: getDefaultClockConfig(),
            defaultSize: {
                width: 280,
                height: 180
            }
        });

        registerWidget({
            id: "systemMonitor",
            name: I18n.tr("System Monitor", "System monitor widget name"),
            icon: "monitoring",
            description: I18n.tr("CPU, memory, network, and disk monitoring", "System monitor widget description"),
            type: "builtin",
            component: "qs.Modules.BuiltinDesktopPlugins.SystemMonitorWidget",
            settingsComponent: "qs.Modules.Settings.DesktopWidgetSettings.SystemMonitorSettings",
            defaultConfig: getDefaultSystemMonitorConfig(),
            defaultSize: {
                width: 320,
                height: 480
            }
        });
    }

    function registerLockBuiltins() {
        const lockWidget = (id, name, icon, greeter) => registerWidget({
                id: id,
                name: name,
                icon: icon,
                description: "",
                type: "builtin",
                lockOnly: true,
                greeter: greeter,
                defaultConfig: Spec.SPEC.lockScreenWidgetInstances.def.find(inst => inst.widgetType === id)?.config ?? {},
                defaultSize: {
                    width: 200,
                    height: 200
                }
            });
        lockWidget("lockDate", I18n.tr("Date"), "event", true);
        lockWidget("lockAuth", I18n.tr("Password"), "lock", true);
        lockWidget("lockNotifications", I18n.tr("Notifications"), "notifications", false);
        lockWidget("lockStatus", I18n.tr("Status"), "wifi", true);
        lockWidget("lockPower", I18n.tr("Power"), "power_settings_new", true);
        registerWidget({
            id: "greeterSession",
            name: I18n.tr("Session", "greeter session picker widget"),
            icon: "login",
            description: "",
            type: "builtin",
            lockOnly: true,
            greeterOnly: true,
            greeter: true,
            defaultConfig: Spec.greeterSessionDefault().config,
            defaultSize: {
                width: 200,
                height: 48
            }
        });
    }

    function getDefaultClockConfig() {
        return {
            style: "analog",
            transparency: 0.8,
            colorMode: "primary",
            customColor: "#ffffff",
            showDate: true,
            showAnalogNumbers: false,
            showAnalogSeconds: true,
            displayPreferences: ["all"]
        };
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
            displayPreferences: ["all"]
        };
    }

    function registerWidget(widgetDef) {
        if (!widgetDef?.id)
            return;

        const newMap = Object.assign({}, registeredWidgets);
        newMap[widgetDef.id] = widgetDef;
        registeredWidgets = newMap;
        _updateWidgetsList();
        registryChanged();
    }

    function unregisterWidget(widgetId) {
        if (!registeredWidgets[widgetId])
            return;

        const newMap = Object.assign({}, registeredWidgets);
        delete newMap[widgetId];
        registeredWidgets = newMap;
        _updateWidgetsList();
        registryChanged();
    }

    function getWidget(widgetType) {
        return registeredWidgets[widgetType] ?? null;
    }

    function getDefaultConfig(widgetType) {
        const widget = getWidget(widgetType);
        if (!widget)
            return {};

        switch (widgetType) {
        case "desktopClock":
            return getDefaultClockConfig();
        case "systemMonitor":
            return getDefaultSystemMonitorConfig();
        }
        return JSON.parse(JSON.stringify(widget.defaultConfig ?? {}));
    }

    function showsOnScreen(prefs, screen) {
        if (!Array.isArray(prefs) || prefs.length === 0 || prefs.includes("all"))
            return true;
        const screenKey = SettingsData.getScreenDisplayName(screen);
        return prefs.some(p => {
            if (typeof p === "string")
                return p === screenKey || p === screen?.name;
            return p?.name === screen?.name || p === screenKey;
        });
    }

    function getDefaultSize(widgetType) {
        const widget = getWidget(widgetType);
        return widget?.defaultSize ?? {
            width: 200,
            height: 200
        };
    }

    function syncPluginWidgets() {
        const desktopPlugins = PluginService.pluginDesktopComponents;
        const availablePlugins = PluginService.availablePlugins;
        const currentPluginIds = [];

        for (const pluginId in desktopPlugins) {
            currentPluginIds.push(pluginId);
            const plugin = availablePlugins[pluginId];
            if (!plugin)
                continue;

            if (registeredWidgets[pluginId]?.type === "plugin")
                continue;

            registerWidget({
                id: pluginId,
                name: plugin.name || pluginId,
                icon: plugin.icon || "extension",
                description: plugin.description || "",
                type: "plugin",
                component: null,
                settingsComponent: PluginService.pluginComponentUrl(pluginId, plugin.settingsPath) || null,
                defaultConfig: {
                    displayPreferences: ["all"]
                },
                defaultSize: {
                    width: 200,
                    height: 200
                },
                pluginInfo: plugin
            });
        }

        const toRemove = [];
        for (const widgetId in registeredWidgets) {
            const widget = registeredWidgets[widgetId];
            if (widget.type !== "plugin")
                continue;
            if (!currentPluginIds.includes(widgetId))
                toRemove.push(widgetId);
        }

        for (const widgetId of toRemove) {
            unregisterWidget(widgetId);
        }
    }

    function _updateWidgetsList() {
        const result = [];
        for (const key in registeredWidgets) {
            result.push(registeredWidgets[key]);
        }
        result.sort((a, b) => {
            if (a.type === "builtin" && b.type !== "builtin")
                return -1;
            if (a.type !== "builtin" && b.type === "builtin")
                return 1;
            return (a.name || "").localeCompare(b.name || "");
        });
        registeredWidgetsList = result;
    }

    function getBuiltinWidgets() {
        return registeredWidgetsList.filter(w => w.type === "builtin" && !w.lockOnly);
    }

    function getDesktopWidgets() {
        return registeredWidgetsList.filter(w => !w.lockOnly);
    }

    function getLockWidgets() {
        return registeredWidgetsList.filter(w => !w.greeterOnly);
    }

    function getGreeterWidgets() {
        return registeredWidgetsList.filter(w => w.greeter);
    }

    function getListWidgets(listKey) {
        switch (listKey) {
        case "lockScreenWidgetInstances":
            return getLockWidgets();
        case "greeterWidgetInstances":
            return getGreeterWidgets();
        }
        return getDesktopWidgets();
    }

    function getPluginWidgets() {
        return registeredWidgetsList.filter(w => w.type === "plugin");
    }

    function getAllWidgets() {
        return registeredWidgetsList;
    }
}
