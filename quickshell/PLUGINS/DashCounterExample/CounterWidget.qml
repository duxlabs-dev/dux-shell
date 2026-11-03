import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null
    readonly property int count: pluginData.count ?? 0

    pillClickAction: (x, y, width, section, screen) => popoutService?.toggleDankDash("plugin_" + pluginId, x, y, width, section, screen)
    pillRightClickAction: () => pluginService?.savePluginData(pluginId, "count", count + 1)

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "counter_1"
                size: root.iconSize
                color: Theme.widgetIconColor
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.count
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS

            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "counter_1"
                size: root.iconSize
                color: Theme.widgetIconColor
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.count
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
            }
        }
    }
}
