pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.ProcessList
import qs.Modules.Sysmon

Item {
    id: root

    property var row: ({})
    property bool stacked: false
    property real labelWidth: 0
    property string valueReserve: ""
    property color accentColor: Theme.primary
    property color cardColor: Theme.surfaceContainer
    property real cardRadius: Theme.cornerRadiusL
    property color contentColor: Theme.surfaceText
    property color mutedColor: Theme.surfaceVariantText
    property bool halo: false

    readonly property bool asleep: row.asleep === true
    readonly property var entries: asleep ? (row.values ?? []).slice(0, 1) : (row.values ?? [])
    readonly property real naturalHeight: content.implicitHeight + Theme.spacingS * 2

    implicitWidth: content.implicitWidth + Theme.spacingM * 2
    implicitHeight: naturalHeight

    Rectangle {
        anchors.fill: parent
        radius: root.cardRadius
        color: root.cardColor
    }

    GridLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        columns: root.stacked ? 1 : 2
        columnSpacing: Theme.spacingM
        rowSpacing: Theme.spacingS

        GridLayout {
            Layout.alignment: root.stacked ? Qt.AlignLeft : Qt.AlignCenter
            Layout.preferredWidth: root.stacked ? -1 : MonitorMetrics.barNameWidth
            columns: root.stacked ? 2 : 1
            columnSpacing: Theme.spacingS
            rowSpacing: Theme.spacingXS

            DeviceIcon {
                Layout.alignment: root.stacked ? Qt.AlignVCenter : Qt.AlignHCenter
                name: root.row.icon ?? ""
                size: Theme.iconSizeSmall
                color: root.mutedColor
            }

            MonitorText {
                Layout.alignment: root.stacked ? Qt.AlignVCenter : Qt.AlignHCenter
                Layout.maximumWidth: MonitorMetrics.barNameWidth
                halo: root.halo
                text: root.row.name ?? ""
                color: root.contentColor
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacingS

            Repeater {
                model: root.entries.length

                RowLayout {
                    id: line

                    required property int index
                    readonly property var entry: root.entries[index] ?? ({})
                    readonly property real fraction: root.asleep ? 0 : Math.min(Math.max(entry.fraction ?? 0, 0), 1)
                    readonly property string valueText: root.asleep ? I18n.tr("Idle", "device state") : (entry.shortText ?? entry.text ?? "—")

                    Layout.fillWidth: true
                    spacing: Theme.spacingS
                    Accessible.role: Accessible.StaticText
                    Accessible.name: (root.row.name ?? "") + " " + (entry.label ?? "") + " " + valueText

                    MonitorText {
                        Layout.preferredWidth: root.labelWidth
                        halo: root.halo
                        text: SysmonService.shortValueLabel(root.row.type ?? "", line.entry.id ?? "")
                        color: root.mutedColor
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideRight
                    }

                    MonitorTrack {
                        Layout.fillWidth: true
                        Layout.minimumWidth: MonitorMetrics.listVisualWidth / 2
                        Layout.preferredHeight: MonitorMetrics.cardBarThickness
                        Layout.alignment: Qt.AlignVCenter
                        color: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)
                        fraction: line.fraction
                        fillColor: MonitorMetrics.levelColor(line.entry.level, root.accentColor)
                        primary: line.index === 0
                    }

                    NumericText {
                        Layout.preferredWidth: reservedWidth
                        style: root.halo ? Text.Outline : Text.Normal
                        styleColor: Theme.surface
                        reserveText: root.valueReserve
                        horizontalAlignment: Text.AlignRight
                        text: line.valueText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: line.index === 0 ? Theme.fontWeightMedium : Font.Normal
                        color: root.asleep || line.index > 0 ? root.mutedColor : root.contentColor
                    }
                }
            }
        }
    }
}
