//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_MEDIA_BACKEND=ffmpeg
//@ pragma Env QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi
//@ pragma Env QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=vaapi
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Material
//@ pragma UseQApplication
//@ pragma AppId dev.duxlabs.shell

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.Common
import qs.DCommon.Common as DC
import qs.Modules
import qs.Modules.Lock
import qs.Services

ShellRoot {
    id: entrypoint

    readonly property bool disableHotReload: Quickshell.env("DMS_DISABLE_HOT_RELOAD") === "1" || Quickshell.env("DMS_DISABLE_HOT_RELOAD") === "true"

    readonly property bool shellReady: !!Quickshell.env("NOTIFY_SOCKET") && dmsShellLoader.status === Loader.Ready && DMSService.isConnected && DMSService.apiVersion >= 38

    onShellReadyChanged: {
        if (shellReady)
            DMSService.sendRequest("shell.ready", {
                "pid": Quickshell.processId
            });
    }

    Binding {
        target: Quickshell
        property: "watchFiles"
        value: !entrypoint.disableHotReload && !IdleService.isShellLocked
    }

    Component.onCompleted: {
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
        DC.Paths.backend = Paths;
        DC.Log.backend = Log;
        DC.Host.session = SessionService;
        DC.Host.cache = CacheData;
        DC.Host.files = FilesService;
        DC.Host.hyprlandFocusGrab = Qt.binding(() => CompositorService.useHyprlandFocusGrab);
        DC.Host.ownWindowDecorations = Qt.binding(() => SettingsData.floatingWindowTitleBars);
        void IconThemeService.ready;
        // Start SNI registration even when no tray widget is visible.
        void SystemTray.items;
        // Build the polkit agent here, outside incubation: first-touching it from a Connections target during DMSShell's async load crashed QQmlConnections::connectSignalsToMethods.
        void PolkitService.agent;
    }

    Loader {
        id: wallpaperLoader
        asynchronous: false

        sourceComponent: Scope {
            WallpaperBackground {}
            LockPlacementPreparer {}

            Loader {
                active: SettingsData.blurredWallpaperLayer && CompositorService.isNiri
                asynchronous: false
                sourceComponent: BlurredWallpaperBackground {}
            }
        }
    }

    Loader {
        id: shellCoreLoader
        asynchronous: true
        source: "ShellCore.qml"
        onLoaded: dmsShellLoader.setSource("DMSShell.qml", {
            core: item
        })
    }

    Loader {
        id: dmsShellLoader
        asynchronous: true
    }
}
