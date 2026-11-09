pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import "../Common/FirewallLabels.js" as FirewallLabels

Singleton {
    id: root
    readonly property var log: Log.scoped("FirewallService")

    readonly property bool available: DMSService.isConnected && DMSService.apiVersion >= 41 && DMSService.capabilities.includes("firewall")

    property int refCount: 0

    property string backend: ""
    property var installed: []
    property bool active: false
    property bool conflict: false
    property bool locked: false
    property string defaultZone: ""
    property var defaults: null
    property var zones: []
    property var rules: []
    property var warnings: []
    property string stateError: ""
    property bool busy: false

    property var services: []
    property bool servicesLoading: false

    readonly property bool isFirewalld: backend === "firewalld"

    onRefCountChanged: syncSubscription()
    onAvailableChanged: syncSubscription()

    function syncSubscription() {
        const subscribed = DMSService.activeSubscriptions.includes("firewall");
        const wanted = refCount > 0 && available;
        if (wanted && !subscribed) {
            DMSService.addSubscription("firewall");
            return;
        }
        if (wanted || !subscribed)
            return;
        DMSService.removeSubscription("firewall");
        updateState({});
        services = [];
    }

    Connections {
        target: DMSService

        function onFirewallStateUpdate(data) {
            root.updateState(data);
        }
    }

    function updateState(data) {
        backend = data.backend || "";
        installed = data.installed || [];
        active = data.active || false;
        conflict = data.conflict || false;
        locked = data.locked || false;
        defaultZone = data.defaultZone || "";
        defaults = data.defaults || null;
        zones = data.zones || [];
        rules = data.rules || [];
        warnings = data.warnings || [];
        stateError = data.error || "";
    }

    function sendAction(method, params, callback) {
        busy = true;
        // Long timeout: wait for 5 minutes, same as polkit prompt expiry time
        DMSService.sendRequest(method, params, response => {
            busy = false;
            if (response.error) {
                root.log.warn(method + " failed: " + response.error);
                ToastService.showError(I18n.tr("Firewall action failed", "toast title when a firewall change is rejected"), response.error);
            }
            if (callback)
                callback(response);
        }, 300000);
    }

    function succeeded(response) {
        return !response.error && response.result?.success !== false;
    }

    function unlock() {
        sendAction("firewall.unlock", null);
    }

    function addRule(params, callback) {
        sendAction("firewall.addRule", params, callback);
    }

    function updateRule(params, callback) {
        sendAction("firewall.updateRule", params, callback);
    }

    function removeRule(zone, id) {
        sendAction("firewall.removeRule", {
            "zone": zone,
            "id": id
        });
    }

    function setDefaults(params, callback) {
        sendAction("firewall.setDefaults", params, callback);
    }

    function setInterfaceZone(iface, zone, callback) {
        sendAction("firewall.setInterfaceZone", {
            "interface": iface,
            "zone": zone
        }, callback);
    }

    function addZone(name, callback) {
        sendAction("firewall.addZone", {
            "name": name
        }, callback);
    }

    function renameZone(name, newName, callback) {
        sendAction("firewall.renameZone", {
            "name": name,
            "newName": newName
        }, callback);
    }

    function removeZone(name) {
        sendAction("firewall.removeZone", {
            "name": name
        });
    }

    function loadServices() {
        if (services.length > 0 || servicesLoading)
            return;
        servicesLoading = true;
        DMSService.sendRequest("firewall.listServices", null, response => {
            root.servicesLoading = false;
            if (root.refCount > 0)
                root.services = response.result || [];
        });
    }

    function findRule(zone, id) {
        const list = isFirewalld ? (zones.find(z => z.name === zone)?.rules ?? []) : rules;
        return list.find(rule => rule.id === id) ?? null;
    }

    function actionLabel(action) {
        switch (action) {
        case "allow":
            return I18n.tr("Allow", "firewall rule action");
        case "drop":
            return I18n.tr("Drop", "firewall rule action");
        case "reject":
            return I18n.tr("Reject", "firewall rule action");
        }
        return "";
    }

    function ruleTarget(rule) {
        if (rule.kind === "port")
            return rule.proto ? rule.target + "/" + rule.proto : rule.target;
        const ports = services.find(s => s.name === rule.target)?.ports ?? [];
        return ports.join(", ");
    }

    function ruleTitle(rule) {
        if (rule.kind === "raw")
            return rule.name || rule.raw;
        const target = ruleTarget(rule);
        const name = rule.name || (rule.kind === "service" ? rule.target : "");
        if (!name)
            return target;
        return target ? name + " (" + target + ")" : name;
    }

    function ruleSource(rule) {
        if (rule.kind === "raw")
            return I18n.tr("Custom rule", "info message when a firewall rule is custom");
        const source = rule.source ? I18n.tr("From %1", "firewall rule source, %1 is an address").arg(rule.source) : I18n.tr("From anywhere");
        return [actionLabel(rule.action), source].filter(part => part).join(" · ");
    }

    function interfaceLabel(name) {
        const custom = SettingsData.firewallInterfaceNames[name];
        if (custom)
            return custom;
        switch (FirewallLabels.interfaceKind(name)) {
        case "tailscale":
            return "Tailscale";
        case "dockerBridge":
            return I18n.tr("Docker bridge", "network interface created by docker");
        case "docker":
            return "Docker";
        case "virtualMachines":
            return I18n.tr("Virtual machines", "network bridge created by libvirt for virtual machines");
        case "wireguard":
            return "WireGuard";
        case "vpn":
            return I18n.tr("VPN", "virtual private network, widget and page title");
        case "wifi":
            return I18n.tr("Wi-Fi", "wireless network, page and section title");
        case "ethernet":
            return I18n.tr("Ethernet");
        case "cellular":
            return I18n.tr("Cellular");
        }
        return "";
    }

    function interfaceTitle(name) {
        const label = interfaceLabel(name);
        return label ? label + " (" + name + ")" : name;
    }

    function setInterfaceLabel(name, label) {
        const names = Object.assign({}, SettingsData.firewallInterfaceNames);
        if (label)
            names[name] = label;
        else
            delete names[name];
        SettingsData.set("firewallInterfaceNames", names);
    }
}
