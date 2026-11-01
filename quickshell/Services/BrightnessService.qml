pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../Common/QmlUtils.js" as QmlUtils

Singleton {
    id: root
    readonly property var log: Log.scoped("BrightnessService")

    property bool brightnessAvailable: devices.length > 0
    property var devices: []
    property var deviceBrightness: ({})
    property var deviceBrightnessUserSet: ({})
    property var deviceMaxCache: ({})
    property var userControlledDevices: ({})
    property var pendingOsdDevices: ({})
    property int brightnessVersion: 0
    property string currentDevice: ""
    property string lastIpcDevice: ""
    property var lastIpcGroup: []
    property int brightnessLevel: {
        brightnessVersion;
        const deviceToUse = lastIpcDevice === "" ? getDefaultDevice() : (lastIpcDevice || currentDevice);
        if (!deviceToUse) {
            return 50;
        }

        return getDeviceBrightness(deviceToUse);
    }
    property bool brightnessInitialized: false
    property bool suppressOsd: true

    signal brightnessChanged(bool showOsd)
    signal deviceSwitched

    function markDeviceUserControlled(deviceId) {
        const newControlled = Object.assign({}, userControlledDevices);
        newControlled[deviceId] = Date.now();
        userControlledDevices = newControlled;
    }

    function isDeviceUserControlled(deviceId) {
        const controlTime = userControlledDevices[deviceId];
        if (!controlTime) {
            return false;
        }
        return (Date.now() - controlTime) < 1000;
    }

    function clearDeviceUserControlled(deviceId) {
        const newControlled = Object.assign({}, userControlledDevices);
        delete newControlled[deviceId];
        userControlledDevices = newControlled;
    }

    function markDevicePendingOsd(deviceId) {
        const newPending = Object.assign({}, pendingOsdDevices);
        newPending[deviceId] = true;
        pendingOsdDevices = newPending;
    }

    function clearDevicePendingOsd(deviceId) {
        const newPending = Object.assign({}, pendingOsdDevices);
        delete newPending[deviceId];
        pendingOsdDevices = newPending;
    }

    function updateSingleDevice(device) {
        if (device.class === "leds") {
            return;
        }

        const isUserControlled = isDeviceUserControlled(device.id);
        if (isUserControlled) {
            return;
        }

        const deviceIndex = devices.findIndex(d => d.id === device.id);
        if (deviceIndex !== -1) {
            const newDevices = [...devices];
            const cachedMax = deviceMaxCache[device.id];

            let displayMax = cachedMax || (device.class === "ddc" ? device.max : 100);
            if (displayMax > 0 && !cachedMax) {
                const newCache = Object.assign({}, deviceMaxCache);
                newCache[device.id] = displayMax;
                deviceMaxCache = newCache;
            }

            newDevices[deviceIndex] = {
                "id": device.id,
                "name": device.id,
                "class": device.class,
                "current": device.current,
                "percentage": device.currentPercent,
                "max": device.max,
                "backend": device.backend,
                "displayMax": displayMax
            };
            devices = newDevices;
        }

        const isExponential = SessionData.getBrightnessExponential(device.id);
        const userSetValue = deviceBrightnessUserSet[device.id];

        let displayValue = device.currentPercent;
        if (isExponential) {
            if (userSetValue !== undefined) {
                const exponent = SessionData.getBrightnessExponent(device.id);
                const expectedHardware = Math.round(Math.pow(userSetValue / 100.0, exponent) * 100.0);
                if (Math.abs(device.currentPercent - expectedHardware) > 2) {
                    const newUserSet = Object.assign({}, deviceBrightnessUserSet);
                    delete newUserSet[device.id];
                    deviceBrightnessUserSet = newUserSet;
                    SessionData.clearBrightnessUserSetValue(device.id);
                    displayValue = linearToExponential(device.currentPercent, device.id);
                } else {
                    displayValue = userSetValue;
                }
            } else {
                displayValue = linearToExponential(device.currentPercent, device.id);
            }
        }

        const oldValue = deviceBrightness[device.id];
        const newBrightness = Object.assign({}, deviceBrightness);
        newBrightness[device.id] = displayValue;
        deviceBrightness = newBrightness;
        brightnessVersion++;

        const isPendingOsd = pendingOsdDevices[device.id] === true;
        if (isPendingOsd) {
            clearDevicePendingOsd(device.id);
            if (!suppressOsd) {
                brightnessChanged(true);
            }
            return;
        }

        if (!brightnessInitialized || oldValue === displayValue) {
            return;
        }
        if (suppressOsd) {
            return;
        }
        brightnessChanged(true);
    }

    function updateFromBrightnessState(state) {
        if (!state || !state.devices) {
            return;
        }

        const newMaxCache = Object.assign({}, deviceMaxCache);
        devices = state.devices.map(d => {
            const cachedMax = deviceMaxCache[d.id];
            let displayMax = cachedMax || (d.class === "ddc" ? d.max : 100);
            if (displayMax > 0 && !cachedMax) {
                newMaxCache[d.id] = displayMax;
            }
            return {
                "id": d.id,
                "name": d.id,
                "class": d.class,
                "current": d.current,
                "percentage": d.currentPercent,
                "max": d.max,
                "backend": d.backend,
                "displayMax": displayMax
            };
        });
        deviceMaxCache = newMaxCache;

        const newBrightness = {};
        let anyDeviceBrightnessChanged = false;

        for (const device of state.devices) {
            const isExponential = SessionData.getBrightnessExponential(device.id);
            const userSetValue = deviceBrightnessUserSet[device.id];
            const oldValue = deviceBrightness[device.id];

            if (isExponential) {
                if (userSetValue !== undefined) {
                    newBrightness[device.id] = userSetValue;
                } else {
                    newBrightness[device.id] = linearToExponential(device.currentPercent, device.id);
                }
            } else {
                newBrightness[device.id] = device.currentPercent;
            }

            const newValue = newBrightness[device.id];
            if (oldValue !== undefined && oldValue !== newValue) {
                anyDeviceBrightnessChanged = true;
            }
        }
        deviceBrightness = newBrightness;
        brightnessVersion++;

        brightnessAvailable = devices.length > 0;

        if (devices.length > 0 && !currentDevice) {
            const lastDevice = SessionData.lastBrightnessDevice || "";
            const deviceExists = devices.some(d => d.id === lastDevice);
            if (deviceExists) {
                setCurrentDevice(lastDevice, false);
            } else {
                const nonKbdDevice = devices.find(d => !d.id.includes("kbd"));
                const defaultDevice = internalPanelDevice() || nonKbdDevice || devices[0];
                setCurrentDevice(defaultDevice.id, false);
            }
        }

        const shouldShowOsd = brightnessInitialized && anyDeviceBrightnessChanged && !suppressOsd;

        if (!brightnessInitialized) {
            brightnessInitialized = true;
        }

        if (shouldShowOsd) {
            brightnessChanged(true);
        }
    }

    function setBrightness(percentage, device, suppressOsd) {
        const actualDevice = device === "" ? getDefaultDevice() : (device || currentDevice || getDefaultDevice());
        if (!actualDevice) {
            log.warn("No device selected for brightness change");
            return;
        }

        if (actualDevice !== lastIpcDevice) {
            lastIpcDevice = actualDevice;
        }
        if (lastIpcGroup.length > 0)
            lastIpcGroup = [];

        const deviceInfo = getCurrentDeviceInfoByName(actualDevice);
        const isExponential = deviceInfo?.class !== "software" && SessionData.getBrightnessExponential(actualDevice);
        const minValue = brightnessMinimum(deviceInfo);
        const maxValue = brightnessMaximum(deviceInfo);

        if (maxValue <= 0) {
            log.warn("Invalid max value for device", actualDevice, "- skipping brightness change");
            return;
        }

        const clampedValue = Math.max(minValue, Math.min(maxValue, percentage));

        if (!DMSService.isConnected) {
            log.warn("Not connected to DMS");
            return;
        }

        const isLedDevice = deviceInfo?.class === "leds";

        if (suppressOsd) {
            markDeviceUserControlled(actualDevice);
        } else if (!isLedDevice) {
            markDevicePendingOsd(actualDevice);
        }

        const newBrightness = Object.assign({}, deviceBrightness);
        newBrightness[actualDevice] = clampedValue;
        deviceBrightness = newBrightness;
        brightnessVersion++;

        if (isLedDevice && !suppressOsd) {
            brightnessChanged(true);
        }

        if (isExponential) {
            const newUserSet = Object.assign({}, deviceBrightnessUserSet);
            newUserSet[actualDevice] = clampedValue;
            deviceBrightnessUserSet = newUserSet;
            SessionData.setBrightnessUserSetValue(actualDevice, clampedValue);
        }

        const params = {
            "device": actualDevice,
            "percent": clampedValue
        };
        if (isExponential) {
            params.exponential = true;
            params.exponent = SessionData.getBrightnessExponent(actualDevice);
        }

        DMSService.sendRequest("brightness.setBrightness", params, response => {
            if (response.error) {
                log.error("Failed to set brightness:", response.error);
                ToastService.showError(I18n.tr("Failed to set brightness"), response.error, "", "brightness");
            } else {
                ToastService.dismissCategory("brightness");
            }
        });
    }

    function setGroupBrightness(percentage, deviceIds, suppressOsd) {
        const lead = getCurrentDeviceInfoByName(deviceIds[0]);
        const leadMin = brightnessMinimum(lead);
        const leadMax = brightnessMaximum(lead);
        const ratio = leadMax > leadMin ? Math.max(0, Math.min(1, (percentage - leadMin) / (leadMax - leadMin))) : 1;

        for (const id of deviceIds.slice(1)) {
            const info = getCurrentDeviceInfoByName(id);
            const min = brightnessMinimum(info);
            setBrightness(Math.round(min + ratio * (brightnessMaximum(info) - min)), id, true);
        }
        setBrightness(percentage, deviceIds[0], suppressOsd);
        lastIpcGroup = deviceIds;
    }

    function lastIpcTargets() {
        return lastIpcGroup.length > 1 && lastIpcGroup[0] === lastIpcDevice ? lastIpcGroup : [lastIpcDevice];
    }

    function setCurrentDevice(deviceName, saveToSession = false) {
        if (currentDevice === deviceName) {
            return;
        }

        currentDevice = deviceName;
        lastIpcDevice = deviceName;

        if (saveToSession) {
            SessionData.setLastBrightnessDevice(deviceName);
        }

        deviceSwitched();
    }

    function getDeviceBrightness(deviceName) {
        if (!deviceName) {
            return 50;
        }

        if (deviceName in deviceBrightness) {
            return deviceBrightness[deviceName];
        }

        return 50;
    }

    function linearToExponential(linearPercent, deviceName) {
        const exponent = SessionData.getBrightnessExponent(deviceName);
        const hardwarePercent = linearPercent / 100.0;
        const normalizedPercent = Math.pow(hardwarePercent, 1.0 / exponent);
        return Math.round(normalizedPercent * 100.0);
    }

    function internalPanelActive() {
        return Quickshell.screens.some(s => isInternalPanelName(s.name));
    }

    function isInternalPanelName(name) {
        return /^(eDP|LVDS|DSI)/i.test(name);
    }

    function internalPanelDevice() {
        if (!internalPanelActive())
            return null;
        return devices.find(d => d.class === "backlight") || devices.find(d => d.class === "software" && isInternalPanelName(d.id.split(":").pop())) || null;
    }

    function getDefaultDevice() {
        const internal = internalPanelDevice();
        if (internal)
            return internal.id;
        const nonKbdDevice = devices.find(d => d.class !== "backlight" && !d.id.includes("kbd"));
        if (nonKbdDevice)
            return nonKbdDevice.id;
        return devices.length > 0 ? devices[0].id : "";
    }

    function pinnedDevices(pinKey) {
        if (!pinKey)
            return [];
        const pinned = QmlUtils.normalizePinList((CacheData.brightnessDevicePins || {})[pinKey]);
        return pinned.filter(id => devices.some(d => d.id === id));
    }

    function getPreferredDevices() {
        const focusedScreen = CompositorService.getFocusedScreen();
        const pinned = focusedScreen ? pinnedDevices(SettingsData.getScreenDisplayName(focusedScreen)) : [];
        return pinned.length > 0 ? pinned : [getDefaultDevice()];
    }

    function getCurrentDeviceInfo() {
        const deviceToUse = lastIpcDevice === "" ? getDefaultDevice() : (lastIpcDevice || currentDevice);
        if (!deviceToUse) {
            return null;
        }

        for (const device of devices) {
            if (device.id === deviceToUse) {
                return device;
            }
        }
        return null;
    }

    function isCurrentDeviceReady() {
        const deviceToUse = lastIpcDevice === "" ? getDefaultDevice() : (lastIpcDevice || currentDevice);
        return deviceToUse !== "";
    }

    function getCurrentDeviceInfoByName(deviceName) {
        if (!deviceName) {
            return null;
        }

        for (const device of devices) {
            if (device.id === deviceName) {
                return device;
            }
        }
        return null;
    }

    function getDeviceMax(deviceName) {
        return brightnessMaximum(getCurrentDeviceInfoByName(deviceName));
    }

    function brightnessMinimum(deviceInfo) {
        if (!deviceInfo || (deviceInfo.class !== "software" && SessionData.getBrightnessExponential(deviceInfo.id)))
            return 1;
        switch (deviceInfo.class) {
        case "backlight":
        case "ddc":
            return 1;
        default:
            return 0;
        }
    }

    function brightnessMaximum(deviceInfo) {
        if (!deviceInfo || SessionData.getBrightnessExponential(deviceInfo.id))
            return 100;
        return deviceInfo.displayMax || 100;
    }

    function brightnessUnit(deviceInfo) {
        if (!deviceInfo || SessionData.getBrightnessExponential(deviceInfo.id))
            return "%";
        return deviceInfo.class === "ddc" ? "" : "%";
    }

    function deviceTitle(device) {
        const name = device?.name || "";
        if (device?.class !== "backlight")
            return name;
        return name.replace("_", " ").replace(/\b\w/g, c => c.toUpperCase());
    }

    function brightnessIconName(deviceInfo, level) {
        if (!deviceInfo)
            return "brightness_medium";
        switch (deviceInfo.class) {
        case "backlight":
        case "ddc":
        case "software":
            break;
        default:
            return String(deviceInfo.name ?? "").includes("kbd") ? "keyboard" : "lightbulb";
        }
        if (level === undefined)
            return "brightness_medium";
        const ratio = level / brightnessMaximum(deviceInfo);
        if (ratio <= 0.33)
            return "brightness_low";
        return ratio <= 0.66 ? "brightness_medium" : "brightness_high";
    }

    function rescanDevices() {
        if (!DMSService.isConnected) {
            return;
        }

        DMSService.sendRequest("brightness.rescan", null, response => {
            if (response.error) {
                log.error("Failed to rescan brightness devices:", response.error);
            }
        });
    }

    function requestBrightnessState() {
        if (!DMSService.isConnected) {
            return;
        }

        DMSService.sendRequest("brightness.getState", null, response => {
            if (response.error) {
                log.error("Failed to request brightness state:", response.error);
                return;
            }
            if (response.result) {
                updateFromBrightnessState(response.result);
            }
        });
    }

    function updateDeviceBrightnessDisplay(deviceName) {
        brightnessVersion++;
        brightnessChanged();
    }

    Connections {
        target: SessionData

        function onBrightnessDisplayHintChanged(deviceName) {
            root.updateDeviceBrightnessDisplay(deviceName);
        }
    }

    Timer {
        id: osdSuppressTimer
        interval: 2000
        running: true
        onTriggered: suppressOsd = false
    }

    Component.onCompleted: {
        deviceBrightnessUserSet = Object.assign({}, SessionData.brightnessUserSetValues);
        if (DMSService.isConnected) {
            requestBrightnessState();
        }
    }

    Timer {
        id: rescanTimer
        property var schedule: []
        property int attempt: 0
        repeat: false
        function run(intervals) {
            schedule = intervals;
            attempt = 0;
            interval = intervals[0];
            restart();
        }
        onTriggered: {
            rescanDevices();
            attempt++;
            if (attempt < schedule.length) {
                interval = schedule[attempt];
                restart();
                return;
            }
            osdSuppressTimer.restart();
        }
    }

    Connections {
        target: Quickshell

        function onScreensChanged() {
            suppressOsd = true;
            rescanTimer.run([3000, 5000, 8000]);
        }
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (!DMSService.isConnected) {
                brightnessAvailable = false;
                return;
            }
            requestBrightnessState();
        }

        function onBrightnessStateUpdate(data) {
            updateFromBrightnessState(data);
        }

        function onBrightnessDeviceUpdate(device) {
            updateSingleDevice(device);
        }
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            suppressOsd = true;
            osdSuppressTimer.restart();
            rescanTimer.run([400, 1400, 2600]);
        }
    }

    IpcHandler {
        function set(percentage: string, device: string): string {
            if (!root.brightnessAvailable)
                return "Brightness control not available";

            const value = parseInt(percentage);
            if (isNaN(value))
                return "Invalid brightness value: " + percentage;

            const targets = device ? [device] : root.getPreferredDevices();
            const actualDevice = targets[0];

            if (actualDevice && !root.devices.some(d => d.id === actualDevice))
                return "Device not found: " + actualDevice;

            const deviceInfo = actualDevice ? root.getCurrentDeviceInfoByName(actualDevice) : null;
            const minValue = (deviceInfo && (deviceInfo.class === "backlight" || deviceInfo.class === "ddc")) ? 1 : 0;
            const clampedValue = Math.max(minValue, Math.min(100, value));

            root.lastIpcDevice = actualDevice;
            if (actualDevice && actualDevice !== root.currentDevice)
                root.setCurrentDevice(actualDevice, false);

            root.setGroupBrightness(clampedValue, targets);

            return actualDevice ? "Brightness set to " + clampedValue + "% on " + actualDevice : "Brightness set to " + clampedValue + "%";
        }

        function increment(step: string, device: string): string {
            if (!root.brightnessAvailable)
                return "Brightness control not available";

            const targets = device ? [device] : root.getPreferredDevices();
            const actualDevice = targets[0];

            if (actualDevice && !root.devices.some(d => d.id === actualDevice))
                return "Device not found: " + actualDevice;

            const stepValue = parseInt(step || "5");

            root.lastIpcDevice = actualDevice;
            if (actualDevice && actualDevice !== root.currentDevice)
                root.setCurrentDevice(actualDevice, false);

            const currentBrightness = root.getDeviceBrightness(actualDevice);
            const deviceInfo = root.getCurrentDeviceInfoByName(actualDevice);
            const maxValue = root.brightnessMaximum(deviceInfo);
            const newBrightness = Math.min(maxValue, currentBrightness + stepValue);

            root.setGroupBrightness(newBrightness, targets);

            return "Brightness increased by " + stepValue + "%" + (device ? " on " + actualDevice : "");
        }

        function decrement(step: string, device: string): string {
            if (!root.brightnessAvailable)
                return "Brightness control not available";

            const targets = device ? [device] : root.getPreferredDevices();
            const actualDevice = targets[0];

            if (actualDevice && !root.devices.some(d => d.id === actualDevice))
                return "Device not found: " + actualDevice;

            const stepValue = parseInt(step || "5");

            root.lastIpcDevice = actualDevice;
            if (actualDevice && actualDevice !== root.currentDevice)
                root.setCurrentDevice(actualDevice, false);

            const currentBrightness = root.getDeviceBrightness(actualDevice);
            const deviceInfo = root.getCurrentDeviceInfoByName(actualDevice);
            const minValue = root.brightnessMinimum(deviceInfo);

            const newBrightness = Math.max(minValue, currentBrightness - stepValue);

            root.setGroupBrightness(newBrightness, targets);

            return "Brightness decreased by " + stepValue + "%" + (device ? " on " + actualDevice : "");
        }

        function status(): string {
            if (!root.brightnessAvailable) {
                return "Brightness control not available";
            }

            return "Device: " + root.currentDevice + " - Brightness: " + root.brightnessLevel + "%";
        }

        function list(): string {
            if (!root.brightnessAvailable) {
                return "No brightness devices available";
            }

            let result = "Available devices:\n";
            for (const device of root.devices) {
                const isExp = SessionData.getBrightnessExponential(device.id);
                result += device.id + " (" + device.class + ")" + (isExp ? " [exponential]" : "") + "\n";
            }
            return result;
        }

        function enableExponential(device: string): string {
            const targetDevice = device || root.currentDevice;
            if (!targetDevice) {
                return "No device specified";
            }

            if (!root.devices.some(d => d.id === targetDevice)) {
                return "Device not found: " + targetDevice;
            }

            SessionData.setBrightnessExponential(targetDevice, true);
            return "Exponential mode enabled for " + targetDevice;
        }

        function disableExponential(device: string): string {
            const targetDevice = device || root.currentDevice;
            if (!targetDevice) {
                return "No device specified";
            }

            if (!root.devices.some(d => d.id === targetDevice)) {
                return "Device not found: " + targetDevice;
            }

            SessionData.setBrightnessExponential(targetDevice, false);
            return "Exponential mode disabled for " + targetDevice;
        }

        function toggleExponential(device: string): string {
            const targetDevice = device || root.currentDevice;
            if (!targetDevice) {
                return "No device specified";
            }

            if (!root.devices.some(d => d.id === targetDevice)) {
                return "Device not found: " + targetDevice;
            }

            const currentState = SessionData.getBrightnessExponential(targetDevice);
            SessionData.setBrightnessExponential(targetDevice, !currentState);
            return "Exponential mode " + (!currentState ? "enabled" : "disabled") + " for " + targetDevice;
        }

        target: "brightness"
    }
}
