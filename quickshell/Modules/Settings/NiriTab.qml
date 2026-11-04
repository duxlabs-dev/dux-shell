import QtQuick
import qs.Common
import qs.Modules.Settings.Niri
import qs.Modules.Settings.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

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
