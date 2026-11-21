pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.ProcessList
import "../../../Services/SysmonCatalog.js" as SysmonCatalog
import "../../../Services/Drives.js" as Drives

Column {
    id: root

    property var metric: null
    property bool allowGraph: true
    property bool allowDeviceOptions: false

    signal metricEdited(var metric)

    readonly property string type: SysmonCatalog.typeOf(metric?.device)
    readonly property var vals: metric?.vals ?? []
    readonly property string currentKey: SysmonService.device(metric?.device)?.key ?? ""
    readonly property var sections: {
        const keys = SysmonService.devices({
            aggregates: true
        }).map(d => d.key);
        const stored = currentKey || metric?.device;
        if (type && keys.indexOf(stored) < 0)
            keys.push(stored);
        return ["cpu", "memory", "gpu", "disk", "net"].map(t => ({
                    type: t,
                    keys: keys.filter(k => SysmonCatalog.typeOf(k) === t)
                })).filter(s => s.keys.length > 0);
    }
    readonly property bool showsSpace: type === "disk" && vals.indexOf("space") >= 0
    readonly property string wholeDevice: "device"
    readonly property string mountKey: {
        const mounts = (DgopService.diskMounts ?? []).map(m => m.mount);
        if (metric?.mount && mounts.indexOf(metric.mount) < 0)
            mounts.push(metric.mount);
        return mounts.join("\n");
    }
    readonly property string deviceLabel: SysmonService.device(metric?.device)?.name ?? SysmonService.displayName(metric?.device)
    readonly property var mountValues: [wholeDevice].concat(mountKey ? mountKey.split("\n") : [])
    readonly property var mountLabels: [deviceLabel].concat(mountValues.slice(1))
    readonly property var chips: (SysmonCatalog.TYPES[type] ?? []).map(def => {
        const position = vals.indexOf(def.id);
        return {
            value: def.id,
            label: SysmonService.valueLabel(type, def.id),
            icon: position >= 0 ? "check" : "",
            enabled: position < 0 || vals.length > 1
        };
    })

    readonly property var selectedInOrder: chips.filter(c => vals.indexOf(c.value) >= 0)

    function withMain(ids, main) {
        const rest = (SysmonCatalog.TYPES[type] ?? []).map(def => def.id).filter(id => id !== main && ids.indexOf(id) >= 0);
        return ids.indexOf(main) >= 0 ? [main].concat(rest) : rest;
    }

    function edit(changes) {
        const next = Object.assign({}, metric, changes);
        if (changes.device !== undefined)
            delete next.mount;
        const normalized = SysmonCatalog.normalizeMetrics([next])[0];
        if (normalized)
            metricEdited(normalized);
    }

    function toggleValue(id, selected) {
        const ids = selected ? vals.concat([id]) : vals.filter(v => v !== id);
        if (ids.length === 0 || (selected && vals.indexOf(id) >= 0))
            return;
        const next = withMain(ids, selected || vals[0] !== id ? vals[0] : withMain(ids, "")[0]);
        let reason = -1;
        for (const chip of chipFlow.children) {
            if (chip.activeFocus)
                reason = chip.focusReason;
        }
        edit({
            vals: next
        });
        if (reason >= 0)
            Qt.callLater(() => {
                for (const chip of chipFlow.children) {
                    if (chip.value === id)
                        chip.forceActiveFocus(reason);
                }
            });
    }

    width: parent?.width ?? 0
    spacing: SettingsMetrics.groupGap

    SettingsRow {
        id: pickerRow

        visible: root.sections.length > 0
        title: I18n.tr("Device", "system monitor metric device field label")

        body: Column {
            width: parent.width
            spacing: SettingsMetrics.groupGap

            Repeater {
                model: ScriptModel {
                    values: root.sections
                    objectProp: "type"
                }

                Column {
                    id: section

                    required property var modelData
                    readonly property string sectionTitle: modelData.type === "gpu" ? I18n.tr("GPUs", "system monitor device picker section: graphics cards") : SysmonService.typeName(modelData.type)

                    width: parent?.width ?? 0

                    SettingsSectionLabel {
                        text: section.sectionTitle
                        topGap: Theme.spacingS
                        bottomGap: Theme.spacingXS
                    }

                    SettingsGroup {
                        slotColor: Qt.colorEqual(pickerRow.rowColor, SettingsMetrics.controlColor) ? SettingsMetrics.rowColor : SettingsMetrics.controlColor

                        Repeater {
                            model: ScriptModel {
                                values: section.modelData.keys
                            }

                            SettingsRow {
                                id: candidate

                                required property string modelData
                                readonly property var entry: SysmonService.device(modelData)
                                readonly property bool aggregate: modelData === "disk" || modelData === "net"
                                readonly property string iface: entry?.net?.iface ?? ""
                                readonly property bool indented: !aggregate && (section.modelData.type === "disk" || section.modelData.type === "net")

                                title: aggregate ? (modelData === "disk" ? I18n.tr("All drives", "system monitor device picker: every drive combined") : I18n.tr("All interfaces", "system monitor device picker: every network interface combined")) : entry?.name ?? (SysmonCatalog.typeOf(modelData) === "gpu" ? SysmonService.displayName(modelData) : SysmonService.parseKey(modelData).id || SysmonService.displayName(modelData))
                                subtitle: section.modelData.type === "gpu" ? SysmonService.gpuSleepNote() : entry?.drive ? Drives.rootMostMount(entry.drive) : iface !== title ? iface : ""
                                active: modelData === (root.currentKey || root.metric?.device)
                                clickable: true
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: section.sectionTitle + ", " + title
                                Accessible.checkable: true
                                Accessible.checked: active
                                onClicked: {
                                    if (!active)
                                        root.edit({
                                            device: modelData
                                        });
                                }

                                leading: Item {
                                    anchors.verticalCenter: parent?.verticalCenter
                                    width: Theme.iconSize + (candidate.indented ? Theme.spacingXL : 0)
                                    height: Theme.iconSize

                                    DeviceIcon {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: candidate.entry?.icon ?? SysmonService.device(section.modelData.type)?.icon ?? "gpu"
                                        size: Theme.iconSize
                                        color: candidate.iconColor
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    SettingsRow {
        title: I18n.tr("Show", "system monitor: values shown for a metric")

        body: DFilterChips {
            id: chipFlow

            width: parent.width
            multiSelect: true
            showCheck: false
            showCounts: false
            model: root.chips
            selectedValues: root.vals
            onSelectionToggled: (index, selected) => root.toggleValue(root.chips[index].value, selected)
        }
    }

    SettingsButtonGroupRow {
        visible: root.vals.length > 1
        text: I18n.tr("Main value", "system monitor: value shown large")
        model: root.selectedInOrder.map(c => c.label)
        values: root.selectedInOrder.map(c => c.value)
        value: root.vals[0]
        onValueSelected: v => {
            if (v !== root.vals[0])
                root.edit({
                    vals: root.withMain(root.vals, v)
                });
        }
    }

    SettingsDropdownRow {
        visible: root.allowDeviceOptions && root.showsSpace
        text: I18n.tr("Mount", "noun, dropdown label for the disk mount point")
        options: root.mountLabels
        optionValues: root.mountValues
        currentValue: root.metric?.mount ?? root.wholeDevice
        onValueChanged: value => root.edit({
                mount: value === root.wholeDevice ? undefined : value
            })
    }

    SettingsToggleRow {
        visible: root.allowDeviceOptions && (root.type === "memory" || (root.type === "gpu" && root.vals.indexOf("vram") >= 0))
        text: I18n.tr("Show percentage", "system monitor memory option, off shows the used amount instead")
        checked: root.metric?.percent !== false
        onToggled: checked => root.edit({
                percent: checked ? undefined : false
            })
    }

    SettingsButtonGroupRow {
        visible: root.allowDeviceOptions && root.showsSpace
        text: I18n.tr("Disk usage format", "system monitor disk entry option")
        model: [I18n.tr("Percentage", "disk usage format option, used share of the disk"), I18n.tr("Total", "disk usage format option, total disk size"), I18n.tr("Remaining", "disk usage format option, free disk space"), I18n.tr("Remaining / Total", "disk usage format option, free space and total size")]
        values: [0, 1, 2, 3]
        value: root.metric?.diskMode ?? 0
        onValueSelected: v => root.edit({
                diskMode: v === 0 ? undefined : v
            })
    }

    SettingsToggleRow {
        visible: root.allowDeviceOptions && root.type === "net"
        text: I18n.tr("Compact mode", "system monitor widget option")
        description: I18n.tr("Whole numbers, at most three digits", "network speed widget option, shows 1 MB/s instead of 1023.4 KB/s")
        checked: root.metric?.compact === true
        onToggled: checked => root.edit({
                compact: checked ? true : undefined
            })
    }

    SettingsToggleRow {
        visible: root.allowDeviceOptions && root.type === "net"
        text: I18n.tr("Hide when idle", "network speed widget option, hides the widget while traffic is low")
        description: I18n.tr("While download and upload are both under 1 KB/s", "network speed widget option description for hide when idle")
        checked: root.metric?.hideIdle === true
        onToggled: checked => root.edit({
                hideIdle: checked ? true : undefined
            })
    }

    SettingsToggleRow {
        visible: root.allowGraph
        text: I18n.tr("Graph", "system monitor: per-metric chart switch")
        checked: root.metric?.graph === true
        onToggled: checked => root.edit({
                graph: checked
            })
    }
}
