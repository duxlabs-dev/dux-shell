pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var appUsageRanking: {}
    property bool _saving: false
    property bool _hasLoaded: false
    property bool _parseError: false

    Component.onCompleted: {
        loadSettings();
    }

    function loadSettings() {
        parseSettings(settingsFile.text());
    }

    function parseSettings(content) {
        _parseError = false;
        try {
            if (content && content.trim()) {
                var settings = JSON.parse(content);
                appUsageRanking = settings.appUsageRanking || {};
            }
            _hasLoaded = true;
        } catch (e) {
            _parseError = true;
        }
    }

    function saveSettings() {
        if (_parseError || !_hasLoaded)
            return;
        settingsFile.setText(JSON.stringify({
            "appUsageRanking": appUsageRanking
        }, null, 2));
    }

    function addAppUsage(app) {
        if (!app || !SettingsData.launcherHistoryEnabled)
            return;
        var appId = app.id || (app.execString || app.exec || "");
        if (!appId)
            return;
        var currentRanking = Object.assign({}, appUsageRanking);

        if (currentRanking[appId]) {
            currentRanking[appId].usageCount = (currentRanking[appId].usageCount || 1) + 1;
            currentRanking[appId].lastUsed = Date.now();
            currentRanking[appId].icon = app.icon ? String(app.icon) : (currentRanking[appId].icon || "application-x-executable");
            currentRanking[appId].name = app.name || currentRanking[appId].name || "";
        } else {
            currentRanking[appId] = {
                "name": app.name || "",
                "exec": app.execString || app.exec || "",
                "icon": app.icon ? String(app.icon) : "application-x-executable",
                "comment": app.comment || "",
                "usageCount": 1,
                "lastUsed": Date.now()
            };
        }

        appUsageRanking = currentRanking;
        _saving = true;
        saveSettings();
        _saving = false;
    }

    function clear() {
        appUsageRanking = {};
        saveSettings();
    }

    function getRankedApps() {
        var apps = [];
        for (var appId in appUsageRanking) {
            var appData = appUsageRanking[appId];
            apps.push({
                "id": appId,
                "name": appData.name,
                "exec": appData.exec,
                "icon": appData.icon,
                "comment": appData.comment,
                "usageCount": appData.usageCount,
                "lastUsed": appData.lastUsed
            });
        }

        return apps.sort(function (a, b) {
            if (a.usageCount !== b.usageCount)
                return b.usageCount - a.usageCount;
            return a.name.localeCompare(b.name);
        });
    }

    function cleanupAppUsageRanking(availableAppIds) {
        var currentRanking = Object.assign({}, appUsageRanking);
        var hasChanges = false;

        for (var appId in currentRanking) {
            if (availableAppIds.indexOf(appId) === -1) {
                delete currentRanking[appId];
                hasChanges = true;
            }
        }

        if (hasChanges) {
            appUsageRanking = currentRanking;
            _saving = true;
            saveSettings();
            _saving = false;
        }
    }

    FileView {
        id: settingsFile

        path: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/dms/appusage.json"
        blockLoading: true
        blockWrites: true
        watchChanges: SettingsData.launcherHistoryEnabled
        onLoaded: {
            if (root._saving)
                return;
            parseSettings(settingsFile.text());
        }
        onLoadFailed: error => {}
    }
}
