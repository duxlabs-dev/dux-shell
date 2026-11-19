pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import "../../../Common/BatteryPopoutMetrics.js" as BatteryPopoutMetrics
import "../../../DCommon/Common/Contrast.js" as Contrast

Item {
    id: root

    property var devices: []
    property var metrics: BatteryPopoutMetrics.metrics("comfortable")

    readonly property var items: Array.isArray(root.devices) ? root.devices : []
    readonly property int count: root.items.length
    readonly property string layoutName: SettingsData.batteryPopoutDevicesLayout
    readonly property string colorMode: SettingsData.batteryPopoutColor
    readonly property bool wavy: SettingsData.batteryPopoutWavy
    readonly property Item body: root.layoutName === "compact" ? tiles : root.layoutName === "chips" ? chips : root.layoutName === "list" ? rows : root.layoutName === "bars" ? bars : gridCard

    readonly property int gridMaxColumns: 4
    readonly property real compactRing: Theme.buttonHeightXS + Theme.spacingM
    readonly property real compactGlyph: Theme.iconSizeSmall + Theme.spacingXXS
    readonly property real gridGlyph: Theme.iconSize - Theme.spacingXXS
    readonly property real boltCircle: Theme.iconSizeSmall + Theme.spacingS
    readonly property real numberLift: Theme.spacingM + Theme.spacingXXS

    visible: root.count > 0
    implicitHeight: root.count > 0 ? root.body.implicitHeight : 0
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    function accent(device) {
        return BatteryService.colorFor(root.colorMode, device.percentage, device.charging, Theme.surfaceText);
    }

    function valueColor(device) {
        return device.low && (root.colorMode === "primary" || root.colorMode === "lowcharging") ? Theme.error : Theme.surfaceText;
    }

    function level(device) {
        return device.unknown ? -1 : device.percentage;
    }

    function percentText(device) {
        return device.unknown ? "–" : device.percentage + "%";
    }

    function accessibleName(device) {
        const state = device.charging ? ", " + I18n.tr("Charging", "device battery state") : device.low ? ", " + I18n.tr("Low Battery", "device battery state") : "";
        return device.name + ": " + root.percentText(device) + state;
    }

    // One ink has to read on fill and track: a track too close to the fill takes on more of the accent.
    function barTrack(accent, ink) {
        let amount = 0;
        let track = Theme.secondaryContainer;
        while (amount < 1 && Contrast.ratio(ink, track) < 3) {
            amount += 0.1;
            track = Contrast.mix(Theme.secondaryContainer, accent, amount);
        }
        return track;
    }

    // Tiles fill one row up to three devices, two columns beyond; a lone last tile spans the row.
    function tileColumns(count) {
        return count <= 3 ? Math.max(1, count) : 2;
    }

    // Outer corners of a connected grid are large, inner ones small; the last tile spans its row.
    function cornerRadius(index, count, columns, atStart, atTop) {
        const row = Math.floor(index / columns);
        const column = index % columns;
        const onEdge = atStart ? column === 0 : column === columns - 1 || index === count - 1;
        const onSide = atTop ? row === 0 : row === Math.floor((count - 1) / columns);
        return onEdge && onSide ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius;
    }

    component DeviceGlyph: Item {
        id: glyph

        required property var device
        required property color accent
        required property color cut
        property real size: Theme.iconSize
        property bool badges: true
        readonly property bool badged: glyph.badges && (glyph.device.charging || glyph.device.low)
        readonly property color badgeFill: glyph.device.charging ? glyph.accent : Theme.error
        readonly property color badgeInk: glyph.device.charging ? Contrast.readableOn(glyph.accent, [Theme.surface, Theme.surfaceText]) : Theme.onError

        implicitWidth: glyph.size + (glyph.badged ? root.metrics.badgeOverhang : 0)
        implicitHeight: glyph.size

        DIcon {
            name: glyph.device.icon
            size: glyph.size
            color: glyph.accent
        }

        Rectangle {
            visible: glyph.badged
            width: root.metrics.badgeSize + root.metrics.badgeCut * 2
            height: width
            radius: width / 2
            color: glyph.badgeFill
            border.width: root.metrics.badgeCut
            border.color: glyph.cut
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -root.metrics.badgeOverhang + 1

            DIcon {
                anchors.centerIn: parent
                name: glyph.device.charging ? "bolt" : "priority_high"
                size: root.metrics.badgeGlyph
                filled: true
                color: glyph.badgeInk
            }
        }
    }

    DCard {
        id: gridCard

        readonly property int columns: Math.max(1, Math.min(root.count, root.gridMaxColumns))

        visible: root.layoutName === "grid"
        width: root.width
        implicitHeight: gridContent.implicitHeight + pad * 2
        pad: root.metrics.pad
        restRadius: Theme.cornerRadiusL

        Grid {
            id: gridContent

            readonly property real cellWidth: (width - columnSpacing * (gridCard.columns - 1)) / gridCard.columns

            width: parent.width
            columns: gridCard.columns
            columnSpacing: Theme.spacingXS
            rowSpacing: Theme.spacingXS

            Repeater {
                model: ScriptModel {
                    values: root.layoutName === "grid" ? root.items : []
                    objectProp: "key"
                }

                delegate: Item {
                    id: cell

                    required property var modelData
                    readonly property color accent: root.accent(cell.modelData)

                    width: gridContent.cellWidth
                    implicitHeight: cellName.y + cellName.implicitHeight
                    Accessible.role: Accessible.StaticText
                    Accessible.name: root.accessibleName(cell.modelData)

                    BatteryLevelRing {
                        id: cellRing
                        x: (parent.width - width) / 2
                        width: root.metrics.deviceRing
                        height: width
                        value: root.level(cell.modelData)
                        charging: cell.modelData.charging
                        wavy: root.wavy
                        fillColor: cell.accent
                        strokeWidth: root.metrics.gaugeStroke
                        startAngle: 135
                        spanAngle: 270
                        moving: false

                        DeviceGlyph {
                            anchors.centerIn: parent
                            device: cell.modelData
                            accent: cell.accent
                            cut: gridCard.color
                            size: root.gridGlyph
                        }
                    }

                    StyledText {
                        id: cellLevel
                        x: (parent.width - width) / 2
                        y: cellRing.height - root.numberLift
                        text: cell.modelData.unknown ? "–" : String(cell.modelData.percentage)
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightMedium
                        font.features: { "tnum": 1 }
                        color: Theme.surfaceText
                    }

                    StyledText {
                        id: cellName
                        y: cellLevel.y + cellLevel.implicitHeight
                        width: parent.width
                        text: cell.modelData.name
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    Grid {
        id: tiles

        readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns

        visible: root.layoutName === "compact"
        width: root.width
        columns: root.tileColumns(root.count)
        columnSpacing: Theme.groupedListGap
        rowSpacing: Theme.groupedListGap

        Repeater {
            model: ScriptModel {
                values: root.layoutName === "compact" ? root.items : []
                objectProp: "key"
            }

            delegate: DCard {
                id: tile

                required property var modelData
                required property int index
                readonly property color accent: root.accent(tile.modelData)
                readonly property int span: tile.index === root.count - 1 ? tiles.columns - tile.index % tiles.columns : 1
                readonly property real startTop: root.cornerRadius(tile.index, root.count, tiles.columns, true, true)
                readonly property real endTop: root.cornerRadius(tile.index, root.count, tiles.columns, false, true)
                readonly property real startBottom: root.cornerRadius(tile.index, root.count, tiles.columns, true, false)
                readonly property real endBottom: root.cornerRadius(tile.index, root.count, tiles.columns, false, false)

                width: tiles.cellWidth * tile.span + tiles.columnSpacing * (tile.span - 1)
                height: tileRow.implicitHeight + pad * 2
                pad: root.metrics.tile
                restRadius: Theme.groupedListInnerRadius
                topLeftRadius: I18n.isRtl ? tile.endTop : tile.startTop
                topRightRadius: I18n.isRtl ? tile.startTop : tile.endTop
                bottomLeftRadius: I18n.isRtl ? tile.endBottom : tile.startBottom
                bottomRightRadius: I18n.isRtl ? tile.startBottom : tile.endBottom
                Accessible.role: Accessible.StaticText
                Accessible.name: root.accessibleName(tile.modelData)

                Row {
                    id: tileRow
                    width: parent.width
                    spacing: Theme.spacingM

                    BatteryLevelRing {
                        id: tileRing
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.compactRing
                        height: width
                        value: root.level(tile.modelData)
                        charging: tile.modelData.charging
                        wavy: root.wavy
                        fillColor: tile.accent
                        strokeWidth: root.metrics.gaugeStroke
                        moving: false

                        DeviceGlyph {
                            anchors.centerIn: parent
                            device: tile.modelData
                            accent: tile.accent
                            cut: tile.color
                            size: root.compactGlyph
                        }
                    }

                    Column {
                        width: parent.width - tileRing.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            width: parent.width
                            text: root.percentText(tile.modelData)
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            font.features: { "tnum": 1 }
                            color: root.valueColor(tile.modelData)
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            text: tile.modelData.name
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.onSurfaceVariant
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    Flow {
        id: chips

        visible: root.layoutName === "chips"
        width: root.width
        spacing: Theme.spacingXS

        Repeater {
            model: ScriptModel {
                values: root.layoutName === "chips" ? root.items : []
                objectProp: "key"
            }

            delegate: BatteryChip {
                id: chip

                required property var modelData
                readonly property color accent: root.accent(chip.modelData)

                implicitHeight: root.metrics.chip
                maximumWidth: chips.width
                value: root.percentText(chip.modelData)
                valueColor: root.valueColor(chip.modelData)
                Accessible.name: root.accessibleName(chip.modelData)

                DeviceGlyph {
                    device: chip.modelData
                    accent: chip.accent
                    cut: chip.color
                    size: root.compactGlyph
                }
            }
        }
    }

    Column {
        id: rows

        visible: root.layoutName === "list"
        width: root.width
        spacing: Theme.groupedListGap

        Repeater {
            model: ScriptModel {
                values: root.layoutName === "list" ? root.items : []
                objectProp: "key"
            }

            delegate: DCard {
                id: row

                required property var modelData
                required property int index
                readonly property color accent: root.accent(row.modelData)
                readonly property real topRadius: row.index === 0 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                readonly property real bottomRadius: row.index === root.count - 1 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius

                width: rows.width
                height: Math.max(root.metrics.row, rowContent.implicitHeight + Theme.spacingXS * 2)
                pad: Theme.spacingM
                restRadius: Theme.groupedListInnerRadius
                topLeftRadius: row.topRadius
                topRightRadius: row.topRadius
                bottomLeftRadius: row.bottomRadius
                bottomRightRadius: row.bottomRadius
                Accessible.role: Accessible.StaticText
                Accessible.name: root.accessibleName(row.modelData)

                Row {
                    id: rowContent
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    DeviceGlyph {
                        id: rowGlyph
                        anchors.verticalCenter: parent.verticalCenter
                        device: row.modelData
                        accent: row.accent
                        cut: row.color
                    }

                    Column {
                        id: rowText
                        width: parent.width - rowPercent.implicitWidth - rowGlyph.implicitWidth - parent.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        StyledText {
                            width: parent.width
                            text: row.modelData.name
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }

                        BatteryLevelBar {
                            value: root.level(row.modelData)
                            charging: row.modelData.charging
                            wavy: root.wavy
                            fillColor: row.accent
                            strokeWidth: root.metrics.barStroke
                            moving: true
                        }
                    }

                    StyledText {
                        id: rowPercent
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.percentText(row.modelData)
                        font.weight: Theme.fontWeightMedium
                        font.features: { "tnum": 1 }
                        color: root.valueColor(row.modelData)
                    }
                }
            }
        }
    }

    Column {
        id: bars

        visible: root.layoutName === "bars"
        width: root.width
        spacing: Theme.groupedListGap

        Repeater {
            model: ScriptModel {
                values: root.layoutName === "bars" ? root.items : []
                objectProp: "key"
            }

            delegate: ClippingRectangle {
                id: bar

                required property var modelData
                required property int index
                readonly property color accent: root.accent(bar.modelData)
                readonly property color ink: Contrast.readableOnAll([bar.accent, Theme.secondaryContainer], [Theme.surfaceText, Theme.surface])
                readonly property color track: root.barTrack(bar.accent, bar.ink)
                readonly property real topRadius: bar.index === 0 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                readonly property real bottomRadius: bar.index === root.count - 1 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                property real shown: Math.max(0, root.level(bar.modelData))

                width: bars.width
                height: root.metrics.row
                color: bar.track
                topLeftRadius: bar.topRadius
                topRightRadius: bar.topRadius
                bottomLeftRadius: bar.bottomRadius
                bottomRightRadius: bar.bottomRadius
                LayoutMirroring.enabled: I18n.isRtl
                LayoutMirroring.childrenInherit: true
                Accessible.role: Accessible.StaticText
                Accessible.name: root.accessibleName(bar.modelData)

                Behavior on shown {
                    enabled: !Theme.reduceMotion
                    NumberAnimation {
                        duration: Theme.expressiveDurations.expressiveSlowEffects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveSlowEffects
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * bar.shown / 100
                    color: bar.accent
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    spacing: Theme.spacingM

                    DeviceGlyph {
                        device: bar.modelData
                        accent: bar.ink
                        cut: bar.track
                        badges: false
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: bar.modelData.name
                        font.weight: Theme.fontWeightMedium
                        color: bar.ink
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: root.percentText(bar.modelData)
                        font.weight: Theme.fontWeightMedium
                        font.features: { "tnum": 1 }
                        color: bar.ink
                    }

                    Rectangle {
                        visible: bar.modelData.charging
                        Layout.preferredWidth: root.boltCircle
                        Layout.preferredHeight: root.boltCircle
                        radius: width / 2
                        color: bar.ink

                        DIcon {
                            anchors.centerIn: parent
                            name: "bolt"
                            size: Theme.iconSizeSmall
                            filled: true
                            color: Contrast.readableOn(bar.ink, [Theme.surface, Theme.surfaceText])
                        }
                    }
                }
            }
        }
    }
}
