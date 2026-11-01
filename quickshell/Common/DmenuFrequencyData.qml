pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var freqRanking: ({})
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
                freqRanking = settings.freqRanking || {};
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
            "freqRanking": freqRanking
        }, null, 2));
    }

    function recordUsage(freqKey, itemText) {
        if (!freqKey || !itemText || !SettingsData.launcherHistoryEnabled)
            return;

        var buckets = Object.assign({}, freqRanking);
        var bucket = Object.assign({}, buckets[freqKey] || {});
        var entry = bucket[itemText];

        bucket[itemText] = {
            "usageCount": (entry ? entry.usageCount : 0) + 1,
            "lastUsed": Date.now()
        };
        buckets[freqKey] = bucket;

        freqRanking = buckets;
        _saving = true;
        saveSettings();
        _saving = false;
    }

    function getUsage(freqKey, itemText) {
        var bucket = (freqRanking || {})[freqKey];
        if (!bucket || !bucket[itemText])
            return null;
        return {
            "usageCount": bucket[itemText].usageCount || 0
        };
    }

    FileView {
        id: settingsFile

        path: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/dms/dmenufreq.json"
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
