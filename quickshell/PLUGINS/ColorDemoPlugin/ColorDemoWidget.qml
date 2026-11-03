import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property color customColor: pluginData.customColor || Theme.primary

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            Rectangle {
                width: 20
                height: 20
                radius: 4
                color: root.customColor
                border.color: Theme.outlineStrong
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.customColor.toString()
                font.pixelSize: root.textSize
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            Rectangle {
                width: 20
                height: 20
                radius: 4
                color: root.customColor
                border.color: Theme.outlineStrong
                border.width: 1
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.customColor.toString()
                font.pixelSize: root.textSize
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
