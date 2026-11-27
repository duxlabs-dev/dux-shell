pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Sysmon

DFlickable {
    id: root
    clip: true

    property string title: ""
    property string titleTooltip: ""
    property string subtitle: ""
    property string subtitle2: ""
    property bool showChart: true
    // Content that replaces the chart matches this, so the stats below do not move when switching.
    readonly property real chartCardHeight: variant === "device" ? ProcessListMetrics.deviceChartHeight : windowLayout?.chartCardHeight ?? 0
    property string chartLabel: ""
    property string chartValue: ""
    property string chartSecondaryLabel: ""
    property string chartSecondaryValue: ""
    property var values: []
    property var secondaryValues: []
    property real maximum: 0
    property string maximumText: ""
    // Entries: { label, value, tooltip, advanced }; advanced ones show only when expanded.
    property var leftStats: []
    property var rightStats: []
    default property alias content: slot.data
    property alias headerActions: headerActionsRow.data
    property alias topContent: topSlot.data

    // "window" is the system monitor pane; "compact", "device" and "overview" are the popout layouts.
    property string variant: "window"
    property string typeKey: ""
    property string iconName: ""
    property string mainValue: chartValue
    property string mainLabel: chartLabel
    // 0 to 1 for the overview ring; negative hides the ring.
    property real mainFraction: -1
    property string mainDetail: ""
    property string extraLabel: chartSecondaryLabel
    property string extraValue: chartSecondaryValue
    property string briefSubtitle: shortSubtitle
    property string shortSubtitle: subtitle
    // Set when the device can't show data; popouts then show only this line.
    property string idleText: ""
    property string idleIcon: "bedtime"
    property int rangeSeconds: variant === "compact" ? 60 : 0
    property var compactSecondaryValues: secondaryValues
    property string compactSecondaryLabel: chartSecondaryLabel
    property string compactSecondaryValue: chartSecondaryValue

    readonly property bool idle: idleText !== ""
    readonly property bool twoLines: chartSecondaryLabel !== ""
    readonly property bool compactTwoLines: compactSecondaryLabel !== ""
    // The count follows the declared tiles so the row doesn't come and go; ones with a value come first.
    readonly property var tiles: {
        const declared = leftStats.concat(rightStats).filter(s => s?.tile === true);
        const waiting = declared.filter(s => !hasValue(s)).map(s => Object.assign({}, s, {
                    value: "—"
                }));
        return declared.filter(s => hasValue(s)).concat(waiting).slice(0, ProcessListMetrics.tileLimit);
    }
    readonly property var deviceStats: present(leftStats, false).concat(present(rightStats, false)).slice(0, ProcessListMetrics.deviceStatRows * 2)
    readonly property var overviewPairs: {
        const pairs = extraLabel !== "" ? [
            {
                label: extraLabel,
                value: extraValue || "—"
            }
        ] : [];
        for (const t of tiles) {
            if (pairs.length < ProcessListMetrics.pairLimit && t.label !== extraLabel)
                pairs.push(t);
        }
        return pairs.length >= ProcessListMetrics.pairMinimum ? pairs : [];
    }
    readonly property string valueReserve: typeKey === "net" ? "000.0 MB/s" : "100%"
    // The CPU thread grid fits the chart's height in the popouts instead of growing past it.
    readonly property bool compactGrid: variant !== "window"
    readonly property real heroFontSize: typeKey === "net" ? Theme.fontSizeXXLarge : Theme.fontSizeDisplay
    readonly property WindowLayout windowLayout: layout.item as WindowLayout
    readonly property DeviceLayout deviceLayout: layout.item as DeviceLayout

    // Rows that had a value keep their place, as "—", so the grid doesn't jump.
    property bool loaded: true
    property var seenLabels: ({})

    function hasValue(s) {
        return s.value !== null && s.value !== undefined && s.value !== "";
    }

    function present(list, advanced) {
        return (list ?? []).filter(s => s && (s.advanced === true) === advanced && (!loaded || hasValue(s) || seenLabels[s.label])).map(s => hasValue(s) ? s : Object.assign({}, s, {
                value: "—",
                loading: !loaded
            }));
    }

    function rememberLabels() {
        const seen = Object.assign({}, seenLabels);
        let added = false;
        for (const s of leftStats.concat(rightStats)) {
            if (s && hasValue(s) && !seen[s.label]) {
                seen[s.label] = true;
                added = true;
            }
        }
        if (added)
            seenLabels = seen;
    }

    onTitleChanged: seenLabels = {}
    onLeftStatsChanged: rememberLabels()
    onRightStatsChanged: rememberLabels()

    contentWidth: width
    contentHeight: variant === "window" ? layout.implicitHeight : height
    implicitHeight: layout.implicitHeight
    interactive: variant === "window"
    wheelEnabled: variant === "window"

    // The pane's own items; each layout gives them a place, or they stay hidden here.
    Item {
        id: stash
        visible: false
    }

    Row {
        id: headerActionsRow
        parent: root.windowLayout?.actionsHolder ?? root.deviceLayout?.actionsHolder ?? stash
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Theme.spacingS
    }

    Column {
        id: topSlot
        parent: root.windowLayout?.topHolder ?? stash
        width: parent.width
    }

    Column {
        id: slot
        parent: root.windowLayout?.slotHolder ?? root.deviceLayout?.slotHolder ?? stash
        width: parent.width
        spacing: Theme.spacingL
    }

    Loader {
        id: layout
        width: root.width
        sourceComponent: root.variant === "compact" ? compactLayout : root.variant === "device" ? deviceLayoutComponent : root.variant === "overview" ? overviewLayout : windowLayoutComponent
    }

    Component {
        id: windowLayoutComponent
        WindowLayout {}
    }

    Component {
        id: deviceLayoutComponent
        DeviceLayout {}
    }

    component WindowLayout: Column {
        readonly property alias actionsHolder: actionsHolder
        readonly property alias topHolder: topHolder
        readonly property alias slotHolder: slotHolder
        readonly property real chartCardHeight: chartCard.implicitHeight

        spacing: Theme.spacingL

        Item {
            width: parent.width
            height: Math.max(titleColumn.implicitHeight, headerActionsRow.implicitHeight)

            Column {
                id: titleColumn
                width: parent.width - (headerActionsRow.implicitWidth > 0 ? headerActionsRow.implicitWidth + Theme.spacingL : 0)

                StyledText {
                    id: titleText
                    width: parent.width
                    text: root.title
                    font.pixelSize: Theme.fontSizeXXLarge
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    maximumLineCount: 1

                    MouseArea {
                        id: titleHover
                        anchors.fill: parent
                        enabled: root.titleTooltip !== ""
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    DTooltipHost {
                        text: root.titleTooltip
                        target: titleText
                        hoverArea: titleHover
                    }
                }

                StyledText {
                    visible: text !== ""
                    width: parent.width
                    text: root.subtitle
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: text !== ""
                    width: parent.width
                    text: root.subtitle2
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }

            Item {
                id: actionsHolder
                anchors.right: parent.right
                anchors.top: parent.top
                width: headerActionsRow.implicitWidth
                height: headerActionsRow.implicitHeight
            }
        }

        Item {
            id: topHolder
            visible: topSlot.children.length > 0
            width: parent.width
            height: topSlot.implicitHeight
        }

        ChartCard {
            id: chartCard
            visible: root.showChart
            width: parent.width
            chartHeight: Theme.listItemHeight * 4
            label: root.chartLabel
            valueText: root.chartValue
            secondaryLabel: root.chartSecondaryLabel
            secondaryValueText: root.chartSecondaryValue
            values: root.values
            secondaryValues: root.secondaryValues
            maximum: root.maximum
            maximumText: root.maximumText
            historyLength: DgopService.historySize
        }

        Item {
            id: slotHolder
            visible: slot.children.length > 0
            width: parent.width
            height: slot.implicitHeight
        }

        StatGrid {
            leftGroup: root.present(root.leftStats, false)
            rightGroup: root.present(root.rightStats, false)
        }

        CollapsibleHeader {
            visible: advancedGrid.hasStats
            text: I18n.tr("Advanced")
            collapsed: !ProcessListMetrics.showAdvanced
            onToggled: ProcessListMetrics.showAdvanced = !ProcessListMetrics.showAdvanced
        }

        StatGrid {
            id: advancedGrid
            leftGroup: root.present(root.leftStats, true)
            rightGroup: root.present(root.rightStats, true)
            visible: hasStats && ProcessListMetrics.showAdvanced
        }
    }

    Component {
        id: compactLayout

        Column {
            spacing: Theme.spacingM

            Row {
                width: parent.width
                spacing: Theme.spacingM

                TypeShape {
                    id: headerShape
                    anchors.verticalCenter: parent.verticalCenter
                }

                TitleBlock {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - headerShape.width - parent.spacing
                    subtitle: root.shortSubtitle
                }
            }

            IdleLine {
                visible: root.idle
            }

            Rectangle {
                visible: !root.idle
                width: parent.width
                height: cardColumn.implicitHeight + Theme.spacingL * 2
                radius: Theme.cornerRadiusL
                color: ProcessListMetrics.cardColor

                Column {
                    id: cardColumn
                    x: Theme.spacingL
                    y: Theme.spacingL
                    width: parent.width - Theme.spacingL * 2
                    spacing: Theme.spacingS

                    Item {
                        id: hero

                        readonly property bool legendBeside: root.compactTwoLines && root.mainDetail === ""

                        width: parent.width
                        height: Math.max(heroValue.implicitHeight, beside.implicitHeight)

                        NumericText {
                            id: heroValue
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(reservedWidth, parent.width - beside.width - Theme.spacingL)
                            text: root.mainValue || "—"
                            reserveText: root.valueReserve
                            font.pixelSize: root.heroFontSize
                            font.weight: Theme.fontWeightMedium
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: Theme.fontSizeXLarge
                            horizontalAlignment: Text.AlignLeft
                            color: Theme.primary
                        }

                        Column {
                            id: beside
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS

                            ChartLegendItem {
                                visible: hero.legendBeside
                                text: root.chartLabel
                            }

                            ChartLegendItem {
                                visible: hero.legendBeside
                                text: root.compactSecondaryLabel
                                value: root.compactSecondaryValue
                                swatchColor: Theme.tertiary
                                dashed: true
                            }

                            StyledText {
                                visible: !hero.legendBeside && text !== ""
                                anchors.right: parent.right
                                text: root.mainLabel
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            NumericText {
                                visible: !hero.legendBeside && text !== ""
                                anchors.right: parent.right
                                text: root.mainDetail
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightMedium
                                color: Theme.surfaceText
                            }
                        }
                    }

                    LegendRow {
                        visible: root.compactTwoLines && root.mainDetail !== ""
                        label: root.chartLabel
                        value: root.chartValue
                        secondaryLabel: root.compactSecondaryLabel
                        secondaryValue: root.compactSecondaryValue
                    }

                    PopoutChart {
                        width: parent.width
                        rangeSeconds: root.rangeSeconds
                        values: root.values
                        secondaryValues: root.compactSecondaryValues
                        secondaryLabel: root.compactSecondaryLabel
                    }
                }
            }

            Row {
                id: tileRow
                visible: !root.idle && root.tiles.length >= 2
                width: parent.width
                spacing: Theme.groupedListGap

                Repeater {
                    model: root.tiles.length

                    Rectangle {
                        id: tile

                        required property int index
                        readonly property var stat: root.tiles[index] ?? ({})
                        readonly property real startRadius: index === 0 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                        readonly property real endRadius: index === root.tiles.length - 1 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius

                        width: (tileRow.width - tileRow.spacing * (root.tiles.length - 1)) / root.tiles.length
                        height: tilePair.implicitHeight + Theme.spacingM * 2
                        color: ProcessListMetrics.cardColor
                        topLeftRadius: I18n.isRtl ? endRadius : startRadius
                        bottomLeftRadius: topLeftRadius
                        topRightRadius: I18n.isRtl ? startRadius : endRadius
                        bottomRightRadius: topRightRadius

                        Accessible.role: Accessible.StaticText
                        Accessible.name: (stat.label ?? "") + ": " + (stat.value ?? "")

                        StatPair {
                            id: tilePair
                            x: Theme.spacingL
                            y: Theme.spacingM
                            width: parent.width - Theme.spacingL * 2
                            stat: tile.stat
                        }
                    }
                }
            }
        }
    }

    component DeviceLayout: Column {
        readonly property alias actionsHolder: actionsHolder
        readonly property alias slotHolder: slotHolder

        spacing: Theme.spacingS

        Rectangle {
            width: parent.width
            height: deviceCard.implicitHeight + Theme.spacingL * 2
            radius: Theme.cornerRadiusL
            color: ProcessListMetrics.cardColor

            Column {
                id: deviceCard
                x: Theme.spacingL
                y: Theme.spacingL
                width: parent.width - Theme.spacingL * 2
                spacing: Theme.spacingS

                Item {
                    width: parent.width
                    height: Math.max(deviceTitle.implicitHeight, deviceValue.implicitHeight)

                    TitleBlock {
                        id: deviceTitle
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - (deviceValue.visible ? deviceValue.width + Theme.spacingL : 0)
                        subtitle: root.briefSubtitle
                    }

                    NumericText {
                        id: deviceValue
                        visible: !root.idle
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.mainValue || "—"
                        reserveText: root.valueReserve
                        font.pixelSize: Theme.fontSizeXXLarge
                        font.weight: Theme.fontWeightMedium
                        horizontalAlignment: Text.AlignRight
                        color: Theme.primary
                    }
                }

                Item {
                    width: parent.width
                    height: root.idle ? idleLine.implicitHeight : liveChart.implicitHeight

                    IdleLine {
                        id: idleLine
                        visible: root.idle
                    }

                    Column {
                        id: liveChart
                        visible: !root.idle
                        width: parent.width
                        spacing: Theme.spacingS

                        Item {
                            width: parent.width
                            height: Theme.buttonHeightXS

                            Item {
                                id: actionsHolder
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: headerActionsRow.implicitWidth
                                height: headerActionsRow.implicitHeight
                            }

                            LegendRow {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                visible: headerActionsRow.implicitWidth === 0 && root.twoLines
                            }

                            StyledText {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.maximumText !== "" && root.showChart
                                text: deviceChart.maximumLabel
                                font.pixelSize: Theme.fontSizeSmall
                                font.features: {
                                    "tnum": 1
                                }
                                color: Theme.surfaceVariantText
                            }
                        }

                        PopoutChart {
                            id: deviceChart
                            visible: root.showChart
                            width: parent.width
                            chartHeight: ProcessListMetrics.deviceChartHeight
                        }

                        Item {
                            id: slotHolder
                            visible: !root.showChart
                            width: parent.width
                            height: ProcessListMetrics.deviceChartHeight
                            clip: true
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: ProcessListMetrics.deviceStatRows * Theme.iconButtonSize + (ProcessListMetrics.deviceStatRows - 1) * Theme.groupedListGap

            StatGrid {
                readonly property int half: Math.ceil(root.deviceStats.length / 2)

                visible: !root.idle
                columns: 2
                leftGroup: root.deviceStats.slice(0, half)
                rightGroup: root.deviceStats.slice(half)
            }
        }
    }

    Component {
        id: overviewLayout

        Item {
            implicitHeight: MonitorMetrics.ringSizeWide

            IdleLine {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: root.idle
            }

            DRingGauge {
                id: ring
                anchors.left: parent.left
                visible: !root.idle
                width: MonitorMetrics.ringSizeWide
                height: width
                value: root.mainFraction >= 0 ? Math.min(1, root.mainFraction) : -1
                strokeWidth: MonitorMetrics.ringStrokeWide
                trackGap: Theme.spacingXS
                ringColor: Theme.primary
                trackColor: Theme.withAlpha(Theme.surfaceText, Theme.stateLayerFocus)
                animated: MonitorMetrics.animationsEnabled
                animationDuration: MonitorMetrics.meterDuration

                Column {
                    anchors.centerIn: parent
                    width: ring.innerSize - ring.strokeWidth

                    NumericText {
                        width: parent.width
                        text: root.mainValue || "—"
                        font.pixelSize: Theme.fontSizeXLarge
                        font.weight: Theme.fontWeightMedium
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }

                    StyledText {
                        visible: text !== ""
                        width: parent.width
                        text: root.mainLabel
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                }
            }

            Column {
                visible: !root.idle
                anchors.left: ring.right
                anchors.leftMargin: Theme.spacingL
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                Row {
                    id: pairRow
                    visible: root.overviewPairs.length > 0
                    width: parent.width
                    spacing: Theme.spacingL

                    Repeater {
                        model: root.overviewPairs.length

                        StatPair {
                            required property int index

                            width: (pairRow.width - pairRow.spacing * (root.overviewPairs.length - 1)) / root.overviewPairs.length
                            stat: root.overviewPairs[index] ?? ({})
                        }
                    }
                }

                PopoutChart {
                    width: parent.width
                    grid: false
                    chartHeight: MonitorMetrics.ringSizeWide - (pairRow.visible ? pairRow.implicitHeight + parent.spacing : 0)
                }
            }
        }
    }

    component TypeShape: DMaterialShape {
        width: Theme.iconButtonSize
        height: width
        shape: ProcessListMetrics.typeShapes[root.typeKey] ?? "circle"
        color: Theme.primaryContainer

        DeviceIcon {
            anchors.centerIn: parent
            name: root.iconName
            size: Theme.iconSize
            color: Theme.onPrimaryContainer
        }
    }

    component TitleBlock: Column {
        id: titleBlock

        property string subtitle

        StyledText {
            width: parent.width
            text: root.title
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        StyledText {
            visible: text !== ""
            width: parent.width
            text: titleBlock.subtitle
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
    }

    component StatPair: Column {
        id: statPair

        property var stat: ({})

        spacing: Theme.spacingXXS

        StyledText {
            width: parent.width
            text: statPair.stat.label ?? ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }

        NumericText {
            width: parent.width
            text: String(statPair.stat.value ?? "")
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
            color: Theme.surfaceText
        }
    }

    component IdleLine: Row {
        spacing: Theme.spacingS

        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.idleIcon
            size: Theme.iconSize
            color: Theme.surfaceVariantText
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.idleText
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
        }
    }

    component LegendRow: Row {
        id: legendRow

        property string label: root.chartLabel
        property string value: root.chartValue
        property string secondaryLabel: root.chartSecondaryLabel
        property string secondaryValue: root.chartSecondaryValue

        spacing: Theme.spacingL

        ChartLegendItem {
            text: legendRow.label
            value: legendRow.value
        }

        ChartLegendItem {
            text: legendRow.secondaryLabel
            value: legendRow.secondaryValue
            swatchColor: Theme.tertiary
            dashed: true
        }
    }

    component PopoutChart: ChartCard {
        compact: true
        cardColor: "transparent"
        legendVisible: false
        values: root.values
        secondaryValues: root.secondaryValues
        secondaryLabel: root.chartSecondaryLabel
        maximum: root.maximum
        maximumText: root.maximumText
        historyLength: DgopService.historySize
    }

    component StatGrid: Grid {
        id: statGrid

        property var leftGroup: []
        property var rightGroup: []
        readonly property bool hasStats: leftGroup.length + rightGroup.length > 0
        readonly property real cellWidth: columns === 2 ? (width - columnSpacing) / 2 : width

        width: parent.width
        columns: width >= Theme.navigationRailWidth * 6 ? 2 : 1
        columnSpacing: Theme.spacingL
        rowSpacing: Theme.spacingL

        StatGroup {
            width: statGrid.cellWidth
            stats: statGrid.leftGroup
        }

        StatGroup {
            width: statGrid.cellWidth
            stats: statGrid.rightGroup
        }
    }

    component StatGroup: SettingsGroup {
        id: group

        property var stats: []

        visible: stats.length > 0
        customPaddingV: 0
        customPaddingH: Theme.spacingL

        Repeater {
            model: group.stats.length

            StatRow {
                required property int index
                readonly property var stat: group.stats[index] ?? ({})

                label: stat.label ?? ""
                value: String(stat.value ?? "")
                tooltip: stat.tooltip ?? ""
                loading: stat.loading ?? false
            }
        }
    }
}
