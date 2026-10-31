pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services

// Shared by every island: plugin activities and system face providers are global settings.
SettingsCard {
    id: root

    property string keyPrefix: "island"
    property bool shown: true

    readonly property var activityPlugins: Object.keys(PluginService.availablePlugins).filter(id => !!PluginService.availablePlugins[id].componentPaths?.island)
    readonly property var systemKinds: [
        {
            "kind": "volume",
            "text": I18n.tr("Volume", "island system face: volume title")
        },
        {
            "kind": "mic",
            "text": I18n.tr("Microphone", "island system face: microphone title")
        },
        {
            "kind": "brightness",
            "text": I18n.tr("Brightness", "island system face: brightness title")
        },
        {
            "kind": "capslock",
            "text": I18n.tr("Caps lock", "island system face: caps lock title")
        },
        {
            "kind": "powerprofile",
            "text": I18n.tr("Power profile", "island system face: power profile title")
        },
        {
            "kind": "idleinhibitor",
            "text": I18n.tr("Idle inhibitor", "island system face: idle inhibitor title")
        },
        {
            "kind": "charging",
            "text": I18n.tr("Charging", "island settings: pulse the island when power is connected or removed")
        }
    ].filter(entry => IslandActivityService.systemFaceProviders(entry.kind).length > 0 || !!SettingsData.islandSystemFaces[entry.kind])
    readonly property string shellFace: I18n.tr("Shell", "island settings: system face drawn by the shell itself")

    function pluginName(pluginId) {
        return PluginService.availablePlugins[pluginId]?.name ?? pluginId;
    }

    // A provider's name in a list of providers, with its id when another one in the list has the same name.
    function providerLabel(pluginId, pluginIds) {
        const name = root.pluginName(pluginId);
        return pluginIds.some(id => id !== pluginId && root.pluginName(id) === name) ? name + " (" + pluginId + ")" : name;
    }

    iconName: "extension"
    title: I18n.tr("Plugins", "island settings: plugins card title")
    settingKey: root.keyPrefix + "Plugins"
    tags: ["island", "plugins", "activity", "alert", "live", "glance", "face", "volume", "osd"]
    visible: root.shown && (root.activityPlugins.length > 0 || root.systemKinds.length > 0)

    Repeater {
        model: root.activityPlugins

        SettingsToggleRow {
            required property string modelData

            settingKey: root.keyPrefix + "Plugin_" + modelData
            tags: ["island", "plugins", "activity", modelData]
            text: root.pluginName(modelData)
            description: I18n.tr("Can show its activities in the island", "island settings: per-plugin activity switch description")
            checked: IslandActivityService.pluginAllowed(modelData)
            onToggled: checked => SettingsData.setIslandPluginAllowed(modelData, checked)
        }
    }

    Repeater {
        model: root.systemKinds

        SettingsDropdownRow {
            id: faceRow

            required property var modelData
            readonly property var providers: IslandActivityService.systemFaceProviders(modelData.kind)
            readonly property var labels: faceRow.providers.map(id => root.providerLabel(id, faceRow.providers))
            readonly property string chosen: SettingsData.islandSystemFaces[modelData.kind] ?? ""
            readonly property bool missing: chosen !== "" && !IslandActivityService.systemFaceFor(modelData.kind)

            settingKey: root.keyPrefix + "SystemFace_" + modelData.kind
            tags: ["island", "plugins", "face", "osd", modelData.kind]
            text: modelData.text
            description: faceRow.missing ? I18n.tr("%1 is not available, the shell's face is shown", "island settings: chosen system face plugin is not loaded").arg(root.pluginName(faceRow.chosen)) : ""
            options: [root.shellFace].concat(faceRow.labels)
            currentValue: faceRow.chosen ? (faceRow.labels[faceRow.providers.indexOf(faceRow.chosen)] ?? root.pluginName(faceRow.chosen)) : root.shellFace
            onValueChanged: value => SettingsData.setIslandSystemFace(modelData.kind, faceRow.providers[faceRow.labels.indexOf(value)] ?? "")
        }
    }
}
