pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

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

    function unlock() {
        sendAction("firewall.unlock", null);
    }

    function addRule(params, callback) {
        sendAction("firewall.addRule", params, callback);
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

    function listServices(callback) {
        DMSService.sendRequest("firewall.listServices", null, response => callback(response.result || []));
    }
}
