import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Rectangle {
    id: root

    property string label: ""
    property string iconName: ""
    property color tone: Theme.primary
    property bool interactive: false
    property bool active: false
    property var tooltipText: null

    signal clicked

    height: Theme.iconSize
    width: content.implicitWidth + Theme.spacingS * 2
    radius: Theme.cornerRadiusS
    color: active ? Theme.primaryContainer : SettingsMetrics.controlColor
    border.color: active ? Theme.primary : Theme.outlineVariant
    border.width: Theme.outlineWidth

    StateLayer {
        visible: root.interactive
        enabled: root.interactive
        stateColor: root.tone
        tooltipText: root.tooltipText
        onClicked: root.clicked()
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.spacingXXS

        DIcon {
            name: root.iconName
            size: Theme.iconSizeSmall
            color: root.tone
            visible: root.iconName.length > 0
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: root.label
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: root.tone
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
