import QtQuick
import qs.Services
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.ControlCenter.Widgets
import qs.Modules.DDash

CcSheetDialog {
    id: root

    property string entryId: ""
    property string instanceId: ""
    property bool tabScope: false

    readonly property var entry: DashRegistry.entry(entryId)

    function presentFor(id, instance = "") {
        entryId = id;
        instanceId = instance;
        present();
    }

    panelWidth: DashMetrics.optionSheetWidth
    iconName: entry?.icon ?? "tune"
    title: entry?.text ?? ""
    subtitle: I18n.tr("Options")
    showScrollBar: false

    DashOptionsForm {
        entryId: root.entryId
        instanceId: root.instanceId
        tabScope: root.tabScope
        onSettingsOpened: root.dismiss()
    }
}
