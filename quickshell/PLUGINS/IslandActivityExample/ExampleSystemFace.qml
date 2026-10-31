import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

IslandSystemFaceComponent {
    id: root

    compactLength: 220

    compactContent: Item {
        Row {
            anchors.centerIn: parent
            spacing: Theme.spacingS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.model?.iconName ?? ""
                size: Theme.iconSizeSmall
                color: Theme.primary
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.model?.levelActivity ?? false
                width: 96
                height: Theme.spacingXS
                radius: height / 2
                color: Theme.surfaceVariant

                Rectangle {
                    width: parent.width * (root.model?.ratio ?? 0)
                    height: parent.height
                    radius: parent.radius
                    color: Theme.primary
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.model?.displayValue ?? ""
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }
}
