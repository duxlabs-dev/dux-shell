pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.ControlCenter.Details
import qs.Modules.Settings.Widgets
import qs.Modals.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets

Item {
    id: networkVpnTab

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Component.onCompleted: {
        NetworkService.addRef();
    }

    Component.onDestruction: {
        NetworkService.removeRef();
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            id: root

            property string expandedVpnUuid: ""

            settingKey: "networkVpn"
            tags: ["vpn", "network", "profiles", "import", "openvpn", "wireguard"]

            function openVpnFileBrowser() {
                vpnFileBrowserLoader.active = true;
                if (vpnFileBrowserLoader.item)
                    vpnFileBrowserLoader.item.open();
            }

            property var vpnFileBrowserLoader: LazyLoader {
                active: false

                FileBrowserModal {
                    browserTitle: I18n.tr("Import VPN")
                    bucket: "vpn"
                    filters: VPNService.getFileFilter()
                    onAccepted: paths => VPNService.importVpn(paths[0])
                }
            }

            property var deleteVpnConfirm: ConfirmModal {}

            width: parent.width

            SettingsRow {
                visible: !DMSNetworkService.vpnAvailable
                subtitle: I18n.tr("Unavailable")
            }

            SettingsRow {
                visible: DMSNetworkService.vpnAvailable && DMSNetworkService.profiles.length === 0
                body: Item {
                    width: parent.width
                    height: SettingsMetrics.emptyStateHeight

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DIcon {
                            name: "vpn_key_off"
                            size: 36
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: I18n.tr("No VPN profiles")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        StyledText {
                            text: I18n.tr("Click Import to add a %1 or %2 file", "VPN import hint, %1 and %2 are file extensions").arg(".ovpn").arg(".conf")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }

            Repeater {
                model: DMSNetworkService.vpnAvailable ? DMSNetworkService.profiles : []

                VpnProfileDelegate {
                    required property var modelData

                    profile: modelData
                    isExpanded: root.expandedVpnUuid === modelData.uuid
                    onToggleExpand: {
                        if (root.expandedVpnUuid === modelData.uuid) {
                            root.expandedVpnUuid = "";
                            return;
                        }
                        root.expandedVpnUuid = modelData.uuid;
                        VPNService.getConfig(modelData.uuid);
                    }
                    onDeleteRequested: root.deleteVpnConfirm.showWithOptions({
                        title: I18n.tr("Delete VPN"),
                        message: I18n.tr("Delete \"%1\"?", "delete confirmation, %1 is a vpn profile or printer name").arg(modelData.name),
                        confirmText: I18n.tr("Delete"),
                        confirmColor: Theme.error,
                        onConfirm: () => VPNService.deleteVpn(modelData.uuid)
                    })
                }
            }
        }

        SettingsFabBar {
            shown: DMSNetworkService.vpnAvailable

            DFab {
                text: I18n.tr("Import VPN")
                iconName: "add"
                busy: VPNService.importing
                enabled: !VPNService.importing
                onClicked: root.openVpnFileBrowser()
            }
        }
    }
}
