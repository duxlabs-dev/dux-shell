import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets

Item {
    id: root

    property var device: ({})
    property string valueText: device.value ?? ""
    property string valueTooltip: device.valueTooltip ?? ""
    property color textColor: Theme.surfaceText
    property color supportingColor: Theme.surfaceVariantText
    property color iconColor: supportingColor
    property color sparkColor: Theme.primary
    property color sparkSecondaryColor: Theme.tertiary
    property real iconSize: Theme.iconSize
    property real iconBoxSize: iconSize
    property real nameSize: Theme.fontSizeMedium
    property real sparkOpacity: 1
    property int historyLength: DgopService.historySize
    // Items drawn behind the icon, such as a type shape.
    default property alias iconBackground: iconBox.data

    Item {
        id: iconBox
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.iconBoxSize
        height: width

        DeviceIcon {
            anchors.centerIn: parent
            z: 1
            name: root.device.icon ?? ""
            size: root.iconSize
            color: root.iconColor
        }
    }

    Column {
        anchors.left: iconBox.right
        anchors.leftMargin: Theme.spacingM
        anchors.right: spark.left
        anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter

        StyledText {
            width: parent.width
            text: root.device.name ?? ""
            color: root.textColor
            font.pixelSize: root.nameSize
            font.weight: Theme.fontWeightMedium
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        StyledText {
            id: valueLabel
            width: parent.width
            text: root.valueText
            color: root.supportingColor
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
            maximumLineCount: 1

            MouseArea {
                id: valueHover
                anchors.fill: parent
                enabled: root.valueTooltip !== ""
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
            }

            DTooltipHost {
                text: root.valueTooltip
                target: valueLabel
                multiline: true
                hoverArea: valueHover
            }
        }
    }

    MetricChart {
        id: spark
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: ProcessListMetrics.sparkWidth
        height: ProcessListMetrics.sparkHeight
        opacity: root.sparkOpacity
        visible: opacity > 0
        compact: true
        values: root.device.values ?? []
        secondaryValues: root.device.secondaryValues ?? []
        color: root.sparkColor
        secondaryColor: root.sparkSecondaryColor
        maximum: root.device.maximum ?? 0
        historyLength: root.historyLength
    }
}
