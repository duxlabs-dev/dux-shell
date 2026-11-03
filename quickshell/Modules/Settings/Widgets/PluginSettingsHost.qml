import QtQuick
import qs.Services

FocusScope {
    id: root

    property string settingsPath: ""
    property bool active: true
    property var pluginService: PluginService

    readonly property int status: loader.status
    readonly property bool loaded: loader.status === Loader.Ready && loader.item !== null

    implicitHeight: loader.item ? loader.item.implicitHeight : 0

    Loader {
        id: loader
        anchors.fill: parent
        asynchronous: false
        active: root.active && root.settingsPath !== ""
        source: {
            if (!active)
                return "";
            return root.settingsPath.startsWith("file://") ? root.settingsPath : "file://" + root.settingsPath;
        }

        onLoaded: {
            if (!item)
                return;
            item.pluginService = root.pluginService;
            if ("popoutService" in item)
                item.popoutService = PopoutService;
        }
    }
}
