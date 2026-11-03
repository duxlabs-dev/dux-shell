pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../Common/GSettings.js" as GSettings // qmllint disable unused-imports
import "IconThemeIndex.js" as IconIndex

Singleton {
    id: root
    readonly property var log: Log.scoped("IconThemeService")

    readonly property string settingsTheme: {
        if (typeof SettingsData === "undefined")
            return "";
        const theme = SettingsData.resolveIconTheme();
        return (!theme || theme === "System Default") ? "" : theme;
    }
    property string systemProbedTheme: ""
    readonly property string managedTheme: settingsTheme || systemProbedTheme
    property bool ready: false
    property var _iconPaths: Object.create(null)
    property bool _initialized: false
    property bool _probing: false
    property bool _building: false
    property bool _rebuildPending: false

    readonly property var _userIconRoots: {
        const localData = Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericDataLocation));
        const home = Paths.strip(StandardPaths.writableLocation(StandardPaths.HomeLocation));
        return [home + "/.icons", localData + "/icons"];
    }

    readonly property var _dataDirs: {
        const xdg = Quickshell.env("XDG_DATA_DIRS") || "";
        const localData = Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericDataLocation));
        const dataDirs = xdg.trim() !== "" ? [localData].concat(xdg.split(":")) : [localData, "/usr/local/share", "/usr/share"];
        for (const flatpak of [localData + "/flatpak/exports/share", "/var/lib/flatpak/exports/share"]) {
            if (!dataDirs.includes(flatpak))
                dataDirs.push(flatpak);
        }
        return dataDirs.filter((dir, index) => dir && dataDirs.indexOf(dir) === index);
    }

    readonly property var _baseDirs: {
        const bases = [..._userIconRoots];
        for (const d of _dataDirs) {
            const icons = d + "/icons";
            if (!bases.includes(icons))
                bases.push(icons);
        }
        return bases;
    }

    readonly property var _looseDirs: {
        const dirs = _userIconRoots.concat(_dataDirs.map(d => d + "/pixmaps"));
        return dirs.filter((dir, index) => dirs.indexOf(dir) === index);
    }

    onSettingsThemeChanged: {
        if (_initialized && !settingsTheme)
            _probeSystemTheme();
    }
    onManagedThemeChanged: Qt.callLater(_rebuild)

    Component.onCompleted: {
        _initialized = true;
        Paths.iconResolver = name => resolve(name);
        if (!settingsTheme)
            _probeSystemTheme();
        Qt.callLater(_rebuild);
    }

    Timer {
        id: rebuildDebounce
        interval: 2000
        repeat: false
        onTriggered: root._rebuild()
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            if (!root.ready)
                return;
            rebuildDebounce.restart();
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
            root.systemProbedTheme = (out || "").trim();
            root._probing = false;
            Qt.callLater(root._rebuild);
        }, 0);
    }

    function _rebuild() {
        if (!_initialized || _probing)
            return;
        if (_building) {
            _rebuildPending = true;
            return;
        }
        _building = true;
        _rebuildPending = false;
        const theme = managedTheme;
        if (!theme) {
            _publishIndex(theme, Object.create(null));
            return;
        }
        const script = `theme=$1
shift
find_index() { target=$1; shift; for b; do [ -f "$b/$target/index.theme" ] && { echo "$b/$target/index.theme"; return 0; }; done; return 1; }
visited=""; queue="$theme"; order=""
while [ -n "$queue" ]; do
cur=\${queue%% *}; rest=\${queue#"$cur"}; queue=\${rest# }
[ -z "$cur" ] && continue
case " $visited " in *" $cur "*) continue;; esac
visited="$visited $cur"; order="$order $cur"
idx=$(find_index "$cur" "$@") || continue
inh=$(sed -n 's/^Inherits=//p' "$idx" | head -1 | tr -d '"' | tr ',' ' ')
queue="$queue $inh"
done
case " $visited " in *" hicolor "*) ;; *) order="$order hicolor";; esac
for t in $order; do for b; do d="$b/$t"; [ -d "$d" ] && echo "$d"; done; done`;

        Proc.runCommand(null, ["sh", "-c", script, "icon-chain", theme].concat(_baseDirs), (out, code) => {
            const dirs = (out || "").trim().split("\n").filter(dir => dir);
            root._indexTheme(theme, dirs);
        }, 0);
    }

    function _indexTheme(theme, dirs) {
        indexJob.createObject(root, {
            theme: theme,
            searchDirs: dirs,
            looseDirs: _looseDirs
        });
    }

    function _publishIndex(theme, paths) {
        _building = false;
        if (managedTheme === theme && !_probing) {
            _iconPaths = paths;
            ready = true;
        }
        if (_rebuildPending)
            Qt.callLater(_rebuild);
    }

    Component {
        id: indexJob

        Scope {
            id: job

            required property string theme
            required property var searchDirs
            required property var looseDirs
            property var themeIndex: IconIndex.create()
            property var looseIndex: IconIndex.create()
            property int remaining: searchDirs.length ? 2 : 1
            property bool finished: false

            function complete() {
                if (finished || --remaining > 0)
                    return;
                for (const name in looseIndex.paths) {
                    if (!themeIndex.paths[name])
                        themeIndex.paths[name] = looseIndex.paths[name];
                }
                publish();
            }

            function publish() {
                if (finished)
                    return;
                finished = true;
                root._publishIndex(theme, themeIndex.paths);
                destroy();
            }

            Process {
                command: ["find", "-L"].concat(job.searchDirs, ["(", "-name", "*.svg", "-o", "-name", "*.png", ")"])
                running: job.searchDirs.length > 0
                stdout: SplitParser {
                    onRead: data => {
                        if (!job.finished)
                            IconIndex.add(job.themeIndex, data, job.searchDirs, job.looseDirs);
                    }
                }
                onExited: job.complete()
            }

            Process {
                command: ["find", "-L"].concat(job.looseDirs, ["-maxdepth", "1", "(", "-name", "*.svg", "-o", "-name", "*.png", "-o", "-name", "*.xpm", ")"])
                running: true
                stdout: SplitParser {
                    onRead: data => {
                        if (!job.finished)
                            IconIndex.add(job.looseIndex, data, job.searchDirs, job.looseDirs);
                    }
                }
                onExited: job.complete()
            }

            Timer {
                interval: 10000
                running: true
                onTriggered: {
                    root.log.warn("Icon theme index timed out:", job.theme);
                    job.publish();
                }
            }
        }
    }

    function resolve(name) {
        if (!name || !/^[\w.+-]+$/.test(name))
            return "";
        const path = _iconPaths[name];
        return path ? Paths.toFileUrl(path) : "";
    }
}
