pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../Common/GSettings.js" as GSettings // qmllint disable unused-imports
import "../Common/IconFolders.js" as IconFolders
import "../Common/AppIconTint.js" as AppIconTint
import "../DCommon/Common/Hct.js" as Hct

Singleton {
    id: root

    readonly property string settingsTheme: {
        if (typeof SettingsData === "undefined")
            return "";
        const theme = IconFolders.indexName(SettingsData.resolveIconTheme(), SettingsData.iconThemeGenerated, SettingsData.iconFolderState);
        return (!theme || theme === "System Default") ? "" : theme;
    }
    // Folder icons resolve by path into the overlay; indexing it would rescan on every color change.
    readonly property var folderIcons: {
        if (typeof SettingsData === "undefined")
            return null;
        return IconFolders.manifest(SettingsData.resolveIconTheme(), SettingsData.iconThemeGenerated, SettingsData.iconFolderState);
    }
    // Shell tiles that sit beside app icons, such as launcher folders, take this outline to match them.
    readonly property string tileShape: {
        if (typeof SettingsData === "undefined")
            return "";
        return IconFolders.tileShape(SettingsData.resolveIconTheme(), SettingsData.iconThemeGenerated, SettingsData.iconFolderState, SettingsData.iconShape);
    }
    // Those shell tiles turn neutral too when the pack draws every app on one neutral tile.
    readonly property bool neutralTiles: tileShape !== "" && SettingsData.iconAppStyle === "monochrome"
    // The theme draws DMS's own launcher entries, as the self-built pack does.
    readonly property bool drawsShellEntries: {
        if (!indexed || !managedTheme)
            return false;
        revision;
        return Quickshell.iconFile("dev.duxlabs.shell.settings") !== "";
    }
    readonly property var builtInTones: {
        const hct = Hct.toHct(Theme.primary);
        return [96, 80, 32].map(tone => String(Hct.fromHct(hct.hue, hct.chroma, tone)));
    }
    readonly property var duxApps: ["dev.duxlabs.calendar", "dev.duxlabs.files", "dev.duxlabs.edit"]
    readonly property bool tintsDuxApps: !drawsShellEntries && (Theme.currentTheme === Theme.dynamic || Theme.availableThemeNames.includes(Theme.currentTheme))
    property var _duxAppSvgs: ({})
    readonly property var _tintedDuxApps: {
        const tinted = Object.create(null);
        if (!tintsDuxApps)
            return tinted;
        const primary = Hct.toHct(Theme.primary);
        for (const id in _duxAppSvgs)
            tinted[id] = AppIconTint.url(_duxAppSvgs[id], primary);
        return tinted;
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

    Instantiator {
        model: root.tintsDuxApps ? root.duxApps : []

        FileView {
            required property string modelData

            path: root._installedSvg(modelData)
            printErrors: false
            onLoaded: root._storeDuxAppSvg(modelData, text())
        }
    }

    function _probeSystemTheme() {
        if (Quickshell.env("QS_ICON_THEME") || _probing)
            return;
        _probing = true;
        const script = `v=$(sed -n 's/^gtk-icon-theme-name *= *//p' "\${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" 2>/dev/null | head -1)
[ -z "$v" ] && v=$(${GSettings.getCmd("org.gnome.desktop.interface", "icon-theme")})
printf '%s' "$v" | tr -d "'\\""`;

        Proc.runCommand(null, ["sh", "-c", script], (out, code) => {
            // The probe can run before the restore lands and read a folder overlay that is about to go.
            root.systemProbedTheme = IconFolders.baseName((out || "").trim());
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

    function _installedSvg(name) {
        if (!indexed || !managedTheme)
            return "";
        revision;
        const file = Quickshell.iconFile(name);
        return file.endsWith(".svg") ? Paths.toFileUrl(file) : "";
    }

    function _storeDuxAppSvg(id, svg) {
        const svgs = Object.assign({}, _duxAppSvgs);
        svgs[id] = svg;
        _duxAppSvgs = svgs;
    }

    // Panels too small for the Dux Icons badge show the app icon without it; any other url is kept.
    function bareIcon(url: string): string {
        if (typeof SettingsData === "undefined")
            return url;
        return IconFolders.bareUrl(SettingsData.resolveIconTheme(), SettingsData.iconThemeGenerated, SettingsData.iconFolderState, url) || url;
    }

    // bareIcon for an AppIconRenderer value, which resolves plain names itself.
    function bareIconValue(value: string): string {
        if (!value || /^[a-z+]+:/.test(value))
            return value;
        const url = Paths.resolveIconPath(value);
        const bare = bareIcon(url);
        return bare !== url ? "svg:" + bare : value;
    }

    function resolve(name) {
        const tinted = _tintedDuxApps[name];
        if (tinted)
            return tinted;
        const recolored = IconFolders.iconUrl(folderIcons, name);
        if (recolored)
            return recolored;
        if (!indexed || !managedTheme || !name)
            return "";
        revision;
        const path = Quickshell.iconFile(name);
        return path ? Paths.toFileUrl(path) : "";
    }
}
