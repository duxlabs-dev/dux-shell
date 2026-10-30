pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/IslandActivities.js" as Activities
import "../Common/IslandActivityInput.js" as Input

Singleton {
    id: root

    readonly property var log: Log.scoped("IslandActivityService")
    property var requests: ({})
    property int revision: 0
    property int nextSeq: 1
    // Plugins' island and islandSystem surfaces, from PluginService.pluginLoaded until unloaded.
    property var islandComponents: ({})
    property var islandSystemComponents: ({})

    signal shown(string token)
    signal interrupted(string token)
    signal resumed(string token)
    signal dropped(string token, string reason)
    signal action(string token, string actionId)

    function pluginRefusal(pluginId): string {
        if (!Input.pluginIdAllowed(pluginId))
            return "an id with a colon";
        if (!PluginService.isPluginLoaded(pluginId))
            return "not loaded";
        if (!root.islandComponents[pluginId])
            return "no island surface in its manifest";
        return root.pluginAllowed(pluginId) ? "" : "blocked in the island settings";
    }

    // "" when refused; the plugin reads why in the log.
    function request(pluginId, options): string {
        const refused = root.pluginRefusal(pluginId);
        if (refused) {
            root.log.warn("island activity refused:", refused, pluginId);
            return "";
        }
        const token = root.add(pluginId, options);
        if (!token)
            root.log.warn("island activity refused: no island on that screen", pluginId);
        return token;
    }

    // Scripts over IPC always get the ready face. The token, or the refusal's IPC answer.
    function requestScript(id, options): string {
        const name = String(id ?? "").trim();
        const prefix = Input.scriptPrefix;
        const live = Object.values(root.requests).filter(r => r.pluginId.startsWith(prefix)).map(r => r.pluginId.slice(prefix.length));
        const refused = Input.scriptRefusal(name, live, options?.notifyApp);
        return refused || root.add(prefix + name, options) || "ISLAND_ACTIVITY_NO_ISLAND";
    }

    // shortcut: "*" covers the islands present at request time; a screen plugged in later stays empty.
    function islandsFor(screenName) {
        const router = PopoutService.dankIslandRouter;
        if (!router)
            return [];
        const names = screenName === "*" ? Quickshell.screens.map(s => s.name) : [screenName];
        return names.map(name => router.hostForScreenName(name, "")?.islandController ?? null).filter(island => !!island);
    }

    function add(sourceId, options): string {
        const opts = Activities.normalizeOptions(options);
        // Shown as live; the log never quotes the kind (it may come over IPC, of any length).
        if (typeof options?.kind === "string" && options.kind !== opts.kind)
            root.log.warn("unknown activity kind, shown as live:", sourceId);
        opts.notifyApp = opts.notifyApp || String(PluginService.availablePlugins[sourceId]?.island?.notifyApp ?? "").trim();
        const screenName = opts.screen || (PopoutService.dankIslandRouter?.focusedHost()?.screen?.name ?? "");
        const islands = root.islandsFor(screenName);
        if (islands.length === 0)
            return "";
        const previous = Object.values(root.requests).find(r => r.pluginId === sourceId);
        if (previous)
            root.remove(previous.token, "replaced");
        const seq = root.nextSeq++;
        const token = sourceId + ":" + seq;
        root.requests = Object.assign({}, root.requests, {
            [token]: Object.assign(opts, {
                "token": token,
                "pluginId": sourceId,
                "screen": screenName,
                "hosts": islands,
                "shownOn": [],
                "seq": seq,
                "state": "waiting",
                "lastAction": ""
            })
        });
        root.revision++;
        return token;
    }

    function trigger(token, actionId) {
        const entry = root.requests[token];
        if (!entry || !actionId)
            return;
        entry.lastAction = actionId;
        root.revision++;
        root.action(token, actionId);
    }

    // Refused when it would empty a ready face that shows something: the face keeps its last content.
    function update(token, data): bool {
        const entry = root.requests[token];
        if (!entry)
            return false;
        const next = data && typeof data === "object" ? data : {};
        if (Input.ipcRefusal(next) && !Input.ipcRefusal(entry.data)) {
            root.log.warn("island activity update refused: it would empty its face", entry.pluginId);
            return false;
        }
        entry.data = next;
        root.revision++;
        return true;
    }

    // compactContent is known only once the island loads it: without it, no title nor icon is an empty pill.
    function dropIfEmpty(token): bool {
        const entry = root.requests[token];
        if (!entry || !Input.ipcRefusal(entry.data))
            return false;
        root.log.warn("island activity dropped: no title, icon nor compactContent", entry.pluginId);
        return root.remove(token, "empty");
    }

    function release(token): bool {
        return root.remove(token, "released");
    }

    function state(token): string {
        return root.requests[token]?.state ?? "";
    }

    function entry(token) {
        // Read so a binding calling this follows the requests, which change in place.
        root.revision;
        return root.requests[token] ?? null;
    }

    // As NotificationService: a bypass rule on the source or its app, or an alert when critical ones may pass.
    function letThroughDnd(request): bool {
        return SettingsData.isAppDndBypassed(request.notifyApp || request.pluginId, request.pluginId) || (request.kind === "alert" && SettingsData.notificationDndAllowCritical);
    }

    function nextFor(island) {
        // As in entry(): the binding's dependency on the requests.
        root.revision;
        return Activities.nextRequest(Object.values(root.requests), island, SessionData.doNotDisturb, root.letThroughDnd);
    }

    function pluginAllowed(pluginId): bool {
        return SettingsData.islandPluginsBlocked.indexOf(pluginId) === -1;
    }

    function setComponents(pluginId, comps) {
        const island = Object.assign({}, root.islandComponents), system = Object.assign({}, root.islandSystemComponents);
        delete island[pluginId];
        delete system[pluginId];
        if (comps?.island)
            island[pluginId] = comps.island;
        if (comps?.islandSystem)
            system[pluginId] = comps.islandSystem;
        root.islandComponents = island;
        root.islandSystemComponents = system;
    }

    function systemFacesOf(pluginId) {
        const faces = PluginService.availablePlugins[pluginId]?.island?.systemFaces;
        return Array.isArray(faces) ? faces : [];
    }

    // The user's pick stays saved while its plugin is away; the shell's face stands in.
    function systemFaceFor(kind) {
        const pluginId = SettingsData.islandSystemFaces[kind] ?? "";
        if (!pluginId || !root.pluginAllowed(pluginId) || root.systemFacesOf(pluginId).indexOf(kind) === -1)
            return null;
        const component = root.islandSystemComponents[pluginId];
        return component ? {
            "pluginId": pluginId,
            "component": component
        } : null;
    }

    function markShown(token, island) {
        root.markShowing(token, island, true);
    }

    function markInterrupted(token, island) {
        root.markShowing(token, island, false);
    }

    function markShowing(token, island, showing) {
        const entry = root.requests[token];
        if (!entry || (entry.shownOn.indexOf(island) !== -1) === showing)
            return;
        const change = Activities.shownChange(entry, island, showing);
        entry.shownOn = change.shownOn;
        entry.state = change.state;
        if (!change.signal)
            return;
        root.revision++;
        root[change.signal](token);
    }

    function remove(token, reason): bool {
        if (!root.requests[token])
            return false;
        const next = Object.assign({}, root.requests);
        delete next[token];
        root.requests = next;
        root.revision++;
        root.dropped(token, reason);
        return true;
    }

    function removePlugin(pluginId, reason) {
        for (const entry of Object.values(root.requests)) {
            if (entry.pluginId === pluginId)
                root.remove(entry.token, reason);
        }
    }

    // An island that goes away takes its activities with it; the plugin falls back on its own.
    function removeHost(island) {
        for (const entry of Object.values(root.requests)) {
            if (entry.hosts.indexOf(island) === -1)
                continue;
            entry.hosts = entry.hosts.filter(host => host !== island);
            if (entry.hosts.length === 0)
                root.remove(entry.token, "unavailable");
            else
                root.markInterrupted(entry.token, island); // shown there: interrupted once no island shows it
        }
    }

    Connections {
        target: PluginService

        function onPluginUnloaded(pluginId) {
            root.removePlugin(pluginId, "unloaded");
            const gone = [root.islandComponents[pluginId], root.islandSystemComponents[pluginId]].filter(comp => !!comp);
            root.setComponents(pluginId, {});
            for (const comp of gone)
                comp.destroy();
        }
    }

    Connections {
        target: SettingsData

        function onIslandPluginsBlockedChanged() {
            for (const pluginId of SettingsData.islandPluginsBlocked) {
                root.removePlugin(pluginId, "disabled");
            }
        }
    }
}
