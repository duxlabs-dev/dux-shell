import QtQuick
import qs.Common
import qs.DCommon.Widgets

StyledRect {
    id: root

    property string symbol: ""
    property color iconColor: Theme.surfaceText
    default property alias content: slot.data

    width: Theme.iconButtonSize
    height: Theme.iconButtonSize
    radius: Theme.cornerRadiusM
    color: SettingsMetrics.controlColor

    DIcon {
        anchors.centerIn: parent
        name: root.symbol
        size: Theme.iconSizeMedium
        color: root.iconColor
        visible: root.symbol !== ""
    }

    Item {
        id: slot
        anchors.fill: parent
    }
}
