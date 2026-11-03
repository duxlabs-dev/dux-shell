import QtQuick
import qs.Common
import qs.Modules.DDash

Item {
    id: root

    property string pluginId: ""
    property var pluginService: null
    property var popoutService: null
    property var dashHost: null
    property var transientSurfaceTracker: null
    property string entryId: ""
    property Item focusTarget: null
    property bool editMode: false
    property var widgetGrid: null
    property var menuActions: []
    readonly property bool editable: widgetGrid !== null
    readonly property var addable: widgetGrid?.addable ?? []
    property bool blocksTabNavigation: widgetGrid?.blocksTabNavigation ?? false
    property bool live: Window.window?.visible ?? false
    property var pluginData: ({})
    readonly property var options: DashRegistry.resolvedOptions(entryId)

    signal tabRequested(string id)
    signal navFocusRequested

    implicitWidth: DashMetrics.contentWidthFor(SettingsData.showWeekNumber)
    implicitHeight: DashMetrics.tabMinHeight

    Component.onCompleted: loadPluginData()
    onPluginServiceChanged: loadPluginData()
    onPluginIdChanged: loadPluginData()

    Binding {
        target: root.widgetGrid
        property: "transientSurfaceTracker"
        value: root.transientSurfaceTracker
        when: root.widgetGrid !== null
    }

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

    function openAddMenu(anchor) {
        widgetGrid?.openAddMenu(anchor);
    }

    function resetWidgets() {
        widgetGrid?.resetWidgets();
    }

    function clearWidgets() {
        widgetGrid?.clearWidgets();
    }

    function handleKeyEvent(event) {
        return widgetGrid?.handleKeyEvent(event) ?? false;
    }

    function cycleFocus(backwards) {
        return widgetGrid?.cycleFocus(backwards) ?? false;
    }
}
