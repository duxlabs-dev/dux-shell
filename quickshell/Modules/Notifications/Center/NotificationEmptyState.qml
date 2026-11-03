import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    anchors.fill: parent
    visible: NotificationService.notifications.length === 0

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: Theme.spacingM

        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "emoji_events"
            size: Theme.iconSizeLarge + Theme.spacingL
            color: Theme.onSurfaceVariant
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("You're all caught up", "notification center empty state, no notifications left to read")
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.onSurfaceVariant
            font.weight: Theme.fontWeightMedium
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
