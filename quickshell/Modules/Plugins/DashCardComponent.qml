import QtQuick
import qs.Common
import qs.Modules.DDash.Overview

Card {
    id: root

    property string pluginId: ""
    property var pluginService: null
    property var popoutService: null
    property bool opensTab: true
    property bool live: Window.window?.visible ?? false
    property var pluginData: ({})

    signal navFocusRequested

    Component.onCompleted: loadPluginData()
    onPluginServiceChanged: loadPluginData()
    onPluginIdChanged: loadPluginData()

    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId !== root.pluginId)
                return;
            root.loadPluginData();
        }
    }

    function loadPluginData() {
        if (!pluginService || !pluginId) {
            pluginData = {};
            return;
        }
        pluginData = SettingsData.getPluginSettingsForPlugin(pluginId);
    }

    function getData(key, defaultValue) {
        if (!pluginService || !pluginId)
            return defaultValue;
        return pluginService.loadPluginData(pluginId, key, defaultValue);
    }

    function setData(key, value) {
        if (!pluginService || !pluginId)
            return;
        pluginService.savePluginData(pluginId, key, value);
    }
}
