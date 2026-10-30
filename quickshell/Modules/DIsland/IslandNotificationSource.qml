pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Notifications
import qs.Common
import qs.Services
import "../../Common/htmlElide.js" as HtmlElide
import "../../Common/IslandArrival.js" as Arrival

QtObject {
    id: root

    required property IslandController controller
    required property var targetScreen
    property bool enabled: true

    property var currentWrapper: null
    property string appName: ""
    property string summary: ""
    property string body: ""
    property string timeText: ""
    property string imageSource: ""
    property string fallbackIcon: "material:notifications"
    property string fallbackText: ""
    property string actionLabel: ""
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
        critical = false;
        important = false;
    }

    function wrapperTimeout(wrapper) {
        const interval = wrapper?.timer?.interval ?? -1;
        return interval >= 0 ? interval : 5000;
    }

    // Every info of a burst keeps its popup until the burst is over (arrival.released): its own popup time is held while it
    // is in the burst (the service starts it once the popup shows), so leaving the popups is always a withdrawal.
    property var heldInBurst: []

    // The hooks put on popup timers ([wrapper, hook]), taken off when the source lets go (turned off, destroyed): the
    // popups it still holds then time out as DMS's own do.
    property var timerHooks: []

    function hookTimer(wrapper, hook) {
        wrapper.timer.runningChanged.connect(hook);
        timerHooks = timerHooks.concat([[wrapper, hook]]);
    }

    function unhookTimers() {
        const alive = NotificationService.allWrappers;
        for (const [wrapper, hook] of timerHooks) {
            if (alive.indexOf(wrapper) === -1)
                continue;
            wrapper.timer.runningChanged.disconnect(hook);
            if (!wrapper.timer.running && wrapper.timer.interval > 0)
                wrapper.timer.restart();
        }
        timerHooks = [];
        heldInBurst = [];
    }

    Component.onDestruction: unhookTimers()

    function holdInBurst(wrapper) {
        const timer = wrapper?.timer;
        if (!timer)
            return;
        if (heldInBurst.indexOf(wrapper) === -1) {
            heldInBurst = heldInBurst.concat([wrapper]);
            hookTimer(wrapper, () => {
                if (timer.running && root.inBurst(wrapper))
                    timer.stop();
            });
        }
        timer.stop();
    }

    // Infos of the burst that left the popups go, current or not: closed by their sender, dismissed, or withdrawn (Do not
    // disturb, all popups dismissed, the notification center opened). One pushed out by the popup limit stays.
    property bool releasing: false

    function dropWithdrawn() {
        const visible = NotificationService.visibleNotifications || [];
        const all = NotificationService.allWrappers;
        const gone = i => !i.wrapper || all.indexOf(i.wrapper) === -1 || (visible.indexOf(i.wrapper) === -1 && !i.wrapper.removedByLimit);
        const items = controller.arrival.burst.items;
        if (!items.some(gone))
            return;
        const current = controller.arrival.current;
        const kept = items.filter(i => i === current || !gone(i));
        if (kept.length < items.length)
            controller.arrival.setBurst({
                "items": kept,
                "index": Math.max(0, kept.indexOf(current)),
                "dir": 0,
                "axis": controller.arrival.burst.axis
            });
        if (!current || !gone(current))
            return;
        if (kept.length > 1) {
            controller.arrival.drop();
            return;
        }
        currentWrapper = null;
        controller.completeNotification();
        scheduleDisplayFieldClear();
    }

    function adopt(wrapper) {
        // The released burst is emptied right after: what joined it then would show nowhere (taken in once it is empty).
        if (releasing || !enabled || !wrapper || !NotificationService.isFocusedScreen(root.targetScreen))
            return false;

        const isCritical = wrapper.urgency === NotificationUrgency.Critical;
        if (!controller.canRequestNotification(isCritical))
            return false;

        const app = wrapper.appName || I18n.tr("Notification", "island notification face: fallback app name");
        const icon = wrapper.fallbackIconName || "material:notifications";
        const actions = wrapper.actions || [];
        const item = {
            "wrapper": wrapper,
            "tier": Arrival.tierOf({
                "critical": isCritical
            }),
            "app": app,
            "title": HtmlElide.plainText(wrapper.summary) || app,
            "detail": HtmlElide.plainText(wrapper.body),
            "time": wrapper.timeStr || "",
            "image": wrapper.displayImage,
            "icon": icon,
            "fallbackText": app.charAt(0).toUpperCase(),
            "critical": isCritical,
            "important": !isCritical && wrapper.urgency === NotificationUrgency.Normal && icon.startsWith("material:battery"),
            "action": actions.length > 0 ? (actions[0].text || I18n.tr("Open", "island notification face: default action button")) : "",
            "timeout": wrapperTimeout(wrapper)
        };
        if (!controller.requestNotification(isCritical))
            return false;
        controller.arrival.arrive(item);
        holdInBurst(wrapper);
        return true;
    }

    // An info of the burst becomes the face's fields.
    function show(item) {
        if (!item)
            return;
        displayFieldClearTimer.stop();
        currentWrapper = item.wrapper ?? null;
        appName = item.app;
        summary = item.title;
        body = item.detail;
        timeText = item.time ?? "";
        imageSource = item.image ?? "";
        fallbackIcon = item.icon;
        fallbackText = item.fallbackText ?? item.app.charAt(0).toUpperCase();
        critical = item.critical === true;
        important = item.important === true;
        actionLabel = item.action ?? "";
        if (item.timeout !== undefined)
            controller.notificationTimeout = item.timeout;
    }

    function inBurst(wrapper) {
        return controller.arrival.burst.items.some(i => i.wrapper === wrapper);
    }

    readonly property int shownInfo: controller.arrival.shown
    onShownInfoChanged: show(controller.arrival.current)

    function refreshDeduplicated(wrapper) {
        if (!wrapper || wrapper !== currentWrapper)
            return;
        controller.refreshNotification();
        holdInBurst(wrapper);
    }

    function syncVisibleNotifications() {
        // A release clears popups from inside completeNotification(): syncing then would complete it again, re-entrant.
        // The release syncs once it is done.
        if (releasing)
            return;
        if (heldInBurst.some(w => NotificationService.allWrappers.indexOf(w) === -1))
            heldInBurst = heldInBurst.filter(w => NotificationService.allWrappers.indexOf(w) !== -1);
        // A gone wrapper's hook went with its timer: only its entry is left.
        if (timerHooks.some(h => NotificationService.allWrappers.indexOf(h[0]) === -1))
            timerHooks = timerHooks.filter(h => NotificationService.allWrappers.indexOf(h[0]) !== -1);
        dropWithdrawn();
        const visible = NotificationService.visibleNotifications || [];
        const latest = visible.length > 0 ? visible[visible.length - 1] : null;
        if (latest && (latest === currentWrapper || inBurst(latest) || adopt(latest)))
            return;
        // An info of the burst out of the popups is still there only once the popup limit pushed it out.
        if (!currentWrapper || visible.indexOf(currentWrapper) !== -1 || inBurst(currentWrapper))
            return;
        currentWrapper = null;
        controller.completeNotification();
        scheduleDisplayFieldClear();
    }

    onEnabledChanged: {
        if (enabled) {
            syncVisibleNotifications();
            return;
        }
        unhookTimers();
        if (!currentWrapper)
            return;
        currentWrapper = null;
        controller.completeNotification();
        scheduleDisplayFieldClear();
    }

    function activate() {
        const wrapper = currentWrapper;
        const actions = wrapper?.actions || [];
        if (actions.length > 0)
            actions[0].invoke();
        // Invoking a non resident one closes it, and the next info of the burst may already show.
        if (currentWrapper === wrapper)
            dismiss();
    }

    function dismiss() {
        const wrapper = currentWrapper;
        // The next info of the burst shows; the last one takes the island back to the clock.
        if (controller.arrival.count > 1) {
            controller.arrival.drop();
        } else {
            currentWrapper = null;
            controller.completeNotification();
            scheduleDisplayFieldClear();
        }
        if (wrapper)
            NotificationService.dismissNotification(wrapper);
    }

    property Connections arrivalConnections: Connections {
        target: root.controller.arrival

        // Seen in the burst: off the screen and into the notification list.
        function onReleased(items) {
            root.releasing = true;
            items.forEach(item => {
                if (item.wrapper && item.wrapper.popup)
                    item.wrapper.popup = false;
            });
            root.releasing = false;
            // The island leaves the face right after; then nothing it showed is current any more.
            Qt.callLater(() => {
                root.syncVisibleNotifications();
                if (root.controller.notificationActive || root.controller.notificationHeldForSystem || root.controller.arrival.count > 0)
                    return;
                root.currentWrapper = null;
                root.scheduleDisplayFieldClear();
            });
        }
    }

    property Connections notificationConnections: Connections {
        target: NotificationService
        enabled: root.enabled

        function onVisibleNotificationsChanged() {
            root.syncVisibleNotifications();
        }

        function onAllWrappersChanged() {
            root.syncVisibleNotifications();
        }

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
