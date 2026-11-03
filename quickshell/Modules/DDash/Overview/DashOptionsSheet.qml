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
    property bool tabScope: false

    readonly property var entry: DashRegistry.entry(entryId)
    readonly property var settingsPages: ({
            "weather": "weather",
            "media": "media_player",
            "wellbeing": "wellbeing"
        })
    readonly property var specs: DashRegistry.sheetOptionSpecs(entryId, tabScope)

    function presentFor(id) {
        entryId = id;
        present();
    }

    panelWidth: DashMetrics.optionSheetWidth
    iconName: entry?.icon ?? "tune"
    title: entry?.text ?? ""
    subtitle: I18n.tr("Options")
    showScrollBar: false

    SettingsGroup {
        width: parent.width
        slotColor: Theme.chipSurface

        Repeater {
            model: root.specs

            DashOptionRow {
                required property var modelData

                spec: modelData
                value: DashRegistry.option(root.entryId, modelData.key)
                onCommitted: next => DashRegistry.setOption(root.entryId, modelData.key, next)
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
        backgroundColor: "transparent"
        textColor: Theme.primary
        enabled: DashRegistry.hasStoredOptions(root.entryId)
        onClicked: DashRegistry.resetOptions(root.entryId)
    }
}
