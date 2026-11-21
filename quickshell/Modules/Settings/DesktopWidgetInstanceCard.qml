pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

SettingsReorderRow {
    id: root

    required property var instanceData

    readonly property string instanceId: instanceData?.id ?? ""
    readonly property string widgetType: instanceData?.widgetType ?? ""
    readonly property var widgetDef: DesktopWidgetRegistry.getWidget(widgetType)
    readonly property string widgetName: instanceData?.name || widgetDef?.name || widgetType
    property bool fixed: false

    signal configureRequested
    signal deleteRequested
    signal duplicateRequested

    iconName: widgetDef?.icon ?? "widgets"
    title: widgetName
    subtitle: actions.confirming ? I18n.tr("Confirm Delete", "delete button confirmation text") : ""
    subtitleColor: Theme.error
    clickable: true
    onClicked: configureRequested()

    trailing: SettingsInstanceActions {
        id: actions
        anchors.verticalCenter: parent.verticalCenter
        fixed: root.fixed
        onDuplicateRequested: root.duplicateRequested()
        onDeleteRequested: root.deleteRequested()

        DToggle {
            anchors.verticalCenter: parent.verticalCenter
            hideText: true
            text: root.title
            checked: root.instanceData?.enabled ?? true
            onToggled: isChecked => {
                SettingsData.updateDesktopWidgetInstance(root.instanceId, {
                    enabled: isChecked
                });
            }
        }
    }
}
