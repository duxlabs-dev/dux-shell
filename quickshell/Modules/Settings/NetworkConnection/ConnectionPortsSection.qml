pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets
import "../../../Common/ConnectionEditor.js" as CE

// Ports are their own profiles, so adding or deleting one is written immediately
// and never touches the controller profile.
SettingsCard {
    id: root

    required property var editor
    readonly property bool valid: true

    readonly property int revision: NetworkService.connectionProfilesRevision
    property var profiles: []
    property bool adding: false

    readonly property var stored: editor.original?.connection ?? {}
    readonly property string controllerUuid: stored.uuid ?? editor.profile?.uuid ?? ""
    readonly property string controllerIfname: stored["interface-name"] ?? ""
    readonly property string controllerType: stored.type ?? editor.profile?.type ?? ""
    readonly property bool locked: editor.readOnly

    readonly property var ports: profiles.filter(p => p.controller && (p.controller === controllerUuid || (controllerIfname !== "" && p.controller === controllerIfname)))
    readonly property var freeDevices: {
        const used = ports.map(p => p.interfaceName || p.device);
        return (NetworkService.ethernetDevices ?? []).filter(d => d.name && d.state !== "unmanaged" && !used.includes(d.name)).map(d => d.name);
    }

    title: I18n.tr("Ports", "interfaces enslaved to a bond or bridge")
    visible: !editor.isNew

    onRevisionChanged: refresh()
    Component.onCompleted: refresh()

    function refresh() {
        NetworkService.listConnections(response => {
            if (!response.error)
                profiles = response.result ?? [];
        });
    }

    function addPort(device) {
        if (!freeDevices.includes(device) || controllerUuid === "")
            return;
        const settings = CE.newPortSettings({
            "uuid": controllerUuid,
            "ifname": controllerIfname,
            "id": stored.id ?? editor.profile?.id ?? "",
            "type": controllerType
        }, device, stored.autoconnect !== false);
        adding = true;
        NetworkService.addConnection(settings, true, response => {
            adding = false;
            if (response?.error)
                ToastService.showError(I18n.tr("Failed to add port", "toast title when adding a bond, bridge or team port fails"), response.error);
        });
    }

    ConfirmModal {
        id: forgetConfirm
    }

    Repeater {
        model: root.ports

        delegate: SettingsRow {
            id: portRow

            required property var modelData

            title: modelData.id
            subtitle: modelData.active ? (modelData.interfaceName ?? "") + " • " + I18n.tr("Connected") : (modelData.interfaceName ?? "")
            iconName: "lan"

            DActionButton {
                visible: !root.locked
                iconName: "tune"
                tooltipText: I18n.tr("Configure")
                onClicked: {
                    if (root.editor.dirty) {
                        ToastService.showWarning(I18n.tr("Unsaved changes"));
                        return;
                    }
                    SettingsUiState.selectConnection(portRow.modelData.uuid, portRow.modelData.id, "");
                }
            }

            DActionButton {
                visible: !root.locked
                iconName: "delete"
                iconColor: Theme.error
                tooltipText: I18n.tr("Delete")
                onClicked: {
                    const port = portRow.modelData;
                    forgetConfirm.showWithOptions({
                        title: I18n.tr("Forget"),
                        message: I18n.tr("Forget \"%1\"?").arg(port.id),
                        confirmText: I18n.tr("Forget"),
                        danger: true,
                        onConfirm: () => NetworkService.deleteConnection(port.uuid, response => {
                            if (response?.error)
                                ToastService.showError(I18n.tr("Failed to forget %1", "toast title, %1 is a network connection name").arg(port.id), response.error);
                        })
                    });
                }
            }
        }
    }

    SettingsRow {
        id: addRow

        visible: !root.locked && root.freeDevices.length > 0
        title: I18n.tr("Add")

        DDropdown {
            anchors.verticalCenter: parent.verticalCenter
            backgroundColor: SettingsMetrics.controlSurface
            compactMode: true
            enabled: !root.adding
            options: root.freeDevices
            emptyText: I18n.tr("Select", "verb, dropdown placeholder or option that opens a picker")
            onValueChanged: value => {
                currentValue = "";
                if (value)
                    root.addPort(value);
            }
        }
    }
}
