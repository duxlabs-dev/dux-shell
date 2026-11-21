import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Modules.DDash
import "../../../Services/SysmonCatalog.js" as SysmonCatalog

Column {
    id: root

    property string instanceId: ""
    property color slotColor: SettingsMetrics.rowColor
    property bool dense: false
    readonly property var config: SysmonCatalog.normalizeConfig(DashRegistry.cardConfig("sysmon", instanceId), SysmonCatalog.defaultDashConfig())

    function edit(key, value) {
        DashRegistry.setCardConfig("sysmon", instanceId, {
            [key]: value
        });
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsMonitorConfig {
        config: root.config
        slotColor: root.slotColor
        dense: root.dense
        onConfigEdited: (key, value) => root.edit(key, value)
    }

    SettingsCard {
        title: I18n.tr("Appearance", "settings section title for visual options")
        slotColor: root.slotColor

        DashOptionRow {
            spec: DashRegistry.toneOption()
            value: root.config.tone ?? ""
            onCommitted: next => root.edit("tone", next)
        }
    }
}
