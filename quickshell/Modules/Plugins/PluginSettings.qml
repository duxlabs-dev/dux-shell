import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root
    readonly property var log: Log.scoped("PluginSettings")

    required property string pluginId
    property var pluginService: null
    default property list<QtObject> content

    signal settingChanged

    property var variants: []
    property alias variantsModel: variantsListModel

    implicitHeight: hasPermission ? settingsColumn.implicitHeight : errorText.implicitHeight
    height: implicitHeight

    readonly property bool isDesktopPlugin: {
        if (!pluginService?.availablePlugins || !pluginId)
            return false;
        const plugin = pluginService.availablePlugins[pluginId];
        return plugin?.type === "desktop";
    }

    readonly property bool hasPermission: {
        if (!pluginService?.availablePlugins || !pluginId)
            return true;
        const plugin = pluginService.availablePlugins[pluginId];
        if (!plugin)
            return true;
        const permissions = Array.isArray(plugin.permissions) ? plugin.permissions : [];
        return permissions.indexOf("settings_write") !== -1;
    }

    Component.onCompleted: {
        loadVariants();
    }

    onPluginServiceChanged: {
        if (pluginService) {
            loadVariants();
            for (let i = 0; i < content.length; i++) {
                const child = content[i];
                if (child.loadValue) {
                    child.loadValue();
                }
            }
        }
    }

    onContentChanged: {
        for (let i = 0; i < content.length; i++) {
            const item = content[i];
            if (item instanceof Item) {
                item.parent = settingsColumn;
            }
        }
    }

    Connections {
        target: pluginService
        enabled: pluginService !== null

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === pluginId) {
                loadVariants();
                reloadChildValues();
            }
        }
    }

    function reloadChildValues() {
        for (let i = 0; i < content.length; i++) {
            const child = content[i];
            if (child.loadValue) {
                child.loadValue();
            }
        }
    }

    function loadVariants() {
        if (!pluginService?.getPluginVariants || !pluginId) {
            variants = [];
            return;
        }
        variants = pluginService.getPluginVariants(pluginId);
        syncVariantsToModel();
    }

    function syncVariantsToModel() {
        variantsListModel.clear();
        for (let i = 0; i < variants.length; i++) {
            variantsListModel.append(variants[i]);
        }
    }

    onVariantsChanged: {
        syncVariantsToModel();
    }

    ListModel {
        id: variantsListModel
    }

    function createVariant(variantName, variantConfig) {
        if (!pluginService?.createPluginVariant || !pluginId) {
            return null;
        }
        return pluginService.createPluginVariant(pluginId, variantName, variantConfig);
    }

    function removeVariant(variantId) {
        if (!pluginService?.removePluginVariant || !pluginId) {
            return;
        }
        pluginService.removePluginVariant(pluginId, variantId);
    }

    function updateVariant(variantId, variantConfig) {
        if (!pluginService?.updatePluginVariant || !pluginId) {
            return;
        }
        pluginService.updatePluginVariant(pluginId, variantId, variantConfig);
    }

    function saveValue(key, value) {
        if (!pluginService) {
            return;
        }
        if (!hasPermission) {
            log.warn("Plugin", pluginId, "does not have settings_write permission");
            return;
        }
        if (pluginService.savePluginData) {
            pluginService.savePluginData(pluginId, key, value);
            settingChanged();
        }
    }

    function loadValue(key, defaultValue) {
        if (pluginService && pluginService.loadPluginData) {
            return pluginService.loadPluginData(pluginId, key, defaultValue);
        }
        return defaultValue;
    }

    function saveState(key, value) {
        if (!pluginService)
            return;
        if (pluginService.savePluginState)
            pluginService.savePluginState(pluginId, key, value);
    }

    function loadState(key, defaultValue) {
        if (pluginService && pluginService.loadPluginState)
            return pluginService.loadPluginState(pluginId, key, defaultValue);
        return defaultValue;
    }

    function clearState() {
        if (pluginService && pluginService.clearPluginState)
            pluginService.clearPluginState(pluginId);
    }

    function findFlickable(item) {
        var current = item?.parent;
        while (current) {
            if (current.contentY !== undefined && current.contentHeight !== undefined) {
                return current;
            }
            current = current.parent;
        }
        return null;
    }

    function ensureItemVisible(item) {
        if (!item)
            return;
        var flickable = findFlickable(root);
        if (!flickable)
            return;
        var itemGlobalY = item.mapToItem(null, 0, 0).y;
        var itemHeight = item.height;
        var flickableGlobalY = flickable.mapToItem(null, 0, 0).y;
        var viewportHeight = flickable.height;

        var itemRelativeY = itemGlobalY - flickableGlobalY;
        var viewportTop = 0;
        var viewportBottom = viewportHeight;

        if (itemRelativeY < viewportTop) {
            flickable.contentY = Math.max(0, flickable.contentY - (viewportTop - itemRelativeY) - Theme.spacingL);
        } else if (itemRelativeY + itemHeight > viewportBottom) {
            flickable.contentY = Math.min(flickable.contentHeight - viewportHeight, flickable.contentY + (itemRelativeY + itemHeight - viewportBottom) + Theme.spacingL);
        }
    }

    StyledText {
        id: errorText
        visible: pluginService && !root.hasPermission
        anchors.fill: parent
        text: I18n.tr("This plugin does not have '%1' permission.\n\nAdd %2 to %3", "plugin settings write warning, %1 is a permission name, %2 a manifest snippet, %3 the manifest file").arg("settings_write").arg('"permissions": ["settings_read", "settings_write"]').arg("plugin.json")
        color: Theme.error
        font.pixelSize: Theme.fontSizeMedium
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Column {
        id: settingsColumn
        visible: root.hasPermission
        width: parent.width
        spacing: Theme.spacingM

        Item {
            id: desktopDisplaySettings
            visible: root.isDesktopPlugin
            width: parent.width
            height: visible ? displaySettingsColumn.implicitHeight : 0

            Column {
                id: displaySettingsColumn
                width: parent.width
                spacing: Theme.spacingS

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outline
                    opacity: 0.3
                    visible: root.content.length > 0
                }

                StyledText {
                    text: I18n.tr("Display Settings")
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                }

                StyledText {
                    text: I18n.tr("Choose which displays show this widget")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    width: parent.width
                    wrapMode: Text.WordWrap
                }

                DToggle {
                    width: parent.width
                    text: I18n.tr("All displays")
                    checked: {
                        const prefs = root.loadValue("displayPreferences", ["all"]);
                        return Array.isArray(prefs) && (prefs.includes("all") || prefs.length === 0);
                    }
                    onToggled: isChecked => {
                        if (isChecked) {
                            root.saveValue("displayPreferences", ["all"]);
                        } else {
                            root.saveValue("displayPreferences", []);
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: {
                        const prefs = root.loadValue("displayPreferences", ["all"]);
                        return !Array.isArray(prefs) || (!prefs.includes("all") && prefs.length >= 0);
                    }

                    Repeater {
                        model: Quickshell.screens

                        DToggle {
                            required property var modelData
                            width: parent.width
                            text: SettingsData.getScreenDisplayName(modelData)
                            description: modelData.width + "×" + modelData.height
                            checked: {
                                const prefs = root.loadValue("displayPreferences", ["all"]);
                                if (!Array.isArray(prefs) || prefs.includes("all"))
                                    return false;
                                return prefs.some(p => p.name === modelData.name);
                            }
                            onToggled: isChecked => {
                                var prefs = root.loadValue("displayPreferences", ["all"]);
                                if (!Array.isArray(prefs) || prefs.includes("all")) {
                                    prefs = [];
                                }
                                prefs = prefs.filter(p => p.name !== modelData.name);
                                if (isChecked) {
                                    prefs.push({
                                        name: modelData.name,
                                        model: modelData.model || ""
                                    });
                                }
                                root.saveValue("displayPreferences", prefs);
                            }
                        }
                    }
                }
            }
        }
    }
}
