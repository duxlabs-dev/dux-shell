pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Services
import qs.DCommon.Widgets
import "../../../Common/QmlUtils.js" as QmlUtils

Item {
    id: root

    implicitHeight: column.height

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property string initialDeviceName: ""
    property string instanceId: ""
    property string screenName: ""
    property string screenModel: ""
    property string currentDeviceName: ""

    readonly property string title: I18n.tr("Brightness")
    readonly property var devices: BrightnessService.devices || []
    readonly property bool multipleDevices: devices.length > 1
    readonly property bool showPins: screenName.length > 0 && multipleDevices

    readonly property Item headerActions: DActionButton {
        visible: root.showPins && QmlUtils.normalizePinList((CacheData.brightnessDevicePins || {})[root.getScreenPinKey()]).length > 0
        buttonSize: CcMetrics.headerActionSize
        iconSize: CcMetrics.headerActionIconSize
        iconName: "keep_off"
        iconColor: Theme.surfaceText
        tooltipText: I18n.tr("Clear All")
        Accessible.name: I18n.tr("Clear All")
        onClicked: root.clearScreenPins()
    }

    signal deviceNameChanged(string newDeviceName)

    function getScreenPinKey() {
        if (!screenName)
            return "";
        const screen = Quickshell.screens.find(s => s.name === screenName);
        if (screen)
            return SettingsData.getScreenDisplayName(screen);
        if (SettingsData.displayNameMode === "model" && screenModel)
            return screenModel;
        return screenName;
    }

    function resolveCurrentDevice() {
        if (!BrightnessService.brightnessAvailable || devices.length === 0)
            return "";
        const pinned = BrightnessService.pinnedDevices(getScreenPinKey());
        if (pinned.length > 0)
            return pinned[0];
        if (instanceId) {
            const widget = (SettingsData.controlCenterWidgets || []).find(w => w.id === "brightnessSlider" && w.instanceId === instanceId);
            if (widget?.deviceName && devices.find(d => d.name === widget.deviceName))
                return widget.deviceName;
        }
        if (BrightnessService.currentDevice && devices.find(d => d.name === BrightnessService.currentDevice))
            return BrightnessService.currentDevice;
        if (initialDeviceName && devices.find(d => d.name === initialDeviceName))
            return initialDeviceName;
        const backlight = devices.find(d => d.class === "backlight");
        if (backlight)
            return backlight.name;
        const ddc = devices.find(d => d.class === "ddc");
        if (ddc)
            return ddc.name;
        return devices[0].name;
    }

    function selectDevice(deviceName) {
        if (!deviceName || deviceName === currentDeviceName)
            return;
        const pinned = QmlUtils.normalizePinList((CacheData.brightnessDevicePins || {})[getScreenPinKey()]);
        if (pinned.length > 0 && !pinned.includes(deviceName))
            clearScreenPins();
        currentDeviceName = deviceName;
        BrightnessService.setCurrentDevice(deviceName, true);
        deviceNameChanged(deviceName);
    }

    function isDevicePinnedToScreen(deviceName) {
        const pinKey = getScreenPinKey();
        if (!pinKey || !deviceName)
            return false;
        return QmlUtils.normalizePinList((CacheData.brightnessDevicePins || {})[pinKey]).includes(deviceName);
    }

    function togglePinForDevice(deviceName) {
        const pinKey = getScreenPinKey();
        if (!pinKey || !deviceName)
            return;
        CacheData.set("brightnessDevicePins", QmlUtils.togglePinEntry(CacheData.brightnessDevicePins, pinKey, deviceName, Infinity));
    }

    function clearScreenPins() {
        const pins = JSON.parse(JSON.stringify(CacheData.brightnessDevicePins || {}));
        delete pins[getScreenPinKey()];
        CacheData.set("brightnessDevicePins", pins);
    }

    function deviceIcon(device, brightness) {
        const deviceClass = device.class || "";
        if (deviceClass !== "backlight" && deviceClass !== "ddc" && deviceClass !== "software")
            return (device.name || "").includes("kbd") ? "keyboard" : "lightbulb";
        if (brightness <= CcMetrics.brightnessLowMax)
            return "brightness_low";

        return brightness <= CcMetrics.brightnessMediumMax ? "brightness_medium" : "brightness_high";
    }

    function deviceClassLabel(device) {
        switch (device.class || "") {
        case "backlight":
            return I18n.tr("Backlight device");
        case "ddc":
            return I18n.tr("DDC/CI monitor");
        case "leds":
            return I18n.tr("LED device");
        case "software":
            return I18n.tr("Software dimming", "brightness device class label, dimmed through the gamma ramp");
        default:
            return device.class || "";
        }
    }

    Component.onCompleted: currentDeviceName = resolveCurrentDevice()

    DFlickable {
        anchors.fill: parent
        contentHeight: column.height
        clip: true

        Column {
            id: column
            width: parent.width
            spacing: CcMetrics.detailContentGap

            CcEmptyState {
                visible: !BrightnessService.brightnessAvailable || root.devices.length === 0
                iconName: BrightnessService.brightnessAvailable ? "brightness_6" : "error"
                iconColor: BrightnessService.brightnessAvailable ? Theme.primary : Theme.error
                title: BrightnessService.brightnessAvailable ? I18n.tr("No brightness devices available") : I18n.tr("Brightness control not available")
            }

            CcSectionLabel {
                visible: root.devices.length > 0
                text: I18n.tr("Devices")
            }

            CcGroup {
                visible: root.devices.length > 0

                Repeater {
                    model: root.devices

                    Column {
                        id: deviceItem

                        required property var modelData

                        readonly property string deviceName: modelData.name || ""
                        readonly property bool active: deviceName === root.currentDeviceName
                        readonly property real deviceBrightness: {
                            BrightnessService.brightnessVersion;
                            return BrightnessService.getDeviceBrightness(deviceName);
                        }
                        readonly property bool pinnedHere: {
                            CacheData.brightnessDevicePins;
                            return root.isDevicePinnedToScreen(deviceName);
                        }
                        readonly property bool exponential: SessionData.getBrightnessExponential(deviceName)
                        readonly property real exponent: SessionData.getBrightnessExponent(deviceName)

                        width: parent?.width ?? 0
                        spacing: Theme.groupedListGap

                        CcListRow {
                            iconName: root.deviceIcon(deviceItem.modelData, deviceItem.deviceBrightness)
                            active: deviceItem.active
                            title: BrightnessService.deviceTitle(deviceItem.modelData)
                            subtitle: [deviceItem.deviceName, root.deviceClassLabel(deviceItem.modelData), Math.round(deviceItem.deviceBrightness) + "%"].join(" • ")
                            clickable: true
                            onClicked: root.selectDevice(deviceItem.deviceName)

                            CcPinChip {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.showPins
                                pinned: deviceItem.pinnedHere
                                onToggled: root.togglePinForDevice(deviceItem.deviceName)
                            }
                        }

                        CcToggleRow {
                            visible: deviceItem.active && deviceItem.modelData.class !== "software"
                            text: I18n.tr("Exponential", "adjective, toggle for an exponential brightness curve per device")
                            checked: deviceItem.exponential
                            onToggled: checked => SessionData.setBrightnessExponential(deviceItem.deviceName, checked)
                        }

                        CcListRow {
                            visible: deviceItem.active && deviceItem.exponential && deviceItem.modelData.class !== "software"
                            title: I18n.tr("Curve")

                            DNumberStepper {
                                anchors.verticalCenter: parent.verticalCenter
                                text: deviceItem.exponent.toFixed(1)
                                decrementEnabled: deviceItem.exponent > CcMetrics.brightnessExponentMin
                                incrementEnabled: deviceItem.exponent < CcMetrics.brightnessExponentMax
                                onDecrement: () => SessionData.setBrightnessExponent(deviceItem.deviceName, Math.max(CcMetrics.brightnessExponentMin, Math.round((deviceItem.exponent - CcMetrics.brightnessExponentStep) * 10) / 10))
                                onIncrement: () => SessionData.setBrightnessExponent(deviceItem.deviceName, Math.min(CcMetrics.brightnessExponentMax, Math.round((deviceItem.exponent + CcMetrics.brightnessExponentStep) * 10) / 10))
                            }
                        }
                    }
                }
            }
        }
    }
}
