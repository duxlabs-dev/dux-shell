pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Common as DCommon
import qs.Modules.Sysmon
import "Layout.js" as Planner
import "../../Services/SysmonCatalog.js" as Catalog

Item {
    id: root

    property var config: ({})
    property bool active: false
    property color accentColor: Theme.primary
    property color tileColor: Theme.surfaceContainer
    property color contentColor: Theme.surfaceText
    property color mutedColor: Theme.surfaceVariantText
    property color trendSecondaryColor: mutedColor
    property real tileRadius: Theme.cornerRadiusL
    property bool halo: false
    property string headerTitle: config.title || Catalog.shortCpuName(DgopService.cpuModel) || DgopService.hostname

    readonly property string layout: config.layout ?? "tiles"
    // Rows and panels sit straight on the wallpaper without a card; tiles always keep their surface.
    readonly property color panelColor: config.background === "none" ? "transparent" : tileColor
    readonly property bool tiled: Catalog.paintsTiles(config)
    readonly property bool listCards: layout === "list" && tiled
    readonly property bool listCardsStacked: width > height
    readonly property real listGap: listCards ? gap : Theme.groupedListGap
    readonly property real listLabelWidth: {
        if (!listCards)
            return 0;
        let w = 0;
        for (const type of Object.keys(Catalog.TYPES)) {
            for (const def of Catalog.TYPES[type])
                w = Math.max(w, DCommon.Fonts.textWidth(labelProbe.font, SysmonService.shortValueLabel(type, def.id)));
        }
        return Math.ceil(w);
    }
    readonly property string listValueReserve: listCards ? MonitorMetrics.widestReserve(rows, true) : ""
    readonly property var rows: source.rows
    readonly property int count: rows.length
    readonly property bool showProcesses: config.showTopProcesses === true
    readonly property bool showHeader: config.showHeader === true && (count > 0 || showProcesses)
    readonly property real gap: Theme.spacingS
    readonly property real headerSpace: showHeader ? MonitorMetrics.headerHeight + gap : 0
    readonly property int processCount: config.topProcessCount ?? 3
    readonly property real processesHeight: showProcesses ? processCount * MonitorMetrics.processRowHeight + (processCount - 1) * Theme.groupedListGap : 0
    readonly property real processesWidth: MonitorMetrics.processesWidth

    readonly property bool solo: count === 1
    readonly property real tileW: solo ? MonitorMetrics.tileSoloMinWidth : MonitorMetrics.tileMinWidth
    readonly property real tileH: solo ? MonitorMetrics.tileSoloMinHeight : MonitorMetrics.tileMinHeight
    // Rows built by an asynchronous Loader arrive after count changes; each one bumps this so the sizes re-read.
    property int builtRows: 0
    readonly property real listRowHeight: listMax("naturalHeight", MonitorMetrics.listRowMinHeight)
    readonly property real listColumnWidth: listMax("implicitWidth", 0)
    readonly property int lineCount: {
        let n = 0;
        for (const r of rows)
            n += (r.values ?? []).length;
        return n;
    }
    readonly property bool barsVertical: config.barOrientation === "vertical" || (config.barOrientation !== "horizontal" && height > width * MonitorMetrics.verticalBarsRatio)
    readonly property var box: ({
            "w": width,
            "h": height
        })
    readonly property var frame: ({
            "gap": gap,
            "headerH": headerSpace,
            "processesW": processesWidth,
            "processesH": processesHeight
        })
    readonly property var placements: !showProcesses ? [false] : width > height ? [true, false] : [false, true]

    readonly property var plan: {
        if (count === 0)
            return Planner.measure(box, frame, 0, 0, false);
        switch (layout) {
        case "tiles":
            return Planner.tilePlan(count, box, Object.assign({
                "tileW": tileW,
                "tileH": tileH
            }, frame));
        case "list":
            {
                const candidates = [];
                for (let c = 1; c <= count; c++) {
                    const r = Math.ceil(count / c);
                    for (const beside of placements)
                        candidates.push(Planner.measure(box, frame, c * listColumnWidth + (c - 1) * gap, r * listRowHeight + (r - 1) * listGap, beside, {
                            "cols": c
                        }));
                }
                return Planner.choose(candidates);
            }
        case "graphs":
            {
                const candidates = [];
                const pad = Theme.spacingM * 2;
                const legend = config.legend ?? "list";
                const listH = lineCount * MonitorMetrics.processRowHeight + (lineCount - 1) * Theme.groupedListGap;
                const legendH = w => legend === "list" ? listH : legend === "inline" ? graphs.inlineLegendHeight(w) : 0;
                const legendSides = legend === "off" ? [false] : width > height ? [true, false] : [false, true];
                for (const legendBeside of legendSides) {
                    for (const beside of placements) {
                        if (legendBeside) {
                            candidates.push(Planner.measure(box, frame, pad + MonitorMetrics.chartMinWidth + Theme.spacingM + processesWidth, pad + Math.max(MonitorMetrics.chartMinHeight, legendH(processesWidth)), beside, {
                                "legendBeside": true
                            }));
                        } else {
                            const legendW = (beside ? width - processesWidth - gap : width) - pad;
                            const h = legend === "off" ? 0 : legendH(legendW) + Theme.spacingS;
                            candidates.push(Planner.measure(box, frame, processesWidth, pad + MonitorMetrics.chartMinHeight + h, beside, {
                                "legendBeside": false
                            }));
                        }
                    }
                }
                return Planner.choose(candidates);
            }
        }
        const candidates = [];
        for (let c = 1; c <= (barsVertical ? 1 : count); c++) {
            const r = Math.ceil(count / c);
            const w = barsVertical ? bars.implicitWidth : c * bars.groupWidth + (c - 1) * bars.minGap;
            const h = barsVertical ? bars.implicitHeight : c === 1 ? bars.stackLength : r * bars.groupHeight + (r - 1) * bars.minGap;
            for (const beside of placements)
                candidates.push(Planner.measure(box, frame, w, h, beside, {
                        "cols": c
                    }));
        }
        return Planner.choose(candidates);
    }
    readonly property bool beside: plan.beside
    readonly property int cols: plan.cols ?? 1
    readonly property int gridRows: Math.ceil(count / cols)
    readonly property real fit: Planner.fitScale(plan.w, plan.h, box, MonitorMetrics.scaleFloor)

    function listMax(prop, floor) {
        const items = listCards ? cardRepeater : listRepeater;
        void builtRows;
        let v = floor;
        for (let i = 0; i < items.count; i++)
            v = Math.max(v, items.itemAt(i)?.[prop] ?? 0);
        return v;
    }

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    SysmonSource {
        id: source

        metrics: {
            const list = root.config.metrics ?? [];
            if (root.layout !== "tiles" || root.config.style !== "graph")
                return list;
            return list.map(m => Object.assign({}, m, {
                    "graph": true
                }));
        }
        rangeSeconds: root.config.graphInterval ?? 60
        charts: root.layout === "graphs" || (root.layout === "tiles" && root.config.style === "graph" && root.solo) ? "all" : root.layout === "bars" || root.listCards ? "none" : "graph"
        processes: root.showProcesses
        processSort: root.config.topProcessSortBy ?? "cpu"
        processCount: root.processCount
        system: root.config.showHeader === true
        active: root.active
    }

    Item {
        id: content

        width: Math.max(root.plan.w, root.width / root.fit)
        height: Math.max(root.plan.h, root.height / root.fit)
        x: (root.width - width * root.fit) / 2
        y: (root.height - height * root.fit) / 2
        scale: root.fit
        transformOrigin: Item.TopLeft

        Item {
            id: header

            anchors.left: parent.left
            anchors.right: parent.right
            height: MonitorMetrics.headerHeight
            visible: root.showHeader

            MonitorText {
                anchors.left: parent.left
                anchors.right: uptime.left
                anchors.leftMargin: Theme.spacingXS
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: root.headerTitle
                halo: root.halo
                color: root.contentColor
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            MonitorText {
                id: uptime

                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                text: DgopService.shortUptime
                halo: root.halo
                color: root.mutedColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        Item {
            id: body

            readonly property real freeHeight: parent.height - root.headerSpace - (root.showProcesses && !root.beside ? root.gap + root.processesHeight : 0)

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: root.headerSpace
            width: parent.width - (root.beside ? root.processesWidth + root.gap : 0)
            height: freeHeight
            visible: root.count > 0

            Repeater {
                model: root.layout === "tiles" ? root.count : 0

                MonitorTile {
                    required property int index
                    readonly property int rest: root.count % root.cols
                    readonly property int span: rest > 0 && index === root.count - 1 ? root.cols - rest + 1 : 1
                    readonly property real cellWidth: (body.width - (root.cols - 1) * root.gap) / root.cols
                    readonly property real cellHeight: (body.height - (root.gridRows - 1) * root.gap) / root.gridRows
                    readonly property real startX: (index % root.cols) * (cellWidth + root.gap)

                    x: I18n.isRtl ? body.width - startX - width : startX
                    y: Math.floor(index / root.cols) * (cellHeight + root.gap)
                    width: span * cellWidth + (span - 1) * root.gap
                    height: cellHeight
                    row: root.rows[index] ?? ({})
                    reserveExtras: {
                        const start = index - index % root.cols;
                        return root.rows.slice(start, start + root.cols).some(r => !r.asleep && (r.values ?? []).length > 1);
                    }
                    style: root.config.style ?? "icon"
                    solo: root.solo
                    size: !root.solo || width < MonitorMetrics.wideThreshold ? "sm" : height < MonitorMetrics.wideThreshold ? "wide" : "big"
                    accentColor: root.accentColor
                    tileColor: root.tileColor
                    contentColor: root.contentColor
                    mutedColor: root.mutedColor
                    trendSecondaryColor: root.trendSecondaryColor
                    radius: root.tileRadius
                    halo: root.halo
                }
            }

            // Columns fill top to bottom, so each one reads as its own grouped list.
            GridLayout {
                anchors.fill: parent
                visible: root.layout === "list"
                flow: GridLayout.TopToBottom
                rows: root.gridRows
                rowSpacing: root.listGap
                columnSpacing: root.gap

                Repeater {
                    id: listRepeater

                    model: root.layout === "list" && !root.listCards ? root.count : 0
                    onItemAdded: root.builtRows++

                    MonitorListRow {
                        required property int index

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: root.listColumnWidth
                        Layout.minimumHeight: root.listRowHeight
                        row: root.rows[index] ?? ({})
                        first: index % root.gridRows === 0
                        last: index % root.gridRows === root.gridRows - 1 || index === root.count - 1
                        accentColor: root.accentColor
                        tileColor: root.panelColor
                        contentColor: root.contentColor
                        mutedColor: root.mutedColor
                        halo: root.halo
                    }
                }

                Repeater {
                    id: cardRepeater

                    model: root.listCards ? root.count : 0
                    onItemAdded: root.builtRows++

                    MonitorListCard {
                        required property int index

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: root.listColumnWidth
                        Layout.minimumHeight: root.listRowHeight
                        row: root.rows[index] ?? ({})
                        stacked: root.listCardsStacked
                        labelWidth: root.listLabelWidth
                        valueReserve: root.listValueReserve
                        accentColor: root.accentColor
                        cardColor: root.tileColor
                        cardRadius: root.tileRadius
                        contentColor: root.contentColor
                        mutedColor: root.mutedColor
                        halo: root.halo
                    }
                }
            }

            MonitorText {
                id: labelProbe
                visible: false
                font.pixelSize: Theme.fontSizeSmall
            }

            MonitorBars {
                id: bars

                anchors.fill: parent
                visible: root.layout === "bars"
                rows: visible ? root.rows : []
                availableHeight: body.freeHeight
                barNames: root.config.barNames === true
                vertical: root.barsVertical
                columns: root.barsVertical ? 1 : root.cols
                tiled: root.tiled
                tileColor: root.tileColor
                tileRadius: root.tileRadius
                accentColor: root.accentColor
                contentColor: root.contentColor
                mutedColor: root.mutedColor
                halo: root.halo
            }

            MonitorGraphs {
                id: graphs

                anchors.fill: parent
                visible: root.layout === "graphs"
                rows: visible ? root.rows : []
                legend: root.config.legend ?? "list"
                legendBeside: root.plan.legendBeside === true
                rangeSeconds: root.config.graphInterval ?? 60
                tileColor: root.panelColor
                contentColor: root.contentColor
                mutedColor: root.mutedColor
                halo: root.halo
            }
        }

        MonitorProcesses {
            anchors.right: parent.right
            y: root.beside ? body.y + (body.height - height) / 2 : body.y + body.height + root.gap
            width: root.beside ? root.processesWidth : parent.width
            height: root.processesHeight
            visible: root.showProcesses
            processes: source.topProcesses
            sortBy: root.config.topProcessSortBy ?? "cpu"
            tileColor: root.panelColor
            contentColor: root.contentColor
            mutedColor: root.mutedColor
            halo: root.halo
        }
    }
}
