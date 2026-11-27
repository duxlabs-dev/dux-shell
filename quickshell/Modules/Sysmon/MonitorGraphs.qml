pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Sysmon

Rectangle {
    id: root

    property var rows: []
    property string legend: "list"
    property int rangeSeconds: 60
    property color tileColor: Theme.surfaceContainerLow
    property color contentColor: Theme.surfaceText
    property color mutedColor: Theme.surfaceVariantText
    property bool halo: false
    property bool legendBeside: false

    readonly property var lines: {
        const out = [];
        for (const row of rows) {
            for (let i = 0; i < (row.values ?? []).length; i++) {
                const v = row.values[i];
                out.push({
                    name: i === 0 ? row.name : row.name + " · " + v.label,
                    text: row.asleep ? I18n.tr("Idle", "device state") : row.missing ? "—" : v.text,
                    muted: row.asleep || row.missing,
                    kind: v.kind,
                    history: v.history ?? [],
                    maximum: v.maximum ?? 100,
                    color: MonitorMetrics.linePalette[out.length % MonitorMetrics.linePalette.length]
                });
            }
        }
        return out;
    }
    readonly property bool allPercent: lines.length > 0 && lines.every(l => l.maximum === 100)
    readonly property string rangeLabel: I18n.tr("%1 min", "chart time span, %1 is a number of minutes").arg(rangeSeconds / 60)

    // Bumped as chips arrive from an asynchronous loader.
    property int builtChips: 0

    // Height of the inline legend wrapped at width w, the way its Flow lays it out.
    function inlineLegendHeight(w) {
        void builtChips;
        let x = 0;
        let lineH = 0;
        let total = 0;
        for (let i = 0; i < inlineRepeater.count; i++) {
            const chip = inlineRepeater.itemAt(i);
            if (!chip)
                continue;
            if (x > 0 && x + chip.implicitWidth > w) {
                total += lineH + inlineLegend.spacing;
                x = 0;
                lineH = 0;
            }
            x += chip.implicitWidth + inlineLegend.spacing;
            lineH = Math.max(lineH, chip.implicitHeight);
        }
        return total + lineH;
    }

    implicitHeight: content.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadiusL
    color: tileColor

    GridLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        columns: root.legendBeside ? 2 : 1
        rowSpacing: Theme.spacingS
        columnSpacing: Theme.spacingM

        Item {
            id: chart
            Layout.row: root.legend === "inline" && !root.legendBeside ? 1 : 0
            Layout.column: 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: MonitorMetrics.chartMinHeight
            Layout.preferredHeight: MonitorMetrics.chartMinHeight
            // Time runs left to right in every language.
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true
            Accessible.role: Accessible.Chart
            Accessible.name: root.lines.map(l => l.name + " " + l.text).join(", ")

            MonitorText {
                id: rangeText
                halo: root.halo
                anchors.left: parent.left
                anchors.top: parent.top
                text: root.rangeLabel
                font.pixelSize: Theme.fontSizeSmall
                color: root.mutedColor
            }
            NumericText {
                style: root.halo ? Text.Outline : Text.Normal
                styleColor: Theme.surface
                anchors.right: parent.right
                anchors.top: parent.top
                visible: root.allPercent
                text: "100"
                font.pixelSize: Theme.fontSizeSmall
                color: root.mutedColor
            }

            Item {
                id: plot
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: rangeText.bottom
                anchors.bottom: parent.bottom

                Repeater {
                    model: 3

                    Rectangle {
                        required property int index
                        width: plot.width
                        height: Theme.outlineWidth
                        y: Math.round((plot.height - height) * (index + 1) / 4)
                        color: Theme.outlineLight
                    }
                }

                Repeater {
                    model: root.lines.length

                    DSparkline {
                        required property int index
                        readonly property var line: root.lines[index] ?? ({})
                        anchors.fill: parent
                        values: line.history ?? []
                        secondaryValues: []
                        maximum: line.maximum ?? 100
                        lineColor: line.color ?? root.contentColor
                        fillOpacity: 0
                        curved: false
                        lineWidth: Theme.outlineWidthFocused
                    }
                }
            }
        }

        Item {
            Layout.row: root.legendBeside || root.legend === "inline" ? 0 : 1
            Layout.column: root.legendBeside ? 1 : 0
            Layout.fillWidth: !root.legendBeside
            Layout.preferredWidth: root.legendBeside ? MonitorMetrics.processesWidth : -1
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: root.legend === "inline" ? inlineLegend.implicitHeight : listLegend.implicitHeight
            visible: root.legend !== "off" && root.lines.length > 0

            Flow {
                id: inlineLegend
                width: parent.width
                visible: root.legend === "inline"
                spacing: Theme.spacingM

                Repeater {
                    id: inlineRepeater

                    model: root.legend === "inline" ? root.lines.length : 0
                    onItemAdded: root.builtChips++

                    Row {
                        id: item
                        required property int index
                        readonly property var modelData: root.lines[index] ?? ({})
                        spacing: Theme.spacingXS
                        opacity: modelData.muted ? Theme.pendingOpacity : 1

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.spacingL
                            height: Theme.outlineWidthFocused
                            radius: height / 2
                            color: item.modelData.color ?? root.contentColor
                        }
                        MonitorText {
                            halo: root.halo
                            width: Math.min(implicitWidth, inlineLegend.width - Theme.spacingL - inlineValue.width - item.spacing * 2)
                            text: item.modelData.name ?? ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.mutedColor
                        }
                        NumericText {
                            id: inlineValue
                            style: root.halo ? Text.Outline : Text.Normal
                            styleColor: Theme.surface
                            reserveText: MonitorMetrics.reserveFor(item.modelData.kind ?? "")
                            horizontalAlignment: Text.AlignLeft
                            text: item.modelData.text ?? ""
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: root.contentColor
                        }
                    }
                }
            }

            Column {
                id: listLegend
                width: parent.width
                visible: root.legend === "list"
                spacing: Theme.groupedListGap

                Repeater {
                    model: root.legend === "list" ? root.lines.length : 0

                    Rectangle {
                        id: entry
                        required property int index
                        readonly property var modelData: root.lines[index] ?? ({})
                        width: parent.width
                        height: MonitorMetrics.processRowHeight
                        color: root.tileColor.a > 0 ? Theme.withAlpha(root.contentColor, Theme.stateLayerHover) : "transparent"
                        radius: Theme.groupedListInnerRadius
                        topLeftRadius: index === 0 ? Theme.groupedListOuterRadius : radius
                        topRightRadius: topLeftRadius
                        bottomLeftRadius: index === root.lines.length - 1 ? Theme.groupedListOuterRadius : radius
                        bottomRightRadius: bottomLeftRadius
                        opacity: modelData.muted ? Theme.pendingOpacity : 1

                        Row {
                            anchors.left: parent.left
                            anchors.right: valueText.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.spacingL
                                height: Theme.outlineWidthFocused
                                radius: height / 2
                                color: entry.modelData.color ?? root.contentColor
                            }
                            MonitorText {
                                halo: root.halo
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Theme.spacingL - Theme.spacingS
                                text: entry.modelData.name ?? ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.mutedColor
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                        NumericText {
                            id: valueText
                            style: root.halo ? Text.Outline : Text.Normal
                            styleColor: Theme.surface
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            reserveText: MonitorMetrics.reserveFor(entry.modelData.kind ?? "")
                            horizontalAlignment: Text.AlignRight
                            text: entry.modelData.text ?? ""
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: root.contentColor
                        }
                    }
                }
            }
        }
    }
}
