pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("NightModeService")

    property bool nightModeEnabled: false
    property bool nightModePaused: false
    property bool automationAvailable: false
    property bool gammaControlAvailable: false
    property int resumeRecoveryAttempt: 0
    readonly property bool _gammaNeeded: nightModeEnabled || SessionData.displayGamma !== 1.0 || SessionData.displayContrast !== 1.0

    property var gammaState: ({})
    property int gammaCurrentTemp: gammaState?.currentTemp ?? 0
    property string gammaNextTransition: gammaState?.nextTransition ?? ""
    property string gammaSunriseTime: gammaState?.sunriseTime ?? ""
    property string gammaSunsetTime: gammaState?.sunsetTime ?? ""
    property string gammaDawnTime: gammaState?.dawnTime ?? ""
    property string gammaNightTime: gammaState?.nightTime ?? ""
    property bool gammaIsDay: gammaState?.isDay ?? true
    property real gammaSunPosition: gammaState?.sunPosition ?? 0
    property int gammaLowTemp: gammaState?.config?.LowTemp ?? 0
    property int gammaHighTemp: gammaState?.config?.HighTemp ?? 0
    property bool gammaAdjustAvailable: gammaControlAvailable && DMSService.apiVersion >= 34

    function _setNightModeEnabled(enabled, quiet, onComplete) {
        if (!gammaControlAvailable) {
            if (!quiet && enabled)
                ToastService.showWarning(I18n.tr("Night mode failed: DMS gamma control not available"));
            if (onComplete)
                onComplete(false);
            return;
        }

        DMSService.sendRequest("wayland.gamma.setEnabled", {
            "enabled": enabled
        }, response => {
            if (response.error) {
                log.error(`Failed to ${enabled ? "enable" : "disable"} gamma control:`, response.error);
                if (!quiet) {
                    const title = enabled ? I18n.tr("Failed to enable night mode") : I18n.tr("Failed to disable night mode");
                    ToastService.showError(title, response.error, "", "night-mode");
                }
                if (onComplete)
                    onComplete(false);
                return;
            }
            ToastService.dismissCategory("night-mode");
            if (onComplete)
                onComplete(true);
        });
    }

    function enableNightMode() {
        nightModeEnabled = true;
        SessionData.setNightModeEnabled(true);

        _setNightModeEnabled(true, false, success => {
            if (!success) {
                nightModeEnabled = false;
                SessionData.setNightModeEnabled(false);
                return;
            }

            if (SessionData.nightModeAutoEnabled) {
                startAutomation();
            } else {
                applyNightModeDirectly();
            }
            root.handleNightModeExceptions();
        });
    }

    function disableNightMode() {
        nightModeEnabled = false;
        nightModePaused = false;
        SessionData.setNightModeEnabled(false);
        _setNightModeEnabled(false, false);
    }

    function toggleNightMode() {
        if (nightModeEnabled) {
            disableNightMode();
        } else {
            enableNightMode();
        }
    }

    function pauseNightMode() {
        nightModePaused = true;
        _setNightModeEnabled(false, true, success => {
            if (!success)
                nightModePaused = false;
        });
    }

    function resumeNightMode() {
        nightModePaused = false;
        _setNightModeEnabled(true, true, success => {
            if (!success)
                nightModePaused = true;
        });
    }

    function isNightModeExcludedApp(appId: string): bool {
        const excludedApps = SettingsData.nightModeExcludedApps || [];
        if (!excludedApps.length)
            return false;

        const desktopId = DesktopEntries.heuristicLookup(Paths.moddedAppId(appId))?.id ?? "";
        return excludedApps.some(excludedId => Paths.isAppIdMatch(appId, excludedId, desktopId));
    }

    function handleNightModeExceptions() {
        if (!nightModeEnabled)
            return;

        if (CompositorService.inOverview) {
            if (nightModePaused)
                resumeNightMode();
            return;
        }

        const activeApp = ToplevelManager.activeToplevel;
        if (!activeApp) {
            if (nightModePaused && !ToplevelManager.toplevels.values.length)
                resumeNightMode();
            return;
        }

        const shouldPause = (SettingsData.nightModeExcludeFullscreen && activeApp.fullscreen) || isNightModeExcludedApp(activeApp.appId);
        if (shouldPause === nightModePaused)
            return;

        if (shouldPause)
            pauseNightMode();
        else
            resumeNightMode();
    }

    function applyGammaAdjustments() {
        if (!gammaAdjustAvailable)
            return;

        DMSService.sendRequest("wayland.gamma.setGamma", {
            "gamma": SessionData.displayGamma,
            "contrast": SessionData.displayContrast
        }, response => {
            if (!response.error)
                return;
            log.error("Failed to set gamma adjustments:", response.error);
        });
    }

    function setDisplayGamma(gamma) {
        SessionData.setDisplayGamma(gamma);
    }

    function setDisplayContrast(contrast) {
        SessionData.setDisplayContrast(contrast);
    }

    function applyNightModeDirectly() {
        const temperature = SessionData.nightModeTemperature || 4000;

        DMSService.sendRequest("wayland.gamma.setManualTimes", {
            "sunrise": null,
            "sunset": null
        }, response => {
            if (response.error) {
                log.error("Failed to clear manual times:", response.error);
                return;
            }

            DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
                "use": false
            }, response => {
                if (response.error) {
                    log.error("Failed to disable IP location:", response.error);
                    return;
                }

                DMSService.sendRequest("wayland.gamma.setTemperature", {
                    "low": temperature,
                    "high": temperature
                }, response => {
                    if (response.error) {
                        log.error("Failed to set temperature:", response.error);
                        ToastService.showError(I18n.tr("Failed to set night mode temperature"), response.error, "", "night-mode");
                    } else {
                        ToastService.dismissCategory("night-mode");
                    }
                });
            });
        });
    }

    function startAutomation() {
        if (!automationAvailable) {
            return;
        }

        const mode = SessionData.nightModeAutoMode || "time";

        switch (mode) {
        case "time":
            startTimeBasedMode();
            break;
        case "location":
            startLocationBasedMode();
            break;
        }
    }

    function startTimeBasedMode() {
        const temperature = SessionData.nightModeTemperature || 4000;
        const highTemp = SessionData.nightModeHighTemperature || 6500;
        const sunriseHour = SessionData.nightModeEndHour;
        const sunriseMinute = SessionData.nightModeEndMinute;
        const sunsetHour = SessionData.nightModeStartHour;
        const sunsetMinute = SessionData.nightModeStartMinute;

        const sunrise = `${String(sunriseHour).padStart(2, '0')}:${String(sunriseMinute).padStart(2, '0')}`;
        const sunset = `${String(sunsetHour).padStart(2, '0')}:${String(sunsetMinute).padStart(2, '0')}`;

        DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
            "use": false
        }, response => {
            if (response.error) {
                log.error("Failed to disable IP location:", response.error);
                return;
            }

            DMSService.sendRequest("wayland.gamma.setTemperature", {
                "low": temperature,
                "high": highTemp
            }, response => {
                if (response.error) {
                    log.error("Failed to set temperature:", response.error);
                    ToastService.showError(I18n.tr("Failed to set night mode temperature"), response.error, "", "night-mode");
                    return;
                }

                DMSService.sendRequest("wayland.gamma.setManualTimes", {
                    "sunrise": sunrise,
                    "sunset": sunset,
                    "durationMinutes": SessionData.nightModeTransitionMinutes
                }, response => {
                    if (response.error) {
                        log.error("Failed to set manual times:", response.error);
                        ToastService.showError(I18n.tr("Failed to set night mode schedule"), response.error, "", "night-mode");
                    } else {
                        ToastService.dismissCategory("night-mode");
                    }
                });
            });
        });
    }

    function startLocationBasedMode() {
        const temperature = SessionData.nightModeTemperature || 4000;
        const highTemp = SessionData.nightModeHighTemperature || 6500;

        DMSService.sendRequest("wayland.gamma.setManualTimes", {
            "sunrise": null,
            "sunset": null
        }, response => {
            if (response.error) {
                log.error("Failed to clear manual times:", response.error);
                return;
            }

            DMSService.sendRequest("wayland.gamma.setTemperature", {
                "low": temperature,
                "high": highTemp
            }, response => {
                if (response.error) {
                    log.error("Failed to set temperature:", response.error);
                    ToastService.showError(I18n.tr("Failed to set night mode temperature"), response.error, "", "night-mode");
                    return;
                }

                if (SessionData.nightModeUseIPLocation) {
                    DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
                        "use": true
                    }, response => {
                        if (response.error) {
                            log.error("Failed to enable IP location:", response.error);
                            ToastService.showError(I18n.tr("Failed to enable IP location"), response.error, "", "night-mode");
                        } else {
                            ToastService.dismissCategory("night-mode");
                        }
                    });
                } else if (SessionData.latitude !== 0.0 && SessionData.longitude !== 0.0) {
                    DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
                        "use": false
                    }, response => {
                        if (response.error) {
                            log.error("Failed to disable IP location:", response.error);
                            return;
                        }

                        DMSService.sendRequest("wayland.gamma.setLocation", {
                            "latitude": SessionData.latitude,
                            "longitude": SessionData.longitude
                        }, response => {
                            if (response.error) {
                                log.error("Failed to set location:", response.error);
                                ToastService.showError(I18n.tr("Failed to set night mode location"), response.error, "", "night-mode");
                            } else {
                                ToastService.dismissCategory("night-mode");
                            }
                        });
                    });
                } else {
                    log.warn("Location mode selected but no coordinates set and IP location disabled");
                }
            });
        });
    }

    function evaluateNightMode() {
        if (SessionData.nightModeAutoEnabled) {
            restartTimer.nextAction = "automation";
            restartTimer.start();
            return;
        }
        if (!nightModeEnabled)
            return;
        restartTimer.nextAction = "direct";
        restartTimer.start();
    }

    function runResumeRecoveryPass() {
        checkGammaControlAvailability();

        if (nightModeEnabled) {
            evaluateNightMode();
        }
    }

    function checkGammaControlAvailability() {
        if (!DMSService.isConnected) {
            return;
        }

        if (DMSService.apiVersion < 6) {
            gammaControlAvailable = false;
            automationAvailable = false;
            return;
        }

        if (!DMSService.capabilities.includes("gamma")) {
            gammaControlAvailable = false;
            automationAvailable = false;
            return;
        }

        DMSService.sendRequest("wayland.gamma.getState", null, response => {
            if (response.error) {
                gammaControlAvailable = false;
                automationAvailable = false;
                log.error("Gamma control not available:", response.error);
            } else {
                gammaControlAvailable = true;
                automationAvailable = true;
                if (_gammaNeeded)
                    applyGammaAdjustments();

                if (!nightModeEnabled) {
                    evaluateNightMode();
                    return;
                }
                _setNightModeEnabled(!nightModePaused, true, success => {
                    if (!success)
                        return;
                    evaluateNightMode();
                    handleNightModeExceptions();
                });
            }
        });
    }

    Timer {
        id: gammaAdjustTimer
        interval: 250
        repeat: false
        onTriggered: applyGammaAdjustments()
    }

    Timer {
        id: restartTimer
        property string nextAction: ""
        interval: 250
        repeat: false

        onTriggered: {
            if (nextAction === "automation") {
                startAutomation();
            } else if (nextAction === "direct") {
                applyNightModeDirectly();
            }
            nextAction = "";
        }
    }

    Timer {
        id: resumeRecoveryTimer
        interval: 400
        repeat: false

        onTriggered: {
            runResumeRecoveryPass();
            resumeRecoveryAttempt++;

            switch (resumeRecoveryAttempt) {
            case 1:
                interval = 1400;
                restart();
                return;
            case 2:
                interval = 2600;
                restart();
                return;
            }

            resumeRecoveryAttempt = 0;
            interval = 400;
        }
    }

    Component.onCompleted: {
        nightModeEnabled = SessionData.nightModeEnabled;
        if (DMSService.isConnected) {
            checkGammaControlAvailability();
        }
    }

    Connections {
        target: DMSService

        function onConnectionStateChanged() {
            if (!DMSService.isConnected) {
                gammaControlAvailable = false;
                automationAvailable = false;
                return;
            }
            checkGammaControlAvailability();
        }

        function onCapabilitiesReceived() {
            checkGammaControlAvailability();
        }

        function onGammaStateUpdate(data) {
            root.gammaState = data;
        }
    }

    Connections {
        target: SessionService
        enabled: root._gammaNeeded

        function onSessionResumed() {
            resumeRecoveryAttempt = 0;
            resumeRecoveryTimer.interval = 400;
            resumeRecoveryTimer.restart();
        }
    }

    Connections {
        target: SessionData

        function onNightModeEnabledChanged() {
            nightModeEnabled = SessionData.nightModeEnabled;
            evaluateNightMode();
        }

        function onNightModeAutoEnabledChanged() {
            evaluateNightMode();
        }
        function onNightModeAutoModeChanged() {
            evaluateNightMode();
        }
        function onNightModeStartHourChanged() {
            evaluateNightMode();
        }
        function onNightModeStartMinuteChanged() {
            evaluateNightMode();
        }
        function onNightModeEndHourChanged() {
            evaluateNightMode();
        }
        function onNightModeEndMinuteChanged() {
            evaluateNightMode();
        }
        function onNightModeTransitionMinutesChanged() {
            evaluateNightMode();
        }
        function onNightModeTemperatureChanged() {
            evaluateNightMode();
        }
        function onNightModeHighTemperatureChanged() {
            evaluateNightMode();
        }
        function onLatitudeChanged() {
            evaluateNightMode();
        }
        function onLongitudeChanged() {
            evaluateNightMode();
        }
        function onNightModeUseIPLocationChanged() {
            evaluateNightMode();
        }
        function onDisplayGammaChanged() {
            gammaAdjustTimer.restart();
        }
        function onDisplayContrastChanged() {
            gammaAdjustTimer.restart();
        }
    }

    Connections {
        target: SettingsData

        function onNightModeExcludedAppsChanged() {
            root.handleNightModeExceptions();
        }

        function onNightModeExcludeFullscreenChanged() {
            root.handleNightModeExceptions();
        }
    }

    Connections {
        target: ToplevelManager
        enabled: root.nightModeEnabled
        function onActiveToplevelChanged() {
            root.handleNightModeExceptions();
        }
    }

    Connections {
        target: ToplevelManager.activeToplevel
        enabled: root.nightModeEnabled
        function onFullscreenChanged() {
            root.handleNightModeExceptions();
        }
    }

    Connections {
        target: CompositorService
        enabled: root.nightModeEnabled
        function onInOverviewChanged() {
            root.handleNightModeExceptions();
        }
    }

    IpcHandler {
        function toggle(): string {
            root.toggleNightMode();
            return root.nightModeEnabled ? "Night mode enabled" : "Night mode disabled";
        }

        function enable(): string {
            root.enableNightMode();
            return "Night mode enabled";
        }

        function disable(): string {
            root.disableNightMode();
            return "Night mode disabled";
        }

        function status(): string {
            if (!root.gammaControlAvailable)
                return "Night mode: unavailable (no gamma control)";

            const parts = ["Night mode: " + (root.nightModeEnabled ? "enabled" : "disabled")];

            if (root.gammaCurrentTemp > 0)
                parts.push("Current temperature: " + root.gammaCurrentTemp + "K");

            parts.push("Target night temperature: " + SessionData.nightModeTemperature + "K");

            if (root.gammaAdjustAvailable) {
                parts.push("Gamma: " + SessionData.displayGamma);
                parts.push("Contrast: " + SessionData.displayContrast);
            }

            if (SessionData.nightModeAutoEnabled) {
                parts.push("Target day temperature: " + SessionData.nightModeHighTemperature + "K");
                parts.push("Automation: " + SessionData.nightModeAutoMode);
                parts.push("Period: " + (root.gammaIsDay ? "day" : "night"));

                if (root.gammaNextTransition)
                    parts.push("Next transition: " + root.gammaNextTransition);
                if (root.gammaSunriseTime)
                    parts.push("Sunrise: " + root.gammaSunriseTime);
                if (root.gammaSunsetTime)
                    parts.push("Sunset: " + root.gammaSunsetTime);
            }

            return parts.join("\n");
        }

        function gamma(value: string): string {
            if (!root.gammaAdjustAvailable)
                return "Gamma adjustment not available (requires dms API v34+)";
            if (!value)
                return SessionData.displayGamma.toString();

            const gamma = parseFloat(value);
            if (isNaN(gamma) || gamma < 0.5 || gamma > 2.0)
                return "Gamma must be between 0.5 and 2.0";

            root.setDisplayGamma(gamma);
            return "Gamma set to " + gamma;
        }

        function contrast(value: string): string {
            if (!root.gammaAdjustAvailable)
                return "Contrast adjustment not available (requires dms API v34+)";
            if (!value)
                return SessionData.displayContrast.toString();

            const contrast = parseFloat(value);
            if (isNaN(contrast) || contrast < 0.5 || contrast > 2.0)
                return "Contrast must be between 0.5 and 2.0";

            root.setDisplayContrast(contrast);
            return "Contrast set to " + contrast;
        }

        function getCurrentTemp(): string {
            if (!root.gammaControlAvailable)
                return "Gamma control not available";
            if (root.gammaCurrentTemp <= 0)
                return "No current temperature reported";
            return root.gammaCurrentTemp.toString();
        }

        function getTargetTemp(): string {
            return SessionData.nightModeTemperature.toString();
        }

        function getDayTemp(): string {
            return SessionData.nightModeHighTemperature.toString();
        }

        function setTargetTemp(value: string): string {
            if (!value)
                return "Usage: night setTargetTemp <1000-6000>";

            const temp = parseInt(value);
            if (isNaN(temp))
                return "Invalid temperature: " + value;
            if (temp < 1000 || temp > 6000)
                return "Temperature must be between 1000K and 6000K";

            const rounded = Math.round(temp / 500) * 500;
            if (rounded > SessionData.nightModeHighTemperature)
                return "Night temperature must not exceed the day temperature (" + SessionData.nightModeHighTemperature + "K)";
            SessionData.setNightModeTemperature(rounded);

            if (root.nightModeEnabled) {
                switch (true) {
                case SessionData.nightModeAutoEnabled:
                    root.startAutomation();
                    break;
                default:
                    root.applyNightModeDirectly();
                    break;
                }
            }

            if (rounded !== temp)
                return "Night temperature set to " + rounded + "K (rounded from " + temp + "K)";
            return "Night temperature set to " + rounded + "K";
        }

        function setDayTemp(value: string): string {
            if (!value)
                return "Usage: night setDayTemp <1000-6500>";

            const temp = parseInt(value);
            if (isNaN(temp))
                return "Invalid temperature: " + value;
            if (temp < 1000 || temp > 6500)
                return "Temperature must be between 1000K and 6500K";

            const rounded = Math.round(temp / 500) * 500;
            if (rounded < SessionData.nightModeTemperature)
                return "Day temperature must be at least the night temperature (" + SessionData.nightModeTemperature + "K)";
            SessionData.setNightModeHighTemperature(rounded);

            if (root.nightModeEnabled && SessionData.nightModeAutoEnabled)
                root.startAutomation();

            if (rounded !== temp)
                return "Day temperature set to " + rounded + "K (rounded from " + temp + "K)";
            return "Day temperature set to " + rounded + "K";
        }

        function getSchedule(): string {
            if (!SessionData.nightModeAutoEnabled)
                return "Automation disabled";

            const parts = ["Mode: " + SessionData.nightModeAutoMode];
            parts.push("Period: " + (root.gammaIsDay ? "day" : "night"));

            if (root.gammaDawnTime)
                parts.push("Dawn: " + root.gammaDawnTime);
            if (root.gammaSunriseTime)
                parts.push("Sunrise: " + root.gammaSunriseTime);
            if (root.gammaSunsetTime)
                parts.push("Sunset: " + root.gammaSunsetTime);
            if (root.gammaNightTime)
                parts.push("Night: " + root.gammaNightTime);
            if (root.gammaNextTransition)
                parts.push("Next transition: " + root.gammaNextTransition);
            if (root.gammaSunPosition > 0)
                parts.push("Sun position: " + root.gammaSunPosition.toFixed(2) + "°");

            return parts.join("\n");
        }

        target: "night"
    }
}
