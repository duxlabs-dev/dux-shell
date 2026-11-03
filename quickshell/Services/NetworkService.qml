pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("NetworkService")

    property bool networkAvailable: activeService !== null
    property string backend: activeService?.backend ?? ""
    property string networkStatus: activeService?.networkStatus ?? "disconnected"
    property string primaryConnection: activeService?.primaryConnection ?? ""

    property string ethernetIP: activeService?.ethernetIP ?? ""
    property string ethernetInterface: activeService?.ethernetInterface ?? ""
    property bool ethernetConnected: activeService?.ethernetConnected ?? false
    property string ethernetConnectionUuid: activeService?.ethernetConnectionUuid ?? ""
    property var ethernetDevices: activeService?.ethernetDevices ?? []

    property var wiredConnections: activeService?.wiredConnections ?? []

    property string cellularIP: activeService?.cellularIP ?? ""
    property string cellularInterface: activeService?.cellularInterface ?? ""
    property bool cellularConnected: activeService?.cellularConnected ?? false
    property bool cellularEnabled: activeService?.cellularEnabled ?? true
    property bool cellularHardwareEnabled: activeService?.cellularHardwareEnabled ?? true
    property string cellularConnectionUuid: activeService?.cellularConnectionUuid ?? ""
    property var cellularDevices: activeService?.cellularDevices ?? []
    property var cellularConnections: activeService?.cellularConnections ?? []
    property bool cellularAvailable: activeService?.cellularAvailable ?? false
    property int cellularSignalStrength: activeService?.cellularSignalStrength ?? 0
    property string cellularAccessTech: activeService?.cellularAccessTech ?? ""
    property string cellularSignalIcon: activeService?.cellularSignalIcon ?? "signal_cellular_off"

    property string wifiIP: activeService?.wifiIP ?? ""
    property string wifiInterface: activeService?.wifiInterface ?? ""
    property bool wifiConnected: activeService?.wifiConnected ?? false
    property bool wifiEnabled: activeService?.wifiEnabled ?? true
    property string wifiConnectionUuid: activeService?.wifiConnectionUuid ?? ""
    property string wifiDevicePath: activeService?.wifiDevicePath ?? ""
    property string activeAccessPointPath: activeService?.activeAccessPointPath ?? ""
    property var wifiDevices: activeService?.wifiDevices ?? []
    property string wifiDeviceOverride: activeService?.wifiDeviceOverride ?? ""
    property string connectingDevice: activeService?.connectingDevice ?? ""

    property string currentWifiSSID: activeService?.currentWifiSSID ?? ""
    property int wifiSignalStrength: activeService?.wifiSignalStrength ?? 0
    property var wifiNetworks: activeService?.wifiNetworks ?? []
    property var savedConnections: activeService?.savedConnections ?? []
    property var ssidToConnectionName: activeService?.ssidToConnectionName ?? ({})
    property var wifiSignalIcon: activeService?.wifiSignalIcon ?? "wifi_off"

    property string userPreference: activeService?.userPreference ?? "auto"
    property bool isConnecting: activeService?.isConnecting ?? false
    readonly property bool isWifiConnecting: isConnecting && !ethernetConnected && !wifiToggling
    property string connectingSSID: activeService?.connectingSSID ?? ""
    property string connectionError: activeService?.connectionError ?? ""

    property bool isScanning: activeService?.isScanning ?? false
    property bool autoScan: activeService?.autoScan ?? false

    property bool wifiAvailable: activeService?.wifiAvailable ?? true
    property bool wifiToggling: activeService?.wifiToggling ?? false
    property bool cellularToggling: activeService?.cellularToggling ?? false
    property bool changingPreference: activeService?.changingPreference ?? false
    property string targetPreference: activeService?.targetPreference ?? ""
    property var savedWifiNetworks: activeService?.savedWifiNetworks ?? []
    readonly property int savedWifiStateApiVersion: activeService?.savedWifiStateApiVersion ?? 26
    readonly property int hotspotApiVersion: activeService?.hotspotApiVersion ?? 28
    property bool hotspotSupported: activeService?.hotspotSupported ?? false
    property bool hotspotAvailable: activeService?.hotspotAvailable ?? false
    property bool hotspotConfigured: activeService?.hotspotConfigured ?? false
    property bool hotspotEnabled: activeService?.hotspotEnabled ?? false
    property bool hotspotActivating: activeService?.hotspotActivating ?? false
    property bool hotspotSecured: activeService?.hotspotSecured ?? false
    property bool hotspotWouldDisconnectWifi: activeService?.hotspotWouldDisconnectWifi ?? false
    property string hotspotSSID: activeService?.hotspotSSID ?? ""
    property string hotspotDevice: activeService?.hotspotDevice ?? ""
    property string hotspotBand: activeService?.hotspotBand ?? ""
    property bool hotspotBusy: activeService?.hotspotBusy ?? false
    property string hotspotError: activeService?.hotspotError ?? ""
    property string connectionStatus: activeService?.connectionStatus ?? ""
    property string lastConnectionError: activeService?.lastConnectionError ?? ""
    property bool passwordDialogShouldReopen: activeService?.passwordDialogShouldReopen ?? false
    property bool autoRefreshEnabled: activeService?.autoRefreshEnabled ?? false
    property string wifiPassword: activeService?.wifiPassword ?? ""
    property string forgetSSID: activeService?.forgetSSID ?? ""

    property string networkInfoSSID: activeService?.networkInfoSSID ?? ""
    property string networkInfoDetails: activeService?.networkInfoDetails ?? ""
    property bool networkInfoLoading: activeService?.networkInfoLoading ?? false

    property string networkWiredInfoUUID: activeService?.networkWiredInfoUUID ?? ""
    property string networkWiredInfoDetails: activeService?.networkWiredInfoDetails ?? ""
    property bool networkWiredInfoLoading: activeService?.networkWiredInfoLoading ?? false

    property int refCount: activeService?.refCount ?? 0
    property bool stateInitialized: activeService?.stateInitialized ?? false

    property bool subscriptionConnected: activeService?.subscriptionConnected ?? false

    property var vpnProfiles: activeService?.vpnProfiles ?? []
    property var vpnActive: activeService?.vpnActive ?? []
    property bool vpnAvailable: activeService?.vpnAvailable ?? false
    property bool vpnIsBusy: activeService?.vpnIsBusy ?? false
    property bool vpnConnected: activeService?.vpnConnected ?? false
    property string vpnActiveUuid: activeService?.activeUuid ?? ""
    property string vpnActiveName: activeService?.activeName ?? ""

    property string credentialsToken: activeService?.credentialsToken ?? ""
    property string credentialsSSID: activeService?.credentialsSSID ?? ""
    property string credentialsSetting: activeService?.credentialsSetting ?? ""
    property var credentialsFields: activeService?.credentialsFields ?? []
    property var credentialsHints: activeService?.credentialsHints ?? []
    property string credentialsReason: activeService?.credentialsReason ?? ""
    property bool credentialsRequested: activeService?.credentialsRequested ?? false

    signal networksUpdated
    signal connectionChanged
    signal credentialsNeeded(string token, string ssid, string setting, var fields, var hints, string reason, string connType, string connName, string vpnService, var fieldsInfo)

    property var activeService: null

    readonly property string socketPath: Quickshell.env("DMS_SOCKET")

    // Backend adoption must be state-checked here, not only edge-triggered below:
    // with staged shell loading this singleton can be instantiated after
    // DMSNetworkService already resolved its capabilities, so the change signal
    // may never fire again.
    Component.onCompleted: {
        log.info("Initializing...");
        if (!socketPath || socketPath.length === 0) {
            log.info("DMS_SOCKET not set, network backend unavailable");
            return;
        }
        if (DMSNetworkService.networkAvailable) {
            log.info("Network capability already available, using DMSNetworkService");
            useDMSService();
            return;
        }
        log.debug("DMS_SOCKET found, waiting for capabilities...");
    }

    Connections {
        target: DMSNetworkService

        function onNetworkAvailableChanged() {
            if (!activeService && DMSNetworkService.networkAvailable) {
                log.info("Network capability detected, using DMSNetworkService");
                useDMSService();
            }
        }
    }

    function useDMSService() {
        activeService = DMSNetworkService;
        log.info("Switched to DMSNetworkService, networkAvailable:", networkAvailable);
        connectSignals();
    }

    function connectSignals() {
        if (activeService) {
            if (activeService.networksUpdated) {
                activeService.networksUpdated.connect(root.networksUpdated);
            }
            if (activeService.connectionChanged) {
                activeService.connectionChanged.connect(root.connectionChanged);
            }
            if (activeService.credentialsNeeded) {
                activeService.credentialsNeeded.connect(root.credentialsNeeded);
            }
        }
    }

    function addRef() {
        if (activeService && activeService.addRef) {
            activeService.addRef();
        }
    }

    function removeRef() {
        if (activeService && activeService.removeRef) {
            activeService.removeRef();
        }
    }

    function getState() {
        if (activeService && activeService.getState) {
            activeService.getState();
        }
    }

    function scanWifi() {
        if (activeService && activeService.scanWifi) {
            activeService.scanWifi();
        }
    }

    function scanWifiNetworks() {
        if (activeService && activeService.scanWifiNetworks) {
            activeService.scanWifiNetworks();
        }
    }

    function refreshSavedWifiNetworks() {
        if (activeService && activeService.refreshSavedWifiNetworks) {
            activeService.refreshSavedWifiNetworks();
        }
    }

    function connectToWifi(ssid, password = "", username = "", anonymousIdentity = "", domainSuffixMatch = "", hidden = false, eapMethod = "", phase2Auth = "") {
        if (activeService && activeService.connectToWifi) {
            activeService.connectToWifi(ssid, password, username, anonymousIdentity, domainSuffixMatch, hidden, eapMethod, phase2Auth);
        }
    }

    function disconnectWifi() {
        if (activeService && activeService.disconnectWifi) {
            activeService.disconnectWifi();
        }
    }

    function forgetWifiNetwork(ssid) {
        if (activeService && activeService.forgetWifiNetwork) {
            activeService.forgetWifiNetwork(ssid);
        }
    }

    function toggleWifiRadio() {
        if (activeService && activeService.toggleWifiRadio) {
            activeService.toggleWifiRadio();
        }
    }

    function toggleCellularRadio() {
        if (activeService && activeService.toggleCellularRadio) {
            activeService.toggleCellularRadio();
        }
    }

    function enableWifiDevice() {
        if (activeService && activeService.enableWifiDevice) {
            activeService.enableWifiDevice();
        }
    }

    function setNetworkPreference(preference) {
        if (activeService && activeService.setNetworkPreference) {
            activeService.setNetworkPreference(preference);
        }
    }

    function toggleNetworkConnection(type) {
        if (activeService && activeService.toggleNetworkConnection) {
            activeService.toggleNetworkConnection(type);
        }
    }

    function disconnectEthernetDevice(deviceName) {
        if (activeService && activeService.disconnectEthernetDevice) {
            activeService.disconnectEthernetDevice(deviceName);
        }
    }

    function disconnectCellularDevice(deviceName) {
        if (activeService && activeService.disconnectCellularDevice) {
            activeService.disconnectCellularDevice(deviceName);
        }
    }

    function connectCellular() {
        if (activeService && activeService.connectCellular) {
            activeService.connectCellular();
        }
    }

    function connectToSpecificCellularConfig(uuid) {
        if (activeService && activeService.connectToSpecificCellularConfig) {
            activeService.connectToSpecificCellularConfig(uuid);
        }
    }

    function startAutoScan() {
        if (activeService && activeService.startAutoScan) {
            activeService.startAutoScan();
        }
    }

    function stopAutoScan() {
        if (activeService && activeService.stopAutoScan) {
            activeService.stopAutoScan();
        }
    }

    function fetchNetworkInfo(ssid) {
        if (activeService && activeService.fetchNetworkInfo) {
            activeService.fetchNetworkInfo(ssid);
        }
    }

    function fetchWiredNetworkInfo(uuid) {
        if (activeService && activeService.fetchWiredNetworkInfo) {
            activeService.fetchWiredNetworkInfo(uuid);
        }
    }

    function getNetworkInfo(ssid) {
        if (activeService && activeService.getNetworkInfo) {
            return activeService.getNetworkInfo(ssid);
        }
        return null;
    }

    function getWiredNetworkInfo(uuid) {
        if (activeService && activeService.getWiredNetworkInfo) {
            return activeService.getWiredNetworkInfo(uuid);
        }
        return null;
    }

    function refreshNetworkState() {
        if (activeService && activeService.refreshNetworkState) {
            activeService.refreshNetworkState();
        }
    }

    function connectToSpecificWiredConfig(uuid) {
        if (activeService && activeService.connectToSpecificWiredConfig) {
            activeService.connectToSpecificWiredConfig(uuid);
        }
    }

    function submitCredentials(token, secrets, save) {
        if (activeService && activeService.submitCredentials) {
            activeService.submitCredentials(token, secrets, save);
        }
    }

    function cancelCredentials(token) {
        if (activeService && activeService.cancelCredentials) {
            activeService.cancelCredentials(token);
        }
    }

    function setWifiAutoconnect(ssid, autoconnect) {
        if (activeService && activeService.setWifiAutoconnect) {
            activeService.setWifiAutoconnect(ssid, autoconnect);
        }
    }

    function configureHotspot(ssid, password = "", device = "", band = "", callback = null) {
        if (activeService && activeService.configureHotspot) {
            return activeService.configureHotspot(ssid, password, device, band, callback);
        }
        return false;
    }

    function startHotspot(callback = null) {
        if (activeService && activeService.startHotspot) {
            return activeService.startHotspot(callback);
        }
        return false;
    }

    function stopHotspot(callback = null) {
        if (activeService && activeService.stopHotspot) {
            return activeService.stopHotspot(callback);
        }
        return false;
    }

    function configureAndStartHotspot(ssid, password = "", device = "", band = "", callback = null) {
        if (activeService && activeService.configureAndStartHotspot) {
            return activeService.configureAndStartHotspot(ssid, password, device, band, callback);
        }
        return false;
    }

    function getHotspotSecrets(callback) {
        if (activeService && activeService.getHotspotSecrets) {
            return activeService.getHotspotSecrets(callback);
        }
        return false;
    }

    function hotspotTargetWouldDisconnectWifi(device, band = "") {
        if (activeService && activeService.hotspotTargetWouldDisconnectWifi) {
            return activeService.hotspotTargetWouldDisconnectWifi(device, band);
        }
        return false;
    }

    function setWifiDeviceOverride(deviceName) {
        if (activeService && activeService.setWifiDeviceOverride) {
            activeService.setWifiDeviceOverride(deviceName);
        }
    }
}
