import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Modules.ControlCenter.Widgets
import "ProcessColumns.js" as ProcessColumns

CcSheetDialog {
    id: root

    property var columns: ProcessColumns.DEFAULT_COLUMNS

    signal columnsEdited(var columns)

    readonly property var entries: [["cpu"], ["memory"], ["gpu"], ["vram"], ["gpuVideo"], ["diskRead", "diskWrite"], ["connections", "netRx", "netTx"], ["status"], ["threads"], ["nice"], ["cpuTime"], ["pid"], ["user"]]

    function setEntry(ids, on) {
        const next = ProcessColumns.COLUMNS.map(c => c.id).filter(id => ids.includes(id) ? on : columns.includes(id));
        columnsEdited(next);
    }

    iconName: "view_column"
    title: I18n.tr("Columns")
    showScrollBar: false

    SettingsGroup {
        width: parent.width
        slotColor: Theme.chipSurface

        Repeater {
            model: root.entries

            SettingsToggleRow {
                required property var modelData

                text: modelData.length > 1 ? ProcessListMetrics.groupLabel(ProcessColumns.COLUMNS.find(c => c.id === modelData[0]).group) : ProcessListMetrics.columnLabel(modelData[0])
                checked: root.columns.includes(modelData[0])
                onToggled: value => root.setEntry(modelData, value)
            }
        }
    }
}
