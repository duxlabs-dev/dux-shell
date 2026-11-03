pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("ThemeAutoService")

    property bool active: false
    readonly property bool backendAvailable: DMSService.isConnected && DMSService.capabilities.includes("theme.auto")

    onActiveChanged: {
        if (active) {
            DMSService.addSubscription("theme.auto");
            return;
        }
        if (DMSService.activeSubscriptions.includes("theme.auto"))
            DMSService.removeSubscription("theme.auto");
    }

    Component.onCompleted: {
        if (typeof SessionData !== "undefined" && SessionData.themeModeAutoEnabled) {
            start();
        }
    }

    Connections {
        target: SessionData

        function onThemeModeAutoEnabledChanged() {
            if (SessionData.themeModeAutoEnabled) {
                root.start();
            } else {
                root.stop();
            }
        }
    }

    Connections {
        target: SessionData
        enabled: root.active

        function onThemeModeAutoModeChanged() {
            root.evaluate();
            root.syncTimeSchedule();
            root.syncLocationSchedule();
        }

        function onThemeModeShareGammaSettingsChanged() {
            root.evaluate();
            root.syncTimeSchedule();
            root.syncLocationSchedule();
        }

        function onThemeModeStartHourChanged() {
            root.resyncOwnSchedule();
        }

        function onThemeModeStartMinuteChanged() {
            root.resyncOwnSchedule();
        }

        function onThemeModeEndHourChanged() {
            root.resyncOwnSchedule();
        }

        function onThemeModeEndMinuteChanged() {
            root.resyncOwnSchedule();
        }

        function onNightModeStartHourChanged() {
            root.resyncSharedSchedule();
        }

        function onNightModeStartMinuteChanged() {
            root.resyncSharedSchedule();
        }

        function onNightModeEndHourChanged() {
            root.resyncSharedSchedule();
        }

        function onNightModeEndMinuteChanged() {
            root.resyncSharedSchedule();
        }

        function onLatitudeChanged() {
            root.resyncCoordinates();
        }

        function onLongitudeChanged() {
            root.resyncCoordinates();
        }

        function onNightModeUseIPLocationChanged() {
            if (SessionData.themeModeAutoMode !== "location")
                return;
            DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
                "use": SessionData.nightModeUseIPLocation
            }, response => {
                if (!response.error && !SessionData.nightModeUseIPLocation && SessionData.latitude !== 0.0 && SessionData.longitude !== 0.0) {
                    DMSService.sendRequest("wayland.gamma.setLocation", {
                        "latitude": SessionData.latitude,
                        "longitude": SessionData.longitude
                    });
                }
            });
            root.evaluate();
            root.syncLocationSchedule();
        }
    }

    function resyncOwnSchedule() {
        if (SessionData.themeModeShareGammaSettings)
            return;
        evaluate();
        syncTimeSchedule();
    }

    function resyncSharedSchedule() {
        if (!SessionData.themeModeShareGammaSettings)
            return;
        evaluate();
        syncTimeSchedule();
    }

    function resyncCoordinates() {
        if (SessionData.themeModeAutoMode !== "location")
            return;
        if (!SessionData.nightModeUseIPLocation && SessionData.latitude !== 0.0 && SessionData.longitude !== 0.0) {
            DMSService.sendRequest("wayland.gamma.setLocation", {
                "latitude": SessionData.latitude,
                "longitude": SessionData.longitude
            });
        }
        evaluate();
        syncLocationSchedule();
    }

    Connections {
        target: NightModeService
        enabled: typeof NightModeService !== "undefined" && typeof SessionData !== "undefined" && SessionData.themeModeAutoEnabled && SessionData.themeModeAutoMode === "location" && !root.backendAvailable

        function onGammaIsDayChanged() {
            if (Theme.isLightMode !== NightModeService.gammaIsDay) {
                Theme.setLightMode(NightModeService.gammaIsDay, true, true);
            }
        }
    }

    Connections {
        target: DMSService

        function onThemeAutoStateUpdate(data) {
            if (!SessionData.themeModeAutoEnabled) {
                return;
            }
            root.applyBackendState(data);
        }

        function onConnectionStateChanged() {
            if (DMSService.isConnected && SessionData.themeModeAutoMode === "time") {
                root.syncTimeSchedule();
            }

            if (DMSService.isConnected && SessionData.themeModeAutoMode === "location") {
                root.syncLocationSchedule();
            }

            if (root.backendAvailable && SessionData.themeModeAutoEnabled) {
                DMSService.sendRequest("theme.auto.getState", null, response => {
                    if (response && response.result) {
                        root.applyBackendState(response.result);
                    }
                });
            }

            if (!SessionData.themeModeAutoEnabled) {
                return;
            }

            if (DMSService.isConnected && SessionData.themeModeAutoMode === "location") {
                if (SessionData.nightModeUseIPLocation) {
                    DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
                        "use": true
                    }, response => {
                        if (!response.error) {
                            root.log.info("Theme automation: IP location enabled after connection");
                        }
                    });
                } else if (SessionData.latitude !== 0.0 && SessionData.longitude !== 0.0) {
                    DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
                        "use": false
                    }, response => {
                        if (!response.error) {
                            DMSService.sendRequest("wayland.gamma.setLocation", {
                                "latitude": SessionData.latitude,
                                "longitude": SessionData.longitude
                            }, locationResponse => {
                                if (locationResponse?.error) {
                                    root.log.warn("Theme automation: Failed to set location", locationResponse.error);
                                }
                            });
                        }
                    });
                } else {
                    root.log.warn("Theme automation: No location configured");
                }
            }
        }
    }

    Connections {
        target: SessionService
        enabled: SessionData.themeModeAutoEnabled

        function onSessionUnlocked() {
            root.refresh();
        }

        function onSessionResumed() {
            root.refresh();
        }
    }

    function refresh() {
        if (!backendAvailable) {
            evaluate();
            return;
        }
        DMSService.sendRequest("theme.auto.trigger", {});
    }

    function applyBackendState(state) {
        if (!state) {
            return;
        }
        if (state.config && state.config.mode && state.config.mode !== SessionData.themeModeAutoMode) {
            return;
        }
        if (typeof SessionData !== "undefined" && state.nextTransition !== undefined) {
            SessionData.themeModeNextTransition = state.nextTransition || "";
        }
        if (state.isLight !== undefined && Theme.isLightMode !== state.isLight) {
            Theme.setLightMode(state.isLight, true, true);
        }
    }

    function syncTimeSchedule() {
        if (typeof SessionData === "undefined" || typeof DMSService === "undefined") {
            return;
        }

        if (!DMSService.isConnected) {
            return;
        }

        const timeModeActive = SessionData.themeModeAutoEnabled && SessionData.themeModeAutoMode === "time";

        if (!timeModeActive) {
            return;
        }

        DMSService.sendRequest("theme.auto.setMode", {
            "mode": "time"
        });

        const shareSettings = SessionData.themeModeShareGammaSettings;
        const startHour = shareSettings ? SessionData.nightModeStartHour : SessionData.themeModeStartHour;
        const startMinute = shareSettings ? SessionData.nightModeStartMinute : SessionData.themeModeStartMinute;
        const endHour = shareSettings ? SessionData.nightModeEndHour : SessionData.themeModeEndHour;
        const endMinute = shareSettings ? SessionData.nightModeEndMinute : SessionData.themeModeEndMinute;

        DMSService.sendRequest("theme.auto.setSchedule", {
            "startHour": startHour,
            "startMinute": startMinute,
            "endHour": endHour,
            "endMinute": endMinute
        }, response => {
            if (response && response.error) {
                log.error("Theme automation: Failed to sync time schedule:", response.error);
            }
        });

        DMSService.sendRequest("theme.auto.setEnabled", {
            "enabled": true
        });
        DMSService.sendRequest("theme.auto.trigger", {});
    }

    function syncLocationSchedule() {
        if (typeof SessionData === "undefined" || typeof DMSService === "undefined") {
            return;
        }

        if (!DMSService.isConnected) {
            return;
        }

        const locationModeActive = SessionData.themeModeAutoEnabled && SessionData.themeModeAutoMode === "location";

        if (!locationModeActive) {
            return;
        }

        DMSService.sendRequest("theme.auto.setMode", {
            "mode": "location"
        });

        if (SessionData.nightModeUseIPLocation) {
            DMSService.sendRequest("theme.auto.setUseIPLocation", {
                "use": true
            });
        } else {
            DMSService.sendRequest("theme.auto.setUseIPLocation", {
                "use": false
            });
            if (SessionData.latitude !== 0.0 && SessionData.longitude !== 0.0) {
                DMSService.sendRequest("theme.auto.setLocation", {
                    "latitude": SessionData.latitude,
                    "longitude": SessionData.longitude
                });
            }
        }

        DMSService.sendRequest("theme.auto.setEnabled", {
            "enabled": true
        });
        DMSService.sendRequest("theme.auto.trigger", {});
    }

    function evaluate() {
        if (typeof SessionData === "undefined" || !SessionData.themeModeAutoEnabled) {
            return;
        }

        if (backendAvailable) {
            DMSService.sendRequest("theme.auto.getState", null, response => {
                if (response && response.result) {
                    applyBackendState(response.result);
                }
            });
            return;
        }

        const mode = SessionData.themeModeAutoMode;

        if (mode === "location") {
            evaluateLocation();
        } else {
            evaluateTime();
        }
    }

    function evaluateLocation() {
        if (typeof NightModeService !== "undefined") {
            const shouldBeLight = NightModeService.gammaIsDay;
            if (Theme.isLightMode !== shouldBeLight) {
                Theme.setLightMode(shouldBeLight, true, true);
            }
            return;
        }

        if (!SessionData.nightModeUseIPLocation && SessionData.latitude !== 0.0 && SessionData.longitude !== 0.0) {
            const shouldBeLight = calculateIsDaytime(SessionData.latitude, SessionData.longitude);
            if (Theme.isLightMode !== shouldBeLight) {
                Theme.setLightMode(shouldBeLight, true, true);
            }
            return;
        }

        if (root.active) {
            if (SessionData.nightModeUseIPLocation) {
                log.warn("Theme automation: Waiting for IP location from backend");
            } else {
                log.warn("Theme automation: Location mode requires coordinates");
            }
        }
    }

    function evaluateTime() {
        const shareSettings = SessionData.themeModeShareGammaSettings;

        const startHour = shareSettings ? SessionData.nightModeStartHour : SessionData.themeModeStartHour;
        const startMinute = shareSettings ? SessionData.nightModeStartMinute : SessionData.themeModeStartMinute;
        const endHour = shareSettings ? SessionData.nightModeEndHour : SessionData.themeModeEndHour;
        const endMinute = shareSettings ? SessionData.nightModeEndMinute : SessionData.themeModeEndMinute;

        const now = new Date();
        const currentMinutes = now.getHours() * 60 + now.getMinutes();
        const startMinutes = startHour * 60 + startMinute;
        const endMinutes = endHour * 60 + endMinute;

        let shouldBeLight;
        if (startMinutes < endMinutes) {
            shouldBeLight = currentMinutes < startMinutes || currentMinutes >= endMinutes;
        } else {
            shouldBeLight = currentMinutes >= endMinutes && currentMinutes < startMinutes;
        }

        if (Theme.isLightMode !== shouldBeLight) {
            Theme.setLightMode(shouldBeLight, true, true);
        }
    }

    function calculateIsDaytime(lat, lng) {
        const now = new Date();
        const start = new Date(now.getFullYear(), 0, 0);
        const diff = now - start;
        const dayOfYear = Math.floor(diff / 86400000);
        const latRad = lat * Math.PI / 180;

        const declination = 23.45 * Math.sin((360 / 365) * (dayOfYear - 81) * Math.PI / 180);
        const declinationRad = declination * Math.PI / 180;

        const cosHourAngle = -Math.tan(latRad) * Math.tan(declinationRad);

        if (cosHourAngle > 1) {
            return false;
        }
        if (cosHourAngle < -1) {
            return true;
        }

        const hourAngle = Math.acos(cosHourAngle);
        const hourAngleDeg = hourAngle * 180 / Math.PI;

        const sunriseHour = 12 - hourAngleDeg / 15;
        const sunsetHour = 12 + hourAngleDeg / 15;

        const timeZoneOffset = now.getTimezoneOffset() / 60;
        const localSunrise = sunriseHour - lng / 15 - timeZoneOffset;
        const localSunset = sunsetHour - lng / 15 - timeZoneOffset;

        const currentHour = now.getHours() + now.getMinutes() / 60;

        const normalizeSunrise = ((localSunrise % 24) + 24) % 24;
        const normalizeSunset = ((localSunset % 24) + 24) % 24;

        return currentHour >= normalizeSunrise && currentHour < normalizeSunset;
    }

    function sendLocationToBackend() {
        if (typeof SessionData === "undefined" || typeof DMSService === "undefined") {
            return false;
        }

        if (!DMSService.isConnected) {
            return false;
        }

        if (SessionData.nightModeUseIPLocation) {
            DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
                "use": true
            }, response => {
                if (response?.error) {
                    log.warn("Theme automation: Failed to enable IP location", response.error);
                }
            });
            return true;
        } else if (SessionData.latitude !== 0.0 && SessionData.longitude !== 0.0) {
            DMSService.sendRequest("wayland.gamma.setUseIPLocation", {
                "use": false
            }, response => {
                if (!response.error) {
                    DMSService.sendRequest("wayland.gamma.setLocation", {
                        "latitude": SessionData.latitude,
                        "longitude": SessionData.longitude
                    }, locResp => {
                        if (locResp?.error) {
                            log.warn("Theme automation: Failed to set location", locResp.error);
                        }
                    });
                }
            });
            return true;
        }
        return false;
    }

    Timer {
        id: locationRetryTimer
        interval: 1000
        repeat: true
        running: false
        property int retryCount: 0

        onTriggered: {
            if (root.sendLocationToBackend()) {
                stop();
                retryCount = 0;
                root.evaluate();
            } else {
                retryCount++;
                if (retryCount >= 10) {
                    stop();
                    retryCount = 0;
                }
            }
        }
    }

    function start() {
        root.active = true;

        syncTimeSchedule();
        syncLocationSchedule();

        const sent = sendLocationToBackend();

        if (!sent && typeof SessionData !== "undefined" && SessionData.themeModeAutoMode === "location") {
            locationRetryTimer.start();
        } else {
            evaluate();
        }
    }

    function stop() {
        root.active = false;
        if (typeof DMSService !== "undefined" && DMSService.isConnected) {
            DMSService.sendRequest("theme.auto.setEnabled", {
                "enabled": false
            });
        }
    }
}
