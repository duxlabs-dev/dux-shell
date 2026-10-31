import QtQuick
import qs.Services

Item {
    id: root

    property string pluginId: ""
    property var pluginService: null
    property string token: ""
    property string kind: "live"
    property var activityData: ({})
    property bool expanded: false
    property bool interrupted: false
    property string screen: ""
    property string edge: "top"
    // In the overflow layer's coordinates; follows the island's spring while overflowContent is set, zero otherwise.
    property rect islandRect: Qt.rect(0, 0, 0, 0)
    property real islandRadius: 0

    property Component compactContent: null
    property Component expandedContent: null
    property Component overflowContent: null
    property real compactLength: 240
    property real expandedWidth: 460
    property real expandedHeight: 200

    visible: false

    function dismiss() {
        IslandActivityService.remove(root.token, "dismissed");
    }
}
