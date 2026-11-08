pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modals
import qs.Modals.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Modules.Network
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../../../Common/QmlUtils.js" as QmlUtils

Item {
    id: root

    implicitHeight: pageList.contentHeight

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var transientSurfaceTracker: null

    readonly property string title: I18n.tr("Network")

    property bool transitioning: false
    property bool holdsScanRef: false

    Component.onCompleted: acquireScanRef()
    Component.onDestruction: {
        if (holdsScanRef)
            NetworkService.removeRef();
    }
    onTransitioningChanged: acquireScanRef()

    readonly property bool hasEthernetAvailable: (NetworkService.ethernetDevices?.length ?? 0) > 0
    readonly property bool hasWifiAvailable: (NetworkService.wifiDevices?.length ?? 0) > 0
    readonly property bool hasCellularAvailable: (NetworkService.cellularDevices?.length ?? 0) > 0
    readonly property var connectionTypes: {
        const types = [];
        if (hasEthernetAvailable)
            types.push("ethernet");
        if (hasWifiAvailable)
            types.push("wifi");
        if (hasCellularAvailable)
            types.push("cellular");
        return types.length > 0 ? types : ["wifi"];
    }
    property string selectedType: ""
    readonly property string currentConnectionType: {
        if (selectedType && connectionTypes.includes(selectedType))
            return selectedType;
        return connectionTypes[defaultTypeIndex] || "wifi";
    }
    readonly property bool wifiMode: currentConnectionType === "wifi"
    readonly property bool ethernetMode: currentConnectionType === "ethernet"
    readonly property bool cellularMode: currentConnectionType === "cellular"
    readonly property bool networkManager: NetworkService.backend === "networkmanager"
    // hosting on the sole wifi radio with no ethernet uplink drops connectivity
    readonly property bool hotspotRelevant: NetworkService.hotspotEnabled || NetworkService.hotspotActivating || NetworkService.hotspotBusy || NetworkService.ethernetConnected || (NetworkService.wifiDevices?.length ?? 0) > 1
    readonly property bool showHotspotRow: wifiMode && NetworkService.hotspotAvailable && NetworkService.hotspotConfigured && hotspotRelevant
    readonly property bool hotspotWorking: NetworkService.hotspotBusy || NetworkService.hotspotActivating
    readonly property var pinnedNetworks: QmlUtils.normalizePinList((CacheData.wifiNetworkPins || {})["preferredWifi"])
    readonly property bool wifiScanningEmpty: wifiMode && NetworkService.wifiEnabled && !NetworkService.wifiToggling && NetworkService.wifiInterface && (NetworkService.wifiNetworks?.length ?? 0) < 1 && (NetworkService.isScanning || transitioning)
    readonly property bool wifiListVisible: wifiMode && NetworkService.wifiEnabled && !NetworkService.wifiToggling && !wifiScanningEmpty

    readonly property bool paneSwitchSupported: connectionTypes.length > 1 && networkManager && DMSService.apiVersion > 10
    readonly property var typeLabels: ({
            "ethernet": I18n.tr("Ethernet"),
            "wifi": I18n.tr("Wi-Fi", "wireless network, page and section title"),
            "cellular": I18n.tr("Cellular")
        })
    readonly property int defaultTypeIndex: {
        const wifiIndex = Math.max(0, connectionTypes.indexOf("wifi"));
        if (!paneSwitchSupported)
            return wifiIndex;
        const byStatus = connectionTypes.indexOf(NetworkService.networkStatus);
        if (byStatus !== -1)
            return byStatus;
        const byPreference = connectionTypes.indexOf(NetworkService.userPreference);
        return byPreference !== -1 ? byPreference : wifiIndex;
    }

    readonly property Item headerActions: Row {
        spacing: Theme.spacingS

        DDropdown {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.wifiMode && (NetworkService.wifiDevices?.length ?? 0) > 1
            compactMode: true
            dropdownWidth: CcMetrics.headerDropdownWidth
            popupWidth: CcMetrics.headerPopupWidth
            alignPopupRight: true
            options: [I18n.tr("Auto")].concat((NetworkService.wifiDevices || []).map(d => d.name))
            currentValue: NetworkService.wifiDeviceOverride || I18n.tr("Auto")
            onValueChanged: value => NetworkService.setWifiDeviceOverride(value === I18n.tr("Auto") ? "" : value)
        }

        DRefreshButton {
            Accessible.name: I18n.tr("Scan")
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: CcMetrics.headerActionSize
            iconSize: CcMetrics.headerActionIconSize
            iconColor: Theme.surfaceText
            visible: root.wifiMode && NetworkService.wifiEnabled && !NetworkService.wifiToggling
            busy: NetworkService.isScanning
            onClicked: NetworkService.scanWifi()
        }

        CcSettingsButton {
            anchors.verticalCenter: parent.verticalCenter
            settingsTab: "network_" + root.currentConnectionType
        }
    }

    function acquireScanRef() {
        if (transitioning || holdsScanRef)
            return;
        holdsScanRef = true;
        NetworkService.addRef();
    }

    function dismissTransient() {
        if (wifiMenu.open) {
            wifiMenu.close();
            return true;
        }
        if (wiredMenu.open) {
            wiredMenu.close();
            return true;
        }
        return false;
    }

    function explainHotspotNeedsWiFi() {
        ToastService.showError(I18n.tr("Wi-Fi is disabled", "hotspot start error title"), I18n.tr("Enable Wi-Fi before starting the hotspot.", "hotspot WiFi requirement message"));
    }

    function startHotspotWithConfirm() {
        if (!NetworkService.hotspotWouldDisconnectWifi) {
            NetworkService.startHotspot();
            return;
        }
        hotspotConfirmLoader.active = true;
        const confirm = hotspotConfirmLoader.item;
        if (!confirm)
            return;
        confirm.showWithOptions({
            title: I18n.tr("Start Hotspot?", "hotspot start confirmation title"),
            message: I18n.tr("Starting the hotspot disconnects Wi-Fi from \"%1\". The radio can\'t do both at once, so sharing internet needs another connection such as Ethernet.", "hotspot WiFi disconnection warning, %1 is the network name").arg(NetworkService.currentWifiSSID),
            confirmText: I18n.tr("Start", "hotspot start confirmation action"),
            onConfirm: () => NetworkService.startHotspot()
        });
    }

    function togglePin(ssid) {
        CacheData.set("wifiNetworkPins", QmlUtils.togglePinEntry(CacheData.wifiNetworkPins, "preferredWifi", ssid, CcMetrics.maxPins));
    }

    function openWifiMenu(network, connected, connecting, anchor) {
        const ssid = network.ssid;
        const saved = network.saved || false;
        const showSavedOptions = saved || connected;
        wifiMenu.items = [
            {
                "label": connecting ? I18n.tr("Connecting...") : (connected ? I18n.tr("Disconnect") : I18n.tr("Connect")),
                "iconName": connected ? "wifi_off" : "wifi",
                "enabled": !connecting,
                "action": () => WifiConnectionActions.connectToNetworkFromDetails(ssid, network.secured, saved, network.enterprise, connected, {
                        disconnectWhenConnected: true
                    })
            },
            {
                "label": I18n.tr("Network Info"),
                "iconName": "info",
                "action": () => {
                    networkInfoModalLoader.active = true;
                    networkInfoModalLoader.item.showNetworkInfo(ssid, NetworkService.getNetworkInfo(ssid));
                }
            },
            {
                "label": I18n.tr("Edit"),
                "iconName": "edit",
                "visible": saved && NetworkService.connectionEditorPagesSupported,
                "action": () => {
                    PopoutService.closeControlCenter();
                    NetworkService.findWifiProfile(ssid, p => p ? PopoutService.openConnectionEditor(p.uuid, ssid) : PopoutService.openSettingsWithTab("network_connections"));
                }
            },
            {
                "label": network.autoconnect ? I18n.tr("Disable autoconnect") : I18n.tr("Enable autoconnect"),
                "iconName": "autorenew",
                "visible": showSavedOptions && DMSService.apiVersion > 13,
                "action": () => NetworkService.setWifiAutoconnect(ssid, !network.autoconnect)
            },
            {
                "label": I18n.tr("Forget network"),
                "iconName": "delete",
                "destructive": true,
                "visible": showSavedOptions,
                "action": () => NetworkService.forgetWifiNetwork(ssid)
            }
        ];
        wifiMenu.openAt(anchor);
    }

    function wiredMenuItems(adapter, profiles) {
        const uuid = adapter.connectionUuid;
        const editable = profiles.find(c => c.uuid === uuid) ?? (profiles.length === 1 ? profiles[0] : null);
        return [
            {
                "label": I18n.tr("Network Info"),
                "iconName": "info",
                "visible": !!adapter.connected && !!uuid,
                "action": () => root.showWiredInfo(adapter, uuid)
            },
            {
                "label": I18n.tr("Edit"),
                "iconName": "edit",
                "visible": !!editable && NetworkService.connectionEditorPagesSupported,
                "action": () => {
                    PopoutService.closeControlCenter();
                    PopoutService.openConnectionEditor(editable.uuid, editable.id || adapter.name);
                }
            }
        ];
    }

    function showWiredInfo(adapter, uuid) {
        const conn = (NetworkService.wiredConnections || []).find(c => c.uuid === uuid);
        networkWiredInfoModalLoader.active = true;
        networkWiredInfoModalLoader.item.showNetworkInfo(conn?.id || adapter.name, NetworkService.getWiredNetworkInfo(uuid));
    }

    ScriptModel {
        id: wifiListModel
        objectProp: "ssid"

        readonly property bool frozen: wifiMenu.open || root.transitioning
        property var frozenNetworks: []
        readonly property var sortedNetworks: {
            const ssid = NetworkService.currentWifiSSID;
            const pinnedList = root.pinnedNetworks;
            const sorted = [...(NetworkService.wifiNetworks || [])];
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
                const aBucket = Math.floor((a.signal || 0) / CcMetrics.wifiSignalBucket);
                const bBucket = Math.floor((b.signal || 0) / CcMetrics.wifiSignalBucket);
                if (aBucket !== bBucket)
                    return bBucket - aBucket;
                return (a.ssid || "").localeCompare(b.ssid || "");
            });
            return sorted;
        }

        values: frozen ? frozenNetworks : sortedNetworks

        onSortedNetworksChanged: {
            if (!frozen)
                frozenNetworks = sortedNetworks;
        }
        onFrozenChanged: {
            if (frozen)
                frozenNetworks = sortedNetworks;
        }
    }

    ScriptModel {
        id: cellularConnectionsModel
        objectProp: "uuid"
        values: {
            const sorted = [...(NetworkService.cellularConnections || [])];
            sorted.sort((a, b) => {
                if (a.isActive !== b.isActive)
                    return a.isActive ? -1 : 1;
                return (a.id || "").localeCompare(b.id || "");
            });
            return sorted;
        }
    }

    DListView {
        id: pageList
        objectName: "networkList"

        anchors.fill: parent
        clip: true
        spacing: Theme.groupedListGap
        add: null
        displaced: null
        move: null
        model: root.wifiListVisible ? wifiListModel : null

        header: Column {
            width: pageList.width
            spacing: CcMetrics.detailContentGap
            bottomPadding: pageList.count > 0 ? CcMetrics.detailContentGap : 0

            CcGroup {
                visible: NetworkService.connectivityPortal

                CcListRow {
                    iconName: "login"
                    active: true
                    clickable: true
                    title: I18n.tr("Log in to network", "captive portal: open the login page")
                    onClicked: NetworkService.openCaptivePortal()
                }
            }

            DButtonGroup {
                anchors.horizontalCenter: parent.horizontalCenter
                size: "small"
                visible: root.paneSwitchSupported
                model: root.connectionTypes.map(t => root.typeLabels[t] || t)
                currentIndex: Math.max(0, root.connectionTypes.indexOf(root.currentConnectionType))
                selectionMode: "single"
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    root.selectedType = root.connectionTypes[index] || "wifi";
                }
            }

            CcGroup {
                visible: root.wifiMode

                CcToggleRow {
                    iconName: NetworkService.wifiEnabled ? "wifi" : "wifi_off"
                    iconColor: NetworkService.wifiEnabled ? Theme.primary : Theme.surfaceText
                    text: I18n.tr("Wi-Fi", "wireless network, page and section title")
                    description: {
                        if (NetworkService.wifiToggling)
                            return NetworkService.wifiEnabled ? I18n.tr("Disabling WiFi...") : I18n.tr("Enabling WiFi...");
                        if (!NetworkService.wifiEnabled)
                            return I18n.tr("WiFi is off", "network status when the wifi radio is disabled");
                        return NetworkService.currentWifiSSID || I18n.tr("Not connected", "network status");
                    }
                    checked: NetworkService.wifiEnabled
                    toggling: NetworkService.wifiToggling
                    onToggled: NetworkService.toggleWifiRadio()
                }

                CcListRow {
                    id: hotspotRow

                    readonly property bool warnsWifiDrop: NetworkService.wifiEnabled && !root.hotspotWorking && !NetworkService.hotspotEnabled && NetworkService.hotspotWouldDisconnectWifi

                    visible: root.showHotspotRow
                    iconName: NetworkService.hotspotEnabled ? "wifi_tethering" : "wifi_tethering_off"
                    active: NetworkService.hotspotEnabled
                    title: I18n.tr("Hotspot", "hotspot control label")
                    subtitle: {
                        if (warnsWifiDrop)
                            return (NetworkService.hotspotSSID || I18n.tr("Ready", "hotspot ready status")) + " • " + I18n.tr("Will disconnect \"%1\"", "hotspot WiFi disconnection warning").arg(NetworkService.currentWifiSSID);
                        if (root.hotspotWorking)
                            return I18n.tr("Starting...", "hotspot activation status");
                        if (NetworkService.hotspotEnabled)
                            return NetworkService.hotspotSSID || I18n.tr("Running", "hotspot active status");
                        if (!NetworkService.wifiEnabled)
                            return I18n.tr("WiFi disabled", "hotspot unavailable status");
                        return NetworkService.hotspotSSID || I18n.tr("Ready", "hotspot ready status");
                    }
                    subtitleColor: warnsWifiDrop ? Theme.warning : Theme.surfaceVariantText

                    DSpinner {
                        anchors.verticalCenter: parent.verticalCenter
                        size: Theme.iconSizeMedium
                        strokeWidth: CcMetrics.spinnerStroke
                        color: Theme.primary
                        visible: root.hotspotWorking
                        running: visible
                    }

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: NetworkService.hotspotEnabled && NetworkService.hotspotSecured && NetworkService.hotspotExtendedSupported
                        buttonSize: Theme.buttonHeightXS
                        iconSize: Theme.iconSizeMedium
                        iconName: "qr_code"
                        tooltipText: I18n.tr("Show QR Code")
                        iconColor: Theme.surfaceText
                        onClicked: PopoutService.showWifiQRCodeModal(NetworkService.hotspotSSID)
                    }

                    DToggle {
                        anchors.verticalCenter: parent.verticalCenter
                        hideText: true
                        visible: !root.hotspotWorking
                        checked: NetworkService.hotspotEnabled
                        onToggled: checked => {
                            if (!checked) {
                                NetworkService.stopHotspot();
                                return;
                            }
                            if (!NetworkService.wifiEnabled) {
                                root.explainHotspotNeedsWiFi();
                                return;
                            }
                            root.startHotspotWithConfirm();
                        }
                    }
                }
            }

            CcEmptyState {
                visible: root.wifiMode && NetworkService.wifiToggling
                spinning: true
                title: NetworkService.wifiEnabled ? I18n.tr("Disabling WiFi...") : I18n.tr("Enabling WiFi...")
            }

            CcEmptyState {
                visible: root.wifiMode && !NetworkService.wifiEnabled && !NetworkService.wifiToggling
                iconName: "wifi_off"
                title: I18n.tr("WiFi is off", "network status when the wifi radio is disabled")
            }

            CcEmptyState {
                visible: root.wifiScanningEmpty
                spinning: true
                title: I18n.tr("Scanning...")
            }

            CcSectionLabel {
                text: I18n.tr("Available networks")
                visible: root.wifiListVisible
            }

            CcGroup {
                visible: root.ethernetMode && root.networkManager && DMSService.apiVersion > 10

                Repeater {
                    model: NetworkService.ethernetDevices || []

                    Column {
                        id: adapterItem

                        required property var modelData
                        readonly property var profiles: {
                            const byUuid = {};
                            for (const c of (NetworkService.wiredConnections || []))
                                byUuid[c.uuid] = c;
                            return (modelData.profileUuids || []).map(u => byUuid[u]).filter(c => !!c);
                        }

                        width: parent.width

                        CcListRow {
                            id: adapterRow

                            iconName: "lan"
                            active: adapterItem.modelData.connected
                            title: adapterItem.modelData.name
                            subtitle: {
                                if (adapterItem.modelData.connected)
                                    return I18n.tr("Connected") + (adapterItem.modelData.ip ? " • " + adapterItem.modelData.ip : "");
                                return adapterItem.modelData.state === "unavailable" ? I18n.tr("Unavailable") : I18n.tr("Disconnected");
                            }
                            clickable: active && !!adapterItem.modelData.connectionUuid
                            onClicked: root.showWiredInfo(adapterItem.modelData, adapterItem.modelData.connectionUuid)

                            DActionButton {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: NetworkService.ethernetDeviceConnectSupported
                                buttonSize: Theme.buttonHeightXS
                                iconSize: Theme.iconSizeMedium
                                iconName: adapterRow.active ? "link_off" : "link"
                                tooltipText: adapterRow.active ? I18n.tr("Disconnect") : I18n.tr("Connect")
                                iconColor: adapterRow.active ? Theme.error : Theme.primary
                                onClicked: {
                                    if (adapterRow.active)
                                        NetworkService.disconnectEthernetDevice(adapterItem.modelData.name);
                                    else
                                        NetworkService.connectEthernetDevice(adapterItem.modelData.name);
                                }
                            }

                            DActionButton {
                                id: wiredOptionsButton

                                readonly property var menuItems: root.wiredMenuItems(adapterItem.modelData, adapterItem.profiles)

                                anchors.verticalCenter: parent.verticalCenter
                                visible: menuItems.some(i => i.visible)
                                buttonSize: Theme.buttonHeightXS
                                iconSize: Theme.iconSizeMedium
                                iconName: "more_horiz"
                                Accessible.name: I18n.tr("Options")
                                iconColor: Theme.surfaceText
                                onClicked: {
                                    wiredMenu.items = menuItems;
                                    wiredMenu.openAt(wiredOptionsButton);
                                }
                            }
                        }

                        Repeater {
                            model: adapterItem.profiles.length > 1 ? adapterItem.profiles : []

                            CcListRow {
                                id: profileRow

                                required property var modelData

                                paddingH: CcMetrics.rowPaddingH + Theme.spacingL
                                title: modelData.id
                                active: modelData.uuid === adapterItem.modelData.connectionUuid
                                clickable: !active
                                onClicked: NetworkService.connectToSpecificWiredConfig(modelData.uuid, adapterItem.modelData.name)
                            }
                        }
                    }
                }
            }

            CcGroup {
                visible: root.cellularMode && root.networkManager

                CcToggleRow {
                    iconName: "network_cell"
                    iconColor: NetworkService.cellularEnabled ? Theme.primary : Theme.surfaceText
                    text: I18n.tr("Cellular")
                    description: {
                        if (NetworkService.cellularToggling)
                            return NetworkService.cellularEnabled ? I18n.tr("Disabling cellular...") : I18n.tr("Enabling cellular...");
                        if (!NetworkService.cellularHardwareEnabled)
                            return I18n.tr("Unavailable");
                        return NetworkService.cellularEnabled ? "" : I18n.tr("Disabled");
                    }
                    checked: NetworkService.cellularEnabled
                    enabled: NetworkService.cellularHardwareEnabled
                    toggling: NetworkService.cellularToggling
                    onToggled: NetworkService.toggleCellularRadio()
                }
            }

            CcEmptyState {
                visible: root.cellularMode && NetworkService.cellularToggling
                spinning: true
                title: NetworkService.cellularEnabled ? I18n.tr("Disabling cellular...") : I18n.tr("Enabling cellular...")
            }

            CcGroup {
                visible: root.cellularMode && root.networkManager && NetworkService.cellularEnabled && !NetworkService.cellularToggling && (cellularDevices.count > 0 || cellularConnections.count > 0)

                Repeater {
                    id: cellularDevices
                    model: (NetworkService.cellularConnections?.length ?? 0) > 0 ? [] : (NetworkService.cellularDevices || [])

                    CcListRow {
                        id: cellularDeviceRow

                        required property var modelData

                        iconName: "network_cell"
                        active: modelData.connected || false
                        title: modelData.description || modelData.name || I18n.tr("Unknown")
                        subtitle: active ? I18n.tr("Connected") : (modelData.state || I18n.tr("Available"))
                        clickable: true
                        onClicked: NetworkService.toggleNetworkConnection("cellular")

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            buttonSize: Theme.buttonHeightXS
                            iconSize: Theme.iconSizeMedium
                            iconName: cellularDeviceRow.active ? "link_off" : "link"
                            tooltipText: cellularDeviceRow.active ? I18n.tr("Disconnect") : I18n.tr("Connect")
                            iconColor: cellularDeviceRow.active ? Theme.error : Theme.primary
                            onClicked: NetworkService.toggleNetworkConnection("cellular")
                        }
                    }
                }

                Repeater {
                    id: cellularConnections
                    model: cellularConnectionsModel

                    CcListRow {
                        id: cellularRow

                        required property var modelData

                        iconName: "network_cell"
                        active: modelData.isActive
                        title: modelData.id || I18n.tr("Unknown")
                        subtitle: active ? I18n.tr("Connected") : (modelData.type || I18n.tr("Available"))
                        clickable: !active
                        onClicked: NetworkService.connectToSpecificCellularConfig(modelData.uuid)

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            buttonSize: Theme.buttonHeightXS
                            iconSize: Theme.iconSizeMedium
                            iconName: cellularRow.active ? "link_off" : "link"
                            tooltipText: cellularRow.active ? I18n.tr("Disconnect") : I18n.tr("Connect")
                            iconColor: cellularRow.active ? Theme.error : Theme.primary
                            onClicked: {
                                if (cellularRow.active) {
                                    NetworkService.toggleNetworkConnection("cellular");
                                    return;
                                }
                                NetworkService.connectToSpecificCellularConfig(cellularRow.modelData.uuid);
                            }
                        }
                    }
                }
            }

            CcEmptyState {
                visible: root.cellularMode && NetworkService.cellularEnabled && !NetworkService.cellularToggling && (NetworkService.cellularDevices?.length ?? 0) === 0 && cellularConnectionsModel.values.length === 0
                iconName: "network_cell"
                title: I18n.tr("No devices found")
            }
        }

        delegate: CcListRow {
            id: wifiRow

            required property var modelData
            required property int index

            readonly property bool isConnected: modelData.ssid === NetworkService.currentWifiSSID
            readonly property bool isConnecting: NetworkService.isWifiConnecting && NetworkService.connectingSSID === modelData.ssid
            readonly property int signalStrength: modelData.signal || 0
            readonly property bool sharesQrCode: modelData.secured && modelData.saved && !(modelData.enterprise || false)

            width: pageList.width
            topRadius: index === 0 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
            bottomRadius: index === pageList.count - 1 ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
            iconName: {
                if (isConnecting)
                    return "";
                if (signalStrength >= CcMetrics.wifiSignalStrong)
                    return "wifi";
                return signalStrength >= CcMetrics.wifiSignalBucket ? "wifi_2_bar" : "wifi_1_bar";
            }
            active: isConnected
            title: modelData.ssid || I18n.tr("Unknown Network")
            subtitle: {
                const parts = [];
                if (isConnecting)
                    parts.push(I18n.tr("Connecting..."));
                else if (isConnected)
                    parts.push(I18n.tr("Connected"));
                else
                    parts.push(modelData.secured ? I18n.tr("Secured") : I18n.tr("Open", "network security type", true));
                if (modelData.saved)
                    parts.push(I18n.tr("Saved", "wifi network status, network has a saved profile", true));
                parts.push(signalStrength + "%");
                return parts.join(" • ");
            }
            subtitleColor: isConnecting ? Theme.warning : Theme.surfaceVariantText
            clickable: true
            onClicked: {
                if (isConnected || NetworkService.isWifiConnecting)
                    return;
                WifiConnectionActions.connectToNetwork(modelData, {
                    connected: isConnected
                });
            }

            leading: Loader {
                active: wifiRow.isConnecting
                visible: active
                sourceComponent: DSpinner {
                    size: Theme.iconSizeMedium
                    strokeWidth: CcMetrics.spinnerStroke
                    color: Theme.warning
                }
            }

            Loader {
                anchors.verticalCenter: parent.verticalCenter
                active: wifiRow.sharesQrCode
                visible: active
                sourceComponent: DActionButton {
                    buttonSize: Theme.buttonHeightXS
                    iconSize: Theme.iconSizeMedium
                    iconName: "qr_code"
                    tooltipText: I18n.tr("Show QR Code")
                    iconColor: Theme.surfaceText
                    onClicked: PopoutService.showWifiQRCodeModal(wifiRow.modelData.ssid)
                }
            }

            CcPinChip {
                anchors.verticalCenter: parent.verticalCenter
                pinned: root.pinnedNetworks.includes(wifiRow.modelData.ssid)
                onToggled: root.togglePin(wifiRow.modelData.ssid)
            }

            DActionButton {
                id: wifiOptionsButton
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: Theme.buttonHeightXS
                iconSize: Theme.iconSizeMedium
                iconName: "more_horiz"
                Accessible.name: I18n.tr("Options")
                iconColor: Theme.surfaceText
                onClicked: root.openWifiMenu(wifiRow.modelData, wifiRow.isConnected, wifiRow.isConnecting, wifiOptionsButton)
            }
        }
    }

    CcMenu {
        id: wifiMenu
        transientSurfaceTracker: root.transientSurfaceTracker
    }

    CcMenu {
        id: wiredMenu
        transientSurfaceTracker: root.transientSurfaceTracker
    }

    Loader {
        id: networkInfoModalLoader
        active: false
        sourceComponent: NetworkInfoModal {}
    }

    Loader {
        id: networkWiredInfoModalLoader
        active: false
        sourceComponent: NetworkInfoModal {
            wired: true
        }
    }

    Loader {
        id: hotspotConfirmLoader
        active: false
        sourceComponent: ConfirmModal {}
    }
}
