import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

DesktopWidgetInstanceSettings {
    id: root

    property string widgetType: ""
    property var widgetDef: null

    readonly property string settingsPath: {
        const path = widgetDef?.settingsComponent ?? "";
        // absolute paths must load via file: or sibling plugin types resolve against the qs: scheme and fail
        return path.startsWith("/") ? "file://" + path : path;
    }

    showAppearance: false
    showPlacement: settingsPath === ""

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
            return SettingsData.getPluginSetting(root.widgetType, key, defaultValue);
        }

        function savePluginData(pluginId, key, value) {
            root.updateConfig(key, value);
            Qt.callLater(() => pluginDataChanged(root.widgetType));
            return true;
        }

        function getPluginVariants(pluginId) {
            return PluginService.getPluginVariants(pluginId);
        }

        function isPluginLoaded(pluginId) {
            return PluginService.isPluginLoaded(pluginId);
        }
    }

    function hasSettingsGroup(node, depth) {
        if (!node || depth > 3)
            return false;
        const list = node.content ?? node.children ?? [];
        for (let i = 0; i < list.length; i++) {
            const child = list[i];
            if (child?.isSettingsGroup === true)
                return true;
            if (hasSettingsGroup(child, depth + 1))
                return true;
        }
        return false;
    }

    Loader {
        id: settingsLoader

        width: parent ? parent.width : 0
        active: root.settingsPath !== ""
        source: root.settingsPath

        onLoaded: {
            if (!item)
                return;
            if (root.hasSettingsGroup(item, 0)) {
                settingsLoader.parent = root.cardsHost;
                settingsLoader.x = 0;
                settingsLoader.y = 0;
            }
            if (item.instanceId !== undefined)
                item.instanceId = root.instanceId;
            if (item.instanceData !== undefined)
                item.instanceData = Qt.binding(() => root.instanceData);
            if (item.pluginService !== undefined)
                item.pluginService = instanceScopedPluginService;
            if (item.reloadChildValues)
                Qt.callLater(item.reloadChildValues);
        }
    }
}
