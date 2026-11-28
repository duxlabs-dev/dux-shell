pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root
    // !TODO: compat facade for plugins, consumers moved to BrightnessService/NightModeService/RefreshRateService
    readonly property bool brightnessAvailable: BrightnessService.brightnessAvailable
    readonly property var devices: BrightnessService.devices
    readonly property int brightnessVersion: BrightnessService.brightnessVersion
    readonly property string currentDevice: BrightnessService.currentDevice
    readonly property string lastIpcDevice: BrightnessService.lastIpcDevice
    readonly property int brightnessLevel: BrightnessService.brightnessLevel
    readonly property bool nightModeEnabled: NightModeService.nightModeEnabled
    readonly property bool automationAvailable: NightModeService.automationAvailable
    readonly property bool gammaControlAvailable: NightModeService.gammaControlAvailable
    readonly property bool gammaAdjustAvailable: NightModeService.gammaAdjustAvailable
    readonly property int gammaCurrentTemp: NightModeService.gammaCurrentTemp
    readonly property string gammaNextTransition: NightModeService.gammaNextTransition
    readonly property string gammaSunriseTime: NightModeService.gammaSunriseTime
    readonly property string gammaSunsetTime: NightModeService.gammaSunsetTime
    readonly property bool gammaIsDay: NightModeService.gammaIsDay

    signal brightnessChanged(bool showOsd, var deviceIds)
    signal deviceSwitched

    Connections {
        target: BrightnessService

        function onBrightnessChanged(showOsd, deviceIds) {
            root.brightnessChanged(showOsd, deviceIds);
        }

        function onDeviceSwitched() {
            root.deviceSwitched();
        }
    }

    function setBrightness(percentage, device, suppressOsd) {
        BrightnessService.setBrightness(percentage, device, suppressOsd);
    }

    function setCurrentDevice(deviceName, saveToSession = false) {
        BrightnessService.setCurrentDevice(deviceName, saveToSession);
    }

    function getDeviceBrightness(deviceName) {
        return BrightnessService.getDeviceBrightness(deviceName);
    }

    function getDefaultDevice() {
        return BrightnessService.getDefaultDevice();
    }

    function getCurrentDeviceInfo() {
        return BrightnessService.getCurrentDeviceInfo();
    }

    function getCurrentDeviceInfoByName(deviceName) {
        return BrightnessService.getCurrentDeviceInfoByName(deviceName);
    }

    function brightnessMinimum(deviceInfo) {
        return BrightnessService.brightnessMinimum(deviceInfo);
    }

    function brightnessMaximum(deviceInfo) {
        return BrightnessService.brightnessMaximum(deviceInfo);
    }

    function brightnessUnit(deviceInfo) {
        return BrightnessService.brightnessUnit(deviceInfo);
    }

    function brightnessIconName(deviceInfo, level) {
        return BrightnessService.brightnessIconName(deviceInfo, level);
    }

    function toggleNightMode() {
        NightModeService.toggleNightMode();
    }

    function setDisplayGamma(gamma) {
        NightModeService.setDisplayGamma(gamma);
    }

    function setDisplayContrast(contrast) {
        NightModeService.setDisplayContrast(contrast);
    }
}
