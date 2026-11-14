pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import "../Common/IslandActivities.js" as Activities

QtObject {
    id: root

    required property string screenName
    required property string barId
    property bool enabled: true
    // Built-in notifications and OSDs never queue here; these only report which host shows them.
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
        return enabled && Activities.matches(entry, screenName, barId, excludedSources);
    }

    // Ignores the slot limit, so an open activity stays open after losing its slot.
    function persistentEntry(entry) {
        if (!enabled || !entry)
            return null;
        const key = Activities.identity(entry);
        return Activities.stableEntries(IslandActivityService.entries.filter(item => Activities.identity(item) === key), screenName, barId, excludedSources, sourceOverrides, 1)[0] ?? null;
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
        IslandActivityService.acknowledge(takeCurrent(), hostKey);
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
            IslandActivityService.acknowledge(entry, hostKey);
        }
        if (current && !accepts(current))
            IslandActivityService.acknowledge(takeCurrent(), hostKey);
        IslandActivityService.seedSession(root);
        advance();
    }

    onBlockedChanged: {
        syncTimer();
        advance();
    }
    onHeldChanged: syncTimer()
    onEnabledChanged: reconfigure()
    onExcludedSourcesChanged: reconfigure()

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
            IslandActivityService.acknowledge(entry, hostKey);
        IslandActivityService.unregisterSession(root);
    }
}
