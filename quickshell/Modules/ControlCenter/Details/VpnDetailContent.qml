pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modals.Common
import qs.Modals.FileBrowser
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var parentPopout: null
    property string expandedUuid: ""
    property int listHeight: -1

    readonly property string title: I18n.tr("VPN", "virtual private network, widget and page title")
    readonly property bool fillsParent: listHeight <= 0
    readonly property bool hasProfiles: DMSNetworkService.profiles.length > 0

    readonly property Item headerActions: Row {
        spacing: Theme.spacingS

        DButton {
            anchors.verticalCenter: parent.verticalCenter
            buttonHeight: Theme.buttonHeightXS
            iconName: VPNService.importing ? "sync" : "add"
            iconSize: Theme.iconSizeSmall
            text: I18n.tr("Import", "verb, button that imports a vpn profile file")
            variant: "tonal"
            enabled: !VPNService.importing
            onClicked: root.openFileBrowser()
        }

        CcSettingsButton {
            anchors.verticalCenter: parent.verticalCenter
            settingsTab: "network_vpn"
            parentPopout: root.parentPopout
        }
    }

    implicitHeight: fillsParent ? 0 : statusGroup.height + column.spacing + listHeight

    function closeHost() {
        if (parentPopout)
            parentPopout.close();
        else
            PopoutService.closeControlCenter();
    }

    function openFileBrowser() {
        fileBrowserLoader.active = true;
        const browser = fileBrowserLoader.item;
        if (!browser)
            return;
        browser.open();
    }

    function confirmDelete(profile) {
        deleteConfirmLoader.active = true;
        const confirm = deleteConfirmLoader.item;
        if (!confirm)
            return;
        confirm.showWithOptions({
            "title": I18n.tr("Delete VPN"),
            "message": I18n.tr("Delete \"%1\"?").arg(profile.name),
            "confirmText": I18n.tr("Delete"),
            "danger": true,
            "onConfirm": () => VPNService.deleteVpn(profile.uuid)
        });
    }

    Loader {
        id: fileBrowserLoader
        active: false
        sourceComponent: FileBrowserSurfaceModal {
            browserTitle: I18n.tr("Import VPN")
            bucket: "vpn"
            filters: VPNService.getFileFilter()
            parentPopout: root.parentPopout
            onAccepted: paths => VPNService.importVpn(paths[0])
        }
    }

    Loader {
        id: deleteConfirmLoader
        active: false
        sourceComponent: ConfirmModal {}
    }

    Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: CcMetrics.detailContentGap

        CcGroup {
            id: statusGroup

            CcListRow {
                iconName: "vpn_key"
                iconColor: DMSNetworkService.connected ? Theme.primary : Theme.surfaceText
                title: {
                    if (!DMSNetworkService.connected)
                        return I18n.tr("Active: None");
                    const names = DMSNetworkService.activeNames || [];
                    if (names.length <= 1)
                        return I18n.tr("Active: %1", "vpn status line, %1 is the active connection name").arg(names[0] || "VPN");
                    return I18n.tr("Active: %1 +%2", "vpn status, %1 is a connection name, %2 counts the others").arg(names[0]).arg(names.length - 1);
                }

                DButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: DMSNetworkService.connected
                    buttonHeight: Theme.buttonHeightXS
                    iconName: "link_off"
                    iconSize: Theme.iconSizeSmall
                    text: I18n.tr("Disconnect", "verb, button or menu action for network, vpn or bluetooth")
                    backgroundColor: Theme.errorHover
                    textColor: Theme.error
                    enabled: !DMSNetworkService.isBusy
                    onClicked: DMSNetworkService.disconnectAllActive()
                }
            }
        }

        Item {
            width: parent.width
            height: root.fillsParent ? Math.max(0, root.height - statusGroup.height - column.spacing) : root.listHeight

            CcEmptyState {
                anchors.centerIn: parent
                visible: !root.hasProfiles
                iconName: "vpn_key_off"
                title: I18n.tr("No VPN profiles")
                subtitle: DMSNetworkService.vpnAvailable ? I18n.tr("Add a profile in Settings", "VPN empty state hint, the button below opens Settings") : ""

                DButton {
                    visible: DMSNetworkService.vpnAvailable
                    anchors.horizontalCenter: parent.horizontalCenter
                    buttonHeight: Theme.buttonHeightXS
                    iconName: "settings"
                    iconSize: Theme.iconSizeSmall
                    text: I18n.tr("Settings")
                    variant: "tonal"
                    onClicked: {
                        root.closeHost();
                        PopoutService.openSettingsWithTab("network_vpn");
                    }
                }
            }

            DListView {
                id: vpnListView
                anchors.fill: parent
                visible: root.hasProfiles
                spacing: Theme.groupedListGap
                clip: true

                model: ScriptModel {
                    values: DMSNetworkService.profiles
                    objectProp: "uuid"
                }

                delegate: VpnProfileDelegate {
                    required property var modelData
                    required property int index

                    width: vpnListView.width
                    profile: modelData
                    showsEditButton: NetworkService.connectionEditorSupported
                    onEditRequested: {
                        root.closeHost();
                        PopoutService.openConnectionEditor(modelData.uuid, modelData.name);
                    }
                    isExpanded: root.expandedUuid === modelData.uuid
                    topRadius: index === 0 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                    bottomRadius: index === vpnListView.count - 1 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
                    onToggleExpand: {
                        if (root.expandedUuid === modelData.uuid) {
                            root.expandedUuid = "";
                            return;
                        }
                        root.expandedUuid = modelData.uuid;
                        VPNService.getConfig(modelData.uuid);
                    }
                    onDeleteRequested: root.confirmDelete(modelData)
                }
            }
        }
    }
}
