import QtQuick
import qs.Common

// Duck-typed store the Island*Cards read; a stand-in must expose config, setting, apply, isDefault and resetToDefault.
QtObject {
    id: root

    property string barId: ""

    readonly property var config: {
        SettingsData.barConfigs;
        return SettingsData.getBarConfig(root.barId);
    }

    function setting(key) {
        return SettingsData.islandSetting(root.config, key);
    }

    function apply(key, value) {
        SettingsData.setIslandSettings(root.barId, {
            [key]: value
        });
    }

    function defaultFor(key) {
        const defaults = SettingsData.islandDefaultsFor(root.config);
        return key in defaults ? defaults[key] : SettingsData.barConfigDefault(key);
    }

    function isDefault(keys) {
        const settings = SettingsData.islandSettings(root.config);
        return keys.every(key => settings[key] === undefined || JSON.stringify(settings[key]) === JSON.stringify(defaultFor(key)));
    }

    function resetToDefault(keys) {
        const patch = {};
        for (const key of keys)
            patch[key] = defaultFor(key);
        SettingsData.setIslandSettings(root.barId, patch);
    }
}
