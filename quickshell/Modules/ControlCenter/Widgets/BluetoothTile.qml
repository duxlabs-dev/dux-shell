import QtQuick
import qs.Common
import qs.Services
import Quickshell.Bluetooth
import "../../../Common/QmlUtils.js" as QmlUtils

CcTile {
    id: root

    readonly property var adapter: BluetoothService.adapter
    readonly property bool adapterOn: !!(BluetoothService.available && adapter && adapter.enabled)

    readonly property var primaryDevice: {
        if (!live || !adapterOn || !adapter.devices)
            return null;
        return adapter.devices.values.find(dev => dev && (dev.paired || dev.trusted) && dev.connected) || null;
    }

    function deviceLabel(device) {
        const name = device.name || device.alias || device.deviceName || I18n.tr("Connected Device", "bluetooth status");
        if (device.batteryAvailable)
            return `${name} • ${Math.round(device.battery * 100)}%`;
        const lowered = name.toLowerCase();
        const btBattery = BatteryService.bluetoothDevices.find(dev => dev.name === name || dev.name.toLowerCase().includes(lowered) || lowered.includes(dev.name.toLowerCase()));
        return btBattery ? `${name} • ${btBattery.percentage}%` : name;
    }

    iconName: "bluetooth"
    iconBlinking: BluetoothService.connecting

    Ref {
        service: BatteryService
    }
    title: {
        if (!BluetoothService.available)
            return I18n.tr("Bluetooth", "bluetooth status");
        if (!adapter)
            return I18n.tr("No adapter", "bluetooth status");
        return adapter.enabled ? I18n.tr("Enabled", "bluetooth status") : I18n.tr("Disabled", "bluetooth status");
    }
    denseTitle: {
        if (!adapter)
            return "";
        return primaryDevice ? deviceLabel(primaryDevice) : I18n.tr("Bluetooth", "bluetooth status");
    }
    subtitle: {
        if (!BluetoothService.available)
            return I18n.tr("No adapters", "bluetooth status");
        if (!adapterOn)
            return I18n.tr("Off", "bluetooth status");
        if (BluetoothService.connecting)
            return I18n.tr("Connecting...", "bluetooth status");
        return primaryDevice ? deviceLabel(primaryDevice) : I18n.tr("No devices", "bluetooth status");
    }
    active: adapterOn
    showExpand: true
    enabled: widgetDef?.enabled ?? true

    onClicked: BluetoothService.toggleBluetooth()
    expandedContent: Component {
        CcTileActions {
            readonly property var pins: QmlUtils.normalizePinList((CacheData.bluetoothDevicePins || {}).preferredDevice)
            readonly property var devices: {
                if (!root.adapterOn || !root.adapter?.devices)
                    return [];
                return root.adapter.devices.values.filter(device => device && (device.paired || device.trusted)).sort((a, b) => {
                    const aPin = pins.indexOf(a.address);
                    const bPin = pins.indexOf(b.address);
                    if (aPin !== bPin)
                        return (aPin < 0 ? Infinity : aPin) - (bPin < 0 ? Infinity : bPin);
                    return Number(b.connected) - Number(a.connected);
                });
            }
            actions: devices.map(device => ({
                        text: root.deviceLabel(device),
                        icon: BluetoothService.getDeviceIcon(device),
                        toggle: true,
                        active: device.connected,
                        enabled: device.state !== BluetoothDeviceState.Connecting,
                        trigger: () => {
                            if (device.connected) {
                                device.disconnect();
                                return;
                            }
                            BluetoothService.connectDeviceWithTrust(device);
                        }
                    })).concat([
                {
                    text: I18n.tr("Devices"),
                    icon: "bluetooth_searching",
                    trigger: () => root.expandClicked()
                }
            ])
        }
    }
}
