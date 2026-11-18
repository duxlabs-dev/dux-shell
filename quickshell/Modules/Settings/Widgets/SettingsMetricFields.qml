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

    signal metricEdited(var metric)

    readonly property string type: SysmonCatalog.typeOf(metric?.device)
    readonly property var vals: metric?.vals ?? []
    readonly property bool multiGpu: type === "gpu" && SysmonService.hostGpuCount() > 1
    readonly property string currentKey: SysmonService.device(metric?.device)?.key ?? ""
    readonly property var candidates: {
        if (type !== "gpu" && type !== "disk" && type !== "net")
            return [];
        const keys = SysmonService.devices({
            aggregates: true
        }).filter(d => d.type === root.type).map(d => d.key);
        return keys.length > 1 ? keys : [];
    }
    readonly property var chips: (SysmonCatalog.TYPES[type] ?? []).map(def => {
        const position = vals.indexOf(def.id);
        return {
            value: def.id,
            label: SysmonService.valueLabel(type, def.id),
            icon: position === 0 ? "star" : position > 0 ? "check" : "",
            enabled: position < 0 || vals.length > 1
        };
    })

    function edit(changes) {
        const next = Object.assign({}, metric, changes);
        if (changes.device !== undefined)
            delete next.mount;
        const normalized = SysmonCatalog.normalizeMetrics([next])[0];
        if (normalized)
            metricEdited(normalized);
    }

    function toggleValue(id, selected) {
        const next = selected ? vals.concat([id]) : vals.filter(v => v !== id);
        if (next.length === 0 || (selected && vals.indexOf(id) >= 0))
            return;
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

        visible: root.candidates.length > 0
        title: root.type === "gpu" ? I18n.tr("GPU", "system monitor device picker") : root.type === "disk" ? I18n.tr("Disk", "system monitor device picker") : I18n.tr("Interface", "system monitor device picker")

        body: SettingsGroup {
            slotColor: Qt.colorEqual(pickerRow.rowColor, SettingsMetrics.controlColor) ? SettingsMetrics.rowColor : SettingsMetrics.controlColor

            Repeater {
                model: ScriptModel {
                    values: root.candidates
                }

                SettingsRow {
                    id: candidate

                    required property string modelData
                    readonly property var entry: SysmonService.device(modelData)
                    readonly property string iface: entry?.net?.iface ?? ""

                    title: entry?.name ?? modelData
                    subtitle: root.multiGpu ? SysmonService.gpuSleepNote() : entry?.drive ? Drives.rootMostMount(entry.drive) : iface !== title ? iface : ""
                    active: modelData === root.currentKey
                    clickable: true
                    Accessible.role: Accessible.RadioButton
                    Accessible.checkable: true
                    Accessible.checked: active
                    onClicked: {
                        if (!active)
                            root.edit({
                                device: modelData
                            });
                    }

                    leading: DeviceIcon {
                        anchors.verticalCenter: parent?.verticalCenter
                        name: candidate.entry?.icon ?? ""
                        size: Theme.iconSize
                        color: candidate.iconColor
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

    SettingsToggleRow {
        visible: root.allowGraph
        text: I18n.tr("Graph", "system monitor: per-metric chart switch")
        checked: root.metric?.graph === true
        onToggled: checked => root.edit({
                graph: checked
            })
    }
}
