import QtQuick
import qs.Modules.ControlCenter.Widgets
import qs.Services

Item {
    id: root

    property string pluginId: ""
    property var builtinInstance: null

    readonly property var instance: builtinInstance ?? pluginHost.instance
    readonly property real preferredHeight: instance?.ccDetailHeight ?? 0
    readonly property bool empty: (instance?.ccDetailContent ?? null) === null
    readonly property string title: instance?.ccWidgetPrimaryText || PluginService.loadedPlugins[pluginId]?.name || PluginService.availablePluginsList.find(p => p.id === pluginId)?.name || ""

    PluginInstanceHost {
        id: pluginHost
        pluginId: root.builtinInstance ? "" : root.pluginId
    }

    Loader {
        id: contentLoader
        anchors.fill: parent
        sourceComponent: root.instance?.ccDetailContent ?? null
    }
}
