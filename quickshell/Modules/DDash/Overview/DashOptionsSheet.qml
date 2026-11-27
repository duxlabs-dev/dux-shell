import QtQuick
import qs.Services
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.ControlCenter.Widgets
import qs.Modules.DDash

CcSheetDialog {
    id: root

    property string entryId: ""
    property string instanceId: ""
    property bool tabScope: false

    readonly property var entry: DashRegistry.entry(entryId)
    readonly property var settingsPages: ({
            "weather": "weather",
            "media": "media_player",
            "wellbeing": "wellbeing"
        })
    readonly property bool cardEditor: !!entry?.card?.settingsPage
    readonly property var specs: DashRegistry.sheetOptionSpecs(entryId, tabScope)

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

    Repeater {
        model: root.cardEditor && root.visible ? [root.instanceId] : []

        DashSysmonOptions {
            required property string modelData

            instanceId: modelData
            slotColor: Theme.chipSurface
            dense: true
        }
    }

    SettingsGroup {
        visible: !root.cardEditor
        width: parent.width
        slotColor: Theme.chipSurface

        Repeater {
            model: root.specs

            DashOptionRow {
                required property var modelData

                spec: modelData
                value: DashRegistry.option(root.entryId, modelData.key, root.instanceId)
                onCommitted: next => DashRegistry.setOption(root.entryId, modelData.key, next, root.instanceId)
            }
        }
    }

    SettingsNavRow {
        visible: root.entryId in root.settingsPages
        width: parent.width
        title: root.entryId === "media" ? I18n.tr("Media player") : root.entry?.text ?? ""
        iconName: "settings"
        onClicked: {
            root.dismiss();
            PopoutService.closeDankDash();
            PopoutService.openSettingsWithTab(root.settingsPages[root.entryId]);
        }
    }

    DButton {
        anchors.right: parent.right
        text: I18n.tr("Reset to default")
        iconName: "restart_alt"
        buttonHeight: Theme.buttonHeightXS
        variant: "text"
        enabled: root.cardEditor ? DashRegistry.hasCardConfig(root.entryId, root.instanceId) : DashRegistry.hasStoredOptions(root.entryId, root.instanceId)
        onClicked: root.cardEditor ? DashRegistry.resetCardConfig(root.entryId, root.instanceId) : DashRegistry.resetOptions(root.entryId, root.instanceId)
    }
}
