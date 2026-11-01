import QtQuick
import qs.Modules.Settings.Niri
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null
    property bool pageActive: false
    readonly property real contentMaxWidth: shell.width
    readonly property real paneMaxWidth: shell.maxWidth + SettingsMetrics.panePadding * 2

    NiriShell {
        id: shell
        width: Math.min(parent.width, maxWidth)
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        pageActive: root.pageActive
    }
}
