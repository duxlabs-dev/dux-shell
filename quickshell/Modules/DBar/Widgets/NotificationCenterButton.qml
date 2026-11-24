import QtQuick
import qs.Common
import qs.Modules.Notifications
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets

BasePill {
    id: root

    property var widgetData: null
    property bool hasUnread: false
    property bool isActive: false

    readonly property bool hideWhenEmpty: SettingsData.widgetOption("notificationButton", widgetData, "hideWhenEmpty")
    readonly property bool shouldHide: hideWhenEmpty && widgetData?.enabled !== false && NotificationService.notifications.length === 0

    width: shouldHide ? 0 : (isVerticalOrientation ? barThickness : visualWidth)
    height: shouldHide ? 0 : (isVerticalOrientation ? visualHeight : barThickness)
    visible: !shouldHide

    content: Component {
        Item {
            implicitWidth: notifIcon.width
            implicitHeight: root.contentThickness

            DIcon {
                id: notifIcon
                anchors.centerIn: parent
                name: SessionData.doNotDisturb ? "notifications_off" : "notifications"
                size: Theme.barIconSize(root.barThickness, -Theme.spacingXS, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: SessionData.doNotDisturb ? Theme.primary : (root.isActive ? Theme.primary : Theme.widgetIconColor)
            }

            Rectangle {
                width: NotificationMetrics.unreadDotSize
                height: width
                radius: width / 2
                color: Theme.error
                anchors.right: notifIcon.right
                anchors.top: notifIcon.top
                visible: root.hasUnread
            }
        }
    }

    MouseArea {
        x: -root.leftMargin
        y: -root.topMargin
        width: root.width + root.leftMargin + root.rightMargin
        height: root.height + root.topMargin + root.bottomMargin
        acceptedButtons: Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            root.triggerRipple(this, mouse.x, mouse.y);
            SessionData.setDoNotDisturb(!SessionData.doNotDisturb);
        }
    }
}
