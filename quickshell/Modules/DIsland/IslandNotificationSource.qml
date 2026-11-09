pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import "../../Common/htmlElide.js" as HtmlElide
import "../../Common/IslandActivities.js" as Activities

QtObject {
    id: root

    required property IslandController controller
    required property var targetScreen
    property bool enabled: true
    required property IslandActivitySession activitySession
    readonly property string visibleVersion: NotificationService.visibleNotifications.map(wrapper => wrapper.seq).join(",")
    readonly property string presentationVersion: activitySession?.current?.kind === "notification" ? activitySession.current.id : ""
    readonly property bool notificationPresented: controller.notificationActive
    onVisibleVersionChanged: syncVisibleNotifications()
    onPresentationVersionChanged: Qt.callLater(syncPresentation)
    onNotificationPresentedChanged: Qt.callLater(completeHiddenNotification)

    property var currentWrapper: null
    property string appName: ""
    property string summary: ""
    property string body: ""
    property string timeText: ""
    property string imageSource: ""
    property string fallbackIcon: "material:notifications"
    property string fallbackText: ""
    property string actionLabel: ""
    property bool summarized: false
    property bool critical: false
    property bool important: false

    readonly property bool hasAction: actionLabel.length > 0

    function scheduleDisplayFieldClear() {
        displayFieldClearTimer.restart();
    }

    function clearDisplayFields() {
        if (currentWrapper)
            return;
        appName = "";
        summary = "";
        body = "";
        timeText = "";
        imageSource = "";
        fallbackIcon = "material:notifications";
        fallbackText = "";
        actionLabel = "";
        summarized = false;
        critical = false;
        important = false;
    }

    function adopt(wrapper) {
        if (!enabled || !wrapper || !NotificationService.isFocusedScreen(root.targetScreen))
            return false;

        const isCritical = wrapper.urgency === NotificationUrgency.Critical;
        if (!controller.canRequestNotification(isCritical))
            return false;

        displayFieldClearTimer.stop();
        currentWrapper = wrapper;
        appName = wrapper.appName || I18n.tr("Notification", "island notification face: fallback app name");
        summary = HtmlElide.plainText(wrapper.summary) || appName;
        body = HtmlElide.plainText(wrapper.body);
        timeText = wrapper.timeStr || "";
        imageSource = wrapper.displayImage;
        fallbackIcon = wrapper.fallbackIconName || "material:notifications";
        fallbackText = appName.charAt(0).toUpperCase();
        summarized = !!wrapper.islandPresentation;
        if (summarized) {
            summary = Activities.notificationTitle(wrapper.islandPresentation.title || "{summary}", {summary: summary, body: body, appName: appName}) || summary;
            fallbackIcon = "material:" + (wrapper.islandPresentation.icon || "event");
            imageSource = "";
        }
        critical = isCritical;
        important = !isCritical && wrapper.urgency === NotificationUrgency.Normal && fallbackIcon.startsWith("material:battery");
        const actions = wrapper.actions || [];
        actionLabel = actions.length > 0 ? (actions[0].text || I18n.tr("Open", "island notification face: default action button")) : "";
        return controller.requestNotification(isCritical);
    }

    function refreshDeduplicated(wrapper) {
        activitySession.refreshNotification(wrapper);
        if (wrapper === currentWrapper)
            adopt(wrapper);
    }

    function syncVisibleNotifications() {
        const visible = NotificationService.visibleNotifications || [];
        activitySession.cancelMissingNotifications(visible);
        if (!enabled || !NotificationService.isFocusedScreen(root.targetScreen))
            return;
        for (const wrapper of visible)
            activitySession.enqueueNotification(wrapper);
    }

    function syncPresentation() {
        const wrapper = activitySession?.current?.kind === "notification" ? activitySession.current.wrapper : null;
        if (wrapper) {
            if (wrapper !== currentWrapper)
                adopt(wrapper);
            return;
        }
        if (!currentWrapper)
            return;
        currentWrapper = null;
        controller.completeNotification();
        scheduleDisplayFieldClear();
    }

    function completeHiddenNotification() {
        if (!controller.notificationActive && !controller.notificationHeldForSystem && activitySession?.current?.kind === "notification" && currentWrapper)
            activitySession.finishCurrent(activitySession.current);
    }

    onEnabledChanged: {
        if (enabled) {
            syncVisibleNotifications();
            return;
        }
        if (!currentWrapper)
            return;
        currentWrapper = null;
        controller.completeNotification();
        scheduleDisplayFieldClear();
    }

    function activate() {
        const actions = currentWrapper?.actions || [];
        if (actions.length > 0)
            actions[0].invoke();
        dismiss();
    }

    function dismiss() {
        const wrapper = currentWrapper;
        currentWrapper = null;
        if (activitySession?.current?.kind === "notification")
            activitySession.finishCurrent(activitySession.current);
        controller.completeNotification();
        scheduleDisplayFieldClear();
        if (wrapper)
            NotificationService.dismissNotification(wrapper);
    }

    property Connections notificationConnections: Connections {
        target: NotificationService
        enabled: root.enabled

        function onNotificationDeduplicated(wrapper) {
            root.refreshDeduplicated(wrapper);
        }
    }

    property Timer displayFieldClearTimer: Timer {
        interval: 400
        onTriggered: root.clearDisplayFields()
    }

    Component.onCompleted: syncVisibleNotifications()
}
