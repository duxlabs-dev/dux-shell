pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services

QtObject {
    id: root

    required property IslandController controller

    property string kind: "volume"
    // Off: system levels and state changes keep their OSDs and only the face's own controls open this activity.
    property bool enabled: true
    property bool chargingPulseEnabled: true

    readonly property bool volumeActivity: kind === "volume"
    readonly property bool micActivity: kind === "mic"
    readonly property bool brightnessActivity: kind === "brightness"
    readonly property bool levelActivity: volumeActivity || micActivity || brightnessActivity
    readonly property var audio: volumeActivity ? AudioService.sink?.audio : (micActivity ? AudioService.source?.audio : null)
    readonly property bool available: levelActivity ? (brightnessActivity ? BrightnessService.brightnessAvailable : !!audio) : true
    readonly property bool muted: !!audio && (audio.muted ?? false)
    readonly property bool mutable: volumeActivity || micActivity
    readonly property real value: {
        switch (kind) {
        case "volume":
            return AudioService.sinkVolumePercent;
        case "mic":
            return AudioService.sourceVolumePercent;
        case "brightness":
            return BrightnessService.brightnessLevel;
        }
        return 0;
    }
    readonly property var brightnessDevice: BrightnessService.getCurrentDeviceInfo()
    readonly property real maximum: {
        switch (kind) {
        case "volume":
            return AudioService.sinkMaxVolume;
        case "brightness":
            return BrightnessService.brightnessMaximum(brightnessDevice);
        }
        return 100;
    }
    readonly property int minimum: brightnessActivity ? BrightnessService.brightnessMinimum(brightnessDevice) : 0
    readonly property real ratio: maximum > 0 ? Math.max(0, Math.min(1, value / maximum)) : 0
    readonly property string title: {
        switch (kind) {
        case "volume":
            return I18n.tr("Volume", "island system face: volume title");
        case "mic":
            return I18n.tr("Microphone", "island system face: microphone title");
        case "brightness":
            return I18n.tr("Brightness", "island system face: brightness title");
        case "capslock":
            return I18n.tr("Caps lock", "island system face: caps lock title");
        case "powerprofile":
            return I18n.tr("Power profile", "island system face: power profile title");
        case "idleinhibitor":
            return I18n.tr("Idle inhibitor", "island system face: idle inhibitor title");
        case "charging":
            return BatteryService.isPluggedIn ? I18n.tr("Plugged in", "island system face: power connected title") : I18n.tr("Discharging", "island system face: power disconnected title");
        }
        return "";
    }
    readonly property string unit: brightnessActivity ? BrightnessService.brightnessUnit(brightnessDevice) : "%"
    readonly property string displayValue: {
        switch (kind) {
        case "capslock":
            return DMSService.capsLockState ? I18n.tr("On") : I18n.tr("Off");
        case "powerprofile":
            return Theme.getPowerProfileLabel(PowerProfileWatcher.currentProfile);
        case "idleinhibitor":
            return SessionService.idleInhibited ? I18n.tr("On") : I18n.tr("Off");
        case "charging":
            return root.chargingValue();
        }
        return muted ? I18n.tr("Muted", "island system face: muted value label") : Math.round(value) + unit;
    }
    readonly property string iconName: {
        switch (kind) {
        case "volume":
            return AudioService.sinkVolumeIconName;
        case "mic":
            return muted ? "mic_off" : "mic";
        case "brightness":
            return BrightnessService.brightnessIconName(brightnessDevice, value);
        case "capslock":
            return DMSService.capsLockState ? "shift_lock" : "shift_lock_off";
        case "powerprofile":
            return Theme.getPowerProfileIcon(PowerProfileWatcher.currentProfile);
        case "idleinhibitor":
            return "local_cafe";
        case "charging":
            return BatteryService.getBatteryIcon();
        }
        return "";
    }
    // Level pulses carry their own controls, so only state pulses link out.
    readonly property string controlCenterSection: {
        switch (kind) {
        case "mic":
            return "audioInput";
        case "powerprofile":
        case "charging":
            return "battery";
        case "idleinhibitor":
            return "idleInhibitor";
        }
        return "";
    }

    function chargingValue() {
        const level = Math.round(BatteryService.displayBatteryLevel) + "%";
        const seconds = BatteryService.estimatedSeconds();
        if (!seconds)
            return level;
        return level + " · " + BatteryService.formatTimeRemaining();
    }

    function show(activityKind) {
        if (!enabled || SessionData.suppressOSD)
            return;
        open(activityKind);
    }

    function open(activityKind) {
        if (controller.requestSystemActivity(activityKind))
            kind = activityKind;
    }

    function setRatio(nextRatio) {
        const clampedRatio = Math.max(0, Math.min(1, nextRatio));
        SessionData.suppressOSDTemporarily();
        switch (kind) {
        case "volume":
            AudioService.setVolume(Math.round(clampedRatio * maximum));
            return;
        case "mic":
            AudioService.setMicVolume(Math.round(clampedRatio * maximum));
            return;
        case "brightness":
            BrightnessService.setGroupBrightness(Math.round(clampedRatio * maximum), BrightnessService.lastIpcTargets(), true);
            return;
        }
    }

    function toggleMute() {
        if (!mutable || !available)
            return;
        SessionData.suppressOSDTemporarily();
        if (micActivity) {
            AudioService.toggleMicMute();
            return;
        }
        AudioService.toggleMute();
    }

    property Connections audioConnection: Connections {
        target: AudioService.sink?.audio ?? null
        enabled: root.enabled

        function onVolumeChanged() {
            if (SettingsData.osdVolumeEnabled)
                root.show("volume");
        }

        function onMutedChanged() {
            if (SettingsData.osdVolumeEnabled)
                root.show("volume");
        }
    }

    property Connections micConnection: Connections {
        target: AudioService.source?.audio ?? null
        enabled: root.enabled

        function onMutedChanged() {
            if (SettingsData.osdMicMuteEnabled)
                root.show("mic");
        }
    }

    property Connections micServiceConnection: Connections {
        target: AudioService
        enabled: root.enabled

        function onMicVolumeChanged() {
            if (SettingsData.osdMicVolumeEnabled)
                root.show("mic");
        }
    }

    property Connections brightnessConnection: Connections {
        target: BrightnessService
        enabled: root.enabled

        function onBrightnessChanged(showOsd) {
            if (showOsd && SettingsData.osdBrightnessEnabled)
                root.show("brightness");
        }
    }

    property Connections capsLockConnection: Connections {
        target: DMSService
        enabled: root.enabled

        function onCapsLockStateChanged() {
            if (SettingsData.osdCapsLockEnabled)
                root.show("capslock");
        }
    }

    property Connections powerProfileConnection: Connections {
        target: PowerProfileWatcher
        enabled: root.enabled

        function onProfileChanged() {
            if (SettingsData.osdPowerProfileEnabled)
                root.show("powerprofile");
        }
    }

    property Connections idleInhibitorConnection: Connections {
        target: SessionService
        enabled: root.enabled

        function onInhibitorChanged() {
            if (SettingsData.osdIdleInhibitorEnabled)
                root.show("idleinhibitor");
        }
    }

    property Connections batteryConnection: Connections {
        target: BatteryService
        enabled: root.enabled

        function onIsPluggedInChanged() {
            if (root.chargingPulseEnabled && BatteryService.batteryAvailable)
                root.show("charging");
        }
    }
}
