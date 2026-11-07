pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("IdleService")

    property bool enabled: true
    property bool respectInhibitors: true

    readonly property bool externalInhibitActive: DMSService.screensaverInhibited

    readonly property bool isOnBattery: BatteryService.batteryAvailable && !BatteryService.isPluggedIn
    readonly property int monitorTimeout: isOnBattery ? SettingsData.batteryMonitorTimeout : SettingsData.acMonitorTimeout
    readonly property int lockTimeout: isOnBattery ? SettingsData.batteryLockTimeout : SettingsData.acLockTimeout
    readonly property int suspendTimeout: isOnBattery ? SettingsData.batterySuspendTimeout : SettingsData.acSuspendTimeout
    readonly property int suspendBehavior: isOnBattery ? SettingsData.batterySuspendBehavior : SettingsData.acSuspendBehavior
    readonly property int postLockMonitorTimeout: isOnBattery ? SettingsData.batteryPostLockMonitorTimeout : SettingsData.acPostLockMonitorTimeout
    readonly property bool postLockMonitorActive: isShellLocked && postLockMonitorTimeout > 0

    onEnabledChanged: _applyMonitorEnableds()
    onPostLockMonitorActiveChanged: _applyMonitorEnableds()
    onMonitorTimeoutChanged: _rearmIdleMonitors()
    onLockTimeoutChanged: _rearmIdleMonitors()
    onSuspendTimeoutChanged: _rearmIdleMonitors()
    onPostLockMonitorTimeoutChanged: _rearmIdleMonitors()
    onIsShellLockedChanged: _rearmIdleMonitors()

    function _applyMonitorEnableds() {
        // Gate on the shell's own inhibit state rather than relying on the
        // compositor honoring the bar-surface zwp_idle_inhibit inhibitor,
        // which goes inactive whenever the bar surface is occluded
        // (fullscreen windows) or hidden (auto-hide).
        const base = enabled && !SessionService.idleInhibited && !externalInhibitActive;
        monitorOffMonitor.enabled = base && monitorTimeout > 0 && !postLockMonitorActive;
        postLockMonitorOffMonitor.enabled = enabled && postLockMonitorActive;
        lockMonitor.enabled = base && lockTimeout > 0;
        suspendMonitor.enabled = base && suspendTimeout > 0;
    }

    function _rearmIdleMonitors() {
        monitorOffMonitor.enabled = false;
        postLockMonitorOffMonitor.enabled = false;
        lockMonitor.enabled = false;
        suspendMonitor.enabled = false;
        Qt.callLater(_applyMonitorEnableds);
    }

    signal lockRequested
    signal fadeToLockRequested
    signal cancelFadeToLock
    signal dismissFadeToLock
    signal fadeToDpmsRequested
    signal cancelFadeToDpms
    signal requestMonitorOff
    signal requestMonitorOn
    signal requestSuspend

    property var lockComponent: null
    property bool monitorsOff: false
    property bool isShellLocked: false
    property bool isSessionLockSecure: false
    property bool lockPowerOffRequested: false
    property bool sleepBlocked: false

    function _updateSleepBlocked(blockInhibited) {
        if (typeof blockInhibited === "string")
            sleepBlocked = blockInhibited.split(":").includes("sleep");
    }

    function reapplyDpmsIfNeeded() {
        if (monitorsOff)
            CompositorService.powerOffMonitors();
    }

    IdleMonitor {
        id: monitorOffMonitor
        timeout: root.monitorTimeout > 0 ? root.monitorTimeout : 86400
        respectInhibitors: root.respectInhibitors
        enabled: false
        onIsIdleChanged: {
            if (!enabled)
                return;
            if (isIdle) {
                if (SettingsData.fadeToDpmsEnabled) {
                    root.fadeToDpmsRequested();
                } else {
                    root.requestMonitorOff();
                }
            } else {
                if (SettingsData.fadeToDpmsEnabled) {
                    root.cancelFadeToDpms();
                }
                root.requestMonitorOn();
            }
        }
    }

    IdleMonitor {
        id: postLockMonitorOffMonitor
        timeout: root.postLockMonitorTimeout > 0 ? root.postLockMonitorTimeout : 86400
        respectInhibitors: root.respectInhibitors
        enabled: false
        onIsIdleChanged: {
            if (!enabled)
                return;
            if (isIdle) {
                root.requestMonitorOff();
            } else {
                root.requestMonitorOn();
            }
        }
    }

    IdleMonitor {
        id: lockMonitor
        timeout: root.lockTimeout > 0 ? root.lockTimeout : 86400
        respectInhibitors: root.respectInhibitors
        enabled: false
        onIsIdleChanged: {
            if (!enabled)
                return;
            if (isIdle) {
                if (SettingsData.fadeToLockEnabled) {
                    root.fadeToLockRequested();
                } else {
                    root.lockRequested();
                }
            } else {
                if (SettingsData.fadeToLockEnabled) {
                    root.cancelFadeToLock();
                }
            }
        }
    }

    IdleMonitor {
        id: suspendMonitor
        timeout: root.suspendTimeout > 0 ? root.suspendTimeout : 86400
        respectInhibitors: root.respectInhibitors
        enabled: false
        onIsIdleChanged: {
            if (!enabled)
                return;
            if (isIdle)
                root.requestSuspend();
        }
    }

    // Rearming the timeout monitors while idle resets their isIdle without a wake
    // transition, so this listener, never rearmed, catches input while outputs are off.
    IdleMonitor {
        id: wakeMonitor
        timeout: 1
        respectInhibitors: false
        enabled: root.enabled && root.monitorsOff
        onIsIdleChanged: {
            if (!enabled)
                return;
            if (!isIdle && root.monitorsOff)
                root.requestMonitorOn();
        }
    }

    Connections {
        target: SessionService

        function onIdleInhibitedChanged() {
            root._rearmIdleMonitors();
        }
    }

    Connections {
        target: DMSService

        function onCapabilitiesReceived() {
            if (!DMSService.capabilities.includes("dbus"))
                return;
            DMSService.dbusSubscribe("system", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.DBus.Properties", "PropertiesChanged");
            DMSService.dbusGetProperty("system", "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "BlockInhibited", r => root._updateSleepBlocked(r.result?.value));
        }

        function onDbusSignalReceived(subscriptionId, data) {
            if (data.path === "/org/freedesktop/login1")
                root._updateSleepBlocked(data.body?.[1]?.BlockInhibited);
        }
    }

    Connections {
        target: root
        function onRequestMonitorOff() {
            monitorsOff = true;
            CompositorService.powerOffMonitors();
        }

        function onRequestMonitorOn() {
            monitorsOff = false;
            CompositorService.powerOnMonitors();
        }

        function onRequestSuspend() {
            SessionService.suspendWithBehavior(root.suspendBehavior);
        }
    }

    onExternalInhibitActiveChanged: {
        if (externalInhibitActive) {
            const apps = DMSService.screensaverInhibitors.map(i => i.appName).join(", ");
            log.info("External idle inhibit active from:", apps || "unknown");
        } else {
            log.info("External idle inhibit released");
        }
        _rearmIdleMonitors();
    }

    onSleepBlockedChanged: {
        log.info(sleepBlocked ? "Sleep blocked by logind inhibitor" : "Sleep inhibitor released");
        if (sleepBlocked || !suspendMonitor.enabled || !suspendMonitor.isIdle)
            return;
        log.info("Sleep inhibitor released while idle, retrying suspend");
        requestSuspend();
    }

    Component.onCompleted: _applyMonitorEnableds()
}
