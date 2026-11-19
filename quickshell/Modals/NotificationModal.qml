import QtQuick
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Modules.Notifications
import qs.Services

DModal {
    id: notificationModal

    layerNamespace: "dms:notification-center-modal"

    modalWidth: Math.min(NotificationMetrics.modalWidth, screenWidth - Theme.spacingL * 2)
    modalHeight: Math.min(NotificationMetrics.modalHeight, screenHeight * NotificationMetrics.modalScreenRatio)
    backgroundColor: Theme.floatingWindowSurface
    visible: false
    onBackgroundClicked: close()
    onOpened: Qt.callLater(() => contentLoader.item?.tab.forceActiveFocus())
    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            NotificationService.onOverlayOpen();
            return;
        }
        NotificationService.onOverlayClose();
    }

    IpcHandler {
        // DIsland owns this trigger whenever it is the sole bar for the screen.
        function open(): string {
            if (PopoutService.routeToIsland("notificationcenter", null, false))
                return "NOTIFICATION_ISLAND_OPEN_SUCCESS";
            notificationModal.open();
            return "NOTIFICATION_MODAL_OPEN_SUCCESS";
        }

        function close(): string {
            const islandClosed = PopoutService.closeIslandActivity("notificationcenter");
            notificationModal.close();
            return islandClosed ? "NOTIFICATION_ISLAND_CLOSE_SUCCESS" : "NOTIFICATION_MODAL_CLOSE_SUCCESS";
        }

        function toggle(): string {
            if (PopoutService.routeToIsland("notificationcenter", null, true))
                return "NOTIFICATION_ISLAND_TOGGLE_SUCCESS";
            notificationModal.toggle();
            return "NOTIFICATION_MODAL_TOGGLE_SUCCESS";
        }

        function toggleDoNotDisturb(): string {
            SessionData.setDoNotDisturb(!SessionData.doNotDisturb);

            return "NOTIFICATION_MODAL_TOGGLE_DND_SUCCESS";
        }

        function enableDoNotDisturbFor(minutes: int): string {
            if (minutes <= 0) {
                return "ERROR: minutes must be > 0";
            }
            SessionData.setDoNotDisturb(true, minutes);
            return "NOTIFICATION_MODAL_DND_SET_FOR_" + minutes + "_SUCCESS";
        }

        function enableDoNotDisturbUntil(timestampMs: string): string {
            const ts = Number(timestampMs);
            if (!ts || ts <= Date.now()) {
                return "ERROR: timestamp must be a future epoch ms";
            }
            SessionData.setDoNotDisturbUntilTimestamp(ts);
            return "NOTIFICATION_MODAL_DND_SET_UNTIL_SUCCESS";
        }

        function enableDoNotDisturbIndefinitely(): string {
            SessionData.setDoNotDisturb(true, 0);
            return "NOTIFICATION_MODAL_DND_INDEFINITE_SUCCESS";
        }

        function enableDoNotDisturbUntilTomorrowMorning(): string {
            const now = new Date();
            const target = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 8, 0, 0, 0);
            SessionData.setDoNotDisturbUntilTimestamp(target.getTime());
            return "NOTIFICATION_MODAL_DND_UNTIL_TOMORROW_SUCCESS";
        }

        function disableDoNotDisturb(): string {
            SessionData.setDoNotDisturb(false);
            return "NOTIFICATION_MODAL_DND_DISABLE_SUCCESS";
        }

        function getDoNotDisturb(): bool {
            return SessionData.doNotDisturb;
        }

        function getDoNotDisturbUntil(): string {
            return String(SessionData.doNotDisturbUntil);
        }

        function clearAll(): string {
            NotificationService.clearAllNotifications();
            return "NOTIFICATION_MODAL_CLEAR_ALL_SUCCESS";
        }

        function dismissAllPopups(): string {
            NotificationService.dismissAllPopups();
            return "NOTIFICATION_MODAL_DISMISS_ALL_POPUPS_SUCCESS";
        }

        function dismiss(): string {
            NotificationService.dismissLastNotification();
            return "NOTIFICATION_DISMISS_SUCCESS";
        }

        function invokeLast(): string {
            if (!NotificationService.invokeLastNotification())
                return "NOTIFICATION_INVOKE_NO_ACTION";
            return "NOTIFICATION_INVOKE_SUCCESS";
        }

        target: "notifications"
    }

    contentSource: Qt.resolvedUrl("NotificationModalContent.qml")
}
