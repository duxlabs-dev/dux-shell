pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/GSettings.js" as GSettings // qmllint disable unused-imports

Singleton {
    id: root

    readonly property string settingsTheme: {
        if (typeof SettingsData === "undefined")
            return "";
        const theme = SettingsData.resolveIconTheme();
        return (!theme || theme === "System Default") ? "" : theme;
    }
    property string systemProbedTheme: ""
    readonly property string managedTheme: settingsTheme || systemProbedTheme
    // Upstream quickshell has no icon index; icons then come from Qt's own theme lookup.
    readonly property bool indexed: "iconIndexRevision" in Quickshell
    readonly property int revision: indexed ? Quickshell.iconIndexRevision : 0
    readonly property bool _settled: _initialized && !_probing && (!indexed || !managedTheme || revision > 0)
    property bool ready: false
    property bool _initialized: false
    property bool _probing: false
    property bool _themeSet: false

    on_SettledChanged: {
        if (_settled)
            ready = true;
    }
    onSettingsThemeChanged: {
        if (_initialized && !settingsTheme)
            _probeSystemTheme();
    }
    onManagedThemeChanged: _applyTheme()

    Component.onCompleted: {
        Paths.iconResolver = name => resolve(name);
        if (!settingsTheme)
            _probeSystemTheme();
        _initialized = true;
        _applyTheme();
    }

    function _probeSystemTheme() {
        if (Quickshell.env("QS_ICON_THEME") || _probing)
            return;
        _probing = true;
        const script = `v=$(sed -n 's/^gtk-icon-theme-name *= *//p' "\${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" 2>/dev/null | head -1)
[ -z "$v" ] && v=$(${GSettings.getCmd("org.gnome.desktop.interface", "icon-theme")})
printf '%s' "$v" | tr -d "'\\""`;

        Proc.runCommand(null, ["sh", "-c", script], (out, code) => {
            root.systemProbedTheme = (out || "").trim();
            root._probing = false;
        }, 0);
    }

    function _applyTheme() {
        if (!indexed || !_initialized)
            return;
        // An empty name hands the theme back to the system, which only matters after setting one.
        if (!managedTheme && !_themeSet)
            return;
        Quickshell.iconTheme = managedTheme;
        _themeSet = managedTheme !== "";
    }

    function resolve(name) {
        if (!indexed || !managedTheme || !name)
            return "";
        revision;
        const path = Quickshell.iconFile(name);
        return path ? Paths.toFileUrl(path) : "";
    }
}
