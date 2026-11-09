pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import "../Common/IslandActivities.js" as Activities

Singleton {
    id: root

    property int publicationRevision: 0
    property var entries: []
    property var renderers: ({})
    property var sessions: []
    property var pendingHosts: ({})
    property var actionQueue: []
    readonly property bool islandAvailable: sessions.length > 0
    readonly property bool activitiesAvailable: sessions.some(session => session.enabled)
    readonly property bool notificationsAvailable: sessions.some(session => session.notificationsEnabled)
    signal actionInvoked(string source, string id, string action)

    function publish(source, id, payload, external = false) {
        const now = Date.now();
        const entry = Activities.normalize(source, id, payload, now);
        if (!entry)
            return false;
        if (external && entry.persistent && !entry.ttl) {
            entry.ttl = Activities.IPC_ACTIVITY_TTL;
            entry.expiresAt = now + entry.ttl;
        }
        expireEntries();
        const previous = entries.find(item => item.source === source && item.id === id);
        if (previous?.persistent && payload.announce !== true)
            entry.announce = false;
        entry.restartPreview = payload.announce === true;
        entry.kind = "activity";
        const receivers = sessions.filter(session => session.accepts(entry));
        const hosts = receivers.filter(session => session.canEnqueue(entry) && (entry.announce || session.contains(entry)));
        if (entry.announce && !entry.persistent && receivers.length && !hosts.length)
            return false;
        if (hosts.length && !entry.persistent)
            entry.expiresAt = 0;
        const next = Activities.upsert(entries, entry, now);
        if (!next)
            return false;
        entry.revision = ++publicationRevision;
        entries = next;
        const key = Activities.identity(entry);
        pendingHosts = Object.assign({}, pendingHosts, {[key]: hosts.map(session => session.hostKey)});
        for (const session of hosts)
            session.enqueue(entry);
        return true;
    }

    function registerSession(session) {
        sessions = sessions.concat([session]);
        seedSession(session);
    }

    function seedSession(session) {
        for (const entry of entries) {
            if (!entry.announce || !session.accepts(entry) || !session.canEnqueue(entry) || session.contains(entry))
                continue;
            const key = Activities.identity(entry);
            const hosts = pendingHosts[key] || [];
            if (hosts.indexOf(session.hostKey) >= 0)
                continue;
            if (!entry.persistent)
                entry.expiresAt = 0;
            pendingHosts = Object.assign({}, pendingHosts, {[key]: hosts.concat([session.hostKey])});
            session.enqueue(entry);
        }
        scheduleExpiry();
    }

    function unregisterSession(session) {
        sessions = sessions.filter(item => item !== session);
        for (const entry of entries.slice())
            acknowledge(entry, session.hostKey);
    }

    function acknowledge(entry, hostKey) {
        const registered = entries.find(item => item.source === entry.source && item.id === entry.id);
        if (!registered || registered.revision !== entry.revision)
            return;
        const key = Activities.identity(entry);
        const hosts = pendingHosts[key] || [];
        if (hosts.indexOf(hostKey) < 0)
            return;
        const remaining = hosts.filter(key => key !== hostKey);
        pendingHosts = Object.assign({}, pendingHosts, {[key]: remaining});
        if (!remaining.length && !registered.persistent)
            remove(entry.source, entry.id);
        else if (!remaining.length) {
            registered.announce = false;
            entries = entries.slice();
        }
    }

    function remove(source, id) {
        const next = entries.filter(entry => entry.source !== source || entry.id !== id);
        if (next.length === entries.length)
            return false;
        entries = next;
        const pending = Object.assign({}, pendingHosts);
        delete pending[Activities.identity({source: source, id: id})];
        pendingHosts = pending;
        for (const session of sessions)
            session.remove(source, id);
        return true;
    }

    function clearSource(source) {
        for (const entry of entries.filter(entry => entry.source === source))
            remove(entry.source, entry.id);
        const next = Object.assign({}, renderers);
        delete next[source];
        renderers = next;
        actionQueue = actionQueue.filter(event => event.source !== source);
    }

    function registerRenderer(source, compact, expanded, icon = undefined) {
        if (!Activities.validId(source) || (!renderers[source] && Object.keys(renderers).length >= 64))
            return false;
        const iconComponent = icon === undefined ? renderers[source]?.icon ?? null : icon;
        renderers = Object.assign({}, renderers, {[source]: {compact: compact, expanded: expanded, icon: iconComponent}});
        return true;
    }

    function registerIconRenderer(source, icon) {
        const renderer = renderers[source];
        return registerRenderer(source, renderer?.compact ?? null, renderer?.expanded ?? null, icon);
    }

    function select(screen, barId, excludedSources) {
        return Activities.select(entries, screen, barId, excludedSources || []);
    }

    function canPresentSource(source, screen = null) {
        const screenName = typeof screen === "string" ? screen : screen?.name ?? "";
        return sessions.some(session => session.enabled && (!screenName || session.screenName === screenName) && (session.excludedSources || []).indexOf(source) < 0);
    }

    function availabilityOn(screenName) {
        const hosts = sessions.filter(session => session.screenName === screenName);
        return {
            islandPresent: hosts.length > 0,
            activitiesAvailable: hosts.some(session => session.enabled),
            notificationsAvailable: hosts.some(session => session.notificationsEnabled),
            hosts: hosts.map(session => ({barId: session.barId, activitiesEnabled: session.enabled, notificationsEnabled: session.notificationsEnabled}))
        };
    }

    function islandAvailableOn(screenName) {
        return sessions.some(session => session.screenName === screenName);
    }

    function availability() {
        return {
            islandPresent: sessions.length > 0,
            activitiesAvailable: sessions.some(session => session.enabled),
            notificationsAvailable: sessions.some(session => session.notificationsEnabled),
            screens: Array.from(new Set(sessions.map(session => session.screenName))).sort().map(screen => Object.assign({screen: screen}, availabilityOn(screen)))
        };
    }

    function invoke(source, id, action) {
        const entry = entries.find(entry => entry.source === source && entry.id === id);
        if (!Activities.canInvoke(entry, action))
            return false;
        actionInvoked(source, id, action);
        actionQueue = actionQueue.concat([{source: source, id: id, action: action}]).slice(-64);
        return true;
    }

    function activate(entry) {
        if (entry.clickAction) {
            invoke(entry.source, entry.id, entry.clickAction);
            return true;
        }
        if (entry.clickTarget && entry.clickMethod) {
            Quickshell.execDetached(["dms", "ipc", "call", entry.clickTarget, entry.clickMethod]);
            return true;
        }
        return false;
    }

    function pollActions(source) {
        if (!Activities.validId(source))
            return "[]";
        const events = actionQueue.filter(event => event.source === source);
        actionQueue = actionQueue.filter(event => event.source !== source);
        return JSON.stringify(events);
    }

    function notificationsQueued() {
        return sessions.some(session => session.notificationsEnabled && NotificationService.isFocusedScreen({name: session.screenName}));
    }

    function open(source, id) {
        const entry = entries.find(entry => entry.source === source && entry.id === id);
        if (!entry)
            return false;
        const hosts = sessions.filter(session => session.accepts(entry));
        for (const session of hosts)
            session.openRequested(entry);
        return hosts.length > 0;
    }

    function scheduleExpiry() {
        expiry.stop();
        const next = Activities.nextExpiry(entries);
        if (!next)
            return;
        expiry.interval = Math.max(1, next - Date.now());
        expiry.start();
    }

    function expireEntries() {
        const now = Date.now();
        for (const entry of entries.filter(entry => entry.expiresAt && entry.expiresAt <= now))
            remove(entry.source, entry.id);
    }

    onEntriesChanged: scheduleExpiry()

    Timer {
        id: expiry
        onTriggered: root.expireEntries()
    }

    IpcHandler {
        target: "islandActivity"

        function publish(source: string, id: string, payload: string): string {
            if (!Activities.validPayloadSize(payload))
                return "ISLAND_ACTIVITY_INVALID";
            try {
                return root.publish(source, id, JSON.parse(payload), true) ? "ISLAND_ACTIVITY_PUBLISHED" : "ISLAND_ACTIVITY_INVALID";
            } catch (error) {
                return "ISLAND_ACTIVITY_INVALID";
            }
        }

        function remove(source: string, id: string): string {
            return root.remove(source, id) ? "ISLAND_ACTIVITY_REMOVED" : "ISLAND_ACTIVITY_NOT_FOUND";
        }

        function clear(source: string): string {
            root.clearSource(source);
            return "ISLAND_ACTIVITY_CLEARED";
        }

        function list(): string {
            return JSON.stringify(root.entries);
        }

        function status(): string {
            return JSON.stringify(root.sessions.map(session => ({
                screen: session.screenName,
                barId: session.barId,
                enabled: session.enabled,
                notificationsEnabled: session.notificationsEnabled,
                blocked: session.blocked,
                held: session.held,
                current: session.current ? {source: session.current.source, id: session.current.id} : null,
                remaining: session.deadline ? Math.max(0, session.deadline - Date.now()) : session.remaining,
                queue: session.queue.map(entry => ({source: entry.source, id: entry.id}))
            })));
        }

        function availability(): string {
            return JSON.stringify(root.availability());
        }

        function availabilityOn(screen: string): string {
            return JSON.stringify(Object.assign({screen: screen}, root.availabilityOn(screen)));
        }

        function canPresentSource(source: string, screen: string): string {
            return root.canPresentSource(source, screen) ? "true" : "false";
        }

        function pollActions(source: string): string {
            return root.pollActions(source);
        }

        function open(source: string, id: string): string {
            return root.open(source, id) ? "ISLAND_ACTIVITY_OPENED" : "ISLAND_ACTIVITY_NOT_FOUND";
        }

        function invoke(source: string, id: string, action: string): string {
            return root.invoke(source, id, action) ? "ISLAND_ACTIVITY_ACTION_INVOKED" : "ISLAND_ACTIVITY_ACTION_INVALID";
        }
    }
}
