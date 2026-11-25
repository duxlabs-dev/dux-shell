import QtQuick
import qs.Common
import qs.Modules.Notifications
import qs.Services
import qs.Widgets

DContextMenu {
    id: root

    property alias notification: actions.notification

    layerNamespace: "dms:notification-context-menu"
    minMenuWidth: NotificationMetrics.menuWidth
    menuItems: actions.items.map(item => ({
                type: "item",
                icon: item.icon,
                text: item.label,
                action: () => {
                    actions.trigger(item.action);
                    hide();
                }
            }))

    function showAt(x, y, targetScreen) {
        open(targetScreen ?? root.targetScreen, x, y, false);
    }

    function closeMenu() {
        hide();
    }

    NotificationActions {
        id: actions
    }

    Connections {
        target: PopoutManager

        function onPopoutOpening() {
            root.hide();
        }
    }
}
