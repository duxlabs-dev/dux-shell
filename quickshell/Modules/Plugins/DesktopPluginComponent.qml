import QtQuick
import qs.Common

Item {
    id: root

    property var pluginService: null
    property string pluginId: ""
    property string instanceId: ""
    property var instanceData: null
    property bool lockScreen: false

    property real widgetWidth: 200
    property real widgetHeight: 200
    property real minWidth: 100
    property real minHeight: 100

    property var requestResize: null
    property var clearResize: null

    readonly property bool isInstance: instanceId !== "" && instanceData !== null
    readonly property var instanceConfig: instanceData?.config ?? {}

    property var pluginData: isInstance ? instanceConfig : _globalPluginData
    property var _globalPluginData: ({})

    Component.onCompleted: loadPluginData()
    onPluginServiceChanged: loadPluginData()
    onPluginIdChanged: loadPluginData()
    onInstanceDataChanged: {
        if (isInstance)
            Qt.callLater(() => {
                pluginData = instanceConfig;
            });
    }

    Connections {
        target: pluginService
        enabled: pluginService !== null

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId !== pluginId)
                return;
            loadPluginData();
        }
    }

    function loadPluginData() {
        if (!pluginService || !pluginId) {
            _globalPluginData = {};
            return;
        }
        if (isInstance) {
            pluginData = instanceConfig;
            return;
        }
        _globalPluginData = SettingsData.getPluginSettingsForPlugin(pluginId);
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
