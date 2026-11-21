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
    readonly property string maximumLabel: I18n.tr("Max %1", "chart axis maximum, %1 is a value like 12 MB/s").arg(maximumText)
    property int historyLength: 0
    // Shows only the newest part of the history; 0 shows all of it.
    property int rangeSeconds: 0
    property bool legendVisible: true
    property bool grid: true
    property real chartHeight: Theme.listItemHeight * 2
    property color cardColor: ProcessListMetrics.cardColor
    property bool compact: false
    readonly property real padding: compact ? 0 : Theme.spacingL

    readonly property bool hasSecondary: secondaryLabel !== ""
    readonly property int rangePoints: rangeSeconds > 0 ? Math.max(1, Math.round(rangeSeconds * 1000 / DgopService.updateInterval)) : 0
    readonly property int spanSeconds: rangeSeconds > 0 ? rangeSeconds : Math.round((historyLength > 0 ? historyLength : DgopService.historySize) * DgopService.updateInterval / 1000)

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
            visible: root.legendVisible

            Row {
                id: legendRow
                spacing: Theme.spacingL

                ChartLegendItem {
                    text: root.label
                    value: root.compact ? "" : root.valueText
                    swatchColor: Theme.primary
                }

                ChartLegendItem {
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
                text: root.maximumLabel
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
            values: root.rangePoints > 0 ? root.values.slice(-root.rangePoints) : root.values
            secondaryValues: !root.hasSecondary ? [] : root.rangePoints > 0 ? root.secondaryValues.slice(-root.rangePoints) : root.secondaryValues
            maximum: root.maximum
            historyLength: root.rangePoints > 0 ? root.rangePoints : root.historyLength
            grid: root.grid
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
}
