pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.DesktopWidgetSettings as DWS

Item {
    id: root

    property var parentModal: null

    readonly property string instanceId: SettingsUiState.selectedDesktopWidgetId
    readonly property string listKey: SettingsData.widgetInstanceListKey(instanceId)
    readonly property bool lockScreenInstance: listKey !== "desktopWidgetInstances"
    readonly property bool greeterInstance: listKey === "greeterWidgetInstances"
    readonly property var instanceData: SettingsData.getDesktopWidgetInstance(instanceId)
    readonly property string widgetType: instanceData?.widgetType ?? ""
    readonly property var widgetDef: DesktopWidgetRegistry.getWidget(widgetType)
    readonly property string widgetName: instanceData?.name || widgetDef?.name || widgetType
    readonly property bool fixed: widgetType === "lockAuth"
    readonly property var cfg: instanceData?.config ?? {}
    readonly property string overlayCommand: "dms ipc call desktopWidget toggleOverlay " + instanceId
    readonly property var groupOptions: [
        {
            "value": "",
            "label": I18n.tr("None")
        }
    ].concat((SettingsData.desktopWidgetGroups || []).map(group => ({
                "value": group.id,
                "label": group.name
            })))

    function updateConfig(key, value) {
        const updates = {};
        updates[key] = value;
        SettingsData.updateDesktopWidgetInstanceConfig(instanceId, updates);
    }

    onWidgetNameChanged: SettingsUiState.selectedWidgetTitle = widgetName

    SettingsPage {
        visible: root.instanceData !== null

        SettingsCard {
            SettingsRow {
                visible: root.fixed
                iconName: root.widgetDef?.icon ?? "widgets"
                title: root.widgetDef?.name ?? root.widgetType
            }

            SettingsToggleRow {
                visible: !root.fixed
                iconName: root.widgetDef?.icon ?? "widgets"
                text: root.widgetDef?.name ?? root.widgetType
                description: root.widgetDef?.description ?? ""
                checked: root.instanceData?.enabled ?? true
                onToggled: checked => SettingsData.updateDesktopWidgetInstance(root.instanceId, {
                        "enabled": checked
                    })
            }

            SettingsTextFieldRow {
                leftIconName: "badge"
                text: I18n.tr("Name")
                value: root.widgetName
                onEditingFinished: value => SettingsData.updateDesktopWidgetInstance(root.instanceId, {
                        "name": value
                    })
            }

            SettingsDropdownRow {
                visible: root.groupOptions.length > 1
                text: I18n.tr("Group", "noun, dropdown label for a desktop widget group")
                options: root.groupOptions.map(group => group.label)
                currentValue: root.groupOptions.find(group => group.value === (root.instanceData?.group ?? ""))?.label ?? I18n.tr("None")
                onValueChanged: value => SettingsData.updateDesktopWidgetInstance(root.instanceId, {
                        "group": root.groupOptions.find(group => group.label === value)?.value || null
                    })
            }
        }

        DWS.DesktopWidgetTypeSettings {
            width: parent.width
            instanceId: root.instanceId
            instanceData: root.instanceData
            widgetDef: root.widgetDef
            parentModal: root.parentModal
        }

        SettingsCard {
            title: I18n.tr("Behavior")

            SettingsToggleRow {
                visible: !root.lockScreenInstance
                text: I18n.tr("Show on overlay")
                description: I18n.tr("Keeps the widget above windows instead of below them", "desktop widget show on overlay toggle description")
                checked: root.cfg.showOnOverlay ?? false
                onToggled: checked => root.updateConfig("showOnOverlay", checked)
            }

            SettingsToggleRow {
                visible: CompositorService.isNiri && !root.lockScreenInstance
                text: I18n.tr("Show on overview")
                checked: root.cfg.showOnOverview ?? false
                onToggled: checked => root.updateConfig("showOnOverview", checked)
            }

            SettingsToggleRow {
                visible: CompositorService.isNiri && !root.lockScreenInstance
                text: I18n.tr("Show on overview only")
                checked: root.cfg.showOnOverviewOnly ?? false
                onToggled: checked => root.updateConfig("showOnOverviewOnly", checked)
            }

            SettingsToggleRow {
                visible: !root.lockScreenInstance
                text: I18n.tr("Click through")
                checked: root.cfg.clickThrough ?? false
                onToggled: checked => root.updateConfig("clickThrough", checked)
            }

            SettingsToggleRow {
                text: I18n.tr("Sync position across displays")
                checked: root.cfg.syncPositionAcrossScreens ?? false
                onToggled: checked => {
                    if (checked)
                        SessionData.syncDesktopWidgetPositionToAllScreens(root.instanceId);
                    root.updateConfig("syncPositionAcrossScreens", checked);
                }
            }
        }

        SettingsCard {
            visible: !root.lockScreenInstance
            title: I18n.tr("Command")

            SettingsRow {
                body: Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - copyButton.width - parent.spacing
                        text: root.overlayCommand
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.monoFontFamily
                        color: Theme.surfaceVariantText
                        elide: Text.ElideMiddle
                    }

                    DActionButton {
                        id: copyButton
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "content_copy"
                        Accessible.name: I18n.tr("Copy")
                        onClicked: {
                            Quickshell.execDetached(["dms", "cl", "copy", root.overlayCommand]);
                            ToastService.showInfo(I18n.tr("Copied to clipboard"));
                        }
                    }
                }
            }
        }
    }
}
