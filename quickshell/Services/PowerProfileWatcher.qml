pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Services

Singleton {
    id: root

    property int currentProfile: -1
    property int previousProfile: -1
    property bool daemonRunning: true

    readonly property bool available: daemonRunning

    function checkDaemon() {
        if (!DMSService.isConnected || !DMSService.capabilities.includes("dbus"))
            return;

        DMSService.dbusCall("system", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", ["org.freedesktop.UPower.PowerProfiles"], response => {
            if (response.error || !response.result)
                return;
            root.daemonRunning = response.result.values?.[0] === true;
        });
    }

    readonly property var availableProfiles: {
        if (!available)
            return [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance];

        return [PowerProfile.PowerSaver, PowerProfile.Balanced].concat(PowerProfiles.hasPerformanceProfile ? [PowerProfile.Performance] : []);
    }

    signal profileChanged(int profile)

    function profileSlug(profile: int): string {
        switch (profile) {
        case PowerProfile.PowerSaver:
            return "power-saver";
        case PowerProfile.Balanced:
            return "balanced";
        case PowerProfile.Performance:
            return "performance";
        default:
            return "unknown";
        }
    }

    function parseProfileSlug(slug: string): int {
        if (!slug)
            return -1;

        const lower = slug.toLowerCase().trim();
        if (lower === "power-saver" || lower === "powersaver" || lower === "saver" || lower === "0")
            return PowerProfile.PowerSaver;
        if (lower === "balanced" || lower === "1")
            return PowerProfile.Balanced;
        if (lower === "performance" || lower === "2")
            return PowerProfile.Performance;
        return -1;
    }

    function applyProfile(profile: int): bool {
        if (!available)
            return false;

        if (profile === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile)
            return false;

        if (availableProfiles.indexOf(profile) === -1)
            return false;

        PowerProfiles.profile = profile;
        return PowerProfiles.profile === profile;
    }

    function cycleProfile(): bool {
        if (!available)
            return false;

        const profiles = availableProfiles;
        const index = profiles.indexOf(PowerProfiles.profile);
        const nextProfile = index === -1 ? PowerProfile.Balanced : profiles[(index + 1) % profiles.length];
        return applyProfile(nextProfile);
    }

    Connections {
        target: PowerProfiles

        function onProfileChanged() {
            root.daemonRunning = true;
            root.previousProfile = root.currentProfile;
            root.currentProfile = PowerProfiles.profile;
            if (root.previousProfile !== -1)
                root.profileChanged(root.currentProfile);
        }
    }

    Connections {
        target: DMSService

        function onCapabilitiesReceived() {
            root.checkDaemon();
        }
    }

    Component.onCompleted: {
        root.currentProfile = PowerProfiles.profile;
        root.previousProfile = PowerProfiles.profile;
    }
}
