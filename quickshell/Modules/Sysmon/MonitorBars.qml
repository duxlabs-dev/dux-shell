pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.DCommon.Common as DCommon
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
    property color tileColor: "transparent"
    property real tileRadius: Theme.cornerRadiusL
    property bool tiled: false
    readonly property real tilePad: !tiled ? 0 : vertical ? Theme.spacingS : Theme.spacingM
    readonly property string idleText: I18n.tr("Idle", "device state")
    readonly property int count: rows.length

    readonly property string readLetter: I18n.tr("R", "system monitor bars: short marker for disk read")
    readonly property string writeLetter: I18n.tr("W", "system monitor bars: short marker for disk write", true)
    // Letter markers are translated, so their column fits the wider one.
    readonly property real markerWidth: Math.max(MonitorMetrics.markerSize, Math.ceil(DCommon.Fonts.textWidth(markerProbe.font, readLetter)), Math.ceil(DCommon.Fonts.textWidth(markerProbe.font, writeLetter)))
    readonly property real columnWidth: Math.max(shortProbe.reservedWidth, markerWidth, MonitorMetrics.barWidth)
    readonly property real columnGap: Theme.spacingXS
    property real availableHeight: Infinity
    // A single value's group is two lines tall, so its bracket keeps its shape, unless the stack then needs columns.
    readonly property bool tight: !vertical && stackHeight(2, Theme.spacingS, tilePad, Theme.spacingS) > availableHeight
    readonly property int minLines: tight ? 1 : 2
    readonly property real lineGap: tight ? Theme.spacingXS : Theme.spacingS
    readonly property bool shortValues: vertical || tiled
    readonly property real lineHeight: Math.max(fullProbe.implicitHeight, MonitorMetrics.markerSize)
    readonly property real columnHeight: shortProbe.implicitHeight + MonitorMetrics.barThickness + MonitorMetrics.markerSize + Theme.spacingXS * 2

    property int columns: 1
    readonly property real minGap: tight && tiled ? Theme.spacingXS : Theme.spacingS
    readonly property real tilePadY: tight ? Math.min(tilePad, Theme.spacingXS) : tilePad
    // Bumped as groups arrive from an asynchronous loader.
    property int builtGroups: 0
    readonly property real groupWidth: largest("implicitWidth")
    readonly property real groupHeight: largest("implicitHeight")
    readonly property real stackLength: {
        void builtGroups;
        let s = Math.max(0, count - 1) * minGap;
        for (let i = 0; i < groups.count; i++)
            s += groups.itemAt(i)?.[vertical ? "implicitWidth" : "implicitHeight"] ?? 0;
        return s;
    }
    readonly property bool wrapped: !vertical && columns > 1
    readonly property int slots: wrapped ? Math.ceil(count / columns) : count
    readonly property real mainLength: wrapped ? slots * groupHeight + (slots - 1) * minGap : stackLength
    readonly property real spare: Math.max(0, (vertical ? width : height) - mainLength)
    // Framed groups grow to fill the box; bare ones stay packed and centered.
    readonly property real share: tiled ? spare / Math.max(1, slots) : 0

    function stackHeight(minLines, gap, pad, groupGap) {
        let s = Math.max(0, count - 1) * groupGap;
        for (const r of rows) {
            const n = Math.max(r.asleep ? 1 : (r.values ?? []).length, minLines);
            s += Math.max(n * lineHeight + (n - 1) * gap, Theme.iconSizeSmall) + pad * 2;
        }
        return s;
    }

    function largest(prop) {
        void builtGroups;
        let v = 0;
        for (let i = 0; i < groups.count; i++)
            v = Math.max(v, groups.itemAt(i)?.[prop] ?? 0);
        return v;
    }

    function markerFor(row, entry) {
        const id = entry?.id ?? "";
        if (id === "read" || id === "write")
            return {
                "icon": "",
                "text": id === "read" ? readLetter : writeLetter
            };
        return {
            "icon": entry?.icon === row?.icon ? "percent" : (entry?.icon ?? ""),
            "text": ""
        };
    }

    implicitWidth: vertical ? stackLength : columns * groupWidth + (columns - 1) * minGap
    implicitHeight: vertical ? groupHeight : mainLength

    NumericText {
        id: shortProbe
        visible: false
        text: ""
        reserveText: MonitorMetrics.widestReserve(root.rows, true)
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
    }

    NumericText {
        id: fullProbe
        visible: false
        text: ""
        reserveText: MonitorMetrics.widestReserve(root.rows, false)
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
    }

    MonitorText {
        id: markerProbe
        visible: false
        font.pixelSize: Theme.fontSizeXSmall
        font.weight: Theme.fontWeightMedium
    }

    MonitorText {
        id: idleProbe
        visible: false
        text: root.idleText
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
    }

    component Track: MonitorTrack {
        required property BarLine owner

        fraction: owner.fraction
        fillColor: owner.color
        primary: owner.index === 0
        vertical: root.vertical
        color: Theme.withAlpha(root.contentColor, Theme.stateLayerFocus)
    }

    component Marker: Item {
        id: marker

        required property BarLine owner
        readonly property var mark: root.markerFor(owner.row, owner.entry)

        implicitWidth: root.markerWidth
        implicitHeight: MonitorMetrics.markerSize

        DIcon {
            anchors.centerIn: parent
            visible: marker.mark.icon !== ""
            name: marker.mark.icon
            size: MonitorMetrics.markerSize
            color: root.mutedColor
        }

        MonitorText {
            anchors.centerIn: parent
            visible: marker.mark.text !== ""
            halo: root.halo
            text: marker.mark.text
            color: root.mutedColor
            font.pixelSize: Theme.fontSizeXSmall
            font.weight: Theme.fontWeightMedium
        }
    }

    component Value: NumericText {
        required property BarLine owner

        style: root.halo ? Text.Outline : Text.Normal
        styleColor: Theme.surface
        text: owner.valueText
        font.pixelSize: Theme.fontSizeSmall
        font.weight: owner.index === 0 ? Theme.fontWeightMedium : Font.Normal
        color: owner.asleep ? root.mutedColor : root.contentColor
    }

    component BarLine: Item {
        id: line

        required property var row
        required property var entry
        required property int index

        readonly property bool asleep: row.asleep === true
        readonly property color color: MonitorMetrics.levelColor(entry?.level, root.accentColor)
        readonly property real fraction: asleep ? 0 : Math.min(Math.max(entry.fraction ?? 0, 0), 1)
        readonly property string valueText: asleep ? root.idleText : root.shortValues ? (entry.shortText ?? entry.text ?? "—") : (entry.text ?? "—")

        implicitWidth: root.vertical ? root.columnWidth : horizontalLine.implicitWidth
        implicitHeight: root.vertical ? root.columnHeight : root.lineHeight
        Accessible.role: Accessible.StaticText
        Accessible.name: (row.name ?? "") + " " + (entry.label ?? "") + " " + valueText

        ColumnLayout {
            id: verticalColumn
            anchors.fill: parent
            visible: root.vertical
            spacing: Theme.spacingXS

            Value {
                owner: line
                Layout.alignment: Qt.AlignHCenter
            }

            Track {
                owner: line
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.preferredWidth: MonitorMetrics.barWidth
                Layout.minimumHeight: MonitorMetrics.barThickness
            }

            Marker {
                owner: line
                Layout.alignment: Qt.AlignHCenter
            }
        }

        RowLayout {
            id: horizontalLine
            anchors.fill: parent
            visible: !root.vertical
            spacing: Theme.spacingS

            Marker {
                owner: line
                Layout.alignment: Qt.AlignVCenter
            }

            Track {
                owner: line
                Layout.fillWidth: true
                Layout.minimumWidth: MonitorMetrics.barThickness * 2
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: MonitorMetrics.barWidth
            }

            Value {
                owner: line
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: reservedWidth
                reserveText: root.shortValues ? shortProbe.reserveText : fullProbe.reserveText
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    component Bracket: Item {
        clip: true
        opacity: MonitorMetrics.bracketOpacity

        Rectangle {
            readonly property real r: MonitorMetrics.bracketDepth

            x: root.vertical || !I18n.isRtl ? 0 : -r
            y: root.vertical ? -r : 0
            width: parent.width + (root.vertical ? 0 : r)
            height: parent.height + (root.vertical ? r : 0)
            radius: r
            color: "transparent"
            border.width: MonitorMetrics.bracketStroke
            border.color: root.mutedColor
        }
    }

    component GroupIcon: DeviceIcon {
        required property var row

        name: row.icon ?? ""
        size: Theme.iconSizeSmall
        color: root.mutedColor
    }

    component GroupName: MonitorText {
        required property var row

        visible: root.barNames
        halo: root.halo
        text: row.name ?? ""
        color: root.mutedColor
        font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight
    }

    component Group: Item {
        id: group

        required property var row

        readonly property var entries: row.asleep ? (row.values ?? []).slice(0, 1) : (row.values ?? [])
        readonly property real pad: root.tilePad
        readonly property real padY: root.vertical ? pad : root.tilePadY

        implicitWidth: (root.vertical ? verticalGroup.implicitWidth : horizontalGroup.implicitWidth) + pad * 2
        implicitHeight: (root.vertical ? verticalGroup.implicitHeight : horizontalGroup.implicitHeight) + padY * 2

        Rectangle {
            anchors.fill: parent
            visible: root.tiled
            radius: root.tileRadius
            color: root.tileColor
        }

        ColumnLayout {
            id: verticalGroup
            anchors.fill: parent
            anchors.margins: group.pad
            visible: root.vertical
            spacing: Theme.spacingXS

            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                implicitWidth: Math.max(columns.implicitWidth, group.row.asleep ? idleProbe.implicitWidth : 0)
                implicitHeight: root.columnHeight

                Row {
                    id: columns
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: parent.height
                    spacing: root.columnGap

                    Repeater {
                        model: root.vertical ? group.entries.length : 0

                        BarLine {
                            height: columns.height
                            row: group.row
                            entry: group.entries[index] ?? ({})
                        }
                    }
                }
            }

            Bracket {
                visible: !root.tiled
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: columns.implicitWidth - Theme.spacingXXS * 2
                Layout.preferredHeight: MonitorMetrics.bracketDepth
            }

            GroupIcon {
                row: group.row
                Layout.alignment: Qt.AlignHCenter
            }

            GroupName {
                row: group.row
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(implicitWidth, MonitorMetrics.barNameWidth)
            }
        }

        RowLayout {
            id: horizontalGroup
            anchors.fill: parent
            anchors.leftMargin: group.pad
            anchors.rightMargin: group.pad
            anchors.topMargin: group.padY
            anchors.bottomMargin: group.padY
            visible: !root.vertical
            spacing: Theme.spacingS

            GroupIcon {
                row: group.row
                Layout.alignment: Qt.AlignVCenter
            }

            GroupName {
                row: group.row
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: MonitorMetrics.barNameWidth
                color: root.contentColor
                font.weight: Theme.fontWeightMedium
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: Math.max(lines.implicitHeight, root.lineHeight * root.minLines + root.lineGap * (root.minLines - 1))
                spacing: Theme.spacingS

                Bracket {
                    visible: !root.tiled
                    Layout.fillHeight: true
                    Layout.preferredWidth: MonitorMetrics.bracketDepth
                }

                ColumnLayout {
                    id: lines
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: root.lineGap

                    Repeater {
                        model: root.vertical ? 0 : group.entries.length

                        BarLine {
                            Layout.fillWidth: true
                            row: group.row
                            entry: group.entries[index] ?? ({})
                        }
                    }
                }
            }
        }
    }

    Grid {
        anchors.centerIn: parent
        columns: root.vertical ? Math.max(1, root.count) : Math.max(1, root.columns)
        rowSpacing: root.vertical ? 0 : root.minGap
        columnSpacing: root.minGap

        Repeater {
            id: groups

            model: root.count
            onItemAdded: root.builtGroups++

            Group {
                required property int index

                width: root.vertical ? implicitWidth + root.share : root.wrapped ? (root.width - (root.columns - 1) * root.minGap) / root.columns : root.width
                height: root.vertical ? root.height : (root.wrapped ? root.groupHeight : implicitHeight) + root.share
                row: root.rows[index] ?? ({})
            }
        }
    }
}
