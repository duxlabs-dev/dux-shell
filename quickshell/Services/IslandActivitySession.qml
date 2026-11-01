pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Notifications
import qs.Common
import "../Common/IslandActivities.js" as Activities

QtObject {
    id: root

    required property string screenName
    required property string barId
    property bool enabled: true
    property bool notificationsEnabled: true
    property bool systemsEnabled: true
    property bool blocked: false
    property bool held: false
    property var excludedSources: []
    property var sourceOverrides: ({})
    property int slotLimit: 3
    property int defaultDuration: 5000
    readonly property string hostKey: JSON.stringify([screenName, barId])
    readonly property var stableEntries: enabled ? Activities.stableEntries(IslandActivityService.entries, screenName, barId, excludedSources, sourceOverrides, slotLimit) : []
    property var queue: []
    property var current: null
    property int remaining: 0
    property double deadline: 0
    property bool registered: false
    signal openRequested(var entry)

    function accepts(entry) {
        if (entry.kind === "system")
            return systemsEnabled;
        if (entry.kind === "notification")
            return notificationsEnabled;
        return enabled && Activities.matches(entry, screenName, barId, excludedSources);
    }

    function contains(entry) {
        const key = Activities.identity(entry);
        return Activities.identity(current) === key || queue.some(item => Activities.identity(item) === key);
    }

    function canEnqueue(entry) {
        return contains(entry) || queue.length < 64;
    }

    function enqueue(entry) {
        if (!accepts(entry) || !canEnqueue(entry))
            return false;
        if (!entry.durationSpecified)
            entry = Object.assign({}, entry, {duration: defaultDuration});
        if (entry.kind === "notification")
            holdNotification(entry);
        if (Activities.identity(current) === Activities.identity(entry)) {
            current = entry.restartPreview ? entry : Object.assign({}, entry, {duration: current.duration});
            if (entry.announce && entry.restartPreview) {
                remaining = entry.duration;
                deadline = 0;
                syncTimer();
            }
            return true;
        }
        queue = Activities.enqueue(queue, entry);
        if (shouldPreempt(entry))
            suspendCurrent();
        advance();
        return true;
    }

    function enqueueSystem(activityId, duration) {
        if (!Activities.validId(activityId))
            return false;
        const entry = Activities.normalize("system", activityId, {
            title: activityId,
            priorityClass: "high",
            preemption: "higher",
            duration: duration
        }, Date.now());
        if (!entry)
            return false;
        entry.kind = "system";
        entry.systemActivity = activityId;
        entry.restartPreview = true;
        return enqueue(entry);
    }

    function shouldPreempt(entry) {
        return !!current && (!blocked || entry.priorityClass === "critical") && queue.length < 64 && entry.preemption === "higher" && entry.priority > current.priority;
    }

    function suspendCurrent() {
        if (!current)
            return;
        const suspended = Object.assign({}, current, {
            duration: current.duration <= 0 ? 0 : Math.max(1, deadline ? deadline - Date.now() : remaining),
            durationSpecified: true,
            resumed: true,
            announce: true
        });
        queue = Activities.enqueue(queue, suspended);
        takeCurrent();
    }

    function enqueueNotification(wrapper) {
        if (!wrapper || contains({source: "notifications", id: String(wrapper.seq)}))
            return;
        const critical = wrapper.urgency === NotificationUrgency.Critical;
        const entry = {source: "notifications", id: String(wrapper.seq), kind: "notification", wrapper: wrapper, title: wrapper.summary, duration: wrapper.timer?.interval ?? 5000, durationSpecified: true, priorityClass: critical ? "critical" : "normal", priority: critical ? 100 : 0, preemption: critical ? "higher" : "never", announce: true};
        enqueue(entry);
    }

    function holdNotification(entry) {
        entry.wrapper?.timer?.stop();
        // NotificationService starts the wrapper timer after emitting its visible-list update.
        Qt.callLater(() => {
            if (root.contains(entry))
                entry.wrapper?.timer?.stop();
        });
    }

    function advance() {
        if (current)
            return;
        const next = Activities.nextEvent(queue);
        if (!next || (blocked && next.priorityClass !== "critical"))
            return;
        queue = queue.filter(entry => entry !== next);
        remaining = next.duration;
        deadline = 0;
        current = next;
        syncTimer();
    }

    function cancelMissingNotifications(visible) {
        queue = queue.filter(entry => entry.kind !== "notification" || visible.indexOf(entry.wrapper) >= 0);
        if (current?.kind === "notification" && visible.indexOf(current.wrapper) < 0)
            finishCurrent(current);
    }

    function refreshNotification(wrapper) {
        const entry = [current].concat(queue).find(entry => entry?.kind === "notification" && entry.wrapper === wrapper);
        if (entry)
            enqueue(Object.assign({}, entry, {duration: wrapper.timer?.interval ?? 5000, restartPreview: true}));
    }

    function syncTimer() {
        const now = Date.now();
        if (deadline)
            remaining = Math.max(0, deadline - now);
        deadline = 0;
        timeout.stop();
        if (!current || held || current.duration <= 0)
            return;
        if (remaining <= 0) {
            finishCurrent(current);
            return;
        }
        deadline = now + remaining;
        timeout.interval = remaining;
        timeout.start();
    }

    function takeCurrent() {
        const previous = current;
        timeout.stop();
        deadline = 0;
        remaining = 0;
        current = null;
        return previous;
    }

    function finishCurrent(expected) {
        if (!current || (expected && Activities.identity(expected) !== Activities.identity(current)))
            return false;
        const finished = takeCurrent();
        if (finished.kind === "notification") {
            if (finished.wrapper)
                finished.wrapper.popup = false;
        } else {
            IslandActivityService.acknowledge(finished, hostKey);
        }
        Qt.callLater(advance);
        return true;
    }

    function remove(source, id) {
        queue = queue.filter(entry => entry.source !== source || (id && entry.id !== id));
        if (current?.source === source && (!id || current.id === id))
            finishCurrent(current);
    }

    function reconfigure() {
        if (!registered)
            return;
        for (const entry of queue.slice()) {
            if (accepts(entry))
                continue;
            queue = queue.filter(item => item !== entry);
            release(entry);
        }
        if (current && !accepts(current)) {
            release(takeCurrent());
        }
        IslandActivityService.seedSession(root);
        advance();
    }

    function release(entry) {
        if (entry.kind === "notification") {
            if (entry.wrapper?.popup && entry.wrapper.timer?.interval > 0)
                entry.wrapper.timer.restart();
        } else if (entry.kind === "activity") {
            IslandActivityService.acknowledge(entry, hostKey);
        }
    }

    onBlockedChanged: {
        syncTimer();
        advance();
    }
    onHeldChanged: syncTimer()
    onEnabledChanged: reconfigure()
    onExcludedSourcesChanged: reconfigure()
    onNotificationsEnabledChanged: reconfigure()
    onSystemsEnabledChanged: reconfigure()

    property Timer timeout: Timer {
        onTriggered: root.finishCurrent(root.current)
    }

    Component.onCompleted: {
        registered = true;
        IslandActivityService.registerSession(root);
    }
    Component.onDestruction: {
        registered = false;
        for (const entry of queue.concat(current ? [current] : []))
            release(entry);
        IslandActivityService.unregisterSession(root);
    }
}
