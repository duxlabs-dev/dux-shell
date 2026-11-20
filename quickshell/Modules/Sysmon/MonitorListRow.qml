pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.ProcessList
import qs.Modules.Sysmon

Item {
    id: root

    property var row: ({})
    property color accentColor: Theme.primary
    property color tileColor: Theme.surfaceContainer
    property color contentColor: Theme.surfaceText
    property color mutedColor: Theme.surfaceVariantText
    property bool halo: false
    property bool first: false
    property bool last: false

    readonly property var main: row.values?.[0] ?? null
    readonly property var extras: row.asleep ? [] : (row.values ?? []).slice(1)
    readonly property bool showTrend: !row.asleep && !!row.graph
    readonly property color levelColor: MonitorMetrics.levelColor(main?.level, accentColor)
    readonly property string valueText: row.asleep ? I18n.tr("Idle", "device state") : (main?.text ?? "—")

    // From the lines the row shows, not their live text, so it holds still while values change.
    readonly property real naturalHeight: Math.max(MonitorMetrics.listRowMinHeight, Theme.spacingS * 2 + nameText.implicitHeight + ((root.row.detail ?? "") !== "" ? Theme.spacingXXS + detailText.implicitHeight : 0) + (root.extras.length > 0 ? Theme.spacingXXS * 2 + extrasRow.implicitHeight : 0))

    implicitWidth: content.implicitWidth + Theme.spacingM * 2
    implicitHeight: naturalHeight
    Accessible.role: Accessible.StaticText
    Accessible.name: (row.name ?? "") + " " + valueText

    Rectangle {
        anchors.fill: parent
        color: root.tileColor
        topLeftRadius: root.first ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
        topRightRadius: topLeftRadius
        bottomLeftRadius: root.last ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
        bottomRightRadius: bottomLeftRadius
    }

    RowLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingM

        DeviceIcon {
            Layout.alignment: Qt.AlignVCenter
            name: root.row.icon ?? ""
            size: Theme.iconSizeMedium
            color: root.mutedColor
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: extrasRow.implicitWidth
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacingXXS

            MonitorText {
                id: nameText
                halo: root.halo
                Layout.fillWidth: true
                text: root.row.name ?? ""
                color: root.contentColor
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            MonitorText {
                id: detailText
                halo: root.halo
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: text !== ""
                text: root.row.detail ?? ""
                color: root.mutedColor
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            Row {
                id: extrasRow

                Layout.topMargin: Theme.spacingXXS
                visible: root.extras.length > 0
                spacing: Theme.spacingM

                Repeater {
                    model: root.extras.length

                    Row {
                        id: chip

                        required property int index
                        readonly property var modelData: root.extras[index] ?? ({})

                        spacing: Theme.spacingXS
                        Accessible.role: Accessible.StaticText
                        Accessible.name: (modelData.label ?? "") + " " + (modelData.text ?? "")

                        DIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: chip.modelData.icon ?? ""
                            size: Theme.iconSizeSmall
                            color: MonitorMetrics.levelColor(chip.modelData?.level, root.accentColor)
                        }

                        NumericText {
                            style: root.halo ? Text.Outline : Text.Normal
                            styleColor: Theme.surface
                            anchors.verticalCenter: parent.verticalCenter
                            reserveText: MonitorMetrics.reserveFor(chip.modelData.kind ?? "")
                            horizontalAlignment: Text.AlignLeft
                            text: chip.modelData.text ?? "—"
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.mutedColor
                        }
                    }
                }
            }
        }

        DSparkline {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: MonitorMetrics.listVisualWidth
            Layout.preferredHeight: MonitorMetrics.listVisualHeight
            visible: root.showTrend
            values: root.row.trend?.values ?? []
            secondaryValues: root.row.trend?.secondaryValues ?? []
            maximum: root.row.trend?.maximum ?? 0
            lineColor: root.levelColor
            secondaryLineColor: root.mutedColor
            fillOpacity: 0
        }

        NumericText {
            style: root.halo ? Text.Outline : Text.Normal
            styleColor: Theme.surface
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: reservedWidth
            reserveText: MonitorMetrics.reserveFor(root.main?.kind ?? "pct")
            horizontalAlignment: Text.AlignRight
            text: root.valueText
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeightMedium
            color: root.row.asleep ? root.mutedColor : root.contentColor
        }
    }
}
