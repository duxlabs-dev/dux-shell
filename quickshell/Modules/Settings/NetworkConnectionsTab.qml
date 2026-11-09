pragma ComponentBehavior: Bound

import QtQuick
import "../../Common/ConnectionEditor.js" as CE
import qs.Common
import qs.Modals.Common
import qs.Modules.Network
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    property var parentModal: null
    property var profiles: []
    property bool loaded: false
    property var duplicateSource: null
    readonly property int revision: NetworkService.connectionProfilesRevision
    readonly property var groups: CE.groupProfiles(profiles, NetworkService.hotspotUuid)
    readonly property var groupIcons: ({
            "hotspot": "wifi_tethering",
            "vpn": "vpn_key",
            "cellular": "signal_cellular_alt",
            "other": "settings_ethernet"
        })

    VpnImportBrowser {
        id: importBrowser
    }

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    onRevisionChanged: refresh()

    Component.onCompleted: {
        NetworkService.addRef();
        NetworkService.probeExternalConnectionEditor();
        refresh();
    }

    Component.onDestruction: NetworkService.removeRef()

    function refresh() {
        NetworkService.listConnections(response => {
            if (!response.error)
                profiles = response.result || [];
            loaded = true;
        });
    }

    function groupTitle(group) {
        switch (group) {
        case "ethernet":
            return I18n.tr("Ethernet");
        case "wifi":
            return I18n.tr("Wi-Fi");
        case "hotspot":
            return I18n.tr("Hotspot", "settings page title for the Wi-Fi hotspot");
        case "vpn":
            return I18n.tr("VPN");
        case "cellular":
            return I18n.tr("Cellular");
        }
        return I18n.tr("Other");
    }

    function profileIcon(profile, group) {
        return group === "hotspot" ? groupIcons.hotspot : CE.typeInfo(profile.type)?.icon ?? groupIcons[group] ?? "settings_ethernet";
    }

    function subtitleFor(profile) {
        if (profile.activeState === "activating")
            return I18n.tr("Connecting...");
        if (profile.active)
            return profile.device ? I18n.tr("Connected") + " • " + profile.device : I18n.tr("Connected");
        switch (CE.lastUsed(profile.timestamp, Date.now() / 1000)) {
        case "never":
            return I18n.tr("Never used");
        case "today":
            return I18n.tr("Today");
        case "yesterday":
            return I18n.tr("Yesterday");
        }
        return Qt.formatDate(new Date(profile.timestamp * 1000), Locale.ShortFormat);
    }

    function openEditor(uuid, title, type) {
        SettingsUiState.selectConnection(uuid, title, type);
        parentModal?.navigateTo("network_connection");
    }

    function addConnection() {
        const wired = NetworkService.ethernetDevices.length > 0;
        openEditor("", I18n.tr("Add connection", "settings page title while creating a new network connection profile"), wired ? "802-3-ethernet" : "802-11-wireless");
    }

    function reportError(title, response) {
        if (response?.error)
            ToastService.showError(title, response.error);
    }

    ConfirmModal {
        id: forgetConfirm
    }

    SettingsRenameDialog {
        id: duplicateDialog
        parent: root.parentModal?.modalFocusScope ?? root
        title: I18n.tr("Duplicate")
        leftIconName: "content_copy"
        onAccepted: name => {
            const source = root.duplicateSource;
            hide();
            if (source)
                NetworkService.duplicateConnection(source.uuid, name, response => root.reportError(I18n.tr("Failed to duplicate %1", "toast title, %1 is a network connection name").arg(name), response));
        }
    }

    component ProfileRow: SettingsRow {
        id: profileRow

        required property var profile
        required property string group
        readonly property bool isHotspot: !!NetworkService.hotspotUuid && profile.uuid === NetworkService.hotspotUuid
        readonly property bool supported: CE.isSupported(profile.type, profile.controller ? profile.portType : "")
        readonly property bool openable: supported && (!isHotspot || NetworkService.hotspotAvailable)

        readonly property bool deviceAvailable: {
            switch (profile.type) {
            case "802-3-ethernet":
                return (NetworkService.ethernetDevices?.length ?? 0) > 0;
            case "802-11-wireless":
                return NetworkService.wifiDevicePresent;
            case "gsm":
                return (NetworkService.cellularDevices?.length ?? 0) > 0;
            }
            return true;
        }

        title: profile.id
        subtitle: root.subtitleFor(profile) + (supported ? "" : " • " + I18n.tr("Not supported in Settings", "network connection list and editor: this connection type can only be edited in another tool"))
        iconName: root.profileIcon(profile, group)
        active: profile.active
        clickable: openable
        showChevron: openable
        onClicked: {
            if (!isHotspot)
                return root.openEditor(profile.uuid, profile.id, "");
            root.parentModal?.navigateTo("network_hotspot");
        }

        DActionButton {
            visible: !profileRow.isHotspot && (profileRow.profile.active || profileRow.deviceAvailable)
            iconName: profileRow.profile.active ? "link_off" : "link"
            tooltipText: profileRow.profile.active ? I18n.tr("Disconnect") : I18n.tr("Connect")
            onClicked: {
                if (profileRow.profile.active)
                    NetworkService.deactivateConnection(profileRow.profile.uuid);
                else
                    NetworkService.activateConnection(profileRow.profile.uuid, "");
            }
        }

        DActionButton {
            visible: profileRow.profile.canModify && !profileRow.isHotspot
            iconName: "content_copy"
            tooltipText: I18n.tr("Duplicate")
            onClicked: {
                root.duplicateSource = profileRow.profile;
                duplicateDialog.show(profileRow.profile.id);
            }
        }

        DActionButton {
            visible: profileRow.profile.canModify
            iconName: "delete"
            iconColor: Theme.error
            tooltipText: I18n.tr("Forget")
            onClicked: forgetConfirm.showWithOptions({
                title: I18n.tr("Forget"),
                message: I18n.tr("Forget \"%1\"?").arg(profileRow.profile.id),
                confirmText: I18n.tr("Forget"),
                danger: true,
                onConfirm: () => NetworkService.deleteConnection(profileRow.profile.uuid, response => root.reportError(I18n.tr("Failed to forget %1", "toast title, %1 is a network connection name").arg(profileRow.profile.id), response))
            })
        }

        DActionButton {
            visible: !profileRow.supported && NetworkService.externalConnectionEditor !== ""
            iconName: "open_in_new"
            tooltipText: I18n.tr("Open in %1", "%1 is an application name").arg(NetworkService.externalConnectionEditor)
            onClicked: NetworkService.openExternalConnectionEditor(profileRow.profile.uuid)
        }
    }

    SettingsPage {
        id: page

        // Static so the search extractor sees a literal settingKey; it stays visible so search can land here.
        SettingsCard {
            title: root.groups.length > 0 ? root.groupTitle(root.groups[0].group) : ""
            settingKey: "networkConnections"
            tags: ["connections", "profiles", "ipv4", "ipv6", "dns", "static ip", "gateway", "routes", "mac", "mtu", "metered", "firewall", "zone", "802.1x", "wired", "wifi", "vlan", "bond", "bridge", "ports", "pppoe", "dsl", "apn", "mobile broadband", "bluetooth"]

            SettingsRow {
                visible: root.loaded && root.groups.length === 0
                title: I18n.tr("No profiles")
            }

            Repeater {
                model: root.groups.length > 0 ? root.groups[0].profiles : []

                delegate: ProfileRow {
                    required property var modelData
                    profile: modelData
                    group: root.groups[0].group
                }
            }
        }

        Repeater {
            model: root.groups.slice(1)

            delegate: SettingsCard {
                id: groupCard

                required property var modelData

                width: parent.width
                title: root.groupTitle(modelData.group)

                Repeater {
                    model: groupCard.modelData.profiles

                    delegate: ProfileRow {
                        required property var modelData
                        profile: modelData
                        group: groupCard.modelData.group
                    }
                }
            }
        }

        SettingsFabBar {
            DFab {
                text: I18n.tr("Add")
                iconName: "add"
                onClicked: root.addConnection()
            }

            DFab {
                visible: DMSNetworkService.vpnAvailable
                text: I18n.tr("Import", "verb, button that imports a vpn profile file")
                iconName: "upload_file"
                colorRole: "secondaryContainer"
                busy: VPNService.importing
                enabled: !VPNService.importing
                onClicked: importBrowser.open()
            }
        }
    }
}
