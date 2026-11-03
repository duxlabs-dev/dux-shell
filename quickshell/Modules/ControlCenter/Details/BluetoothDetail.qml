pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../../../Common/QmlUtils.js" as QmlUtils

Item {
    id: root

    Ref {
        service: BatteryService
    }

    implicitHeight: column.height

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var transientSurfaceTracker: null

    readonly property string title: I18n.tr("Bluetooth")
    readonly property var adapter: BluetoothService.adapter
    readonly property bool adapterEnabled: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false
    readonly property var pinnedDevices: QmlUtils.normalizePinList((CacheData.bluetoothDevicePins || {})["preferredDevice"])
    property var devicesBeingPaired: new Set()

    readonly property Item headerActions: Row {
        spacing: Theme.spacingS

        DDropdown {
            id: adapterDropdown

            function adapterLabel(adapter) {
                const name = adapter.name || adapter.adapterId;
                const collides = BluetoothService.adapters.some(a => a !== adapter && (a.name || a.adapterId) === name);
                return collides ? `${name} (${adapter.adapterId})` : name;
            }

            anchors.verticalCenter: parent.verticalCenter
            visible: BluetoothService.adapters.length > 1
            compactMode: true
            dropdownWidth: CcMetrics.headerDropdownWidth
            popupWidth: CcMetrics.headerPopupWidth
            alignPopupRight: true
            options: BluetoothService.adapters.map(a => adapterLabel(a))
            currentValue: BluetoothService.adapter ? adapterLabel(BluetoothService.adapter) : ""
            onValueChanged: value => {
                const selected = BluetoothService.adapters.find(a => adapterDropdown.adapterLabel(a) === value);
                SessionData.set("bluetoothAdapterOverride", selected?.dbusPath ?? "");
            }
        }

        DButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.adapterEnabled
            buttonHeight: Theme.buttonHeightXS
            iconName: root.discovering ? "stop" : "bluetooth_searching"
            iconSize: Theme.iconSizeSmall
            text: root.discovering ? I18n.tr("Scanning...") : I18n.tr("Scan")
            backgroundColor: Theme.secondaryContainer
            textColor: Theme.onSecondaryContainer
            onClicked: {
                if (!root.adapter)
                    return;
                root.adapter.discovering = !root.adapter.discovering;
            }
        }
    }

    signal showCodecSelector(var device)

    function dismissTransient() {
        if (!deviceMenu.open)
            return false;
        deviceMenu.close();
        return true;
    }

    readonly property bool controlCenterPopoutVisible: PopoutService.controlCenterPopout?.shouldBeVisible ?? false

    onControlCenterPopoutVisibleChanged: {
        if (!controlCenterPopoutVisible)
            deviceMenu.close();
    }

    function isDeviceBeingPaired(deviceAddress) {
        return devicesBeingPaired.has(deviceAddress);
    }

    function handlePairDevice(device) {
        if (!device)
            return;
        const deviceAddr = device.address;
        const pairingSet = devicesBeingPaired;
        pairingSet.add(deviceAddr);
        devicesBeingPairedChanged();
        BluetoothService.pairDevice(device, response => {
            pairingSet.delete(deviceAddr);
            devicesBeingPairedChanged();
            if (response.error) {
                ToastService.showError(I18n.tr("Pairing failed"), response.error);
                return;
            }
            if (!BluetoothService.enhancedPairingAvailable)
                ToastService.showInfo(I18n.tr("Device paired"));
        });
    }

    function togglePin(address) {
        CacheData.set("bluetoothDevicePins", QmlUtils.togglePinEntry(CacheData.bluetoothDevicePins, "preferredDevice", address, CcMetrics.maxPins));
    }

    function forgetDevice(device) {
        if (!BluetoothService.enhancedPairingAvailable) {
            device.forget();
            return;
        }
        DMSService.bluetoothRemove(BluetoothService.getDevicePath(device), response => {
            if (!response.error)
                return;
            ToastService.showError(I18n.tr("Failed to remove device"), response.error);
        });
    }

    function openDeviceMenu(device, anchor) {
        const connected = device.connected;
        deviceMenu.items = [
            {
                "label": connected ? I18n.tr("Disconnect") : I18n.tr("Connect"),
                "iconName": connected ? "bluetooth_disabled" : "bluetooth_connected",
                "action": () => {
                    if (connected) {
                        device.disconnect();
                        return;
                    }
                    BluetoothService.connectDeviceWithTrust(device);
                }
            },
            {
                "label": I18n.tr("Audio Codec"),
                "iconName": "graphic_eq",
                "visible": connected && BluetoothService.isAudioDevice(device),
                "action": () => root.showCodecSelector(device)
            },
            {
                "label": device.trusted ? I18n.tr("Untrust", "verb, bluetooth device menu action removing trust") : I18n.tr("Trust"),
                "iconName": device.trusted ? "shield_with_heart" : "verified_user",
                "action": () => device.trusted = !device.trusted
            },
            {
                "label": I18n.tr("Forget Device"),
                "iconName": "delete",
                "destructive": true,
                "action": () => root.forgetDevice(device)
            }
        ];
        deviceMenu.openAt(anchor);
    }

    ScriptModel {
        id: pairedDevicesModel
        objectProp: "address"
        values: {
            if (!root.adapter?.devices)
                return [];
            const pinnedList = root.pinnedDevices;
            const devices = [...root.adapter.devices.values.filter(dev => dev && (dev.paired || dev.trusted))];
            devices.sort((a, b) => {
                const aPinnedIndex = pinnedList.indexOf(a.address);
                const bPinnedIndex = pinnedList.indexOf(b.address);
                if (aPinnedIndex !== -1 || bPinnedIndex !== -1) {
                    if (aPinnedIndex === -1)
                        return 1;
                    if (bPinnedIndex === -1)
                        return -1;
                    return aPinnedIndex - bPinnedIndex;
                }
                if (a.connected !== b.connected)
                    return a.connected ? -1 : 1;
                return (b.signalStrength || 0) - (a.signalStrength || 0);
            });
            return devices;
        }
    }

    ScriptModel {
        id: availableDevicesModel
        objectProp: "address"
        values: {
            if (!root.discovering || !Bluetooth.devices)
                return [];
            const filtered = Bluetooth.devices.values.filter(dev => dev && !dev.paired && !dev.pairing && !dev.blocked && (dev.signalStrength === undefined || dev.signalStrength > 0));
            return BluetoothService.sortDevices(filtered);
        }
    }

    DFlickable {
        anchors.fill: parent
        contentHeight: column.height
        clip: true

        Column {
            id: column
            width: parent.width
            spacing: CcMetrics.detailContentGap

            CcGroup {
                CcToggleRow {
                    iconName: "bluetooth"
                    iconColor: root.adapterEnabled ? Theme.primary : Theme.surfaceText
                    text: I18n.tr("Bluetooth")
                    description: root.adapter ? (root.adapter.name || root.adapter.adapterId) : I18n.tr("No Bluetooth adapter found")
                    checked: root.adapterEnabled
                    enabled: !!root.adapter
                    onToggled: BluetoothService.toggleBluetooth()
                }
            }

            CcSectionLabel {
                text: I18n.tr("Paired", "adjective, bluetooth paired devices section label and device status")
                visible: pairedGroup.visible
            }

            CcGroup {
                id: pairedGroup
                visible: root.adapterEnabled && pairedRepeater.count > 0

                Repeater {
                    id: pairedRepeater
                    model: pairedDevicesModel

                    CcListRow {
                        id: pairedRow

                        required property var modelData

                        readonly property string currentCodec: BluetoothService.deviceCodecs[modelData.address] || ""
                        readonly property bool isConnecting: modelData.state === BluetoothDeviceState.Connecting
                        readonly property bool isConnected: modelData.connected
                        readonly property string deviceName: modelData.name || modelData.deviceName || I18n.tr("Unknown Device")
                        readonly property string batteryText: {
                            if (modelData.batteryAvailable)
                                return Math.round(modelData.battery * 100) + "%";
                            const lowered = deviceName.toLowerCase();
                            const btBattery = BatteryService.bluetoothDevices.find(dev => dev.name === deviceName || dev.name.toLowerCase().includes(lowered) || lowered.includes(dev.name.toLowerCase()));
                            return btBattery ? btBattery.percentage + "%" : "";
                        }

                        Component.onCompleted: {
                            if (!isConnected || !BluetoothService.isAudioDevice(modelData))
                                return;
                            BluetoothService.refreshDeviceCodec(modelData);
                        }

                        iconName: BluetoothService.getDeviceIcon(modelData)
                        iconColor: {
                            if (isConnecting)
                                return Theme.warning;
                            return contentColor;
                        }
                        active: isConnected
                        title: deviceName
                        subtitle: {
                            if (isConnecting)
                                return I18n.tr("Connecting...");
                            const parts = [isConnected ? I18n.tr("Connected") : I18n.tr("Paired")];
                            if (isConnected && currentCodec)
                                parts.push(currentCodec);
                            if (batteryText)
                                parts.push(batteryText);
                            if (modelData.signalStrength > 0)
                                parts.push(modelData.signalStrength + "%");
                            return parts.join(" • ");
                        }
                        subtitleColor: isConnecting ? Theme.warning : Theme.surfaceVariantText
                        clickable: true
                        onClicked: {
                            if (isConnected) {
                                modelData.disconnect();
                                return;
                            }
                            BluetoothService.connectDeviceWithTrust(modelData);
                        }

                        CcPinChip {
                            anchors.verticalCenter: parent.verticalCenter
                            pinned: root.pinnedDevices.includes(pairedRow.modelData.address)
                            onToggled: root.togglePin(pairedRow.modelData.address)
                        }

                        DActionButton {
                            id: optionsButton
                            anchors.verticalCenter: parent.verticalCenter
                            buttonSize: Theme.buttonHeightXS
                            iconSize: Theme.iconSizeMedium
                            iconName: "more_horiz"
                            Accessible.name: I18n.tr("Options")
                            iconColor: Theme.surfaceText
                            onClicked: root.openDeviceMenu(pairedRow.modelData, optionsButton)
                        }
                    }
                }
            }

            CcEmptyState {
                visible: root.adapterEnabled && root.discovering && availableRepeater.count === 0
                spinning: true
                title: I18n.tr("Scanning...")
            }

            CcSectionLabel {
                text: I18n.tr("Available")
                visible: availableGroup.visible
            }

            CcGroup {
                id: availableGroup
                visible: root.adapterEnabled && availableRepeater.count > 0

                Repeater {
                    id: availableRepeater
                    model: availableDevicesModel

                    CcListRow {
                        required property var modelData

                        readonly property bool canConnect: BluetoothService.canConnect(modelData)
                        readonly property bool isBusy: BluetoothService.isDeviceBusy(modelData) || root.isDeviceBeingPaired(modelData.address)
                        readonly property bool isInteractive: canConnect && !isBusy

                        iconName: BluetoothService.getDeviceIcon(modelData)
                        title: modelData.name || modelData.deviceName || I18n.tr("Unknown Device")
                        subtitle: {
                            if (modelData.pairing || isBusy)
                                return I18n.tr("Pairing...", "bluetooth device status while pairing is in progress");
                            if (modelData.blocked)
                                return I18n.tr("Blocked", "adjective, bluetooth device status");
                            const signal = BluetoothService.getSignalStrength(modelData);
                            return modelData.signalStrength > 0 ? signal + " • " + modelData.signalStrength + "%" : signal;
                        }
                        trailingBadge: {
                            if (isBusy)
                                return I18n.tr("Pairing...");
                            return canConnect ? I18n.tr("Pair") : I18n.tr("Cannot pair");
                        }
                        trailingBadgeColor: isInteractive ? Theme.primary : Theme.surfaceVariantText
                        enabled: isInteractive
                        clickable: true
                        onClicked: root.handlePairDevice(modelData)
                    }
                }
            }

            CcEmptyState {
                visible: !root.adapter
                iconName: "bluetooth_disabled"
                title: I18n.tr("No Bluetooth adapter found")
            }
        }
    }

    CcMenu {
        id: deviceMenu
        transientSurfaceTracker: root.transientSurfaceTracker
    }

    Connections {
        target: DMSService

        function onBluetoothPairingRequest(data) {
            const modal = PopoutService.ensureBluetoothPairingModal();
            if (!modal || modal.token === data.token)
                return;
            modal.show(data);
        }
    }
}
