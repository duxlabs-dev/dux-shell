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
    subtitle: deleteButton.confirming ? I18n.tr("Confirm Delete") : ""
    subtitleColor: Theme.error
    clickable: true
    onClicked: configureRequested()

    trailing: [
        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron_right"
            size: Theme.iconSize
            color: Theme.onSurfaceVariant
            rotation: I18n.isRtl ? 180 : 0
        },
        SettingsDivider {
            vertical: true
        },
        DToggle {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.fixed
            hideText: true
            text: root.title
            checked: root.instanceData?.enabled ?? true
            onToggled: isChecked => {
                SettingsData.updateDesktopWidgetInstance(root.instanceId, {
                    enabled: isChecked
                });
            }
        },
        DActionButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.fixed
            iconName: "content_copy"
            tooltipText: I18n.tr("Duplicate", "verb, desktop widget menu action")
            onClicked: root.duplicateRequested()
        },
        SettingsDeleteButton {
            id: deleteButton
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.fixed
            onDeleteRequested: root.deleteRequested()
        }
    ]
}
