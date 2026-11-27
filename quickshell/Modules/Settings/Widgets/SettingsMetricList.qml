pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.ProcessList
import "../../../Services/SysmonCatalog.js" as SysmonCatalog

Column {
    id: root

    property var metrics: []
    property bool allowGraph: true
    property bool allowDeviceOptions: false

    signal metricsEdited(var metrics)

    readonly property var items: SysmonCatalog.normalizeMetrics(metrics)
    property int expandedIndex: -1
    property string expandedDevice: ""
    readonly property bool firstInGroup: parent?.isSettingsGroupHost ? parent.isEdge(root, true) : true

    // Metrics have no ids, so a list changed from outside closes the open row unless it still holds the same device
    onItemsChanged: {
        if ((items[expandedIndex]?.device ?? "") !== expandedDevice)
            expandedIndex = -1;
    }

    function expand(index, list) {
        expandedIndex = index;
        expandedDevice = (list ?? items)[index]?.device ?? "";
    }

    function publish(list, expanded) {
        const next = SysmonCatalog.normalizeMetrics(list);
        expand(expanded, next);
        metricsEdited(next);
    }

    function replace(index, metric) {
        const next = items.slice();
        next[index] = metric;
        publish(next, expandedIndex);
    }

    function remove(index) {
        const next = items.slice();
        next.splice(index, 1);
        publish(next, expandedIndex === index ? -1 : expandedIndex > index ? expandedIndex - 1 : expandedIndex);
    }

    function reorder(indices) {
        publish(indices.map(i => items[i]), indices.indexOf(expandedIndex));
    }

    function addMetric() {
        // Never a GPU: reading one keeps it awake, so it's only added when picked in the entry.
        const used = items.map(m => m.device);
        const key = ["cpu", "memory", "disk", "net"].find(k => used.indexOf(k) < 0) ?? "cpu";
        publish(items.concat([
            {
                device: key,
                vals: [SysmonCatalog.TYPES[SysmonCatalog.typeOf(key)][0].id],
                graph: false,
                on: true
            }
        ]), items.length);
    }

    width: parent?.width ?? 0
    spacing: SettingsMetrics.groupGap
    Component.onCompleted: DgopService.ensureMeta()

    Ref {
        service: DgopService
        modules: ["disk-rate", "net-rate"]
        active: root.visible
    }

    Ref {
        service: DriveService
        active: root.visible
    }

    SettingsReorderList {
        id: list

        visible: count > 0
        model: root.items.length
        onReordered: indices => root.reorder(indices)

        delegate: SettingsReorderRow {
            id: row

            readonly property var metric: root.items[index] ?? null
            readonly property string type: SysmonCatalog.typeOf(metric?.device)
            readonly property bool expanded: root.expandedIndex === index
            readonly property string shown: (metric?.vals ?? []).map(id => SysmonService.valueLabel(type, id)).join(", ")

            reorderList: list
            title: SysmonService.displayName(metric?.device)
            subtitle: root.allowGraph && metric?.graph ? shown + " · " + I18n.tr("Graph", "system monitor: per-metric chart switch") : shown
            iconColor: metric?.on ? Theme.primary : Theme.onSurface_38
            clickable: true
            topRadius: dragging || (position === 0 && root.firstInGroup) ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
            bottomRadius: dragging ? Theme.groupedListOuterRadius : SettingsMetrics.groupInnerRadius
            Accessible.checkable: true
            Accessible.checked: expanded
            Accessible.onToggleAction: root.expand(expanded ? -1 : index)
            onClicked: root.expand(expanded ? -1 : index)

            leading: Item {
                anchors.verticalCenter: parent?.verticalCenter
                width: Theme.iconSize + Theme.spacingL - Theme.spacingS
                height: Theme.iconSize

                DeviceIcon {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    name: SysmonService.device(row.metric?.device)?.icon ?? SysmonService.valueIcon(row.type, "")
                    size: Theme.iconSize
                    color: row.iconColor
                }
            }

            body: Loader {
                width: parent.width
                // The reorder list places rows by height, so a dragged row folds its fields away until it drops
                visible: active && !row.dragging
                active: row.expanded

                sourceComponent: SettingsGroup {
                    slotColor: SettingsMetrics.controlColor

                    SettingsMetricFields {
                        metric: row.metric
                        allowGraph: root.allowGraph
                        allowDeviceOptions: root.allowDeviceOptions
                        onMetricEdited: metric => root.replace(row.index, metric)
                    }

                    SettingsRow {
                        title: I18n.tr("Remove", "verb, button that removes an item from a list")
                        iconName: "delete"
                        iconColor: Theme.error
                        titleColor: Theme.error
                        clickable: true
                        onClicked: root.remove(row.index)
                    }
                }
            }

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: row.expanded ? "expand_less" : "expand_more"
                size: Theme.iconSize
                color: row.supportingContentColor
            }

            DToggle {
                anchors.verticalCenter: parent.verticalCenter
                hideText: true
                text: row.title
                checked: row.metric?.on ?? false
                onToggled: checked => root.replace(row.index, Object.assign({}, row.metric, {
                        on: checked
                    }))
            }
        }
    }

    SettingsRow {
        title: I18n.tr("Add", "verb, button that adds a new item to a list")
        iconName: "add"
        clickable: true
        onClicked: {
            if (root.items.length < SysmonCatalog.maxMetrics)
                root.addMetric();
            else
                ToastService.showWarning(I18n.tr("Maximum entries reached", "system monitor settings: the entry list is full"));
        }
    }
}
