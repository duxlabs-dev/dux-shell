pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets
import "../../../Common/BatteryPopoutMetrics.js" as BatteryPopoutMetrics

Item {
    id: root

    property var model: []
    property var metrics: BatteryPopoutMetrics.metrics("comfortable")
    property bool active: false

    readonly property string layout: SettingsData.batteryPopoutDetailsLayout
    readonly property int count: model.length
    readonly property bool tiled: layout === "grid" || layout === "compact"
    readonly property bool sideBySide: layout === "compact"
    readonly property int columns: Math.max(1, sideBySide && count === 4 ? 2 : count)

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    visible: count > 0
    implicitHeight: count === 0 ? 0 : tiled ? tileGrid.implicitHeight : layout === "chips" ? chipFlow.implicitHeight : listColumn.implicitHeight

    Grid {
        id: tileGrid
        width: parent.width
        columns: root.columns
        columnSpacing: Theme.groupedListGap
        rowSpacing: Theme.groupedListGap

        Repeater {
            model: root.tiled ? root.model : []

            StatTile {
                required property var modelData
                required property int index
                readonly property int column: index % root.columns
                readonly property bool lastInColumn: index + root.columns >= root.count

                width: (tileGrid.width - tileGrid.columnSpacing * (root.columns - 1)) / root.columns
                label: modelData.label
                value: modelData.value
                iconName: modelData.icon
                ratio: modelData.ratio ?? -1
                bad: modelData.bad === true
                sideBySide: root.sideBySide
                topStartLarge: index < root.columns && column === 0
                topEndLarge: index < root.columns && (column === root.columns - 1 || index === root.count - 1)
                bottomStartLarge: lastInColumn && column === 0
                bottomEndLarge: lastInColumn && (column === root.columns - 1 || index === root.count - 1)
            }
        }
    }

    Flow {
        id: chipFlow
        width: parent.width
        spacing: Theme.spacingXS

        Repeater {
            model: root.layout === "chips" ? root.model : []

            BatteryChip {
                required property var modelData

                label: modelData.label
                value: modelData.value
                valueColor: modelData.bad === true ? Theme.error : Theme.surfaceText
                implicitHeight: root.metrics.chip
                maximumWidth: chipFlow.width
            }
        }
    }

    Column {
        id: listColumn
        width: parent.width
        spacing: Theme.groupedListGap

        Repeater {
            model: root.layout === "list" ? root.model : []

            StatRow {
                required property var modelData
                required property int index

                width: listColumn.width
                label: modelData.label
                value: modelData.value
                iconName: modelData.icon
                ratio: modelData.ratio ?? -1
                bad: modelData.bad === true
                topRadius: index === 0 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                bottomRadius: index === root.count - 1 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
            }
        }
    }

    component StatGlyph: DRingGauge {
        id: glyph
        property string iconName: ""
        property real ratio: -1
        property bool bad: false

        implicitWidth: Theme.iconSize
        implicitHeight: implicitWidth
        value: ratio
        strokeWidth: Theme.outlineWidthFocused
        trackGap: Theme.spacingXXS
        ringColor: bad ? Theme.error : Theme.primary
        animated: root.active

        DIcon {
            anchors.centerIn: parent
            name: glyph.iconName
            size: glyph.ratio >= 0 ? Theme.iconSizeSmall : Theme.iconSize
            color: glyph.bad ? Theme.error : Theme.primary
        }
    }

    component StatTile: DCard {
        id: tile
        property string label: ""
        property string value: ""
        property string iconName: ""
        property real ratio: -1
        property bool bad: false
        property bool sideBySide: false
        property bool topStartLarge: false
        property bool topEndLarge: false
        property bool bottomStartLarge: false
        property bool bottomEndLarge: false
        readonly property real horizontalPad: sideBySide ? root.metrics.tile : Theme.spacingXS
        readonly property real verticalPad: root.metrics.tile
        readonly property real largeRadius: Theme.groupedListOuterRadius
        readonly property real smallRadius: Theme.groupedListInnerRadius

        pad: 0
        height: (sideBySide ? tileRow.implicitHeight : tileColumn.implicitHeight) + verticalPad * 2
        restRadius: smallRadius
        topLeftRadius: (I18n.isRtl ? topEndLarge : topStartLarge) ? largeRadius : smallRadius
        bottomLeftRadius: (I18n.isRtl ? bottomEndLarge : bottomStartLarge) ? largeRadius : smallRadius
        topRightRadius: (I18n.isRtl ? topStartLarge : topEndLarge) ? largeRadius : smallRadius
        bottomRightRadius: (I18n.isRtl ? bottomStartLarge : bottomEndLarge) ? largeRadius : smallRadius
        Accessible.role: Accessible.StaticText
        Accessible.name: label + ": " + value

        Column {
            id: tileColumn
            x: tile.horizontalPad
            y: tile.verticalPad
            width: parent.width - tile.horizontalPad * 2
            spacing: Theme.spacingXS
            visible: !tile.sideBySide

            StatGlyph {
                anchors.horizontalCenter: parent.horizontalCenter
                iconName: tile.iconName
                ratio: tile.ratio
                bad: tile.bad
            }

            StyledText {
                width: parent.width
                text: tile.value
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                font.features: {
                    "tnum": 1
                }
                color: tile.bad ? Theme.error : Theme.onSurface
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: tile.label
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.onSurfaceVariant
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }

        Row {
            id: tileRow
            x: tile.horizontalPad
            y: tile.verticalPad
            width: parent.width - tile.horizontalPad * 2
            spacing: Theme.spacingM
            visible: tile.sideBySide

            StatGlyph {
                id: tileGlyph
                anchors.verticalCenter: parent.verticalCenter
                iconName: tile.iconName
                ratio: tile.ratio
                bad: tile.bad
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - tileGlyph.width - parent.spacing

                StyledText {
                    width: parent.width
                    text: tile.value
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    font.features: {
                        "tnum": 1
                    }
                    color: tile.bad ? Theme.error : Theme.onSurface
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: tile.label
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.onSurfaceVariant
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }
        }
    }

    component StatRow: DCard {
        id: row
        property string label: ""
        property string value: ""
        property string iconName: ""
        property real ratio: -1
        property bool bad: false
        property real topRadius: Theme.groupedListInnerRadius
        property real bottomRadius: Theme.groupedListInnerRadius

        pad: 0
        height: Math.max(root.metrics.row, rowContent.implicitHeight + Theme.spacingXS * 2)
        restRadius: Theme.groupedListInnerRadius
        topLeftRadius: topRadius
        topRightRadius: topRadius
        bottomLeftRadius: bottomRadius
        bottomRightRadius: bottomRadius
        Accessible.role: Accessible.StaticText
        Accessible.name: label + ": " + value

        RowLayout {
            id: rowContent
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            anchors.topMargin: Theme.spacingXS
            anchors.bottomMargin: Theme.spacingXS
            spacing: Theme.spacingM

            StatGlyph {
                iconName: row.iconName
                ratio: row.ratio
                bad: row.bad
            }

            StyledText {
                Layout.fillWidth: true
                text: row.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.onSurface
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            StyledText {
                text: row.value
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                font.features: {
                    "tnum": 1
                }
                color: row.bad ? Theme.error : Theme.onSurface
                wrapMode: Text.NoWrap
            }
        }
    }
}
