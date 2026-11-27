pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Sysmon
import "../../Services/SysmonCatalog.js" as SysmonCatalog

Column {
    id: root

    property string deviceKey: ""
    property string entryType: ""
    property bool active: false

    property string chosenKey: ""

    readonly property real rowHeight: Theme.iconButtonSize + Theme.spacingS
    readonly property real shapeSize: Theme.iconSizeLarge
    readonly property real expandedGap: Theme.spacingS
    readonly property real bodyTopPadding: Theme.spacingXS
    readonly property real bodyBottomPadding: Theme.spacingM
    // DevicePane's overview layout is as tall as its ring.
    readonly property real bodyHeight: MonitorMetrics.ringSizeWide + bodyTopPadding + bodyBottomPadding

    readonly property var rows: SysmonService.popoutDevices(deviceKey)
    readonly property string expandedKey: SysmonService.popoutSelection(rows, chosenKey || deviceKey, entryType)
    readonly property string monitorTarget: expandedKey || "processes"
    readonly property string expandedType: SysmonService.parseKey(expandedKey).type

    readonly property var modules: {
        const list = SysmonCatalog.modulesFor(rows.map(e => ({
                    device: e.key,
                    vals: ["read", "write"]
                })));
        const extra = SysmonCatalog.paneModules(expandedKey);
        extra.forEach(m => {
            if (list.indexOf(m) < 0)
                list.push(m);
        });
        return list;
    }

    // Opening takes focus without the keyboard highlight; arrow keys move it with the highlight.
    function focusExpanded() {
        focusRow(rows.findIndex(e => e.key === expandedKey), Qt.OtherFocusReason);
    }

    function focusRow(index, reason = Qt.TabFocusReason) {
        (rowRepeater.itemAt(Math.max(0, Math.min(rows.length - 1, index))) as OverviewRow)?.focusHeader(reason);
    }

    Ref {
        service: DgopService
        modules: root.modules
        active: root.active
    }

    Ref {
        service: DriveService
        active: root.active && (root.expandedType === "disk" || root.rows.some(e => e.type === "disk" && e.key !== "disk"))
    }

    // Fixed, so the popout keeps its size while one row collapses and another expands.
    Item {
        width: parent.width
        height: root.rows.length * root.rowHeight + Math.max(0, root.rows.length - 1) * Theme.groupedListGap + (root.rows.length > 0 ? root.bodyHeight + root.expandedGap * 2 : 0)

        Column {
            width: parent.width
            spacing: Theme.groupedListGap

            Repeater {
                id: rowRepeater

                model: root.rows.length

                OverviewRow {}
            }
        }
    }

    component OverviewRow: Item {
        id: row

        required property int index
        readonly property var entry: root.rows[index] ?? ({})
        readonly property var summary: SysmonService.summary(entry)
        readonly property bool expanded: entry.key === root.expandedKey
        readonly property bool first: index === 0
        readonly property bool last: index === root.rows.length - 1
        readonly property DevicePane pane: paneLoader.item as DevicePane
        readonly property real outer: Theme.groupedListOuterRadius
        readonly property real inner: Theme.groupedListInnerRadius

        property real progress: expanded ? 1 : 0

        function focusHeader(reason) {
            header.forceActiveFocus(reason);
        }

        function corner(collapsed) {
            return collapsed + (outer - collapsed) * progress;
        }

        width: parent.width
        height: card.y + card.height + (last ? 0 : root.expandedGap * progress)

        Behavior on progress {
            enabled: !Theme.reduceMotion
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }

        Rectangle {
            id: card
            y: row.first ? 0 : root.expandedGap * row.progress
            width: parent.width
            height: root.rowHeight + root.bodyHeight * row.progress
            clip: true
            color: ProcessListMetrics.cardColor
            border.width: Theme.layerOutlineWidth
            border.color: Theme.outlineMedium
            topLeftRadius: row.corner(row.first ? row.outer : row.inner)
            topRightRadius: topLeftRadius
            bottomLeftRadius: row.corner(row.last ? row.outer : row.inner)
            bottomRightRadius: bottomLeftRadius

            DListItem {
                id: header
                width: parent.width
                implicitHeight: root.rowHeight
                surfaceColor: "transparent"
                border.width: 0
                topLeftRadius: card.topLeftRadius
                topRightRadius: card.topRightRadius
                bottomLeftRadius: row.last ? row.outer + (row.inner - row.outer) * row.progress : row.inner
                bottomRightRadius: bottomLeftRadius
                isHovered: hovered && !row.expanded
                Accessible.name: (row.entry.name ?? "") + ", " + deviceRow.valueText
                // These need Qt 6.12, older Qt fails to load the whole popout. Restore once 6.12 is the minimum.
                // Accessible.expandable: true
                // Accessible.expanded: row.expanded
                Keys.onUpPressed: root.focusRow(row.index - 1)
                Keys.onDownPressed: root.focusRow(row.index + 1)
                onClicked: root.chosenKey = row.entry.key ?? ""

                DeviceRow {
                    id: deviceRow
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    device: Object.assign({}, row.entry, row.summary)
                    valueText: row.expanded && row.pane?.shortSubtitle ? row.pane.shortSubtitle : (row.summary.value ?? "")
                    valueTooltip: row.expanded ? "" : (row.summary.valueTooltip ?? "")
                    textColor: header.contentColor
                    supportingColor: header.supportingContentColor
                    iconColor: Theme.blend(header.supportingContentColor, Theme.onPrimaryContainer, row.progress)
                    iconSize: Theme.iconSizeMedium
                    iconBoxSize: root.shapeSize
                    nameSize: Theme.fontSizeMedium + (Theme.fontSizeLarge - Theme.fontSizeMedium) * row.progress
                    sparkOpacity: 1 - row.progress

                    DMaterialShape {
                        anchors.fill: parent
                        shape: ProcessListMetrics.typeShapes[row.entry.type] ?? "circle"
                        color: Theme.withAlpha(Theme.primaryContainer, row.progress)
                    }
                }
            }

            DevicePaneLoader {
                id: paneLoader
                x: Theme.spacingM
                y: root.rowHeight + root.bodyTopPadding
                width: parent.width - Theme.spacingM * 2
                height: implicitHeight
                active: row.expanded || row.progress > 0
                opacity: row.progress
                key: row.entry.key ?? "cpu"
                variant: "overview"
            }
        }
    }
}
