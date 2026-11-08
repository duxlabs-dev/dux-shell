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
        } else if (refCount === 0) {
            profilesLoaded = canOperate = grantAvailable = false;
            profiles = [];
            currentProfile = "";
            if (DMSService.activeSubscriptions.includes("tailscale"))
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
    property var prefs: ({})
    property string authUrl: ""
    property bool loginRequested: false
    property bool profilesLoaded: false
    property bool canOperate: false
    property bool grantAvailable: false
    property var profiles: []
    property string currentProfile: ""
    property int profilesRequest: 0
    property bool addPending: false
    property bool addBusy: false
    property bool addAbandoned: false
    property string addReturnProfile: ""
    signal addCompleted
    readonly property bool prefsSupported: DMSService.apiVersion >= 41
    readonly property bool canWritePrefs: available && prefsSupported

    property bool available: false
    property bool stateInitialized: false

    readonly property var allPeersList: {
        const result = [];
        if (selfNode && selfNode.id)
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
        const previousState = backendState;
        backendState = data.backendState || "";
        if (addPending && backendState !== previousState)
            Qt.callLater(loadProfiles);
        magicDnsSuffix = data.magicDnsSuffix || "";
        tailnetName = data.tailnetName || "";
        selfNode = data.self || null;
        peers = data.peers || [];
        exitNodeAllowLanAccess = data.exitNodeAllowLanAccess || false;
        prefs = data.prefs || ({});
        authUrl = data.authUrl || "";
        // Only open a login page the user asked for from DMS.
        if (loginRequested && authUrl !== "") {
            Qt.openUrlExternally(authUrl);
            loginRequested = false;
        } else if (backendState === "Running") {
            loginRequested = false;
        }
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

    function setPrefs(patch, callback) {
        if (!canWritePrefs)
            return false;
        sendAction("tailscale.setPrefs", patch, response => {
            const warning = response.result ? response.result.warning : "";
            if (warning)
                ToastService.showWarning(I18n.tr("Tailscale", "Tailscale mesh VPN widget title"), warning);
            if (callback)
                callback(response);
        });
        return true;
    }

    function login() {
        if (!canWritePrefs)
            return false;
        loginRequested = true;
        sendAction("tailscale.login", {}, r => {
            if (r.error)
                loginRequested = false;
        });
        return true;
    }

    function addProfile(server, callback) {
        if (!canWritePrefs || addBusy)
            return false;
        if (!addPending) {
            addPending = true;
            addReturnProfile = currentProfile;
        }
        addBusy = true;
        loginRequested = true;
        sendAction("tailscale.addProfile", {
            "server": server || ""
        }, r => {
            addBusy = false;
            if (r.error || addAbandoned)
                abandonAdd();
            else
                loadProfiles();
            if (callback)
                callback(r);
        });
        return true;
    }

    // tailscaled stays on the new unsaved profile until its login completes, so give back the account that was active.
    function abandonAdd() {
        if (!addPending)
            return;
        if (addBusy) {
            addAbandoned = true;
            return;
        }
        const id = addReturnProfile;
        addPending = addAbandoned = false;
        addReturnProfile = "";
        loginRequested = false;
        if (id === "" || !canWritePrefs)
            return;
        // Ask tailscaled directly: loadProfiles drops replies once nothing holds a Ref, and a completed login must stay.
        DMSService.sendRequest("tailscale.profiles", {}, response => {
            if (!addPending && response?.result && (response.result.current || "") === "")
                switchProfile(id, () => loadProfiles());
        });
    }

    function logout(callback) {
        if (!canWritePrefs)
            return false;
        loginRequested = false;
        sendAction("tailscale.logout", {}, callback);
        return true;
    }

    function switchProfile(id, callback) {
        if (!canWritePrefs)
            return false;
        loginRequested = false;
        sendAction("tailscale.switchProfile", {
            "id": id
        }, callback);
        return true;
    }

    function removeProfile(id, callback) {
        if (!canWritePrefs)
            return false;
        sendAction("tailscale.removeProfile", {
            "id": id
        }, callback);
        return true;
    }

    function grantOperator(callback) {
        if (!canWritePrefs)
            return false;
        sendAction("tailscale.grantOperator", {}, callback);
        return true;
    }

    function applyProfiles(result) {
        if (!result)
            return;
        profilesLoaded = true;
        canOperate = result.canOperate === true;
        grantAvailable = result.grantAvailable === true;
        profiles = result.profiles || [];
        currentProfile = result.current || "";
        if (addPending && !addBusy && currentProfile !== "" && currentProfile !== addReturnProfile) {
            addPending = false;
            addReturnProfile = "";
            addCompleted();
        }
    }

    // resumeAdd: an add left pending when its page closed is finished if a new account is current, else given up.
    function loadProfiles(resumeAdd) {
        if (!canWritePrefs)
            return;
        const request = ++profilesRequest;
        DMSService.sendRequest("tailscale.profiles", {}, response => {
            if (refCount === 0 || request !== profilesRequest)
                return;
            if (!response || response.error) {
                profilesLoaded = canOperate = false;
                return;
            }
            applyProfiles(response.result);
            if (resumeAdd === true && addPending && !addBusy && currentProfile === "")
                abandonAdd();
        });
    }

    function suggestExitNode(callback) {
        if (!canWritePrefs)
            return false;
        DMSService.sendRequest("tailscale.suggestExitNode", {}, callback);
        return true;
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
