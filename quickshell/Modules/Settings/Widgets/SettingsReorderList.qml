import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "../../../Common/QmlUtils.js" as QmlUtils

DReorderList {
    id: root

    readonly property bool isSettingsRow: true
    readonly property bool transparentSlot: true
    readonly property bool firstInGroup: parent?.isSettingsGroupHost ? parent.isEdge(root, true) : true
    readonly property bool lastInGroup: parent?.isSettingsGroupHost ? parent.isEdge(root, false) : true
    spacing: SettingsMetrics.groupGap
    Component.onCompleted: flickable = QmlUtils.findParentFlickable(root.parent)
}
