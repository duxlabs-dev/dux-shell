import QtQuick

Item {
    id: root

    property string pluginId: ""
    property var pluginService: null
    // The island's system source: kind, value, ratio, muted, displayValue, iconName, setRatio(), toggleMute().
    property var model: null

    property Component compactContent: null
    property Component expandedContent: null
    // Zero keeps the shell's own size for that shape.
    property real compactLength: 0
    property real expandedWidth: 0
    property real expandedHeight: 0

    visible: false
}
