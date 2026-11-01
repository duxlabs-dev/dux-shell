import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Rectangle {
    id: root

    property string title: ""
    property string icon: ""
    property string aside: ""
    default property alias content: column.data

    width: parent?.width ?? 0
    implicitHeight: column.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadiusL
    color: SettingsMetrics.rowColor

    Column {
        id: column

        x: Theme.spacingL
        y: Theme.spacingL
        width: parent.width - Theme.spacingL * 2
        spacing: Theme.spacingXXS

        Item {
            width: parent.width
            height: header.height + Theme.spacingS
            visible: root.title !== ""

            Row {
                id: header
                spacing: Theme.spacingS

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.icon !== ""
                    name: root.icon
                    size: Theme.iconSizeMedium
                    color: Theme.surfaceText
                }

                StyledText {
                    id: titleText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightBold
                    color: Theme.surfaceText
                }

                StyledText {
                    visible: root.aside !== ""
                    text: root.aside
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.baseline: titleText.baseline
                }
            }
        }
    }
}
