import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool isEnabled: pluginData.isEnabled || false
    property int clickCount: pluginData.clickCount || 0

    ccWidgetIcon: isEnabled ? "toggle_on" : "toggle_off"
    ccWidgetPrimaryText: "Example Toggle"
    ccWidgetSecondaryText: isEnabled ? `Active • ${clickCount} clicks` : "Inactive"
    ccWidgetIsActive: isEnabled

    onCcWidgetToggled: {
        isEnabled = !isEnabled;
        clickCount += 1;
        if (pluginService) {
            pluginService.savePluginData("controlCenterExample", "isEnabled", isEnabled);
            pluginService.savePluginData("controlCenterExample", "clickCount", clickCount);
        }
        ToastService.showInfo("Example Toggle", isEnabled ? "Activated!" : "Deactivated!");
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                name: root.isEnabled ? "toggle_on" : "toggle_off"
                color: root.isEnabled ? Theme.primary : Theme.surfaceVariantText
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: `${root.clickCount}`
                color: root.isEnabled ? Theme.primary : Theme.surfaceVariantText
                font.pixelSize: root.textSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DIcon {
                name: root.isEnabled ? "toggle_on" : "toggle_off"
                color: root.isEnabled ? Theme.primary : Theme.surfaceVariantText
                size: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: `${root.clickCount}`
                color: root.isEnabled ? Theme.primary : Theme.surfaceVariantText
                font.pixelSize: root.textSize
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
