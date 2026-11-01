import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    property string iconName: ""
    property string title: ""

    spacing: Theme.spacingM

    Row {
        spacing: Theme.spacingS

        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: Theme.iconSizeMedium
            color: Theme.primary
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeightBold
            color: Theme.surfaceText
        }
    }

    Rectangle {
        width: parent.width
        height: comingText.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadiusL
        color: SettingsMetrics.rowColor

        StyledText {
            id: comingText
            x: Theme.spacingL
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x * 2
            text: I18n.tr("Coming soon", "niri page placeholder for a section not built yet")
            wrapMode: Text.WordWrap
            color: Theme.surfaceVariantText
        }
    }
}
