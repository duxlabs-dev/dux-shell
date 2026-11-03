import QtQuick
import qs.Common
import qs.Services
import qs.Modules.BuiltinDesktopPlugins
import qs.Modules.Lock.Widgets

Loader {
    id: root

    required property string pluginId
    required property DesktopWidgetGeometry geometry
    property string instanceId: ""
    property var instanceData: null
    property var screen: null
    property bool lockScreen: false
    property var lockHost: null
    property bool persistDefaults: true

    readonly property bool isInstance: instanceId !== "" && instanceData !== null
    readonly property var activeComponent: {
        switch (pluginId) {
        case "desktopClock":
            return clockComponent;
        case "systemMonitor":
            return systemMonitorComponent;
        case "lockDate":
            return lockDateComponent;
        case "lockAuth":
            return lockAuthComponent;
        case "lockNotifications":
            return lockNotificationsComponent;
        case "lockStatus":
            return lockStatusComponent;
        case "lockPower":
            return lockPowerComponent;
        case "greeterSession":
            return greeterSessionComponent;
        }
        return PluginService.pluginDesktopComponents[pluginId] ?? null;
    }
    readonly property real contentMinWidth: item?.minWidth ?? 100
    readonly property real contentMinHeight: item?.minHeight ?? 100
    readonly property bool contentForceSquare: item?.forceSquare ?? false
    readonly property bool contentResizable: item?.resizable ?? true
    readonly property real contentDefaultWidth: item?.defaultWidth ?? ((item?.implicitWidth ?? 0) > 0 ? item.implicitWidth : 280)
    readonly property real contentDefaultHeight: item?.defaultHeight ?? ((item?.implicitHeight ?? 0) > 0 ? item.implicitHeight : 180)
    readonly property bool acceptsKeyboardFocus: item?.acceptsKeyboardFocus ?? false

    property Component clockComponent: Component {
        DesktopClockWidget {}
    }

    property Component systemMonitorComponent: Component {
        SystemMonitorWidget {}
    }

    property Component lockDateComponent: Component {
        LockDateWidget {}
    }

    property Component lockAuthComponent: Component {
        LockAuthWidget {}
    }

    property Component lockNotificationsComponent: Component {
        LockNotificationsWidget {}
    }

    property Component lockStatusComponent: Component {
        LockStatusWidget {}
    }

    property Component lockPowerComponent: Component {
        LockPowerWidget {}
    }

    property Component greeterSessionComponent: Component {
        GreeterSessionWidget {}
    }

    onInstanceDataChanged: {
        if (!item || item.instanceData === undefined)
            return;
        item.instanceData = instanceData;
    }

    sourceComponent: activeComponent
    // The lock surface is presented as one frame, so its widgets must not fade in after the background.
    opacity: lockScreen ? 1 : 0

    NumberAnimation {
        id: revealFade
        target: root
        property: "opacity"
        from: 0
        to: 1
        duration: Theme.mediumDuration
        easing.type: Theme.standardEasing
    }

    QtObject {
        id: instanceScopedPluginService

        readonly property var availablePlugins: PluginService.availablePlugins
        readonly property var loadedPlugins: PluginService.loadedPlugins
        readonly property var pluginDesktopComponents: PluginService.pluginDesktopComponents

        signal pluginDataChanged(string pluginId)
        signal pluginLoaded(string pluginId)
        signal pluginUnloaded(string pluginId)

        function loadPluginData(pluginId, key, defaultValue) {
            const cfg = root.instanceData?.config;
            if (cfg && key in cfg)
                return cfg[key];
            return SettingsData.getPluginSetting(pluginId, key, defaultValue);
        }

        function savePluginData(pluginId, key, value) {
            if (!root.instanceId)
                return false;
            var updates = {};
            updates[key] = value;
            SettingsData.updateDesktopWidgetInstanceConfig(root.instanceId, updates);
            Qt.callLater(() => pluginDataChanged(pluginId));
            return true;
        }

        function getPluginVariants(pluginId) {
            return PluginService.getPluginVariants(pluginId);
        }

        function isPluginLoaded(pluginId) {
            return PluginService.isPluginLoaded(pluginId);
        }
    }

    onLoaded: {
        if (!item)
            return;
        if (!lockScreen)
            revealFade.restart();
        if (item.pluginService !== undefined)
            item.pluginService = instanceScopedPluginService;
        if (item.pluginId !== undefined)
            item.pluginId = root.pluginId;
        if (item.instanceId !== undefined)
            item.instanceId = root.instanceId;
        if (item.instanceData !== undefined)
            item.instanceData = root.instanceData;
        if (item.lockScreen !== undefined)
            item.lockScreen = root.lockScreen;
        if (item.lockHost !== undefined)
            item.lockHost = root.lockHost;
        if (root.persistDefaults)
            geometry.saveDefaultGeometry(item.defaultWidth ?? item.widgetWidth ?? 280, item.defaultHeight ?? item.widgetHeight ?? 180);
        if (item.widgetWidth !== undefined)
            item.widgetWidth = Qt.binding(() => root.width);
        if (item.widgetHeight !== undefined)
            item.widgetHeight = Qt.binding(() => root.height);
        if (item.screen !== undefined)
            item.screen = Qt.binding(() => root.screen);
        if (item.requestResize !== undefined)
            item.requestResize = geometry.requestResize;
        if (item.clearResize !== undefined)
            item.clearResize = geometry.clearResize;
    }
}
