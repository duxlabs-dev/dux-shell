import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import qs.Modules.DDash
import qs.Modules.DDash.Overview
import "../../Services/SysmonCatalog.js" as SysmonCatalog

Item {
    id: root

    property var parentModal: null

    readonly property string instanceId: SettingsUiState.selectedDashCardId
    readonly property bool placed: DashRegistry.instanceIndex("sysmon", instanceId) >= 0
    readonly property string cardTitle: SysmonService.configTitle(SysmonCatalog.normalizeConfig(DashRegistry.cardConfig("sysmon", instanceId), SysmonCatalog.defaultDashConfig())) || DashRegistry.entry("sysmon")?.text || ""

    onCardTitleChanged: {
        if (placed)
            SettingsUiState.selectedWidgetTitle = cardTitle;
    }

    SettingsPage {
        visible: root.placed

        DashSysmonOptions {
            instanceId: root.instanceId
        }
    }
}
