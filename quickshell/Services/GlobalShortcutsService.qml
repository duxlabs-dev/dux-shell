pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/KeyUtils.js" as KeyUtils

Singleton {
    id: root

    readonly property bool available: DMSService.isConnected && DMSService.capabilities.includes("globalshortcuts")
    property var apps: []
    property var prompts: []

    onAvailableChanged: {
        if (available)
            return;
        applyState(null);
    }

    Connections {
        target: DMSService

        function onGlobalShortcutsStateUpdate(data) {
            root.applyState(data);
        }
    }

    function applyState(state) {
        apps = state?.apps ?? [];
        prompts = state?.prompts ?? [];
    }

    function appName(appId) {
        // read so callers re-evaluate once the lazy desktop entry scan lands
        DesktopEntries.applications.values;
        return Paths.getAppName(appId, appId ? DesktopEntries.heuristicLookup(Paths.moddedAppId(appId)) : null);
    }

    function retainBinds() {
        KeybindsService.addRef();
        if (KeybindsService._dataVersion === 0)
            KeybindsService.loadBinds(false);
    }

    function releaseBinds() {
        KeybindsService.removeRef();
    }

    function bindAction(appId, shortcutId) {
        return appId + "\n" + shortcutId;
    }

    function bindEntry(appId, shortcut, key) {
        return {
            "appId": appId,
            "action": bindAction(appId, shortcut.id),
            "desc": appName(appId) + ": " + (shortcut.description || shortcut.id),
            "keys": key ? [
                {
                    "key": key
                }
            ] : []
        };
    }

    function savedBinds() {
        const binds = [];
        for (const app of apps) {
            for (const shortcut of app.shortcuts ?? [])
                binds.push(bindEntry(app.id, shortcut, shortcut.triggers?.[0] ?? ""));
        }
        return binds;
    }

    function conflicts(key, appId, shortcutId, appBinds) {
        if (!key)
            return [];
        return KeyUtils.getConflictingBinds(key, bindAction(appId, shortcutId), KeybindsService.getFlatBinds().concat(appBinds), KeybindsService.modKey, KeybindsService.modSymbol);
    }

    function submit(token, shortcuts) {
        DMSService.sendRequest("globalshortcuts.submit", {
            "token": token,
            "shortcuts": shortcuts
        }, null);
    }

    function cancel(token) {
        DMSService.sendRequest("globalshortcuts.cancel", {
            "token": token
        }, null);
    }

    function setTriggers(appId, shortcutId, triggers) {
        DMSService.sendRequest("globalshortcuts.setTriggers", {
            "appId": appId,
            "id": shortcutId,
            "triggers": triggers
        }, null);
    }

    function remove(appId) {
        DMSService.sendRequest("globalshortcuts.remove", {
            "appId": appId
        }, null);
    }
}
