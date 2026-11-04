import QtQuick
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modals.Common
import qs.Modules.DDash
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

    content: Component {
        FocusScope {
            readonly property alias tab: tab

            anchors.fill: parent
            LayoutMirroring.enabled: I18n.isRtl
            LayoutMirroring.childrenInherit: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Left && tab.currentTab > 0) {
                    tab.currentTab = 0;
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Right && tab.currentTab === 0 && SettingsData.notificationHistoryEnabled) {
                    tab.currentTab = 1;
                    event.accepted = true;
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: PopoutMetrics.contentPadding
                spacing: PopoutMetrics.contentGap

                DWindowHeader {
                    id: header
                    width: parent.width
                    controls: null
                    horizontalPadding: 0
                    verticalPadding: 0
                    title: I18n.tr("Notifications")
                    onCloseRequested: notificationModal.close()
                }

                NotificationsTab {
                    id: tab
                    width: parent.width
                    height: parent.height - header.height - parent.spacing
                    live: notificationModal.shouldBeVisible
                    settingsAction: true
                    swipeBleed: PopoutMetrics.contentPadding
                    transientSurfaceTracker: notificationModal.transientSurfaceTracker
                    onSettingsRequested: {
                        notificationModal.close();
                        PopoutService.openSettingsWithTab("notifications", notificationModal, () => notificationModal.open());
                    }
                }
            }
        }
    }
}
