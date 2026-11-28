pragma ComponentBehavior: Bound

import QtQuick
import qs.Services
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.ControlCenter.Widgets
import qs.Modules.ControlCenter
import qs.Modules.DDash
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation

Column {
    id: root

    property string entryId: ""
    property string instanceId: ""
    property bool tabScope: false
    property var specs: DashRegistry.sheetOptionSpecs(entryId, tabScope)
    property var valueFor: key => DashRegistry.option(entryId, key, instanceId)
    property var commit: (key, value) => DashRegistry.setOption(entryId, key, value, instanceId)
    property bool resettable: true
    property bool settingsLink: true
    property color slotColor: Theme.chipSurface

    readonly property var entry: DashRegistry.entry(entryId)
    readonly property var settingsPages: ({
            "weather": "weather",
            "media": "media_player",
            "wellbeing": "wellbeing"
        })
    readonly property bool cardEditor: !!entry?.card?.settingsPage
    readonly property bool hasSpecs: (specs?.length ?? 0) > 0
    readonly property var focusTargets: {
        const targets = cardEditorRepeater.count > 0 ? FocusNavigation.tabStops(cardEditorRepeater.itemAt(0)) : [];
        for (let i = 0; i < optionRows.count; i++)
            targets.push(optionRows.itemAt(i));
        targets.push(navRow, resetButton);
        return targets.filter(t => t && t.visible && t.enabled);
    }

    signal settingsOpened

    width: parent?.width ?? 0
    spacing: CcMetrics.detailContentGap

    Repeater {
        id: cardEditorRepeater

        model: root.cardEditor && root.visible ? [root.instanceId] : []

        DashSysmonOptions {
            required property string modelData

            instanceId: modelData
            slotColor: root.slotColor
            dense: true
        }
    }

    SettingsGroup {
        visible: !root.cardEditor && root.hasSpecs
        width: parent.width
        slotColor: root.slotColor

        Repeater {
            id: optionRows

            model: root.specs

            DashOptionRow {
                required property var modelData

                spec: modelData
                value: root.valueFor(modelData.key)
                onCommitted: next => root.commit(modelData.key, next)
            }
        }
    }

    CcEmptyState {
        visible: !root.cardEditor && !root.hasSpecs
        iconName: "tune"
        title: I18n.tr("No configurable settings")
    }

    SettingsNavRow {
        id: navRow

        visible: root.settingsLink && root.entryId in root.settingsPages
        width: parent.width
        title: root.entryId === "media" ? I18n.tr("Media player") : root.entry?.text ?? ""
        iconName: "settings"
        onClicked: {
            root.settingsOpened();
            PopoutService.closeDankDash();
            PopoutService.openSettingsWithTab(root.settingsPages[root.entryId]);
        }
    }

    DButton {
        id: resetButton

        visible: root.resettable
        anchors.right: parent.right
        text: I18n.tr("Reset to default")
        iconName: "restart_alt"
        buttonHeight: Theme.buttonHeightXS
        variant: "text"
        enabled: root.cardEditor ? DashRegistry.hasCardConfig(root.entryId, root.instanceId) : DashRegistry.hasStoredOptions(root.entryId, root.instanceId)
        onClicked: root.cardEditor ? DashRegistry.resetCardConfig(root.entryId, root.instanceId) : DashRegistry.resetOptions(root.entryId, root.instanceId)
    }
}
