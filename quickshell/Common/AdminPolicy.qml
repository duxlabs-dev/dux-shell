pragma Singleton

import Quickshell
import qs.Services
import "settings/ManagedSettings.js" as ManagedSettings

// cli-policy.json switches and lock settings, set by `dms run` on each launch (core/internal/clipolicy).
Singleton {
    readonly property bool disableLockIpcUnlock: Quickshell.env("DMS_POLICY_DISABLE_LOCK_IPC_UNLOCK") === "1"
    readonly property bool disableLogindUnlock: Quickshell.env("DMS_POLICY_DISABLE_LOGIND_UNLOCK") === "1"
    readonly property bool disableCustomLockPam: Quickshell.env("DMS_POLICY_DISABLE_CUSTOM_LOCK_PAM") === "1"
    readonly property bool disableUserPlugins: Quickshell.env("DMS_POLICY_DISABLE_USER_PLUGINS") === "1"
    readonly property bool disableSettingsIpcSet: Quickshell.env("DMS_POLICY_DISABLE_SETTINGS_IPC_SET") === "1"
    readonly property var lockSettings: ManagedSettings.parse(Quickshell.env("DMS_POLICY_LOCK_SETTINGS"), Log.scoped("AdminPolicy").warn)
}
