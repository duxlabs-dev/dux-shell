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

    property var rows: []
    property bool barNames: false
    property color accentColor: Theme.primary
    property color contentColor: Theme.surfaceText
    property color mutedColor: Theme.surfaceVariantText
    property bool halo: false
    property bool vertical: false
    readonly property string idleText: I18n.tr("Idle", "device state")
    readonly property string reserveText: widestSample(false)
    readonly property string shortReserveText: widestSample(true)

    function widestSample(short) {
        let best = MonitorMetrics.reserveFor("pct", short);
        for (const r of rows ?? []) {
            for (const v of r.values ?? []) {
                const s = MonitorMetrics.reserveFor(v.kind, short);
                if (s.length > best.length)
                    best = s;
            }
        }
        return best;
    }

    implicitHeight: layout.implicitHeight
    implicitWidth: layout.implicitWidth

    component Glyph: Item {
        id: glyph

        required property BarLine owner

        implicitWidth: Theme.iconSizeSmall
        implicitHeight: Theme.iconSizeSmall

        DeviceIcon {
            anchors.centerIn: parent
            name: glyph.owner.main ? (glyph.owner.row.icon ?? "") : (glyph.owner.entry.icon ?? "")
            size: Theme.iconSizeSmall
            color: glyph.owner.asleep ? root.mutedColor : glyph.owner.color
        }
    }

    component Track: Rectangle {
        id: track

        required property BarLine owner
        property bool upright: false

        radius: Theme.fullRadius(width, height)
        color: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: parent.upright ? parent.width : parent.width * track.owner.fraction
            height: parent.upright ? parent.height * track.owner.fraction : parent.height
            radius: parent.radius
            color: track.owner.color

            MeterBehavior on width {}
            MeterBehavior on height {}
        }
    }

    component BarLine: Item {
        id: line

        required property var row
        required property var entry
        property bool main: false

        readonly property bool asleep: row.asleep === true
        readonly property color color: MonitorMetrics.levelColor(entry?.level, root.accentColor)
        readonly property real fraction: asleep ? 0 : Math.min(Math.max(entry.fraction ?? 0, 0), 1)
        readonly property real thickness: main ? MonitorMetrics.barThickness : MonitorMetrics.barThicknessExtra
        readonly property string valueText: asleep ? root.idleText : root.vertical ? (entry.shortText ?? entry.text ?? "—") : (entry.text ?? "—")
        readonly property color valueColor: asleep || !main ? root.mutedColor : root.contentColor

        implicitWidth: root.vertical ? Math.max(verticalColumn.implicitWidth, thickness) : horizontalRow.implicitWidth
        implicitHeight: root.vertical ? verticalColumn.implicitHeight : horizontalRow.implicitHeight
        Accessible.role: Accessible.StaticText
        Accessible.name: (row.name ?? "") + " " + (entry.label ?? "") + " " + valueText

        RowLayout {
            id: horizontalRow
            anchors.fill: parent
            visible: !root.vertical
            spacing: Theme.spacingM

            Glyph {
                owner: line
                Layout.alignment: Qt.AlignVCenter
            }

            MonitorText {
                halo: root.halo
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: MonitorMetrics.barNameWidth
                visible: root.barNames
                text: line.main ? (line.row.name ?? "") : ""
                color: root.contentColor
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                elide: Text.ElideRight
            }

            Track {
                owner: line
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: line.thickness
            }

            NumericText {
                style: root.halo ? Text.Outline : Text.Normal
                styleColor: Theme.surface
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: reservedWidth
                text: line.valueText
                reserveText: root.reserveText
                font.pixelSize: line.main ? Theme.fontSizeMedium : Theme.fontSizeSmall
                font.weight: line.main ? Theme.fontWeightMedium : Font.Normal
                color: line.valueColor
            }
        }

        ColumnLayout {
            id: verticalColumn
            anchors.fill: parent
            visible: root.vertical
            spacing: Theme.spacingS

            NumericText {
                style: root.halo ? Text.Outline : Text.Normal
                styleColor: Theme.surface
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: reservedWidth
                text: line.valueText
                reserveText: root.shortReserveText
                font.pixelSize: line.main ? Theme.fontSizeMedium : Theme.fontSizeSmall
                font.weight: line.main ? Theme.fontWeightMedium : Font.Normal
                color: line.valueColor
            }

            Track {
                owner: line
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.preferredWidth: line.thickness
                Layout.minimumHeight: MonitorMetrics.barThickness
                upright: true
            }

            Glyph {
                owner: line
                Layout.alignment: Qt.AlignHCenter
            }

            MonitorText {
                halo: root.halo
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: MonitorMetrics.barNameWidth
                visible: root.barNames
                text: line.main ? (line.row.name ?? "") : " "
                color: root.mutedColor
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }
    }

    component Group: Item {
        id: group

        required property var row

        readonly property var entries: row.asleep ? (row.values ?? []).slice(0, 1) : (row.values ?? [])

        implicitWidth: root.vertical ? verticalGroup.implicitWidth : horizontalGroup.implicitWidth
        implicitHeight: root.vertical ? verticalGroup.implicitHeight : horizontalGroup.implicitHeight

        ColumnLayout {
            id: horizontalGroup
            anchors.fill: parent
            visible: !root.vertical
            spacing: Theme.spacingS

            Repeater {
                model: root.vertical ? 0 : group.entries.length

                BarLine {
                    required property int index

                    Layout.fillWidth: true
                    row: group.row
                    entry: group.entries[index] ?? ({})
                    main: index === 0
                }
            }
        }

        RowLayout {
            id: verticalGroup
            anchors.fill: parent
            visible: root.vertical
            spacing: Theme.spacingS

            Repeater {
                model: root.vertical ? group.entries.length : 0

                BarLine {
                    required property int index

                    Layout.fillHeight: true
                    row: group.row
                    entry: group.entries[index] ?? ({})
                    main: index === 0
                }
            }
        }
    }

    GridLayout {
        id: layout
        anchors.fill: parent
        rows: root.vertical ? 1 : -1
        columns: root.vertical ? -1 : 1
        flow: root.vertical ? GridLayout.LeftToRight : GridLayout.TopToBottom
        rowSpacing: 0
        columnSpacing: root.vertical ? Theme.spacingM : 0

        Repeater {
            model: root.rows.length

            Item {
                id: slot

                required property int index

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                implicitWidth: groupItem.implicitWidth
                implicitHeight: groupItem.implicitHeight + Theme.spacingL

                Group {
                    id: groupItem
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.vertical ? implicitWidth : parent.width
                    height: root.vertical ? parent.height : implicitHeight
                    row: root.rows[slot.index] ?? ({})
                }
            }
        }
    }
}
