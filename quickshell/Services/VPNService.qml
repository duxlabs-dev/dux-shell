pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("VPNService")

    readonly property bool available: DMSNetworkService.vpnAvailable

    property var plugins: []
    property var allExtensions: []
    property bool importing: false
    property string importError: ""

    property var editConfig: null
    property bool configLoading: false

    property bool pluginsLoading: false

    signal importComplete(string uuid, string name)
    signal configLoaded(var config)
    signal configUpdated
    signal credentialsSet(string uuid)
    signal vpnDeleted(string uuid)

    Component.onCompleted: {
        if (available) {
            fetchPlugins();
        }
    }

    Connections {
        target: DMSNetworkService
        function onVpnAvailableChanged() {
            if (DMSNetworkService.vpnAvailable && plugins.length === 0) {
                fetchPlugins();
            }
        }
    }

    function fetchPlugins() {
        if (!available || pluginsLoading)
            return;
        pluginsLoading = true;

        DMSService.sendRequest("network.vpn.plugins", null, response => {
            pluginsLoading = false;
            if (response.error) {
                log.warn("Failed to fetch plugins:", response.error);
                return;
            }
            if (!response.result)
                return;
            plugins = response.result;
            const extSet = new Set();
            for (const plugin of response.result) {
                for (const ext of plugin.fileExtensions || []) {
                    extSet.add(ext);
                }
            }
            allExtensions = Array.from(extSet);
        });
    }

    function importVpn(filePath, name = "") {
        if (!available || importing)
            return;
        importing = true;
        importError = "";

        const params = {
            file: filePath
        };
        if (name)
            params.name = name;

        DMSService.sendRequest("network.vpn.import", params, response => {
            importing = false;

            if (response.error) {
                importError = response.error;
                ToastService.showError(I18n.tr("Failed to import VPN"), response.error);
                return;
            }

            if (!response.result)
                return;
            if (response.result.success) {
                ToastService.showInfo(I18n.tr("VPN imported: %1", "toast after importing a vpn profile, %1 is its name").arg(response.result.name || ""));
                DMSNetworkService.refreshVpnProfiles();
                importComplete(response.result.uuid || "", response.result.name || "");
                return;
            }

            importError = response.result.error || "Import failed";
            ToastService.showError(I18n.tr("Failed to import VPN"), importError);
        });
    }

    function getConfig(uuidOrName) {
        if (!available)
            return;
        configLoading = true;
        editConfig = null;

        DMSService.sendRequest("network.vpn.getConfig", {
            uuid: uuidOrName
        }, response => {
            configLoading = false;

            if (response.error) {
                ToastService.showError(I18n.tr("Failed to load VPN config"), response.error);
                return;
            }

            if (response.result) {
                editConfig = response.result;
                configLoaded(response.result);
            }
        });
    }

    function updateConfig(uuid, updates) {
        if (!available)
            return;
        const params = {
            uuid: uuid
        };
        if (updates.name !== undefined)
            params.name = updates.name;
        if (updates.autoconnect !== undefined)
            params.autoconnect = updates.autoconnect;
        if (updates.data !== undefined)
            params.data = updates.data;

        DMSService.sendRequest("network.vpn.updateConfig", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to update VPN"), response.error);
                return;
            }
            ToastService.showInfo(I18n.tr("VPN configuration updated"));
            DMSNetworkService.refreshVpnProfiles();
            getConfig(uuid);
            configUpdated();
        });
    }

    function setCredentials(uuid, username, password, save = true) {
        if (!available)
            return;
        const params = {
            uuid: uuid,
            save: save
        };
        if (username)
            params.username = username;
        if (password)
            params.password = password;

        DMSService.sendRequest("network.vpn.setCredentials", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to save VPN credentials"), response.error);
                return;
            }
            ToastService.showInfo(I18n.tr("VPN credentials saved"));
            credentialsSet(uuid);
        });
    }

    function deleteVpn(uuidOrName) {
        if (!available)
            return;
        DMSService.sendRequest("network.vpn.delete", {
            uuid: uuidOrName
        }, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to delete VPN"), response.error);
                return;
            }
            ToastService.showInfo(I18n.tr("VPN deleted"));
            DMSNetworkService.refreshVpnProfiles();
            vpnDeleted(uuidOrName);
        });
    }

    function getFileFilter() {
        // openfortivpn configs are conventionally extensionless, so the browser
        // has to offer every file; core sniffs the contents on import.
        if (allExtensions.length === 0) {
            return ["*.ovpn", "*.conf", "*"];
        }
        return allExtensions.map(e => "*" + e).concat(["*"]);
    }

    function getExtensionsForPlugin(serviceType) {
        const plugin = plugins.find(p => p.serviceType === serviceType);
        if (!plugin)
            return ["*.conf"];
        return (plugin.fileExtensions || [".conf"]).map(e => "*" + e);
    }

    function getPluginName(serviceType) {
        if (!serviceType)
            return "VPN";

        const svc = serviceType.toLowerCase();
        if (svc.includes("protun"))
            return "Proton VPN";
        if (svc.includes("openvpn"))
            return "OpenVPN";
        if (svc.includes("wireguard"))
            return "WireGuard";
        if (svc.includes("openconnect"))
            return "OpenConnect";
        if (svc.includes("fortissl") || svc.includes("forti"))
            return "Fortinet";
        if (svc.includes("strongswan"))
            return "IPsec (strongSwan)";
        if (svc.includes("libreswan"))
            return "IPsec (Libreswan)";
        if (svc.includes("l2tp"))
            return "L2TP/IPsec";
        if (svc.includes("pptp"))
            return "PPTP";
        if (svc.includes("vpnc"))
            return "Cisco (vpnc)";
        if (svc.includes("sstp"))
            return "SSTP";

        const plugin = plugins.find(p => p.serviceType === serviceType);
        if (plugin && plugin.name)
            return plugin.name;

        const parts = serviceType.split('.');
        return parts[parts.length - 1] || "VPN";
    }

    function getVpnTypeFromProfile(profile) {
        if (!profile)
            return "VPN";
        if (profile.typeLabel)
            return profile.typeLabel;
        if (profile.type === "wireguard")
            return "WireGuard";
        return getPluginName(profile.serviceType);
    }
}
