pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root
    readonly property var log: Log.scoped("TailscaleService")

    property int refCount: 0

    onRefCountChanged: {
        if (refCount > 0) {
            ensureSubscription();
        } else if (refCount === 0 && DMSService.activeSubscriptions.includes("tailscale")) {
            DMSService.removeSubscription("tailscale");
        }
    }

    function ensureSubscription() {
        if (refCount <= 0)
            return;
        if (!DMSService.isConnected)
            return;
        if (DMSService.activeSubscriptions.includes("tailscale"))
            return;
        if (DMSService.activeSubscriptions.includes("all"))
            return;
        DMSService.addSubscription("tailscale");
        if (available) {
            getStatus();
        }
    }

    property bool connected: false
    property string version: ""
    property string backendState: ""
    property string magicDnsSuffix: ""
    property string tailnetName: ""
    property var selfNode: null
    property var peers: []
    property bool exitNodeAllowLanAccess: false

    property bool available: false
    property bool stateInitialized: false

    readonly property var allPeersList: {
        const result = [];
        if (selfNode)
            result.push(selfNode);
        if (peers)
            result.push(...peers);
        return result;
    }

    readonly property var onlinePeers: allPeersList.filter(p => p.online)

    // Peers that may be used as an exit node (offered && approved). Self is
    // excluded: a node can never route through itself, and tailscaled rejects it.
    readonly property var exitNodeOptions: allPeersList.filter(p => p && p.exitNodeOption && p !== selfNode)

    // The currently selected exit node, or null if none is in use.
    readonly property var currentExitNode: {
        for (const p of allPeersList) {
            if (p && p.exitNode)
                return p;
        }
        return null;
    }

    readonly property var myPeers: {
        if (!selfNode)
            return allPeersList;
        return allPeersList.filter(p => isMine(p));
    }

    readonly property var myOnlinePeers: {
        if (!selfNode)
            return onlinePeers;
        return allPeersList.filter(p => p.online && isMine(p));
    }

    readonly property int onlinePeerCount: onlinePeers.length

    readonly property string socketPath: Quickshell.env("DMS_SOCKET")

    Component.onCompleted: {
        if (socketPath && socketPath.length > 0) {
            checkDMSCapabilities();
        }
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                checkDMSCapabilities();
                ensureSubscription();
            }
        }
    }

    Connections {
        target: DMSService
        enabled: DMSService.isConnected

        function onTailscaleStateUpdate(data) {
            root.log.debug("Subscription update received");
            updateState(data);
        }

        function onCapabilitiesReceived() {
            checkDMSCapabilities();
        }
    }

    function checkDMSCapabilities() {
        if (!DMSService.isConnected)
            return;
        if (DMSService.capabilities.length === 0)
            return;
        const wasAvailable = available;
        available = DMSService.capabilities.includes("tailscale");

        if (!available)
            return;
        if (refCount > 0 && !stateInitialized) {
            stateInitialized = true;
            getStatus();
        }
        if (!wasAvailable)
            ensureSubscription();
    }

    function getStatus() {
        if (!available)
            return;
        DMSService.sendRequest("tailscale.getStatus", null, response => {
            if (response.result) {
                updateState(response.result);
            }
        });
    }

    function updateState(data) {
        if (!data)
            return;
        connected = data.connected || false;
        version = data.version || "";
        backendState = data.backendState || "";
        magicDnsSuffix = data.magicDnsSuffix || "";
        tailnetName = data.tailnetName || "";
        selfNode = data.self || null;
        peers = data.peers || [];
        exitNodeAllowLanAccess = data.exitNodeAllowLanAccess || false;
    }

    function refresh(callback) {
        if (!available)
            return;
        DMSService.sendRequest("tailscale.refresh", null, response => {
            if (callback)
                callback(response);
        });
    }

    // sendAction issues a state-changing request. The backend refreshes and
    // broadcasts on success, so subscribers update without an extra getStatus.
    function sendAction(method, params, callback) {
        if (!available)
            return;
        DMSService.sendRequest(method, params, response => {
            if (response.error) {
                root.log.warn(method + " failed: " + response.error);
                ToastService.showError(I18n.tr("Tailscale action failed", "Toast shown when a Tailscale write action is rejected"), response.error);
            }
            if (callback)
                callback(response);
        });
    }

    function connectTailscale(callback) {
        sendAction("tailscale.connect", null, callback);
    }

    function disconnectTailscale(callback) {
        sendAction("tailscale.disconnect", null, callback);
    }

    function setExitNode(id, callback) {
        sendAction("tailscale.setExitNode", {
            "id": id || ""
        }, callback);
    }

    function clearExitNode(callback) {
        setExitNode("", callback);
    }

    function setAllowLanAccess(enabled, callback) {
        sendAction("tailscale.setAllowLanAccess", {
            "enabled": enabled
        }, callback);
    }

    function isMine(peer) {
        if (!peer)
            return false;
        if (selfNode && (peer === selfNode || peer.id === selfNode.id))
            return true;
        const myOwner = selfNode ? (selfNode.owner || "") : "";
        if (peer.owner === myOwner && myOwner !== "")
            return true;
        if (peer.tags && peer.tags.length > 0)
            return true;
        return false;
    }

    function searchPeers(query, list) {
        const base = list || allPeersList;
        if (!query || query.length === 0)
            return base;
        const q = query.toLowerCase();
        return base.filter(p => {
            if (p.hostname && p.hostname.toLowerCase().includes(q))
                return true;
            if (p.dnsName && p.dnsName.toLowerCase().includes(q))
                return true;
            if (p.tailscaleIp && p.tailscaleIp.includes(q))
                return true;
            if (p.os && p.os.toLowerCase().includes(q))
                return true;
            return false;
        });
    }
}
