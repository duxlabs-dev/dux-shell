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
    property string updatingPluginId: ""
    property var updatedPlugins: ({})
    property var updateErrors: ({})
    readonly property int pendingCount: updatesList.filter(plugin => !updatedPlugins[plugin.id]).length

    signal updatesRequested(var plugins)

    iconName: "download"
    title: I18n.tr("Available Updates (%1)", "plugin updates dialog title, %1 is a count").arg(pendingCount)
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
                finishUpdates();
                return;
            }
            const plugin = list[index++];
            updatingPluginId = plugin.id;
            PluginService.updatePlugin(plugin.id, response => {
                if (response.error) {
                    updateErrors = Object.assign({}, updateErrors, {
                        [plugin.id]: response.error
                    });
                    updateNext();
                    return;
                }
                updatedPlugins = Object.assign({}, updatedPlugins, {
                    [plugin.id]: true
                });
                updateNext();
            });
        }
        updateNext();
    }

    function finishUpdates() {
        isUpdating = false;
        updatingPluginId = "";
        updatesList = updatesList.filter(plugin => !updatedPlugins[plugin.id]);
        updatedPlugins = ({});
        if (updatesList.length === 0)
            hide();
        DMSService.listInstalled();
    }

    SettingsNoteRow {
        visible: root.updatesList.length > 0
        text: I18n.tr("Plugin updates can change the code running in your session. Review the changes before updating.", "plugin update audit reminder")
    }

    Repeater {
        model: root.updatesList

        delegate: SettingsRow {
            id: updateRow

            required property var modelData

            readonly property bool compatible: PluginService.checkPluginCompatibility(modelData.requires_dms)
            readonly property bool updating: root.updatingPluginId === modelData.id
            readonly property bool updated: !!root.updatedPlugins[modelData.id]
            readonly property string updateError: root.updateErrors[modelData.id] || ""
            readonly property string requirement: compatible ? "" : I18n.tr("Requires DMS %1", "plugin incompatibility notice, %1 is the required DMS version").arg(modelData.requires_dms)
            readonly property string author: modelData.author ? I18n.tr("by %1", "author attribution").arg(modelData.author) : ""

            iconName: modelData.icon || "extension"
            title: modelData.name || ""
            subtitle: updateError || requirement || author
            subtitleColor: updateError || requirement ? Theme.error : supportingContentColor

            DSpinner {
                size: Theme.iconSize
                visible: updateRow.updating
            }

            DIcon {
                name: "check"
                size: Theme.iconSize
                color: Theme.primary
                visible: updateRow.updated
            }

            DActionButton {
                iconName: "open_in_new"
                tooltipText: I18n.tr("View Changes", "open plugin changes before updating")
                visible: !updateRow.updating && !updateRow.updated && (!!modelData.diffUrl || !!modelData.repo)
                onClicked: Qt.openUrlExternally(modelData.diffUrl || modelData.repo)
            }

            DActionButton {
                iconName: "download"
                tooltipText: I18n.tr("Update", "verb, button installing a newer plugin version")
                visible: !updateRow.updating && !updateRow.updated
                enabled: !root.isUpdating && !root.operationsBlocked && updateRow.compatible
                onClicked: root.updateSingle(modelData)
            }
        }
    }

    SettingsRow {
        visible: root.updatesList.length === 0
        subtitle: I18n.tr("No updates available.")
    }

    SettingsRow {
        DButton {
            text: I18n.tr("Cancel")
            iconName: "close"
            variant: "text"
            enabled: !root.isUpdating && !root.operationsBlocked
            onClicked: root.hide()
        }

        DButton {
            text: I18n.tr("Update All")
            iconName: "download"
            busy: root.isUpdating
            enabled: !root.isUpdating && !root.operationsBlocked && root.updatesList.some(plugin => PluginService.checkPluginCompatibility(plugin.requires_dms))
            onClicked: root.updateAll()
        }
    }
}
