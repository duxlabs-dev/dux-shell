pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Common

Singleton {
    id: root

    property bool suppressSound: true
    property bool previousPluggedState: false

    property int refCount: 0

    function addRef() {
        refCount++;
    }

    function removeRef() {
        refCount = Math.max(0, refCount - 1);
    }

    // FreeBSD native ACPI fallback. UPower exists in ports, but on some FreeBSD
    // installations it exposes no usable laptop battery. Keep UPower as the
    // preferred path when it works and fall back to acpiconf(8)/sysctl(8).
    readonly property bool isBSD: Qt.platform.os === "unix"
    property bool freebsdBatteryAvailable: false
    property bool freebsdBatteryProbeComplete: false
    property real freebsdBatteryLevel: 0
    property bool freebsdIsCharging: false
    property bool freebsdPluggedIn: true
    property real freebsdChangeRate: 0
    property real freebsdFullCapacityWh: 0
    property real freebsdDesignCapacityWh: 0
    property string freebsdBatteryState: ""

    function parseFreeBsdCapacity(value, unit) {
        const n = parseFloat(value || "0");
        if (!isFinite(n) || n <= 0)
            return 0;
        return unit === "mWh" ? n / 1000 : 0;
    }

    function applyFreeBsdBatteryState(output) {
        const text = output || "";
        const blocks = text.split(/__DMS_BATTERY_\d+__\n?/).filter(b => /Remaining capacity:/i.test(b));
        let weightedPct = 0;
        let weight = 0;
        let pctSum = 0;
        let pctCount = 0;
        let totalRateW = 0;
        let fullWh = 0;
        let designWh = 0;
        let charging = false;
        let state = "";

        for (const block of blocks) {
            const pctMatch = block.match(/Remaining capacity:\s*(\d+(?:\.\d+)?)%/i);
            const stateMatch = block.match(/State:\s*([^\n\r]+)/i);
            const rateMatch = block.match(/Present rate:\s*[^\n\r]*?\((\d+(?:\.\d+)?)\s*mW\)/i) || block.match(/Present rate:\s*(\d+(?:\.\d+)?)\s*mW/i);
            const fullMatch = block.match(/Last full capacity:\s*(\d+(?:\.\d+)?)\s*(mWh|mAh)/i);
            const designMatch = block.match(/Design capacity:\s*(\d+(?:\.\d+)?)\s*(mWh|mAh)/i);
            const pct = pctMatch ? parseFloat(pctMatch[1]) : NaN;
            const full = fullMatch ? root.parseFreeBsdCapacity(fullMatch[1], fullMatch[2]) : 0;

            if (isFinite(pct)) {
                pctSum += pct;
                pctCount++;

                if (full > 0) {
                    weightedPct += pct * full;
                    weight += full;
                }
            }

            if (rateMatch)
                totalRateW += parseFloat(rateMatch[1]) / 1000;

            fullWh += full;

            if (designMatch)
                designWh += root.parseFreeBsdCapacity(designMatch[1], designMatch[2]);

            if (stateMatch) {
                const thisState = stateMatch[1].trim().toLowerCase();

                if (!state)
                    state = thisState;

                if (thisState === "charging" || thisState.startsWith("charging"))
                    charging = true;
            }
        }

        const acMatch = text.match(/__DMS_AC__:(\d+)/);

        root.freebsdBatteryAvailable = blocks.length > 0;
        root.freebsdBatteryLevel = blocks.length > 0 ? Math.max(0, Math.min(100, weight > 0 ? weightedPct / weight : (pctCount > 0 ? pctSum / pctCount : 0))) : 0;
        root.freebsdIsCharging = charging;
        root.freebsdPluggedIn = acMatch ? acMatch[1] === "1" : charging;
        root.freebsdChangeRate = totalRateW;
        root.freebsdFullCapacityWh = fullWh;
        root.freebsdDesignCapacityWh = designWh;
        root.freebsdBatteryState = state;
    }

    function refreshFreeBsdBattery() {
        if (!root.isBSD || root.batteries.length > 0)
            return;

        const script = 'units=$(sysctl -n hw.acpi.battery.units 2>/dev/null || echo 0); i=0; while [ "$i" -lt "$units" ]; do echo "__DMS_BATTERY_${i}__"; acpiconf -i "$i" 2>/dev/null; i=$((i+1)); done; printf "__DMS_AC__:"; sysctl -n hw.acpi.acline 2>/dev/null || echo 1';

        Proc.runCommand("battery-freebsd-acpi", ["nice", "-n", "10", "sh", "-c", script], (output, exitCode) => {
            root.freebsdBatteryProbeComplete = true;

            if (exitCode === 0)
                root.applyFreeBsdBatteryState(output);
            else
                root.freebsdBatteryAvailable = false;
        }, 0);
    }

    function updateFreeBsdBatteryFallback() {
        if (!root.isBSD)
            return;

        if (root.batteries.length > 0) {
            root.freebsdBatteryAvailable = false;
            root.freebsdBatteryProbeComplete = false;
            return;
        }

        if (!root.freebsdBatteryProbeComplete)
            root.refreshFreeBsdBattery();
    }

    onBatteriesChanged: root.updateFreeBsdBatteryFallback()

    onRefCountChanged: {
        if (root.refCount === 1)
            root.refreshFreeBsdBattery();
    }

    Timer {
        interval: 15000
        repeat: true
        running: root.isBSD && root.batteries.length === 0 && root.freebsdBatteryAvailable && root.refCount > 0

        onTriggered: root.refreshFreeBsdBattery()
    }

    Timer {
        id: startupTimer
        interval: 500
        repeat: false
        running: true

        onTriggered: {
            root.suppressSound = false;
            root.applyPowerProfile();
        }
    }

    Connections {
        target: typeof PowerProfiles !== "undefined" ? PowerProfiles : null

        function onHasPerformanceProfileChanged() {
            root.applyPowerProfile();
        }
    }

    function applyPowerProfile() {
        if (!batteryAvailable)
            return;

        const profileValue = isPluggedIn ? SettingsData.acProfileName : SettingsData.batteryProfileName;

        if (profileValue === "")
            return;

        const targetProfile = parseInt(profileValue);

        if (isNaN(targetProfile) || PowerProfiles.profile === targetProfile)
            return;

        PowerProfileWatcher.applyProfile(targetProfile);
    }

    readonly property string preferredBatteryOverride: Quickshell.env("DMS_PREFERRED_BATTERY")

    // List of laptop batteries
    readonly property var batteries: UPower.devices.values.filter(dev => dev.isLaptopBattery)

    readonly property var readyBatteries: batteries.filter(b => b.ready)
    readonly property var stateKnownBatteries: batteries.filter(b => b.ready && b.state !== UPowerDeviceState.Unknown)
    readonly property var chargeBatteries: readyBatteries.filter(b => root._hasUsableCharge(b))
    readonly property var energyBatteries: readyBatteries.filter(b => b.energyCapacity > 0)

    property real _lastBatteryLevel: 0
    property bool _lastIsCharging: false
    property real _lastChangeRate: 0
    property real _lastBatteryEnergy: 0
    property real _lastBatteryCapacity: 0

    // UPower: 0 means unset. State can be Unknown with a valid Percentage, or Unknown with 0.
    function _hasUsableCharge(dev) {
        if (!dev || !dev.ready)
            return false;

        if (dev.percentage > 0)
            return true;

        return dev.energy > 0 && dev.energyCapacity > 0;
    }

    function _chargePercent(dev) {
        if (!dev)
            return 0;

        if (dev.percentage > 0)
            return Math.min(100, Math.round(dev.percentage * 100));

        if (dev.energy > 0 && dev.energyCapacity > 0)
            return Math.min(100, Math.round((dev.energy * 100) / dev.energyCapacity));

        return 0;
    }

    function _liveChargePercent() {
        if (usePreferred && preferredDevice) {
            if (_hasUsableCharge(preferredDevice))
                return _chargePercent(preferredDevice);

            return 0;
        }

        if (batteries.length > 1 && _hasUsableCharge(UPower.displayDevice))
            return _chargePercent(UPower.displayDevice);

        if (chargeBatteries.length === 1)
            return _chargePercent(chargeBatteries[0]);

        if (chargeBatteries.length > 1) {
            const energyPacks = chargeBatteries.filter(b => b.energy > 0 && b.energyCapacity > 0);

            if (energyPacks.length === chargeBatteries.length) {
                const energy = energyPacks.reduce((sum, b) => sum + b.energy, 0);
                const cap = energyPacks.reduce((sum, b) => sum + b.energyCapacity, 0);

                if (cap > 0)
                    return Math.min(100, Math.round((energy * 100) / cap));
            }

            return Math.min(100, Math.round(chargeBatteries.reduce((sum, b) => sum + _chargePercent(b), 0) / chargeBatteries.length));
        }

        if (_hasUsableCharge(UPower.displayDevice))
            return _chargePercent(UPower.displayDevice);

        return 0;
    }

    function _liveEnergy() {
        if (usePreferred && preferredDevice) {
            if (preferredDeviceReady && preferredDevice.energy > 0)
                return preferredDevice.energy;

            return 0;
        }

        const packs = energyBatteries.filter(b => b.energy > 0);

        if (packs.length === 0)
            return 0;

        return packs.reduce((sum, b) => sum + b.energy, 0);
    }

    function _liveCapacity() {
        if (usePreferred && preferredDevice) {
            if (preferredDeviceReady && preferredDevice.energyCapacity > 0)
                return preferredDevice.energyCapacity;

            return 0;
        }

        if (energyBatteries.length === 0)
            return 0;

        return energyBatteries.reduce((sum, b) => sum + b.energyCapacity, 0);
    }

    readonly property bool usePreferred: preferredBatteryOverride && preferredBatteryOverride.length > 0

    readonly property UPowerDevice preferredDevice: {
        if (!usePreferred)
            return null;

        const override = preferredBatteryOverride.toLowerCase();
        return batteries.find(dev => dev.nativePath.toLowerCase().includes(override)) || null;
    }

    readonly property bool preferredDeviceReady: preferredDevice && preferredDevice.ready
    readonly property bool preferredDeviceKnown: preferredDeviceReady && preferredDevice.state !== UPowerDeviceState.Unknown

    readonly property bool _hasKnownChargingState: {
        if (!batteryAvailable)
            return false;

        if (usePreferred)
            return preferredDeviceKnown;

        return stateKnownBatteries.length > 0;
    }

    readonly property bool _currentIsCharging: {
        if (!batteryAvailable)
            return false;

        if (usePreferred && preferredDeviceKnown)
            return preferredDevice.state === UPowerDeviceState.Charging;

        if (usePreferred)
            return false;

        return stateKnownBatteries.some(b => b.state === UPowerDeviceState.Charging);
    }

    // Main battery (for backward compatibility)
    readonly property UPowerDevice device: {
        if (usePreferred) {
            if (preferredDeviceKnown)
                return preferredDevice;

            return stateKnownBatteries[0] || null;
        }

        return stateKnownBatteries[0] || readyBatteries[0] || batteries[0] || null;
    }

    // Whether at least one battery is available
    readonly property bool batteryAvailable: (isBSD && freebsdBatteryAvailable) || batteries.length > 0

    readonly property real batteryLevel: {
        if (!batteryAvailable)
            return 0;

        if (isBSD && freebsdBatteryAvailable)
            return freebsdBatteryLevel;

        const live = _liveChargePercent();
        return live > 0 ? live : _lastBatteryLevel;
    }
    readonly property real displayBatteryLevel: displayLevelForChargeLimit(batteryLevel, SettingsData.batteryChargeLimit, SettingsData.batteryScaleToChargeLimit)
    readonly property string displayBatteryLevelText: SettingsData.batteryScaleToChargeLimit ? Math.round(displayBatteryLevel).toString() : displayBatteryLevel.toString()
    readonly property real batteryAlertLevel: batteryAlertLevelForDisplay(batteryLevel, displayBatteryLevel, SettingsData.batteryScaleToChargeLimit, SettingsData.batteryScaleAlertThresholds)

    readonly property bool isCharging: (isBSD && freebsdBatteryAvailable) ? freebsdIsCharging : (_hasKnownChargingState ? _currentIsCharging : _lastIsCharging)

    // Is the system plugged in (Is not running on battery)
    readonly property bool isPluggedIn: (isBSD && freebsdBatteryAvailable) ? freebsdPluggedIn : !UPower.onBattery

    readonly property bool hasBatteryReading: batteryAvailable && batteryLevel > 0
    readonly property bool isLowBattery: hasBatteryReading && isBatteryLevelAtOrBelow(batteryLevel, SettingsData.batteryLowThreshold)
    readonly property bool isCriticalBattery: hasBatteryReading && isBatteryLevelAtOrBelow(batteryLevel, SettingsData.batteryCriticalThreshold)
    readonly property bool isLowBatteryAlert: hasBatteryReading && isBatteryLevelAtOrBelow(batteryAlertLevel, SettingsData.batteryLowThreshold)
    readonly property bool isCriticalBatteryAlert: hasBatteryReading && isBatteryLevelAtOrBelow(batteryAlertLevel, SettingsData.batteryCriticalThreshold)

    readonly property color levelCautionColor: "#FFC107"
    readonly property color levelCriticalColor: "#F44336"

    function displayLevelForChargeLimit(level, chargeLimit, enabled) {
        if (!enabled || chargeLimit <= 0 || chargeLimit >= 100)
            return level;
        return Math.max(0, Math.min(100, level / chargeLimit * 100));
    }

    function isBatteryLevelAtOrBelow(level, threshold) {
        return level > 0 && level <= threshold;
    }

    function batteryAlertLevelForDisplay(actualLevel, scaledLevel, scaleDisplayEnabled, scaleAlertsEnabled) {
        return scaleDisplayEnabled && scaleAlertsEnabled ? scaledLevel : actualLevel;
    }

    readonly property color levelColor: {
        if (isCharging)
            return Theme.success;

        if (isCriticalBattery)
            return levelCriticalColor;

        if (isLowBattery)
            return Theme.warning;

        if (batteryLevel <= SettingsData.batteryLowThreshold * 2)
            return levelCautionColor;

        return Theme.success;
    }

    property bool _hasNotifiedLowBattery: false
    property bool _hasNotifiedCriticalBattery: false
    property bool _hasNotifiedChargeLimit: false

    function _syncLastIsCharging() {
        if (_hasKnownChargingState)
            _lastIsCharging = _currentIsCharging;
    }

    on_HasKnownChargingStateChanged: _syncLastIsCharging()
    on_CurrentIsChargingChanged: _syncLastIsCharging()
    onBatteryAlertLevelChanged: updateBatteryWarnings()

    Connections {
        target: SettingsData
        function onBatteryLowThresholdChanged() {
            root.updateBatteryWarnings();
        }
        function onBatteryCriticalThresholdChanged() {
            root.updateBatteryWarnings();
        }
        function onBatteryScaleToChargeLimitChanged() {
            root.updateBatteryWarnings();
        }
        function onBatteryScaleAlertThresholdsChanged() {
            root.updateBatteryWarnings();
        }
    }

    Component.onCompleted: {
        Qt.callLater(root.updateFreeBsdBatteryFallback);
        _syncLastIsCharging();

        if (batteryLevel > 0)
            _lastBatteryLevel = batteryLevel;

        if (batteryEnergy > 0)
            _lastBatteryEnergy = batteryEnergy;

        if (batteryCapacity > 0)
            _lastBatteryCapacity = batteryCapacity;
    }

    // urgency: "critical" (red), "warning" (orange/important), or "info"
    function sendAlert(title, message, urgency, icon, notificationType) {
        if (notificationType === 1) {
            const dbusUrgency = urgency === "critical" ? "critical" : (urgency === "warning" ? "normal" : "low");

            Quickshell.execDetached(["notify-send", "-u", dbusUrgency, "-a", "DMS", "-i", icon, title, message]);
        } else if (urgency === "critical") {
            ToastService.showError(title, message, "", icon);
        } else if (urgency === "warning") {
            ToastService.showWarning(title, message, "", icon);
        } else {
            ToastService.showInfo(title, message, "", icon);
        }
    }

    onBatteryLevelChanged: {
        if (batteryLevel > 0)
            _lastBatteryLevel = batteryLevel;

        if (isCharging && batteryLevel >= SettingsData.batteryChargeLimit) {
            if (!_hasNotifiedChargeLimit && SettingsData.batteryNotifyChargeLimit) {
                _hasNotifiedChargeLimit = true;

                sendAlert(I18n.tr("Charge Limit Reached"), I18n.tr("Battery has charged to your set limit of %1%", "charge limit notification body, %1 is the limit percentage").arg(SettingsData.batteryChargeLimit), "info", "material:battery_profile", SettingsData.batteryChargeLimitNotificationType);
            }
        } else if (!isCharging || batteryLevel < SettingsData.batteryChargeLimit - 2) {
            _hasNotifiedChargeLimit = false;
        }
        updateBatteryWarnings();
    }

    function updateBatteryWarnings() {
        if (isCharging) {
            _hasNotifiedLowBattery = false;
            _hasNotifiedCriticalBattery = false;
            return;
        }

        // Critical battery check (higher priority)
        if (isCriticalBatteryAlert) {
            if (!_hasNotifiedCriticalBattery && SettingsData.batteryNotifyCritical) {
                _hasNotifiedCriticalBattery = true;

                sendAlert(I18n.tr("Critical Battery"), I18n.tr("Battery is at %1% - Connect charger immediately!", "critical battery notification body, %1 is the battery percentage").arg(Math.round(batteryAlertLevel)), "critical", "material:battery_alert", SettingsData.batteryCriticalNotificationType);
            }

            return;
        }

        if (batteryAlertLevel > SettingsData.batteryCriticalThreshold)
            _hasNotifiedCriticalBattery = false;

        // Low battery check
        if (isLowBatteryAlert) {
            if (!_hasNotifiedLowBattery && SettingsData.batteryNotifyLow) {
                _hasNotifiedLowBattery = true;

                sendAlert(I18n.tr("Low Battery"), I18n.tr("Battery is at %1% - Consider charging soon", "low battery notification body, %1 is the battery percentage").arg(Math.round(batteryAlertLevel)), "warning", "material:battery_0_bar", SettingsData.batteryLowNotificationType);
            }

        }

        if (isLowBattery && SettingsData.batteryAutoPowerSaver && PowerProfileWatcher.available) {
            if (PowerProfileWatcher.currentProfile !== PowerProfile.PowerSaver)
                PowerProfileWatcher.applyProfile(PowerProfile.PowerSaver);
        }

        if (batteryAlertLevel > SettingsData.batteryLowThreshold)
            _hasNotifiedLowBattery = false;
    }

    onIsChargingChanged: {
        // Reset average when switching states
        _smoothedChangeRate = (_hasKnownChargingState && changeRate > 0) ? changeRate : 0;

        _lastRateSampleTime = _smoothedChangeRate > 0 ? Date.now() : 0;

        if (isCharging) {
            _hasNotifiedLowBattery = false;
            _hasNotifiedCriticalBattery = false;
        } else {
            _hasNotifiedChargeLimit = false;
            updateBatteryWarnings();
        }
    }

    onIsPluggedInChanged: {
        if (suppressSound || !batteryAvailable) {
            previousPluggedState = isPluggedIn;
            return;
        }

        if (SettingsData.soundsEnabled && SettingsData.soundPluggedIn) {
            if (isPluggedIn && !previousPluggedState) {
                AudioService.playPowerPlugSound();
            } else if (!isPluggedIn && previousPluggedState) {
                AudioService.playPowerUnplugSound();
            }
        }

        applyPowerProfile();

        if (isPluggedIn) {
            const dismissLow = SettingsData.batteryLowNotificationType === 1 && SettingsData.notificationTimeoutNormal === 0;

            const dismissCritical = SettingsData.batteryCriticalNotificationType === 1 && SettingsData.notificationTimeoutCritical === 0;

            if (dismissLow || dismissCritical) {
                const lowSummary = I18n.tr("Low Battery");
                const criticalSummary = I18n.tr("Critical Battery");

                for (const w of NotificationService.visibleNotifications) {
                    if (!w || !w.notification)
                        continue;

                    const summary = w.notification.summary;

                    if ((dismissLow && summary === lowSummary) || (dismissCritical && summary === criticalSummary)) {
                        NotificationService.dismissNotification(w);
                    }
                }
            }
        }

        previousPluggedState = isPluggedIn;
    }

    // Aggregated charge/discharge rate
    readonly property real changeRate: {
        if (!batteryAvailable)
            return 0;

        if (isBSD && freebsdBatteryAvailable) {
            _lastChangeRate = freebsdChangeRate;
            return _lastChangeRate;
        }

        if (usePreferred && preferredDeviceKnown) {
            _lastChangeRate = preferredDevice.changeRate;
            return _lastChangeRate;
        }

        if (usePreferred && preferredDevice)
            return _lastChangeRate;

        if (stateKnownBatteries.length === 0)
            return _lastChangeRate;

        const val = stateKnownBatteries.reduce((sum, b) => sum + b.changeRate, 0);
        _lastChangeRate = val;
        return val;
    }

    // Aggregated charge/discharge rate, signed: positive while charging,
    // negative while draining the battery, zero when idle/fully charged.
    readonly property real signedChangeRate: {
        if (!batteryAvailable)
            return 0;

        const rate = Math.abs(changeRate);

        if (!isFinite(rate) || rate < 0.05)
            return 0;

        return isCharging ? rate : -rate;
    }

    // Compact signed wattage for bar widgets, e.g. "+45W" / "-8.4W".
    // Returns an empty string when there is nothing meaningful to show.
    // compact drops the decimal entirely (used by vertical bars).
    function formatPowerRate(compact) {
        const rate = signedChangeRate;

        if (rate === 0)
            return "";

        const magnitude = Math.abs(rate);
        const value = (compact || magnitude >= 10) ? Math.round(magnitude).toString() : magnitude.toFixed(1);

        return `${rate > 0 ? "+" : "-"}${value}W`;
    }

    // A time-weighted exponential moving average based on the aggregated charge/discharge rate
    property real _smoothedChangeRate: 0
    property real _lastRateSampleTime: 0
    readonly property real _rateSmoothingHalfLife: 90 // in seconds

    function _updateSmoothedRate() {
        if (!_hasKnownChargingState || changeRate <= 0)
            return;

        const now = Date.now();

        if (_smoothedChangeRate <= 0 || _lastRateSampleTime <= 0) {
            _smoothedChangeRate = changeRate;
            _lastRateSampleTime = now;
            return;
        }

        const dt = (now - _lastRateSampleTime) / 1000;
        _lastRateSampleTime = now;

        if (dt <= 0)
            return;

        const tau = _rateSmoothingHalfLife / Math.LN2;
        const alpha = 1 - Math.exp(-dt / tau);
        _smoothedChangeRate += alpha * (changeRate - _smoothedChangeRate);
    }

    onChangeRateChanged: _updateSmoothedRate()

    onBatteryAvailableChanged: {
        if (!batteryAvailable) {
            _smoothedChangeRate = 0;
            _lastRateSampleTime = 0;
        }
    }

    // Aggregated battery health
    readonly property string batteryHealth: {
        if (!batteryAvailable)
            return "N/A";

        if (isBSD && freebsdBatteryAvailable) {
            if (freebsdDesignCapacityWh > 0 && freebsdFullCapacityWh > 0)
                return `${Math.round(Math.min(100, freebsdFullCapacityWh * 100 / freebsdDesignCapacityWh))}%`;

            return "N/A";
        }

        if (usePreferred && preferredDeviceReady && preferredDevice.healthSupported)
            return `${Math.round(preferredDevice.healthPercentage)}%`;

        const validBatteries = readyBatteries.filter(b => b.healthSupported && b.healthPercentage > 0);

        if (validBatteries.length === 0)
            return "N/A";

        const avgHealth = validBatteries.reduce((sum, b) => sum + b.healthPercentage, 0) / validBatteries.length;

        return `${Math.round(avgHealth)}%`;
    }

    readonly property real batteryEnergy: {
        if (!batteryAvailable)
            return 0;

        if (isBSD && freebsdBatteryAvailable && freebsdFullCapacityWh > 0)
            return freebsdFullCapacityWh * freebsdBatteryLevel / 100;

        const live = _liveEnergy();
        return live > 0 ? live : _lastBatteryEnergy;
    }

    onBatteryEnergyChanged: {
        if (batteryEnergy > 0)
            _lastBatteryEnergy = batteryEnergy;
    }

    readonly property real batteryCapacity: {
        if (!batteryAvailable)
            return 0;

        if (isBSD && freebsdBatteryAvailable)
            return freebsdFullCapacityWh;

        const live = _liveCapacity();
        return live > 0 ? live : _lastBatteryCapacity;
    }

    onBatteryCapacityChanged: {
        if (batteryCapacity > 0)
            _lastBatteryCapacity = batteryCapacity;
    }

    function translateBatteryState(state) {
        switch (state) {
        case UPowerDeviceState.Charging:
            return I18n.tr("Charging", "battery status");
        case UPowerDeviceState.Discharging:
            return I18n.tr("Discharging", "battery status");
        case UPowerDeviceState.Empty:
            return I18n.tr("Empty", "battery status");
        case UPowerDeviceState.FullyCharged:
            return I18n.tr("Fully Charged", "battery status");
        case UPowerDeviceState.PendingCharge:
            return I18n.tr("Pending Charge", "battery status");
        case UPowerDeviceState.PendingDischarge:
            return I18n.tr("Pending Discharge", "battery status");
        default:
            return I18n.tr("Unknown", "battery status");
        }
    }

    readonly property string batteryStatus: {
        if (!batteryAvailable)
            return I18n.tr("No battery", "battery status");

        if (isBSD && freebsdBatteryAvailable) {
            if (isCharging)
                return I18n.tr("Charging", "battery status");

            return isPluggedIn ? I18n.tr("Plugged in", "battery status") : I18n.tr("Discharging", "battery status");
        }

        if (stateKnownBatteries.length === 0) {
            if (isCharging)
                return I18n.tr("Charging", "battery status");

            return isPluggedIn ? I18n.tr("Plugged in", "battery status") : I18n.tr("Discharging", "battery status");
        }

        if (isCharging && !stateKnownBatteries.some(b => b.changeRate > 0))
            return I18n.tr("Plugged in", "battery status");

        const states = stateKnownBatteries.map(b => b.state);

        if (states.every(s => s === states[0]))
            return translateBatteryState(states[0]);

        return isCharging ? I18n.tr("Charging", "battery status") : (isPluggedIn ? I18n.tr("Plugged in", "battery status") : I18n.tr("Discharging", "battery status"));
    }

    readonly property bool suggestPowerSaver: false

    readonly property var peripheralDevices: refCount === 0 ? [] : UPower.devices.values.filter(dev => dev && dev.ready && !dev.isLaptopBattery && peripheralIcon(dev.type) !== "").map(dev => ({
                "name": dev.model || UPowerDeviceType.toString(dev.type),
                "percentage": Math.round(dev.percentage * 100),
                "type": dev.type,
                "icon": peripheralIcon(dev.type),
                "charging": dev.state === UPowerDeviceState.Charging
            }))

    readonly property var bluetoothDevices: {
        if (refCount === 0)
            return [];
        const bluetoothTypes = [UPowerDeviceType.BluetoothGeneric, UPowerDeviceType.Headphones, UPowerDeviceType.Headset, UPowerDeviceType.Keyboard, UPowerDeviceType.Mouse, UPowerDeviceType.Speakers];

        return peripheralDevices.filter(dev => bluetoothTypes.includes(dev.type));
    }

    function peripheralIcon(type) {
        switch (type) {
        case UPowerDeviceType.BluetoothGeneric:
            return "bluetooth";
        case UPowerDeviceType.Headphones:
            return "headphones";
        case UPowerDeviceType.Headset:
            return "headset_mic";
        case UPowerDeviceType.Speakers:
            return "speaker";
        case UPowerDeviceType.Keyboard:
            return "keyboard";
        case UPowerDeviceType.Mouse:
            return "mouse";
        case UPowerDeviceType.Touchpad:
            return "touchpad_mouse";
        case UPowerDeviceType.Pen:
            return "stylus";
        case UPowerDeviceType.GamingInput:
            return "sports_esports";
        case UPowerDeviceType.Phone:
            return "smartphone";
        case UPowerDeviceType.Tablet:
            return "tablet";
        case UPowerDeviceType.MediaPlayer:
            return "media_output";
        case UPowerDeviceType.Wearable:
            return "watch";
        default:
            return "";
        }
    }

    function estimatedSeconds() {
        if (!batteryAvailable)
            return 0;

        const rate = _smoothedChangeRate > 0 ? _smoothedChangeRate : changeRate;

        const totalTime = isCharging ? ((batteryCapacity - batteryEnergy) / rate) : (batteryEnergy / rate);

        const seconds = Math.abs(totalTime * 3600);

        if (!seconds || seconds <= 0 || seconds > 86400)
            return 0;

        return seconds;
    }

    function formatDuration(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);

        return hours > 0 ? I18n.tr("%1h %2m", "battery time remaining").arg(hours).arg(minutes) : I18n.tr("%1m", "battery time remaining").arg(minutes);
    }

    function formatTimeRemaining() {
        const seconds = estimatedSeconds();

        if (!seconds)
            return "Unknown";

        return formatDuration(seconds);
    }

    function formatEstimatedTime() {
        const seconds = estimatedSeconds();

        if (!seconds)
            return "";

        const target = new Date(Date.now() + seconds * 1000);
        const use24Hour = SettingsData.use24HourClock !== false;

        return target.toLocaleTimeString(Qt.locale(), use24Hour ? "HH:mm" : "h:mm AP");
    }

    function getBatteryIcon() {
        if (!batteryAvailable)
            return "power";

        if (isCharging) {
            if (displayBatteryLevel >= 90)
                return "battery_charging_full";
            if (displayBatteryLevel >= 80)
                return "battery_charging_90";
            if (displayBatteryLevel >= 60)
                return "battery_charging_80";
            if (displayBatteryLevel >= 50)
                return "battery_charging_60";
            if (displayBatteryLevel >= 30)
                return "battery_charging_50";
            if (displayBatteryLevel >= 20)
                return "battery_charging_30";

            return "battery_charging_20";
        }

        if (isPluggedIn) {
            if (displayBatteryLevel >= 90)
                return "battery_charging_full";
            if (displayBatteryLevel >= 80)
                return "battery_charging_90";
            if (displayBatteryLevel >= 60)
                return "battery_charging_80";
            if (displayBatteryLevel >= 50)
                return "battery_charging_60";
            if (displayBatteryLevel >= 30)
                return "battery_charging_50";
            if (displayBatteryLevel >= 20)
                return "battery_charging_30";

            return "battery_charging_20";
        }

        if (displayBatteryLevel >= 95)
            return "battery_full";
        if (displayBatteryLevel >= 85)
            return "battery_6_bar";
        if (displayBatteryLevel >= 70)
            return "battery_5_bar";
        if (displayBatteryLevel >= 55)
            return "battery_4_bar";
        if (displayBatteryLevel >= 40)
            return "battery_3_bar";
        if (displayBatteryLevel >= 25)
            return "battery_2_bar";

        return "battery_1_bar";
    }
}
