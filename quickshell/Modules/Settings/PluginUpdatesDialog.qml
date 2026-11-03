import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Services

SettingsCard {
    id: root

    property var updatesList: []
    property bool isUpdating: false
    property bool operationsBlocked: false
    property string currentUpdatingPlugin: ""
    property var updateErrors: ({})

    signal pluginUpdated(string pluginId)
    signal updatesRequested(var plugins)

    iconName: "download"
    title: I18n.tr("Available Updates (%1)", "plugin updates dialog title, %1 is a count").arg(updatesList.length)
    visible: false

    headerActions: DActionButton {
        iconName: "close"
        tooltipText: I18n.tr("Close")
        iconColor: Theme.surfaceVariantText
        enabled: !root.isUpdating && !root.operationsBlocked
        onClicked: root.hide()
    }

    function show(list) {
        if (isUpdating || operationsBlocked)
            return;
        updatesList = list || [];
        visible = true;
    }

    function hide() {
        if (isUpdating || operationsBlocked)
            return;
        visible = false;
        updatesList = [];
        updateErrors = ({});
    }

    function updateSingle(plugin) {
        updatesRequested([plugin]);
    }

    function updateAll() {
        updatesRequested(updatesList.filter(plugin => PluginService.checkPluginCompatibility(plugin.requires_dms)));
    }

    function updatePlugins(list) {
        if (isUpdating || operationsBlocked || list.length === 0)
            return;
        isUpdating = true;
        updateErrors = ({});
        let index = 0;
        function updateNext() {
            if (index >= list.length) {
                isUpdating = false;
                currentUpdatingPlugin = "";
                DMSService.listInstalled();
                return;
            }
            const plugin = list[index++];
            currentUpdatingPlugin = plugin.name;
            PluginService.updatePlugin(plugin.id, response => {
                if (response.error) {
                    updateErrors = Object.assign({}, updateErrors, {
                        [plugin.id]: I18n.tr("Failed to update %1: %2", "plugin update error, %1 is the plugin name, %2 is the error message").arg(plugin.name).arg(response.error)
                    });
                    updateNext();
                    return;
                }
                root.pluginUpdated(plugin.id);
                updatesList = updatesList.filter(entry => entry.id !== plugin.id);
                updateNext();
            });
        }
        updateNext();
    }

    SettingsNoteRow {
        visible: !root.isUpdating && root.updatesList.length > 0
        text: I18n.tr("Plugin updates can change the code running in your session. Review the changes before updating.", "plugin update audit reminder")
    }

    SettingsRow {
        visible: root.isUpdating
        title: root.currentUpdatingPlugin ? I18n.tr("Updating %1...", "plugin updates dialog progress, %1 is the plugin name").arg(root.currentUpdatingPlugin) : I18n.tr("Updating plugins...")
        leading: DSpinner {
            size: Theme.iconSize
            running: root.isUpdating
        }
    }

    SettingsRow {
        visible: Object.keys(root.updateErrors).length > 0
        subtitle: Object.values(root.updateErrors).join("\n")
        subtitleColor: Theme.error
    }

    Repeater {
        model: root.isUpdating ? [] : root.updatesList

        delegate: SettingsRow {
            required property var modelData

            readonly property bool compatible: PluginService.checkPluginCompatibility(modelData.requires_dms)

            iconName: modelData.icon || "extension"
            title: modelData.name || ""
            subtitle: !compatible ? I18n.tr("Requires DMS %1", "plugin incompatibility notice, %1 is the required DMS version").arg(modelData.requires_dms) : modelData.author ? I18n.tr("by %1", "author attribution").arg(modelData.author) : ""
            subtitleColor: compatible ? supportingContentColor : Theme.error

            DActionButton {
                iconName: "open_in_new"
                tooltipText: I18n.tr("View Changes", "open plugin changes before updating")
                visible: !!modelData.diffUrl || !!modelData.repo
                onClicked: Qt.openUrlExternally(modelData.diffUrl || modelData.repo)
            }

            DActionButton {
                iconName: "download"
                tooltipText: I18n.tr("Update", "verb, button installing a newer plugin version")
                enabled: !root.isUpdating && !root.operationsBlocked && compatible
                onClicked: root.updateSingle(modelData)
            }
        }
    }

    SettingsRow {
        visible: !root.isUpdating && root.updatesList.length === 0
        subtitle: I18n.tr("No updates available.")
    }

    SettingsRow {
        visible: !root.isUpdating

        DButton {
            text: I18n.tr("Cancel")
            iconName: "close"
            backgroundColor: "transparent"
            textColor: Theme.primary
            onClicked: root.hide()
        }

        DButton {
            text: I18n.tr("Update All")
            iconName: "download"
            enabled: !root.operationsBlocked && root.updatesList.some(plugin => PluginService.checkPluginCompatibility(plugin.requires_dms))
            onClicked: root.updateAll()
        }
    }
}
