pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Network
import qs.Modules.Settings.Widgets
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

Item {
    id: networkWifiTab

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Component.onCompleted: {
        NetworkService.addRef();
        Qt.callLater(() => NetworkService.refreshSavedWifiNetworks());
    }

    Component.onDestruction: {
        NetworkService.removeRef();
    }

    function wifiDetailFields(net) {
        const fields = [];
        if (!net || net.outOfRange)
            return fields;

        fields.push({
            label: I18n.tr("Signal"),
            value: (net.signal || 0) + "%"
        });
        if (net.frequency)
            fields.push({
                label: I18n.tr("Frequency", "wifi network detail label, radio frequency in GHz"),
                value: (net.frequency / 1000).toFixed(1) + " GHz"
            });
        if (net.channel)
            fields.push({
                label: I18n.tr("Channel", "wifi network detail label, radio channel number"),
                value: String(net.channel)
            });
        if (net.rate)
            fields.push({
                label: I18n.tr("Rate", "noun, wifi network detail label, link speed in Mbps"),
                value: net.rate + " Mbps"
            });
        if (net.mode)
            fields.push({
                label: I18n.tr("Mode"),
                value: net.mode
            });
        if (net.bssid)
            fields.push({
                label: "BSSID",
                value: net.bssid
            });
        fields.push({
            label: I18n.tr("Security", "noun, settings page name and wifi security type label"),
            value: net.secured ? (net.enterprise ? I18n.tr("Enterprise", "wifi security type value, 802.1x enterprise network") : "WPA/WPA2") : I18n.tr("Open", "network security type", true)
        });

        return fields;
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            id: root

            property string expandedWifiSsid: ""
            property string expandedSavedWifiSsid: ""
            property int maxPinnedWifiNetworks: 3

            function getPinnedWifiNetworks() {
                const pins = CacheData.wifiNetworkPins || {};
                return QmlUtils.normalizePinList(pins["preferredWifi"]);
            }

            function toggleWifiPin(ssid) {
                const pins = JSON.parse(JSON.stringify(CacheData.wifiNetworkPins || {}));
                let pinnedList = QmlUtils.normalizePinList(pins["preferredWifi"]);
                const pinIndex = pinnedList.indexOf(ssid);

                if (pinIndex !== -1) {
                    pinnedList.splice(pinIndex, 1);
                } else {
                    pinnedList.unshift(ssid);
                    if (pinnedList.length > maxPinnedWifiNetworks)
                        pinnedList = pinnedList.slice(0, maxPinnedWifiNetworks);
                }

                if (pinnedList.length > 0)
                    pins["preferredWifi"] = pinnedList;
                else
                    delete pins["preferredWifi"];

                CacheData.set("wifiNetworkPins", pins);
            }

            property var forgetNetworkConfirm: ConfirmModal {}

            width: parent.width
            settingKey: "networkWifi"
            tags: ["wifi", "wi-fi", "wireless", "network", "ssid", "adapter", "radio"]

            function visibleWifiBySsid(ssid) {
                const networks = NetworkService.wifiNetworks || [];
                return networks.find(network => network.ssid === ssid) || null;
            }

            function mergedSavedWifiNetworks() {
                const saved = NetworkService.savedWifiNetworks || [];
                const supportsSavedWifiState = DMSService.apiVersion >= NetworkService.savedWifiStateApiVersion;
                const result = [];
                const seen = new Set();

                for (const network of saved) {
                    if (!network?.ssid || seen.has(network.ssid))
                        continue;
                    const isOutOfRange = supportsSavedWifiState ? network.outOfRange === true : false;
                    const visibleNetwork = !isOutOfRange ? visibleWifiBySsid(network.ssid) : null;
                    if (visibleNetwork) {
                        result.push(Object.assign({}, network, visibleNetwork, {
                            saved: true,
                            autoconnect: network.autoconnect ?? visibleNetwork.autoconnect,
                            hidden: (network.hidden || false) || (visibleNetwork.hidden || false),
                            outOfRange: false
                        }));
                    } else {
                        result.push(Object.assign({}, network, {
                            saved: true,
                            outOfRange: isOutOfRange
                        }));
                    }
                    seen.add(network.ssid);
                }

                return result;
            }

            function sortedSavedWifiNetworks() {
                const ssid = NetworkService.currentWifiSSID;
                const pinnedList = root.getPinnedWifiNetworks();
                let sorted = root.mergedSavedWifiNetworks();

                sorted.sort((a, b) => {
                    const aPinnedIndex = pinnedList.indexOf(a.ssid);
                    const bPinnedIndex = pinnedList.indexOf(b.ssid);
                    if (aPinnedIndex !== -1 || bPinnedIndex !== -1) {
                        if (aPinnedIndex === -1)
                            return 1;
                        if (bPinnedIndex === -1)
                            return -1;
                        return aPinnedIndex - bPinnedIndex;
                    }
                    if (a.ssid === ssid)
                        return -1;
                    if (b.ssid === ssid)
                        return 1;
                    if ((a.outOfRange || false) !== (b.outOfRange || false))
                        return (a.outOfRange || false) ? 1 : -1;
                    if ((a.signal || 0) !== (b.signal || 0))
                        return (b.signal || 0) - (a.signal || 0);
                    return (a.ssid || "").localeCompare(b.ssid || "");
                });
                return sorted;
            }

            function showForgetNetworkConfirm(ssid) {
                forgetNetworkConfirm.showWithOptions({
                    title: I18n.tr("Forget network"),
                    message: I18n.tr("Forget \"%1\"?", "forget wifi network confirmation, %1 is the network name").arg(ssid),
                    confirmText: I18n.tr("Forget", "verb, remove a saved wifi network, button"),
                    confirmColor: Theme.error,
                    onConfirm: () => NetworkService.forgetWifiNetwork(ssid)
                });
            }

            SettingsRow {
                title: I18n.tr("Wi-Fi")
                subtitle: {
                    if (NetworkService.wifiToggling)
                        return I18n.tr("Toggling...", "wifi status while the radio is switching on or off");
                    if (!NetworkService.wifiEnabled)
                        return I18n.tr("Disabled");
                    if (NetworkService.wifiConnected)
                        return NetworkService.currentWifiSSID;
                    return I18n.tr("Not connected");
                }

                DToggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: NetworkService.wifiEnabled
                    enabled: !NetworkService.wifiToggling
                    onToggled: NetworkService.toggleWifiRadio()
                }
            }

            SettingsDropdownRow {
                visible: NetworkService.wifiEnabled && (NetworkService.wifiDevices?.length ?? 0) > 1
                text: I18n.tr("Device")
                dropdownWidth: 150
                popupWidth: 180
                currentValue: NetworkService.wifiDeviceOverride || I18n.tr("Auto")
                options: {
                    const devices = NetworkService.wifiDevices;
                    if (!devices || devices.length === 0)
                        return [I18n.tr("Auto")];
                    return [I18n.tr("Auto")].concat(devices.map(d => d.name));
                }
                onValueChanged: value => {
                    const deviceName = value === I18n.tr("Auto") ? "" : value;
                    NetworkService.setWifiDeviceOverride(deviceName);
                }
            }

            SettingsRow {
                visible: NetworkService.wifiEnabled && !NetworkService.wifiToggling && NetworkService.wifiInterface.length > 0
                title: I18n.tr("Interface", "noun, wifi network interface name label") + ":"
                trailingBadge: NetworkService.wifiInterface || "-"
            }

            SettingsRow {
                visible: NetworkService.wifiEnabled && !NetworkService.wifiToggling && NetworkService.wifiInterface.length > 0 && NetworkService.wifiIP.length > 0
                title: I18n.tr("IP address") + ":"
                trailingBadge: NetworkService.wifiIP || "-"
            }

            SettingsRow {
                visible: NetworkService.wifiEnabled && !NetworkService.wifiToggling && NetworkService.wifiInterface.length > 0 && NetworkService.wifiConnected
                title: I18n.tr("Signal", "noun, wifi signal strength label") + ":"
                trailingBadge: NetworkService.wifiSignalStrength + "%"

                DIcon {
                    name: {
                        const s = NetworkService.wifiSignalStrength;
                        if (s >= 50)
                            return "wifi";
                        if (s >= 25)
                            return "wifi_2_bar";
                        return "wifi_1_bar";
                    }
                    size: Theme.iconSizeSmall
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        SettingsCard {
            id: availableWifiCard

            readonly property var sortedNetworks: {
                const ssid = NetworkService.currentWifiSSID;
                const networks = NetworkService.wifiNetworks || [];
                const pinnedList = root.getPinnedWifiNetworks();

                let sorted = [...networks];
                sorted.sort((a, b) => {
                    const aPinnedIndex = pinnedList.indexOf(a.ssid);
                    const bPinnedIndex = pinnedList.indexOf(b.ssid);
                    if (aPinnedIndex !== -1 || bPinnedIndex !== -1) {
                        if (aPinnedIndex === -1)
                            return 1;
                        if (bPinnedIndex === -1)
                            return -1;
                        return aPinnedIndex - bPinnedIndex;
                    }
                    if (a.ssid === ssid)
                        return -1;
                    if (b.ssid === ssid)
                        return 1;
                    const aKnown = !!a.saved && (a.signal || 0) > 0;
                    const bKnown = !!b.saved && (b.signal || 0) > 0;
                    if (aKnown !== bKnown)
                        return aKnown ? -1 : 1;
                    return b.signal - a.signal;
                });
                return sorted;
            }

            width: parent.width
            title: I18n.tr("Available networks")
            iconName: "wifi"
            settingKey: "networkAvailableWifi"
            tags: ["wifi", "wi-fi", "wireless", "network", "scan", "hidden", "connect"]
            visible: NetworkService.wifiEnabled && !NetworkService.wifiToggling

            headerActions: [
                StyledText {
                    text: availableWifiCard.sortedNetworks.length
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                },
                DActionButton {
                    iconName: "wifi_find"
                    tooltipText: I18n.tr("Connect to Hidden Network")
                    buttonSize: Theme.buttonHeightXS
                    visible: NetworkService.backend === "networkmanager"
                    onClicked: PopoutService.showHiddenNetworkModal()
                },
                DRefreshButton {
                    tooltipText: I18n.tr("Scan")
                    buttonSize: Theme.buttonHeightXS
                    busy: NetworkService.isScanning
                    onClicked: NetworkService.scanWifi()
                }
            ]

            SettingsRow {
                visible: NetworkService.isScanning && (NetworkService.wifiNetworks?.length ?? 0) === 0
                body: Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    DLoadingIndicator {
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: I18n.tr("Scanning...")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            Repeater {
                model: availableWifiCard.sortedNetworks

                delegate: Column {
                    id: wifiNetworkDelegate
                    required property var modelData
                    required property int index

                    readonly property bool isConnected: modelData.ssid === NetworkService.currentWifiSSID
                    readonly property bool isConnecting: NetworkService.isWifiConnecting && NetworkService.connectingSSID === modelData.ssid
                    readonly property bool isPinned: root.getPinnedWifiNetworks().includes(modelData.ssid)
                    readonly property bool isExpanded: root.expandedWifiSsid === modelData.ssid

                    width: parent?.width ?? 0
                    spacing: SettingsMetrics.groupGap
                    SettingsRow {
                        id: wifiNetworkRow
                        title: wifiNetworkDelegate.modelData.ssid || I18n.tr("Unknown")
                        active: wifiNetworkDelegate.isConnected
                        subtitle: {
                            const parts = [wifiNetworkDelegate.isConnecting ? I18n.tr("Connecting...") : (wifiNetworkDelegate.isConnected ? I18n.tr("Connected") : (wifiNetworkDelegate.modelData.secured ? I18n.tr("Secured", "adjective, wifi network requires a password, opposite of open") : I18n.tr("Open", "network security type", true)))];
                            if (wifiNetworkDelegate.modelData.saved)
                                parts.push(I18n.tr("Saved", "wifi network status, network has a saved profile", true));
                            if (wifiNetworkDelegate.modelData.hidden || false)
                                parts.push(I18n.tr("Hidden", "adjective, wifi network with hidden name"));
                            parts.push(wifiNetworkDelegate.modelData.signal + "%");
                            return parts.join(" • ");
                        }
                        subtitleColor: wifiNetworkDelegate.isConnecting ? Theme.warning : supportingContentColor
                        clickable: !NetworkService.isWifiConnecting || wifiNetworkDelegate.isConnected
                        onClicked: {
                            WifiConnectionActions.connectToNetwork(wifiNetworkDelegate.modelData, {
                                connected: wifiNetworkDelegate.isConnected,
                                disconnectWhenConnected: true
                            });
                        }

                        leading: [
                            DSpinner {
                                size: Theme.iconSizeMedium
                                strokeWidth: 2
                                color: Theme.warning
                                running: wifiNetworkDelegate.isConnecting
                                visible: wifiNetworkDelegate.isConnecting
                                anchors.verticalCenter: parent.verticalCenter
                            },
                            DIcon {
                                visible: !wifiNetworkDelegate.isConnecting
                                name: {
                                    const s = wifiNetworkDelegate.modelData.signal || 0;
                                    if (s >= 50)
                                        return "wifi";
                                    if (s >= 25)
                                        return "wifi_2_bar";
                                    return "wifi_1_bar";
                                }
                                size: Theme.iconSizeMedium
                                color: wifiNetworkRow.contentColor
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        ]

                        DActionButton {
                            iconName: wifiNetworkDelegate.isExpanded ? "expand_less" : "expand_more"
                            Accessible.name: wifiNetworkDelegate.isExpanded ? I18n.tr("Collapse") : I18n.tr("Expand")
                            iconSize: Theme.iconSizeSmall
                            visible: wifiNetworkDelegate.isConnected || wifiNetworkDelegate.modelData.saved
                            onClicked: {
                                if (wifiNetworkDelegate.isExpanded) {
                                    root.expandedWifiSsid = "";
                                } else {
                                    root.expandedWifiSsid = wifiNetworkDelegate.modelData.ssid;
                                    NetworkService.fetchNetworkInfo(wifiNetworkDelegate.modelData.ssid);
                                }
                            }
                        }

                        DActionButton {
                            iconName: "qr_code"
                            tooltipText: I18n.tr("Show QR Code")
                            visible: wifiNetworkDelegate.modelData.secured && wifiNetworkDelegate.modelData.saved && !(wifiNetworkDelegate.modelData.enterprise || false)
                            onClicked: {
                                PopoutService.showWifiQRCodeModal(wifiNetworkDelegate.modelData.ssid);
                            }
                        }

                        DActionButton {
                            iconName: "push_pin"
                            Accessible.name: wifiNetworkDelegate.isPinned ? I18n.tr("Unpin") : I18n.tr("Pin", "verb, keep an item pinned in place")
                            iconColor: wifiNetworkDelegate.isPinned ? Theme.primary : Theme.surfaceVariantText
                            onClicked: {
                                root.toggleWifiPin(wifiNetworkDelegate.modelData.ssid);
                            }
                        }

                        DActionButton {
                            iconName: "delete"
                            tooltipText: I18n.tr("Forget", "verb, remove a saved wifi network, button")
                            iconColor: Theme.error
                            visible: wifiNetworkDelegate.modelData.saved || wifiNetworkDelegate.isConnected
                            onClicked: {
                                root.showForgetNetworkConfirm(wifiNetworkDelegate.modelData.ssid);
                            }
                        }
                    }

                    SettingsRow {
                        visible: wifiNetworkDelegate.isExpanded
                        body: Column {
                            width: parent.width
                            spacing: Theme.spacingS

                            Item {
                                width: parent.width
                                height: NetworkService.networkInfoLoading ? 40 : 0
                                visible: NetworkService.networkInfoLoading

                                DSpinner {
                                    anchors.centerIn: parent
                                    size: Theme.iconSizeMedium
                                }
                            }

                            Flow {
                                width: parent.width
                                spacing: Theme.spacingXS
                                visible: !NetworkService.networkInfoLoading

                                Repeater {
                                    model: wifiNetworkDelegate.isExpanded ? networkWifiTab.wifiDetailFields(wifiNetworkDelegate.modelData) : []

                                    delegate: DDetailChip {
                                        required property var modelData

                                        label: modelData.label
                                        value: modelData.value
                                    }
                                }
                            }
                        }
                    }

                    SettingsToggleRow {
                        visible: wifiNetworkDelegate.isExpanded && (wifiNetworkDelegate.modelData.saved || wifiNetworkDelegate.isConnected) && DMSService.apiVersion > 13
                        text: I18n.tr("Autoconnect", "toggle, connect to this wifi or vpn automatically")
                        checked: wifiNetworkDelegate.modelData.autoconnect || false
                        onToggled: checked => {
                            NetworkService.setWifiAutoconnect(wifiNetworkDelegate.modelData.ssid, checked);
                        }
                    }
                }
            }
        }
        SettingsCard {
            id: savedWifiCard

            readonly property var savedNetworks: root.sortedSavedWifiNetworks()

            width: parent.width
            title: I18n.tr("Saved networks")
            iconName: "bookmark"
            settingKey: "networkSavedWifi"
            tags: ["wifi", "wi-fi", "wireless", "network", "saved", "known", "ssid", "autoconnect", "forget"]
            collapsible: true
            expanded: false
            visible: savedNetworks.length > 0

            headerActions: [
                StyledText {
                    text: savedWifiCard.savedNetworks.length
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    verticalAlignment: Text.AlignVCenter
                }
            ]

            Repeater {
                model: savedWifiCard.expanded ? savedWifiCard.savedNetworks : []

                delegate: Column {
                    id: savedWifiDelegate

                    required property var modelData
                    required property int index

                    readonly property bool isConnected: modelData.ssid === NetworkService.currentWifiSSID
                    readonly property bool isConnecting: NetworkService.isWifiConnecting && NetworkService.connectingSSID === modelData.ssid
                    readonly property bool isPinned: root.getPinnedWifiNetworks().includes(modelData.ssid)
                    readonly property bool isOutOfRange: modelData.outOfRange || false
                    readonly property bool isExpanded: root.expandedSavedWifiSsid === modelData.ssid
                    readonly property var detailFields: networkWifiTab.wifiDetailFields(modelData)

                    width: parent?.width ?? 0
                    spacing: SettingsMetrics.groupGap

                    SettingsRow {
                        id: savedWifiRow
                        title: savedWifiDelegate.modelData.ssid || I18n.tr("Unknown")
                        active: savedWifiDelegate.isConnected
                        subtitle: {
                            if (savedWifiDelegate.isConnecting)
                                return I18n.tr("Connecting...");
                            const parts = [savedWifiDelegate.isConnected ? I18n.tr("Connected") : (savedWifiDelegate.modelData.secured ? I18n.tr("Secured") : I18n.tr("Open", "network security type", true))];
                            parts.push(savedWifiDelegate.isOutOfRange ? I18n.tr("Unavailable") : (savedWifiDelegate.modelData.signal || 0) + "%");
                            if (savedWifiDelegate.modelData.hidden || false)
                                parts.push(I18n.tr("Hidden"));
                            return parts.join(" • ");
                        }
                        subtitleColor: savedWifiDelegate.isConnecting ? Theme.warning : supportingContentColor
                        clickable: !savedWifiDelegate.isOutOfRange && (!NetworkService.isWifiConnecting || savedWifiDelegate.isConnected)
                        onClicked: {
                            WifiConnectionActions.connectToNetwork(savedWifiDelegate.modelData, {
                                connected: savedWifiDelegate.isConnected,
                                disconnectWhenConnected: true
                            });
                        }

                        leading: [
                            DSpinner {
                                size: Theme.iconSizeMedium
                                strokeWidth: 2
                                color: Theme.warning
                                running: savedWifiDelegate.isConnecting
                                visible: savedWifiDelegate.isConnecting
                                anchors.verticalCenter: parent.verticalCenter
                            },
                            DIcon {
                                visible: !savedWifiDelegate.isConnecting
                                name: {
                                    if (savedWifiDelegate.isOutOfRange)
                                        return "wifi_off";
                                    const s = savedWifiDelegate.modelData.signal || 0;
                                    if (s >= 50)
                                        return "wifi";
                                    if (s >= 25)
                                        return "wifi_2_bar";
                                    return "wifi_1_bar";
                                }
                                size: Theme.iconSizeMedium
                                color: savedWifiRow.contentColor
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        ]

                        DActionButton {
                            iconName: savedWifiDelegate.isExpanded ? "expand_less" : "expand_more"
                            Accessible.name: savedWifiDelegate.isExpanded ? I18n.tr("Collapse") : I18n.tr("Expand")
                            iconSize: Theme.iconSizeSmall
                            onClicked: {
                                if (savedWifiDelegate.isExpanded) {
                                    root.expandedSavedWifiSsid = "";
                                } else {
                                    root.expandedSavedWifiSsid = savedWifiDelegate.modelData.ssid;
                                }
                            }
                        }

                        DActionButton {
                            iconName: "qr_code"
                            tooltipText: I18n.tr("Show QR Code")
                            visible: savedWifiDelegate.modelData.secured && !(savedWifiDelegate.modelData.enterprise || false)
                            onClicked: {
                                PopoutService.showWifiQRCodeModal(savedWifiDelegate.modelData.ssid);
                            }
                        }

                        DActionButton {
                            iconName: "push_pin"
                            Accessible.name: savedWifiDelegate.isPinned ? I18n.tr("Unpin") : I18n.tr("Pin", "verb, keep an item pinned in place")
                            iconColor: savedWifiDelegate.isPinned ? Theme.primary : Theme.surfaceVariantText
                            onClicked: {
                                root.toggleWifiPin(savedWifiDelegate.modelData.ssid);
                            }
                        }

                        DActionButton {
                            iconName: "delete"
                            tooltipText: I18n.tr("Forget", "verb, remove a saved wifi network, button")
                            iconColor: Theme.error
                            onClicked: root.showForgetNetworkConfirm(savedWifiDelegate.modelData.ssid)
                        }
                    }

                    SettingsRow {
                        visible: savedWifiDelegate.isExpanded && savedWifiDelegate.detailFields.length > 0
                        body: Flow {
                            width: parent.width
                            spacing: Theme.spacingXS

                            Repeater {
                                model: savedWifiDelegate.isExpanded ? savedWifiDelegate.detailFields : []

                                delegate: DDetailChip {
                                    required property var modelData

                                    label: modelData.label
                                    value: modelData.value
                                }
                            }
                        }
                    }

                    SettingsToggleRow {
                        visible: savedWifiDelegate.isExpanded && DMSService.apiVersion > 13
                        text: I18n.tr("Autoconnect", "toggle, connect to this wifi or vpn automatically")
                        checked: savedWifiDelegate.modelData.autoconnect || false
                        onToggled: checked => NetworkService.setWifiAutoconnect(savedWifiDelegate.modelData.ssid, checked)
                    }
                }
            }
        }

        SettingsCard {
            id: hotspotCard

            width: parent.width
            title: I18n.tr("Hotspot", "hotspot settings card title")
            iconName: "wifi_tethering"
            settingKey: "networkHotspot"
            tags: ["wifi", "wi-fi", "wireless", "network", "hotspot", "access point", "sharing", "ssid"]
            visible: NetworkService.hotspotAvailable

            property string ssid: NetworkService.hotspotSSID || ""
            property string password: ""
            property string device: NetworkService.hotspotDevice || ""
            property string band: NetworkService.hotspotBand || ""
            property bool editing: false
            property bool passwordLoading: false
            property bool passwordResolved: true
            property int passwordRequestId: 0
            property int passwordEditRevision: 0
            readonly property bool showForm: !NetworkService.hotspotConfigured || editing
            readonly property bool passwordValid: password.length === 0 || (password.length >= 8 && password.length <= 63) || /^[0-9a-fA-F]{64}$/.test(password)
            readonly property bool starting: NetworkService.hotspotBusy || NetworkService.hotspotActivating
            property var startConfirm: ConfirmModal {}

            function confirmThenStart(targetDevice, targetBand, startFn) {
                if (!NetworkService.hotspotTargetWouldDisconnectWifi(targetDevice, targetBand)) {
                    startFn();
                    return;
                }
                startConfirm.showWithOptions({
                    title: I18n.tr("Start Hotspot?", "hotspot start confirmation title"),
                    message: I18n.tr("Starting the hotspot disconnects Wi-Fi from \"%1\". The radio can\'t do both at once, so sharing internet needs another connection such as Ethernet.", "hotspot WiFi disconnection warning, %1 is the network name").arg(NetworkService.currentWifiSSID),
                    confirmText: I18n.tr("Start", "hotspot start confirmation action"),
                    onConfirm: startFn
                });
            }

            function bandLabel(value) {
                switch (value) {
                case "bg":
                    return I18n.tr("2.4 GHz", "hotspot WiFi band option");
                case "a":
                    return I18n.tr("5 GHz", "hotspot WiFi band option");
                default:
                    return I18n.tr("Auto", "hotspot device or band option");
                }
            }

            function bandValue(label) {
                if (label === I18n.tr("2.4 GHz", "hotspot WiFi band option"))
                    return "bg";
                if (label === I18n.tr("5 GHz", "hotspot WiFi band option"))
                    return "a";
                return "";
            }

            function syncFromService() {
                ssid = NetworkService.hotspotSSID || ssid || "";
                device = NetworkService.hotspotDevice || "";
                band = NetworkService.hotspotBand || "";
            }

            function beginEditing() {
                syncFromService();
                password = "";
                editing = true;
                passwordRequestId++;
                const requestId = passwordRequestId;
                const editRevision = passwordEditRevision;
                passwordLoading = NetworkService.hotspotSecured;
                passwordResolved = !NetworkService.hotspotSecured;
                if (NetworkService.hotspotSecured) {
                    NetworkService.getHotspotSecrets(response => {
                        if (!editing || requestId !== passwordRequestId)
                            return;
                        passwordLoading = false;
                        if (response.error) {
                            ToastService.showError(I18n.tr("Couldn't load hotspot password", "hotspot password error title"), I18n.tr("Re-enter the password before saving.", "hotspot password recovery message"));
                        } else {
                            const storedPassword = response.result?.password ?? response.password ?? "";
                            if (!storedPassword) {
                                ToastService.showError(I18n.tr("Couldn't load hotspot password", "hotspot password error title"), I18n.tr("Re-enter the password before saving.", "hotspot password recovery message"));
                            } else {
                                passwordResolved = true;
                                if (editRevision === passwordEditRevision) {
                                    password = storedPassword;
                                }
                            }
                        }
                    });
                }
            }

            function stopEditing() {
                passwordRequestId++;
                editing = false;
                password = "";
                passwordLoading = false;
                passwordResolved = true;
            }

            function buildCanConfigure() {
                return ssid.trim().length > 0 && passwordValid && passwordResolved && !passwordLoading && !NetworkService.hotspotBusy && !NetworkService.hotspotEnabled && !NetworkService.hotspotActivating;
            }

            function explainWiFiDisabled() {
                ToastService.showError(I18n.tr("Wi-Fi is disabled", "hotspot start error title"), I18n.tr("Enable Wi-Fi before starting the hotspot.", "hotspot WiFi requirement message"));
            }

            function saveOnly() {
                if (!buildCanConfigure())
                    return;
                NetworkService.configureHotspot(ssid.trim(), password, device, band, response => {
                    if (!response.error) {
                        stopEditing();
                        ToastService.showInfo(I18n.tr("Hotspot saved", "hotspot configuration success message"));
                    }
                });
            }

            function startOrStop() {
                if (NetworkService.hotspotEnabled) {
                    NetworkService.stopHotspot(response => {
                        if (!response.error)
                            ToastService.showInfo(I18n.tr("Hotspot stopped", "hotspot stop success message"));
                    });
                    return;
                }

                if (!NetworkService.wifiEnabled) {
                    explainWiFiDisabled();
                    return;
                }

                if (showForm) {
                    if (!buildCanConfigure())
                        return;
                    confirmThenStart(device, band, () => {
                        NetworkService.configureAndStartHotspot(ssid.trim(), password, device, band, response => {
                            if (!response.error)
                                stopEditing();
                        });
                    });
                    return;
                }

                confirmThenStart(NetworkService.hotspotDevice, NetworkService.hotspotBand, () => NetworkService.startHotspot());
            }

            onVisibleChanged: if (visible)
                syncFromService()

            SettingsRow {
                body: StyledText {
                    width: parent.width
                    text: {
                        if (NetworkService.hotspotEnabled)
                            return I18n.tr("Your hotspot is running.", "hotspot active status message");
                        if (hotspotCard.starting)
                            return I18n.tr("Starting hotspot...", "hotspot activation status message");
                        if (NetworkService.hotspotConfigured)
                            return I18n.tr("Your hotspot profile is saved and ready to start.", "configured hotspot status message");
                        return I18n.tr("Set up a Wi-Fi hotspot for sharing this connection.", "unconfigured hotspot description");
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: NetworkService.hotspotEnabled ? Theme.primary : Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            SettingsRow {
                visible: !NetworkService.wifiEnabled
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Wi-Fi is disabled. You can still edit and save hotspot settings, but starting the hotspot requires Wi-Fi to be enabled.", "hotspot WiFi requirement explanation")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                    wrapMode: Text.WordWrap
                }
            }

            SettingsRow {
                visible: NetworkService.wifiEnabled && !NetworkService.hotspotEnabled && !hotspotCard.starting && (hotspotCard.showForm ? NetworkService.hotspotTargetWouldDisconnectWifi(hotspotCard.device, hotspotCard.band) : NetworkService.hotspotWouldDisconnectWifi)
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Starting the hotspot disconnects Wi-Fi from \"%1\". The radio can\'t do both at once, so sharing internet needs another connection such as Ethernet.", "hotspot WiFi disconnection warning, %1 is the network name").arg(NetworkService.currentWifiSSID)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.warning
                    wrapMode: Text.WordWrap
                }
            }

            SettingsRow {
                visible: !hotspotCard.showForm
                iconName: NetworkService.hotspotEnabled ? "wifi_tethering" : "wifi_tethering_off"
                iconColor: NetworkService.hotspotEnabled ? Theme.primary : Theme.surfaceVariantText
                title: NetworkService.hotspotSSID
                subtitle: {
                    const parts = [NetworkService.hotspotSecured ? I18n.tr("WPA2 password", "hotspot security summary") : I18n.tr("Open network", "hotspot security summary"), hotspotCard.bandLabel(NetworkService.hotspotBand)];
                    if (NetworkService.hotspotDevice)
                        parts.push(NetworkService.hotspotDevice);
                    return parts.join(" • ");
                }
            }

            SettingsRow {
                visible: hotspotCard.showForm
                body: DTextField {
                    outlined: true
                    width: parent.width
                    labelText: I18n.tr("Hotspot name", "hotspot SSID field label")
                    placeholderText: I18n.tr("SSID", "hotspot network name placeholder")
                    text: hotspotCard.ssid
                    leftIconName: "badge"
                    showClearButton: true
                    onTextEdited: hotspotCard.ssid = text
                    onAccepted: hotspotCard.saveOnly()
                }
            }

            SettingsRow {
                visible: hotspotCard.showForm
                body: DTextField {
                    outlined: true
                    width: parent.width
                    labelText: I18n.tr("Password", "hotspot password field label")
                    placeholderText: I18n.tr("Optional; leave blank for open hotspot", "hotspot password field placeholder")
                    text: hotspotCard.password
                    leftIconName: "key"
                    showPasswordToggle: true
                    echoMode: passwordVisible ? TextInput.Normal : TextInput.Password
                    onTextEdited: {
                        hotspotCard.password = text;
                        hotspotCard.passwordEditRevision++;
                        if (text.length > 0)
                            hotspotCard.passwordResolved = true;
                    }
                    onAccepted: hotspotCard.saveOnly()
                }
            }

            SettingsRow {
                visible: hotspotCard.showForm && !hotspotCard.passwordValid
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Password must be 8 to 63 characters, or a 64-digit hex key.", "hotspot password length requirement")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                    wrapMode: Text.WordWrap
                }
            }

            SettingsDropdownRow {
                visible: hotspotCard.showForm
                text: I18n.tr("Device", "hotspot WiFi device field label")
                currentValue: hotspotCard.device || I18n.tr("Auto", "hotspot device or band option")
                options: {
                    const devices = NetworkService.wifiDevices || [];
                    return [I18n.tr("Auto", "hotspot device or band option")].concat(devices.filter(d => d.apCapable).map(d => d.name));
                }
                onValueChanged: value => hotspotCard.device = value === I18n.tr("Auto", "hotspot device or band option") ? "" : value
            }

            SettingsDropdownRow {
                visible: hotspotCard.showForm
                text: I18n.tr("Band", "hotspot WiFi band field label")
                currentValue: hotspotCard.bandLabel(hotspotCard.band)
                options: [I18n.tr("Auto", "hotspot device or band option"), I18n.tr("2.4 GHz", "hotspot WiFi band option"), I18n.tr("5 GHz", "hotspot WiFi band option")]
                onValueChanged: value => hotspotCard.band = hotspotCard.bandValue(value)
            }

            SettingsRow {
                DButton {
                    visible: hotspotCard.editing
                    text: I18n.tr("Cancel", "cancel hotspot editing action")
                    buttonHeight: 36
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.surfaceText
                    onClicked: hotspotCard.stopEditing()
                }

                DButton {
                    visible: !hotspotCard.showForm
                    text: I18n.tr("Edit", "edit hotspot action")
                    iconName: "edit"
                    buttonHeight: 36
                    enabled: !NetworkService.hotspotEnabled && !hotspotCard.starting
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.surfaceText
                    onClicked: hotspotCard.beginEditing()
                }

                DButton {
                    visible: hotspotCard.showForm
                    text: hotspotCard.passwordLoading ? I18n.tr("Loading...", "hotspot password loading status") : (NetworkService.hotspotBusy ? I18n.tr("Saving...", "hotspot configuration saving status") : I18n.tr("Save", "save hotspot configuration action"))
                    iconName: "save"
                    buttonHeight: 36
                    enabled: hotspotCard.buildCanConfigure()
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.surfaceText
                    onClicked: hotspotCard.saveOnly()
                }

                DButton {
                    text: {
                        if (NetworkService.hotspotEnabled)
                            return I18n.tr("Stop", "stop hotspot action");
                        if (hotspotCard.starting)
                            return I18n.tr("Starting...", "hotspot activation status");
                        return hotspotCard.showForm ? I18n.tr("Save & Start", "save and start hotspot action") : I18n.tr("Start", "start hotspot action");
                    }
                    iconName: NetworkService.hotspotEnabled ? "stop" : "wifi_tethering"
                    buttonHeight: 36
                    enabled: !hotspotCard.starting && (NetworkService.hotspotEnabled || hotspotCard.buildCanConfigure())
                    backgroundColor: NetworkService.hotspotEnabled ? Theme.error : Theme.primary
                    textColor: NetworkService.hotspotEnabled ? Theme.surfaceText : Theme.onPrimary
                    onClicked: hotspotCard.startOrStop()
                }
            }
        }
    }
}
