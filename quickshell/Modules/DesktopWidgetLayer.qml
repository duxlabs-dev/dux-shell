import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.Plugins

Variants {
    id: root
    model: ShellLayout.realScreens

    Component.onCompleted: Qt.callLater(autoEnablePluginsForInstances)

    function autoEnablePluginsForInstances() {
        const instances = (SettingsData.desktopWidgetInstances || []).concat(SettingsData.lockScreenWidgetInstances || []);
        const pluginTypes = new Set();

        for (const inst of instances) {
            if (!inst.enabled)
                continue;
            if (inst.widgetType === "desktopClock" || inst.widgetType === "systemMonitor")
                continue;
            pluginTypes.add(inst.widgetType);
        }

        for (const pluginId of pluginTypes) {
            if (PluginService.isPluginLoaded(pluginId))
                continue;
            if (!PluginService.availablePlugins[pluginId])
                continue;
            PluginService.enablePlugin(pluginId);
        }
    }

    Connections {
        target: PluginService
        function onPluginListUpdated() {
            Qt.callLater(root.autoEnablePluginsForInstances);
        }
    }

    QtObject {
        id: screenDelegate

        required property var modelData

        readonly property var screen: modelData

        // Layer surfaces stack by map order, so recreate them in list order on
        // reorder/enable/display-pref changes or once a plugin component loads (#2715).
        property bool rebuilding: false

        readonly property string orderSignature: {
            const instances = SettingsData.desktopWidgetInstances || [];
            let sig = "";
            for (const inst of instances) {
                const prefs = inst.config?.displayPreferences ?? ["all"];
                const prefsKey = Array.isArray(prefs) ? prefs.join(",") : "all";
                sig += inst.id + ":" + (inst.enabled ? "1" : "0") + ":" + prefsKey + "|";
            }
            return sig;
        }

        readonly property string pluginReadyKey: {
            const instances = SettingsData.desktopWidgetInstances || [];
            const comps = PluginService.pluginDesktopComponents;
            let key = "";
            for (const inst of instances) {
                if (!inst.enabled)
                    continue;
                if (inst.widgetType === "desktopClock" || inst.widgetType === "systemMonitor")
                    continue;
                key += inst.widgetType + (comps[inst.widgetType] ? ":1" : ":0") + ",";
            }
            return key;
        }

        onOrderSignatureChanged: rebuildDebounce.restart()
        onPluginReadyKeyChanged: rebuildDebounce.restart()

        property Timer rebuildDebounce: Timer {
            interval: 150
            repeat: false
            onTriggered: {
                screenDelegate.rebuilding = true;
                rebuildApply.restart();
            }
        }

        property Timer rebuildApply: Timer {
            interval: 32
            repeat: false
            onTriggered: screenDelegate.rebuilding = false
        }

        property Instantiator widgetInstantiator: Instantiator {
            model: ScriptModel {
                objectProp: "id"
                // Reversed so the top of the list maps last and renders in front.
                values: {
                    if (screenDelegate.rebuilding)
                        return [];
                    const instances = SettingsData.desktopWidgetInstances || [];
                    return instances.filter(inst => inst.enabled && DesktopWidgetRegistry.showsOnScreen(inst.config?.displayPreferences ?? ["all"], screenDelegate.screen)).reverse();
                }
            }

            DesktopPluginWrapper {
                required property var modelData
                required property int index

                readonly property string instanceIdRef: modelData.id
                readonly property var liveInstanceData: {
                    const instances = SettingsData.desktopWidgetInstances || [];
                    return instances.find(inst => inst.id === instanceIdRef) ?? modelData;
                }

                readonly property bool shouldBeVisible: {
                    if (!liveInstanceData.enabled || DesktopWidgetRegistry.editing)
                        return false;
                    const prefs = liveInstanceData.config?.displayPreferences ?? ["all"];
                    return DesktopWidgetRegistry.showsOnScreen(prefs, screenDelegate.screen);
                }

                pluginId: liveInstanceData.widgetType
                instanceId: instanceIdRef
                instanceData: liveInstanceData
                screen: screenDelegate.screen
                widgetEnabled: shouldBeVisible
            }
        }
    }
}
