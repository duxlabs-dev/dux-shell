pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Rectangle {
    id: root

    property string label: ""
    property string valueText: ""
    property string secondaryLabel: ""
    property string secondaryValueText: ""
    property var values: []
    property var secondaryValues: []
    property real maximum: 0
    property string maximumText: ""
    property int historyLength: 0
    property real chartHeight: Theme.listItemHeight * 2
    property color cardColor: Theme.surfaceContainerLow
    property bool compact: false
    readonly property real padding: compact ? 0 : Theme.spacingL

    readonly property bool hasSecondary: secondaryLabel !== ""
    readonly property int spanSeconds: Math.round((historyLength > 0 ? historyLength : DgopService.historySize) * DgopService.updateInterval / 1000)

    implicitHeight: content.implicitHeight + padding * 2
    radius: Theme.cornerRadiusL
    color: cardColor

    Column {
        id: content
        x: root.padding
        y: root.padding
        width: parent.width - root.padding * 2
        spacing: Theme.spacingS

        Item {
            width: parent.width
            height: legendRow.implicitHeight

            Row {
                id: legendRow
                spacing: Theme.spacingL

                LegendItem {
                    text: root.label
                    value: root.compact ? "" : root.valueText
                    swatchColor: Theme.primary
                }

                LegendItem {
                    visible: root.hasSecondary
                    text: root.secondaryLabel
                    value: root.compact ? "" : root.secondaryValueText
                    swatchColor: Theme.tertiary
                    dashed: true
                }
            }

            StyledText {
                anchors.right: parent.right
                anchors.verticalCenter: legendRow.verticalCenter
                visible: !root.compact && root.maximumText !== ""
                text: I18n.tr("Max %1", "chart axis maximum, %1 is a value like 12 MB/s").arg(root.maximumText)
                font.pixelSize: Theme.fontSizeSmall
                font.features: {
                    "tnum": 1
                }
                color: Theme.surfaceVariantText
            }
        }

        MetricChart {
            width: parent.width
            height: root.chartHeight
            values: root.values
            secondaryValues: root.hasSecondary ? root.secondaryValues : []
            maximum: root.maximum
            historyLength: root.historyLength
        }

        Item {
            width: parent.width
            height: axisStart.implicitHeight
            visible: !root.compact

            StyledText {
                id: axisStart
                text: root.spanSeconds % 60 === 0 ? I18n.tr("%1 min").arg(root.spanSeconds / 60) : I18n.tr("%1 seconds").arg(root.spanSeconds)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.right: parent.right
                text: I18n.tr("now")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }

    component LegendItem: Row {
        id: legendItem

        property string text: ""
        property string value: ""
        property color swatchColor: Theme.primary
        property bool dashed: false

        spacing: Theme.spacingXS

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXXS

            Repeater {
                model: legendItem.dashed ? 2 : 1

                Rectangle {
                    width: legendItem.dashed ? Theme.spacingS : Theme.spacingL
                    height: Theme.outlineWidthFocused
                    radius: height / 2
                    color: legendItem.swatchColor
                }
            }
        }

        StyledText {
            text: legendItem.text
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        NumericText {
            visible: text !== ""
            text: legendItem.value
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }
    }
}
