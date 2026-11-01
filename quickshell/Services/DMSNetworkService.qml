pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("DMSNetworkService")

    property bool networkAvailable: false
    property string backend: ""

    property string networkStatus: "disconnected"
    property string primaryConnection: ""

    property string ethernetIP: ""
    property string ethernetInterface: ""
    property bool ethernetConnected: false
    property string ethernetConnectionUuid: ""
    property var ethernetDevices: []

    property var wiredConnections: []

    property string cellularIP: ""
    property string cellularInterface: ""
    property bool cellularConnected: false
    property bool cellularEnabled: true
    property bool cellularHardwareEnabled: true
    property string cellularConnectionUuid: ""
    property var cellularDevices: []
    property var cellularConnections: []

    readonly property var activeCellularDevice: {
        const devices = cellularDevices || [];
        for (const device of devices) {
            if (device.connected) {
                return device;
            }
        }
        return devices.length > 0 ? devices[0] : null;
    }
    readonly property int cellularSignalStrength: activeCellularDevice?.signalQuality ?? 0
    readonly property string cellularAccessTech: activeCellularDevice?.accessTech ?? ""
    readonly property bool cellularAvailable: (cellularDevices?.length ?? 0) > 0
    readonly property string cellularSignalIcon: {
        if (!cellularAvailable || !cellularEnabled || !cellularHardwareEnabled) {
            return "signal_cellular_off";
        }
        // Daemons older than the ModemManager metrics don't send signalQuality.
        if (activeCellularDevice.signalQuality === undefined) {
            return "network_cell";
        }
        if (cellularSignalStrength >= 80) {
            return "signal_cellular_4_bar";
        }
        if (cellularSignalStrength >= 60) {
            return "signal_cellular_3_bar";
        }
        if (cellularSignalStrength >= 40) {
            return "signal_cellular_2_bar";
        }
        if (cellularSignalStrength >= 20) {
            return "signal_cellular_1_bar";
        }
        return "signal_cellular_0_bar";
    }

    property string wifiIP: ""
    property string wifiInterface: ""
    property bool wifiConnected: false
    property bool wifiEnabled: true
    property string wifiConnectionUuid: ""
    property string wifiDevicePath: ""
    property string activeAccessPointPath: ""
    property var wifiDevices: []
    property string wifiDeviceOverride: SessionData.wifiDeviceOverride || ""
    property string connectingDevice: ""

    property string currentWifiSSID: ""
    property int wifiSignalStrength: 0
    property var wifiNetworks: []
    property var savedConnections: []
    property var ssidToConnectionName: ({})
    property var wifiSignalIcon: {
        if (isConnecting) {
            return "wifi";
        }
        if (!wifiConnected) {
            return "wifi_off";
        }
        if (wifiSignalStrength >= 50) {
            return "wifi";
        }
        if (wifiSignalStrength >= 25) {
            return "wifi_2_bar";
        }
        return "wifi_1_bar";
    }

    readonly property string userPreference: SettingsData.networkPreference
    property bool isConnecting: false
    property string connectingSSID: ""
    property string connectionError: ""

    property bool isScanning: false
    property bool autoScan: false

    property bool wifiAvailable: true
    property bool wifiToggling: false
    property bool cellularToggling: false
    property bool changingPreference: false
    property string targetPreference: ""
    property var savedWifiNetworks: []
    readonly property int savedWifiStateApiVersion: 26
    readonly property int hotspotApiVersion: 28
    property bool backendHotspotSupported: false
    property bool backendHotspotAvailable: false
    property bool backendHotspotConfigured: false
    property bool backendHotspotEnabled: false
    property bool backendHotspotActivating: false
    property bool backendHotspotSecured: false
    property string backendHotspotSSID: ""
    property string backendHotspotDevice: ""
    property string backendHotspotBand: ""
    property string backendHotspotLastError: ""
    readonly property bool hotspotSupported: DMSService.isConnected && networkAvailable && DMSService.apiVersion >= hotspotApiVersion && backendHotspotSupported
    readonly property bool hotspotAvailable: hotspotSupported && backendHotspotAvailable
    readonly property bool hotspotConfigured: hotspotSupported && backendHotspotConfigured
    readonly property bool hotspotEnabled: hotspotSupported && backendHotspotEnabled
    readonly property bool hotspotActivating: hotspotSupported && backendHotspotActivating
    readonly property bool hotspotSecured: hotspotSupported && backendHotspotSecured
    readonly property bool hotspotWouldDisconnectWifi: hotspotSupported && !hotspotEnabled && !hotspotActivating && hotspotTargetWouldDisconnectWifi(backendHotspotDevice, backendHotspotBand)
    readonly property string hotspotSSID: hotspotSupported ? backendHotspotSSID : ""
    readonly property string hotspotDevice: hotspotSupported ? backendHotspotDevice : ""
    readonly property string hotspotBand: hotspotSupported ? backendHotspotBand : ""
    property bool hotspotBusy: false
    property string hotspotError: ""
    property string connectionStatus: ""
    property string lastConnectionError: ""
    property bool passwordDialogShouldReopen: false
    property bool autoRefreshEnabled: false
    property string wifiPassword: ""
    property string forgetSSID: ""

    property var vpnProfiles: []
    property var vpnActive: []
    property bool vpnAvailable: false
    property bool vpnIsBusy: false
    property string lastConnectedVpnUuid: ""
    property string pendingVpnUuid: ""
    property var vpnBusyStartTime: 0
    property string vpnError: ""
    property string vpnErrorUuid: ""

    property var profiles: {
        const mergedProfiles = vpnProfiles ? vpnProfiles.slice() : [];
        const seen = new Set();

        for (const profile of mergedProfiles) {
            if (profile?.uuid)
                seen.add("uuid:" + profile.uuid);
            if (profile?.name)
                seen.add("name:" + profile.name);
        }

        for (const active of vpnActive || []) {
            const entryUuid = active?.uuid || active?.name || "";
            const uuidKey = active?.uuid ? "uuid:" + active.uuid : "";
            const nameKey = active?.name ? "name:" + active.name : "";

            if ((uuidKey && seen.has(uuidKey)) || (!uuidKey && nameKey && seen.has(nameKey)))
                continue;

            mergedProfiles.unshift({
                uuid: entryUuid,
                name: active?.name || I18n.tr("Active VPN"),
                serviceType: active?.serviceType || "",
                type: active?.type || "",
                typeLabel: active?.typeLabel || active?.vpnType || "",
                state: active?.state || "",
                device: active?.device || "",
                transient: true,
                canDelete: false,
                canExpand: false
            });

            if (uuidKey)
                seen.add(uuidKey);
            if (nameKey)
                seen.add(nameKey);
        }

        return mergedProfiles;
    }
    property alias activeConnections: root.vpnActive
    property var activeUuids: vpnActive.map(v => v.uuid).filter(u => !!u)
    property var activeNames: vpnActive.map(v => v.name).filter(n => !!n)
    property string activeUuid: activeUuids.length > 0 ? activeUuids[0] : ""
    property string activeName: activeNames.length > 0 ? activeNames[0] : ""
    property string activeDevice: vpnActive.length > 0 ? (vpnActive[0].device || "") : ""
    property string activeState: vpnActive.length > 0 ? (vpnActive[0].state || "") : ""
    property bool vpnConnected: activeUuids.length > 0
    property alias available: root.vpnAvailable
    property alias isBusy: root.vpnIsBusy
    property alias connected: root.vpnConnected

    function vpnStateForUuid(uuid) {
        if (!uuid)
            return "";
        const match = vpnActive.find(v => v.uuid === uuid);
        return match ? (match.state || "") : "";
    }

    function isVpnConnectingUuid(uuid) {
        return vpnStateForUuid(uuid) === "activating" || (vpnIsBusy && pendingVpnUuid === uuid);
    }

    property string networkInfoSSID: ""
    property string networkInfoDetails: ""
    property bool networkInfoLoading: false

    property string networkWiredInfoUUID: ""
    property string networkWiredInfoDetails: ""
    property bool networkWiredInfoLoading: false

    property int refCount: 0
    property bool stateInitialized: false
    property var _lastRawState: null

    property string credentialsToken: ""
    property string credentialsSSID: ""
    property string credentialsSetting: ""
    property var credentialsFields: []
    property var credentialsHints: []
    property string credentialsReason: ""
    property bool credentialsRequested: false

    property string pendingConnectionSSID: ""
    property var pendingConnectionStartTime: 0
    property bool wasConnecting: false

    signal networksUpdated
    signal connectionChanged
    signal credentialsNeeded(string token, string ssid, string setting, var fields, var hints, string reason, string connType, string connName, string vpnService, var fieldsInfo)

    readonly property string socketPath: Quickshell.env("DMS_SOCKET")

    readonly property string effectiveWifiDevice: {
        if (!wifiDeviceOverride)
            return "";
        const deviceExists = wifiDevices.some(d => d.name === wifiDeviceOverride);
        return deviceExists ? wifiDeviceOverride : "";
    }

    Component.onCompleted: {
        lastConnectedVpnUuid = SessionData.vpnLastConnected || "";
        if (socketPath && socketPath.length > 0) {
            checkDMSCapabilities();
        }
    }

    Connections {
        target: DMSService

        function onNetworkStateUpdate(data) {
            const networksCount = data.wifiNetworks?.length ?? "null";
            log.debug("Subscription update received, networks:", networksCount);
            updateState(data);
        }
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (DMSService.isConnected) {
                checkDMSCapabilities();
            }
        }
    }

    Connections {
        target: DMSService
        enabled: DMSService.isConnected

        function onCapabilitiesChanged() {
            checkDMSCapabilities();
        }

        function onCredentialsRequest(data) {
            handleCredentialsRequest(data);
        }
    }

    function checkDMSCapabilities() {
        if (!DMSService.isConnected) {
            return;
        }

        if (DMSService.capabilities.length === 0) {
            return;
        }

        networkAvailable = DMSService.capabilities.includes("network");

        if (networkAvailable && !stateInitialized) {
            stateInitialized = true;
            getState();
        }
    }

    function handleCredentialsRequest(data) {
        credentialsToken = data.token || "";
        credentialsSSID = data.ssid || "";
        credentialsSetting = data.setting || "802-11-wireless-security";
        credentialsFields = data.fields || ["psk"];
        credentialsHints = data.hints || [];
        credentialsReason = data.reason || "Credentials required";
        credentialsRequested = true;

        const connType = data.connType || "";
        const connName = data.name || data.connectionId || "";
        const vpnService = data.vpnService || "";
        const fInfo = data.fieldsInfo || [];

        credentialsNeeded(credentialsToken, credentialsSSID, credentialsSetting, credentialsFields, credentialsHints, credentialsReason, connType, connName, vpnService, fInfo);
    }

    function addRef() {
        refCount++;
        if (refCount !== 1)
            return;
        if (_lastRawState)
            syncLists(_lastRawState);
        if (networkAvailable)
            startAutoScan();
    }

    function removeRef() {
        refCount = Math.max(0, refCount - 1);
        if (refCount === 0) {
            stopAutoScan();
        }
    }

    property bool initialStateFetched: false

    function getState() {
        if (!networkAvailable)
            return;
        DMSService.sendRequest("network.getState", null, response => {
            if (response.result) {
                updateState(response.result);
                if (refCount > 0 && !initialStateFetched && response.result.wifiEnabled && (!response.result.wifiNetworks || response.result.wifiNetworks.length === 0)) {
                    initialStateFetched = true;
                    Qt.callLater(() => scanWifi());
                }
            }
        });
    }

    function keepUnchanged(previous, next) {
        if (!(previous instanceof Array) || !(next instanceof Array))
            return next;
        const byContent = new Map();
        for (const item of previous)
            byContent.set(JSON.stringify(item), item);
        let same = previous.length === next.length;
        const merged = [];
        for (let i = 0; i < next.length; i++) {
            const item = byContent.get(JSON.stringify(next[i])) ?? next[i];
            same = same && item === previous[i];
            merged.push(item);
        }
        return same ? previous : merged;
    }

    function syncLists(state) {
        ethernetDevices = keepUnchanged(ethernetDevices, state.ethernetDevices || []);
        wiredConnections = keepUnchanged(wiredConnections, state.wiredConnections || []);
        cellularDevices = keepUnchanged(cellularDevices, state.cellularDevices || []);
        cellularConnections = keepUnchanged(cellularConnections, state.cellularConnections || []);

        if (state.wifiNetworks) {
            wifiNetworks = keepUnchanged(wifiNetworks, state.wifiNetworks);
        }

        if (!state.wifiNetworks && !state.savedWifiNetworks)
            return;
        const hasSavedWifiState = DMSService.apiVersion >= savedWifiStateApiVersion && state.savedWifiNetworks instanceof Array;
        const sourceSavedNetworks = hasSavedWifiState ? state.savedWifiNetworks : (state.wifiNetworks || []).filter(network => network.saved);
        const normalized = sourceSavedNetworks.map(network => Object.assign({}, network, {
                saved: true,
                outOfRange: hasSavedWifiState ? network.outOfRange === true : false
            }));
        const saved = keepUnchanged(savedWifiNetworks, normalized);
        if (saved !== savedWifiNetworks) {
            const mapping = {};
            for (const network of saved) {
                if (network?.ssid)
                    mapping[network.ssid] = network.ssid;
            }
            savedConnections = saved;
            savedWifiNetworks = saved;
            ssidToConnectionName = mapping;
        }

        networksUpdated();
    }

    function updateState(state) {
        _lastRawState = state;
        const previousConnecting = isConnecting;
        const previousConnectingSSID = connectingSSID;

        backend = state.backend || "";
        vpnAvailable = networkAvailable && backend === "networkmanager";
        networkStatus = state.networkStatus || "disconnected";
        primaryConnection = state.primaryConnection || "";

        ethernetIP = state.ethernetIP || "";
        ethernetInterface = state.ethernetDevice || "";
        ethernetConnected = state.ethernetConnected || false;
        ethernetConnectionUuid = state.ethernetConnectionUuid || "";

        cellularIP = state.cellularIP || "";
        cellularInterface = state.cellularDevice || "";
        cellularConnected = state.cellularConnected || false;
        cellularEnabled = state.cellularEnabled !== undefined ? state.cellularEnabled : true;
        cellularHardwareEnabled = state.cellularHardwareEnabled !== undefined ? state.cellularHardwareEnabled : true;
        cellularConnectionUuid = state.cellularConnectionUuid || "";

        wifiIP = state.wifiIP || "";
        wifiInterface = state.wifiDevice || "";
        wifiConnected = state.wifiConnected || false;
        wifiEnabled = state.wifiEnabled !== undefined ? state.wifiEnabled : true;
        wifiConnectionUuid = state.wifiConnectionUuid || "";
        wifiDevicePath = state.wifiDevicePath || "";
        activeAccessPointPath = state.activeAccessPointPath || "";
        wifiDevices = keepUnchanged(wifiDevices, state.wifiDevices || []);
        connectingDevice = state.connectingDevice || "";

        if (DMSService.apiVersion >= hotspotApiVersion) {
            const supportsHotspot = state.hotspotSupported === true;
            const wasHotspotEnabled = backendHotspotEnabled;
            const wasHotspotActivating = backendHotspotActivating;
            backendHotspotSupported = supportsHotspot;
            backendHotspotAvailable = state.hotspotAvailable === true;
            backendHotspotConfigured = state.hotspotConfigured === true;
            backendHotspotEnabled = state.hotspotEnabled === true;
            backendHotspotActivating = state.hotspotActivating === true;
            backendHotspotSecured = state.hotspotSecured === true;
            backendHotspotSSID = state.hotspotSSID || "";
            backendHotspotDevice = state.hotspotDevice || "";
            backendHotspotBand = state.hotspotBand || "";
            backendHotspotLastError = state.hotspotLastError || "";

            // Activation is asynchronous: only toast outcomes of starts we watched
            // begin, so restoring state after a shell restart stays silent.
            const watchedStart = wasHotspotActivating || hotspotBusy;
            if (watchedStart && !wasHotspotEnabled && backendHotspotEnabled) {
                ToastService.showInfo(I18n.tr("Hotspot started", "hotspot start success message"));
            } else if (wasHotspotActivating && !backendHotspotActivating && !backendHotspotEnabled && backendHotspotLastError) {
                hotspotError = backendHotspotLastError;
                ToastService.showError(I18n.tr("Failed to start hotspot", "hotspot start error title"), hotspotErrorMessage(backendHotspotLastError));
            }
        } else {
            backendHotspotSupported = false;
            backendHotspotAvailable = false;
            backendHotspotConfigured = false;
            backendHotspotEnabled = false;
            backendHotspotActivating = false;
            backendHotspotSecured = false;
            backendHotspotSSID = "";
            backendHotspotDevice = "";
            backendHotspotBand = "";
            backendHotspotLastError = "";
        }

        currentWifiSSID = state.wifiSSID || "";
        wifiSignalStrength = state.wifiSignal || 0;

        if (refCount > 0)
            syncLists(state);

        if (state.vpnProfiles) {
            vpnProfiles = keepUnchanged(vpnProfiles, state.vpnProfiles);
        }

        const previousVpnActive = vpnActive;
        vpnActive = keepUnchanged(vpnActive, state.vpnActive || []);

        if (vpnConnected && activeUuid) {
            lastConnectedVpnUuid = activeUuid;
            SessionData.setVpnLastConnected(activeUuid);
        }

        if (vpnIsBusy) {
            const busyDuration = Date.now() - vpnBusyStartTime;
            const timeout = 30000;

            if (busyDuration > timeout) {
                log.warn("VPN operation timed out after", timeout, "ms");
                vpnIsBusy = false;
                pendingVpnUuid = "";
                vpnBusyStartTime = 0;
            } else if (pendingVpnUuid) {
                const isPendingVpnActive = activeUuids.includes(pendingVpnUuid);
                if (isPendingVpnActive) {
                    vpnIsBusy = false;
                    pendingVpnUuid = "";
                    vpnBusyStartTime = 0;
                }
            } else {
                const previousCount = previousVpnActive ? previousVpnActive.length : 0;
                const currentCount = vpnActive ? vpnActive.length : 0;

                if (previousCount !== currentCount) {
                    vpnIsBusy = false;
                    vpnBusyStartTime = 0;
                }
            }
        }

        const incomingVpnError = state.vpnError || "";
        if (incomingVpnError && incomingVpnError !== vpnError) {
            vpnIsBusy = false;
            pendingVpnUuid = "";
            vpnBusyStartTime = 0;
            const failedName = (vpnProfiles.find(p => p.uuid === state.vpnErrorUuid)?.name) || I18n.tr("VPN", "virtual private network, widget and page title");
            ToastService.showError(I18n.tr("%1: %2", "vpn error toast, %1 is the vpn name, %2 is the error").arg(failedName).arg(incomingVpnError));
        }
        vpnError = incomingVpnError;
        vpnErrorUuid = state.vpnErrorUuid || "";

        isConnecting = state.isConnecting || false;
        connectingSSID = state.connectingSSID || "";
        connectionError = state.lastError || "";
        lastConnectionError = state.lastError || "";

        if (pendingConnectionSSID) {
            if (wifiConnected && currentWifiSSID === pendingConnectionSSID && wifiIP) {
                const elapsed = Date.now() - pendingConnectionStartTime;
                log.info("Successfully connected to", pendingConnectionSSID, "in", elapsed, "ms");
                ToastService.showInfo(I18n.tr("Connected to %1", "wifi toast, %1 is the network name").arg(pendingConnectionSSID));

                if (userPreference === "wifi") {
                    applyNetworkPreference("wifi");
                }

                pendingConnectionSSID = "";
                connectionStatus = "connected";
            } else if (previousConnecting && !isConnecting && !wifiConnected) {
                const isCancellationError = connectionError === "user-canceled";
                const isBadCredentials = connectionError === "bad-credentials";

                if (isCancellationError) {
                    connectionStatus = "cancelled";
                    pendingConnectionSSID = "";
                } else if (isBadCredentials) {
                    connectionStatus = "invalid_password";
                    pendingConnectionSSID = "";
                } else {
                    if (connectionError) {
                        ToastService.showError(I18n.tr("Failed to connect to %1", "wifi error toast, %1 is the network name").arg(pendingConnectionSSID));
                    }
                    connectionStatus = "failed";
                    pendingConnectionSSID = "";
                }
            }
        }

        wasConnecting = isConnecting;

        connectionChanged();
    }

    function connectToSpecificWiredConfig(uuid) {
        if (!networkAvailable || isConnecting)
            return;
        isConnecting = true;
        connectionError = "";
        connectionStatus = "connecting";

        const params = {
            uuid: uuid
        };

        DMSService.sendRequest("network.ethernet.connect.config", params, response => {
            if (response.error) {
                connectionError = response.error;
                lastConnectionError = response.error;
                connectionStatus = "failed";
                ToastService.showError(I18n.tr("Failed to activate configuration"), response.error);
            } else {
                connectionError = "";
                connectionStatus = "connected";
                ToastService.showInfo(I18n.tr("Configuration activated"));
            }

            isConnecting = false;
        });
    }

    function connectCellular() {
        if (!networkAvailable || isConnecting)
            return;
        isConnecting = true;
        connectionError = "";
        connectionStatus = "connecting";

        DMSService.sendRequest("network.cellular.connect", null, response => {
            if (response.error) {
                connectionError = response.error;
                lastConnectionError = response.error;
                connectionStatus = "failed";
                ToastService.showError(I18n.tr("Failed to activate configuration"), response.error);
            } else {
                connectionError = "";
                connectionStatus = "connected";
                ToastService.showInfo(I18n.tr("Configuration activated"));
            }
            isConnecting = false;
        });
    }

    function connectToSpecificCellularConfig(uuid) {
        if (!networkAvailable || isConnecting)
            return;
        isConnecting = true;
        connectionError = "";
        connectionStatus = "connecting";

        DMSService.sendRequest("network.cellular.connect.config", {
            uuid: uuid
        }, response => {
            if (response.error) {
                connectionError = response.error;
                lastConnectionError = response.error;
                connectionStatus = "failed";
                ToastService.showError(I18n.tr("Failed to activate configuration"), response.error);
            } else {
                connectionError = "";
                connectionStatus = "connected";
                ToastService.showInfo(I18n.tr("Configuration activated"));
            }

            isConnecting = false;
        });
    }

    function scanWifi() {
        if (!networkAvailable || isScanning || !wifiEnabled)
            return;
        isScanning = true;
        const params = effectiveWifiDevice ? {
            device: effectiveWifiDevice
        } : null;
        DMSService.sendRequest("network.wifi.scan", params, response => {
            isScanning = false;
            if (response.error) {
                log.warn("WiFi scan failed:", response.error);
            } else {
                Qt.callLater(() => getState());
            }
        });
    }

    function scanWifiNetworks() {
        scanWifi();
    }

    function connectToWifi(ssid, password = "", username = "", anonymousIdentity = "", domainSuffixMatch = "", hidden = false, eapMethod = "", phase2Auth = "") {
        if (!networkAvailable || isConnecting)
            return;
        pendingConnectionSSID = ssid;
        pendingConnectionStartTime = Date.now();
        isConnecting = true;
        connectingSSID = ssid;
        connectionError = "";
        connectionStatus = "connecting";
        credentialsRequested = false;

        const params = {
            ssid: ssid
        };
        if (effectiveWifiDevice)
            params.device = effectiveWifiDevice;
        if (hidden)
            params.hidden = true;
        if (eapMethod)
            params.eapMethod = eapMethod;
        if (phase2Auth)
            params.phase2Auth = phase2Auth;

        if (DMSService.apiVersion >= 7) {
            if (password || username) {
                params.password = password;
                if (username)
                    params.username = username;
                if (anonymousIdentity)
                    params.anonymousIdentity = anonymousIdentity;
                if (domainSuffixMatch)
                    params.domainSuffixMatch = domainSuffixMatch;
                params.interactive = false;
            } else {
                params.interactive = true;
            }
        } else {
            if (password)
                params.password = password;
            if (username)
                params.username = username;
            if (anonymousIdentity)
                params.anonymousIdentity = anonymousIdentity;
            if (domainSuffixMatch)
                params.domainSuffixMatch = domainSuffixMatch;
        }

        DMSService.sendRequest("network.wifi.connect", params, response => {
            if (response.error) {
                if (connectionStatus === "cancelled")
                    return;
                connectionError = response.error;
                lastConnectionError = response.error;
                pendingConnectionSSID = "";
                isConnecting = false;
                connectingSSID = "";
                connectionStatus = "failed";
                ToastService.showError(I18n.tr("Failed to start connection to %1", "wifi error toast, %1 is the network name").arg(ssid));
            }
        });
    }

    function disconnectWifi() {
        if (!networkAvailable || !wifiInterface)
            return;
        const params = effectiveWifiDevice ? {
            device: effectiveWifiDevice
        } : null;
        DMSService.sendRequest("network.wifi.disconnect", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to disconnect WiFi"), response.error);
            } else {
                ToastService.showInfo(I18n.tr("Disconnected from WiFi"));
                currentWifiSSID = "";
                connectionStatus = "";
            }
        });
    }

    function submitCredentials(token, secrets, save) {
        log.debug("submitCredentials: networkAvailable=" + networkAvailable + " apiVersion=" + DMSService.apiVersion);

        if (!networkAvailable || DMSService.apiVersion < 7) {
            log.warn("submitCredentials: Aborting - networkAvailable=" + networkAvailable + " apiVersion=" + DMSService.apiVersion);
            return;
        }

        const params = {
            token: token,
            secrets: secrets,
            save: save || false
        };

        credentialsRequested = false;

        if (credentialsReason === "wrong-password" && credentialsSSID && credentialsSetting === "802-11-wireless-security") {
            pendingConnectionSSID = credentialsSSID;
            pendingConnectionStartTime = Date.now();
            connectionStatus = "connecting";
        }

        DMSService.sendRequest("network.credentials.submit", params, response => {
            if (response.error) {
                log.warn("Failed to submit credentials:", response.error);
            }
        });
    }

    function cancelCredentials(token) {
        if (!networkAvailable || DMSService.apiVersion < 7)
            return;
        const params = {
            token: token
        };

        credentialsRequested = false;
        pendingConnectionSSID = "";
        connectionStatus = "cancelled";

        DMSService.sendRequest("network.credentials.cancel", params, response => {
            if (response.error) {
                log.warn("Failed to cancel credentials:", response.error);
            }
        });
    }

    function forgetWifiNetwork(ssid) {
        if (!networkAvailable)
            return;
        forgetSSID = ssid;
        DMSService.sendRequest("network.wifi.forget", {
            ssid: ssid
        }, response => {
            if (response.error) {
                log.warn("Failed to forget network:", response.error);
            } else {
                ToastService.showInfo(I18n.tr("Forgot network %1", "toast after removing a saved wifi network, %1 is its name").arg(ssid));

                savedConnections = savedConnections.filter(s => s.ssid !== ssid);
                savedWifiNetworks = savedWifiNetworks.filter(s => s.ssid !== ssid);

                if (wifiNetworks.some(network => network.ssid === ssid && network.connected))
                    currentWifiSSID = "";
                wifiNetworks = wifiNetworks.map(network => network.ssid !== ssid ? network : Object.assign({}, network, {
                        saved: false,
                        connected: false
                    }));
                networksUpdated();
                Qt.callLater(() => refreshSavedWifiNetworks());
            }
            forgetSSID = "";
        });
    }

    function toggleWifiRadio() {
        if (!networkAvailable || wifiToggling)
            return;
        wifiToggling = true;
        DMSService.sendRequest("network.wifi.toggle", null, response => {
            wifiToggling = false;

            if (response.error) {
                log.warn("Failed to toggle WiFi:", response.error);
            } else if (response.result) {
                wifiEnabled = response.result.enabled;
                ToastService.showInfo(wifiEnabled ? I18n.tr("WiFi enabled") : I18n.tr("WiFi disabled"));
            }
        });
    }

    function toggleCellularRadio() {
        if (!networkAvailable || cellularToggling)
            return;
        cellularToggling = true;
        DMSService.sendRequest("network.cellular.toggle", null, response => {
            cellularToggling = false;

            if (response.error) {
                ToastService.showError(I18n.tr("Failed to toggle cellular"), response.error);
            } else if (response.result) {
                cellularEnabled = response.result.enabled;
                ToastService.showInfo(cellularEnabled ? I18n.tr("Cellular enabled") : I18n.tr("Cellular disabled"));
            }
        });
    }

    function enableWifiDevice() {
        if (!networkAvailable)
            return;
        DMSService.sendRequest("network.wifi.enable", null, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to enable WiFi"), response.error);
            } else {
                ToastService.showInfo(I18n.tr("WiFi enabled"));
            }
        });
    }

    function setNetworkPreference(preference) {
        if (!networkAvailable)
            return;
        SettingsData.set("networkPreference", preference);
        applyNetworkPreference(preference);
    }

    function applyNetworkPreference(preference) {
        changingPreference = true;
        targetPreference = preference;
        DMSService.sendRequest("network.preference.set", {
            preference: preference
        }, response => {
            changingPreference = false;
            targetPreference = "";

            if (response.error) {
                log.warn("Failed to set network preference:", response.error);
            }
        });
    }

    function toggleNetworkConnection(type) {
        if (!networkAvailable)
            return;
        if (type === "ethernet") {
            if (ethernetConnected) {
                DMSService.sendRequest("network.ethernet.disconnect", null, null);
            } else {
                DMSService.sendRequest("network.ethernet.connect", null, null);
            }
        } else if (type === "cellular") {
            if (cellularConnected) {
                DMSService.sendRequest("network.cellular.disconnect", null, null);
            } else {
                connectCellular();
            }
        }
    }

    function disconnectEthernetDevice(deviceName) {
        if (!networkAvailable)
            return;
        DMSService.sendRequest("network.ethernet.disconnect", {
            device: deviceName
        }, null);
    }

    function disconnectCellularDevice(deviceName) {
        if (!networkAvailable)
            return;
        DMSService.sendRequest("network.cellular.disconnect", {
            device: deviceName
        }, null);
    }

    function startAutoScan() {
        autoScan = true;
        autoRefreshEnabled = true;
        if (networkAvailable && wifiEnabled) {
            scanWifi();
        }
    }

    function stopAutoScan() {
        autoScan = false;
        autoRefreshEnabled = false;
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.autoScan && root.networkAvailable && root.wifiEnabled
        onTriggered: root.scanWifi()
    }

    function fetchWiredNetworkInfo(uuid) {
        if (!networkAvailable)
            return;
        networkWiredInfoUUID = uuid;
        networkWiredInfoLoading = true;
        networkWiredInfoDetails = "Loading network information...";

        DMSService.sendRequest("network.ethernet.info", {
            uuid: uuid
        }, response => {
            networkWiredInfoLoading = false;

            if (response.error) {
                networkWiredInfoDetails = "Failed to fetch network information";
            } else if (response.result) {
                formatWiredNetworkInfo(response.result);
            }
        });
    }

    function formatWiredNetworkInfo(info) {
        let details = "";

        if (!info) {
            details = "Network information not found or network not available.";
        } else {
            details += "Interface: " + info.iface + "\\n";
            details += "Driver: " + info.driver + "\\n";
            details += "MAC Addr: " + info.hwAddr + "\\n";
            details += "Speed: " + info.speed + " Mb/s\\n\\n";

            details += "IPv4 information:\\n";

            for (const ip4 of info.IPv4s.ips) {
                details += "    IPv4 address: " + ip4 + "\\n";
            }
            details += "    Gateway: " + info.IPv4s.gateway + "\\n";
            details += "    DNS: " + info.IPv4s.dns + "\\n";

            if (info.IPv6s.ips) {
                details += "\\nIPv6 information:\\n";

                for (const ip6 of info.IPv6s.ips) {
                    details += "    IPv6 address: " + ip6 + "\\n";
                }
                if (info.IPv6s.gateway.length > 0) {
                    details += "    Gateway: " + info.IPv6s.gateway + "\\n";
                }
                if (info.IPv6s.dns.length > 0) {
                    details += "    DNS: " + info.IPv6s.dns + "\\n";
                }
            }
        }

        networkWiredInfoDetails = details;
    }

    function fetchNetworkInfo(ssid) {
        if (!networkAvailable)
            return;
        networkInfoSSID = ssid;
        networkInfoLoading = true;
        networkInfoDetails = "Loading network information...";

        DMSService.sendRequest("network.info", {
            ssid: ssid
        }, response => {
            networkInfoLoading = false;

            if (response.error) {
                networkInfoDetails = "Failed to fetch network information";
            } else if (response.result) {
                formatNetworkInfo(response.result);
            }
        });
    }

    function formatNetworkInfo(info) {
        let details = "";

        if (!info || !info.bands || info.bands.length === 0) {
            details = "Network information not found or network not available.";
        } else {
            for (const band of info.bands) {
                const freqGHz = band.frequency / 1000;
                let bandName = "Unknown";
                if (band.frequency >= 2400 && band.frequency <= 2500) {
                    bandName = "2.4 GHz";
                } else if (band.frequency >= 5000 && band.frequency <= 6000) {
                    bandName = "5 GHz";
                } else if (band.frequency >= 6000) {
                    bandName = "6 GHz";
                }

                const statusPrefix = band.connected ? "● " : "  ";
                const statusSuffix = band.connected ? " (Connected)" : "";

                details += statusPrefix + bandName + statusSuffix + " - " + band.signal + "%\\n";
                details += "  Channel " + band.channel + " (" + freqGHz.toFixed(1) + " GHz) • " + band.rate + " Mbit/s\\n";
                details += "  BSSID: " + band.bssid + "\\n";
                details += "  Mode: " + band.mode + "\\n";
                details += "  Security: " + (band.secured ? "Secured" : "Open") + "\\n";
                if (band.saved) {
                    details += "  Status: Saved network\\n";
                }
                details += "\\n";
            }
        }

        networkInfoDetails = details;
    }

    function getNetworkInfo(ssid) {
        const network = wifiNetworks.find(n => n.ssid === ssid);
        if (!network) {
            return null;
        }

        return {
            "ssid": network.ssid,
            "signal": network.signal,
            "secured": network.secured,
            "saved": network.saved,
            "connected": network.connected,
            "bssid": network.bssid
        };
    }

    function getWiredNetworkInfo(uuid) {
        const network = wiredConnections.find(n => n.uuid === uuid);
        if (!network) {
            return null;
        }

        return {
            "uuid": uuid
        };
    }

    function refreshVpnProfiles() {
        if (!vpnAvailable)
            return;
        DMSService.sendRequest("network.vpn.profiles", null, response => {
            if (response.result) {
                vpnProfiles = response.result;
            }
        });
    }

    function refreshVpnActive() {
        if (!vpnAvailable)
            return;
        DMSService.sendRequest("network.vpn.active", null, response => {
            if (response.result) {
                vpnActive = response.result;
            }
        });
    }

    function connectVpn(uuidOrName, singleActive = false) {
        if (!vpnAvailable || vpnIsBusy)
            return;
        vpnIsBusy = true;
        pendingVpnUuid = uuidOrName;
        vpnBusyStartTime = Date.now();

        const params = {
            uuidOrName: uuidOrName,
            singleActive: singleActive
        };

        DMSService.sendRequest("network.vpn.connect", params, response => {
            if (response.error) {
                vpnIsBusy = false;
                pendingVpnUuid = "";
                vpnBusyStartTime = 0;
                ToastService.showError(I18n.tr("Failed to connect VPN"), response.error);
            }
        });
    }

    function connect(uuidOrName, singleActive = false) {
        connectVpn(uuidOrName, singleActive);
    }

    function disconnectVpn(uuidOrName) {
        if (!vpnAvailable || vpnIsBusy)
            return;
        vpnIsBusy = true;
        pendingVpnUuid = "";
        vpnBusyStartTime = Date.now();

        const params = {
            uuidOrName: uuidOrName
        };

        DMSService.sendRequest("network.vpn.disconnect", params, response => {
            if (response.error) {
                vpnIsBusy = false;
                vpnBusyStartTime = 0;
                ToastService.showError(I18n.tr("Failed to disconnect VPN"), response.error);
            }
        });
    }

    function disconnect(uuidOrName) {
        disconnectVpn(uuidOrName);
    }

    function disconnectAllVpns() {
        if (!vpnAvailable || vpnIsBusy)
            return;
        vpnIsBusy = true;
        pendingVpnUuid = "";

        DMSService.sendRequest("network.vpn.disconnectAll", null, response => {
            if (response.error) {
                vpnIsBusy = false;
                ToastService.showError(I18n.tr("Failed to disconnect VPNs"), response.error);
            }
        });
    }

    function disconnectAllActive() {
        disconnectAllVpns();
    }

    function toggleVpn(uuid) {
        if (uuid) {
            if (isActiveVpnUuid(uuid)) {
                disconnectVpn(uuid);
            } else {
                connectVpn(uuid);
            }
            return;
        }

        if (vpnConnected) {
            disconnectAllVpns();
            return;
        }

        const targetUuid = lastConnectedVpnUuid || (vpnProfiles.length > 0 ? vpnProfiles[0].uuid : "");
        if (targetUuid) {
            connectVpn(targetUuid);
        }
    }

    function toggle(uuid) {
        toggleVpn(uuid);
    }

    function isActiveVpnUuid(uuid) {
        return activeUuids && activeUuids.indexOf(uuid) !== -1;
    }

    function refreshNetworkState() {
        if (networkAvailable) {
            getState();
        }
    }

    function setWifiDeviceOverride(deviceName) {
        SessionData.setWifiDeviceOverride(deviceName || "");
        if (networkAvailable && wifiEnabled) {
            scanWifi();
        }
    }

    function setWifiAutoconnect(ssid, autoconnect) {
        if (!networkAvailable || DMSService.apiVersion <= 13)
            return;
        const params = {
            ssid: ssid,
            autoconnect: autoconnect
        };

        DMSService.sendRequest("network.wifi.setAutoconnect", params, response => {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to update autoconnect"), response.error);
            } else {
                ToastService.showInfo(autoconnect ? I18n.tr("Autoconnect enabled") : I18n.tr("Autoconnect disabled"));
                Qt.callLater(() => getState());
            }
        });
    }

    function configureHotspot(ssid, password = "", device = "", band = "", callback = null) {
        if (!hotspotSupported || hotspotBusy)
            return false;

        const params = {
            ssid: ssid
        };
        if (password)
            params.password = password;
        if (device)
            params.device = device;
        if (band)
            params.band = band;

        hotspotBusy = true;
        hotspotError = "";

        DMSService.sendRequest("network.hotspot.configure", params, response => {
            hotspotBusy = false;
            if (response.error) {
                hotspotError = response.error;
                ToastService.showError(I18n.tr("Failed to configure hotspot", "hotspot configuration error title"), response.error);
            } else {
                Qt.callLater(() => getState());
            }
            if (callback)
                callback(response);
        });

        return true;
    }

    function startHotspot(callback = null) {
        if (!hotspotAvailable || hotspotBusy)
            return false;

        hotspotBusy = true;
        hotspotError = "";

        DMSService.sendRequest("network.hotspot.start", null, response => {
            hotspotBusy = false;
            if (response.error) {
                hotspotError = response.error;
                ToastService.showError(I18n.tr("Failed to start hotspot", "hotspot start error title"), response.error);
            } else {
                Qt.callLater(() => getState());
            }
            if (callback)
                callback(response);
        });

        return true;
    }

    function stopHotspot(callback = null) {
        if (!hotspotSupported || hotspotBusy)
            return false;

        hotspotBusy = true;
        hotspotError = "";

        DMSService.sendRequest("network.hotspot.stop", null, response => {
            hotspotBusy = false;
            if (response.error) {
                hotspotError = response.error;
                ToastService.showError(I18n.tr("Failed to stop hotspot", "hotspot stop error title"), response.error);
            } else {
                Qt.callLater(() => getState());
            }
            if (callback)
                callback(response);
        });

        return true;
    }

    function configureAndStartHotspot(ssid, password = "", device = "", band = "", callback = null) {
        return configureHotspot(ssid, password, device, band, configureResponse => {
            if (configureResponse.error) {
                if (callback)
                    callback(configureResponse);
                return;
            }
            startHotspot(callback);
        });
    }

    function getHotspotSecrets(callback) {
        if (!hotspotSupported) {
            if (callback)
                callback({
                    error: "hotspot not supported"
                });
            return false;
        }

        DMSService.sendRequest("network.hotspot.getSecrets", null, response => {
            if (callback)
                callback(response);
        });

        return true;
    }

    function hotspotTargetWouldDisconnectWifi(device, band = "") {
        const devices = wifiDevices || [];
        const active = devices.find(d => d.connected);
        if (!active)
            return false;
        if (device) {
            const target = devices.find(d => d.name === device);
            return target ? target.connected : device === active.name;
        }
        // Band capabilities are not exposed per device, so a fixed-band automatic
        // selection cannot safely promise that an idle radio will be usable.
        if (band)
            return true;
        return !devices.some(d => d.apCapable && !d.connected && d.state === "disconnected" && d.name !== active.name);
    }

    function hotspotErrorMessage(code) {
        switch (code) {
        case "hotspot-ip-config-failed":
            return I18n.tr("IP sharing setup failed. Check that %1 is installed.", "hotspot IP configuration failure message, %1 is a package name").arg("dnsmasq");
        case "hotspot-supplicant-failed":
            return I18n.tr("The WiFi adapter could not start access point mode.", "hotspot adapter failure message");
        default:
            return I18n.tr("Hotspot activation failed.", "generic hotspot activation failure message");
        }
    }

    function refreshSavedWifiNetworks() {
        if (!networkAvailable)
            return;

        getState();
    }
}
