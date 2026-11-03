# Composite Example

A single plugin that provides **all three surfaces at once** by combining three of
the standalone example plugins:

| Surface | Source example | File |
|---------|----------------|------|
| `daemon` | WallpaperWatcherDaemon | `CompositeDaemon.qml` |
| `widget` | Emoji Cycler (bar widget + popout) | `CompositeBarWidget.qml` |
| `desktop` | Desktop Clock | `CompositeDesktopWidget.qml` |

It demonstrates the `components` manifest map, where each surface points at its own
QML file:

```json
"type": "composite",
"components": {
    "daemon":  "./CompositeDaemon.qml",
    "widget":  "./CompositeBarWidget.qml",
    "desktop": "./CompositeDesktopWidget.qml"
}
```

All surfaces share one settings UI (`CompositeSettings.qml`) and one plugin-settings
namespace (`exampleComposite`), so `pluginData` is the same for every surface.

## Surfaces

- **Daemon** — watches `SessionData.wallpaperPath` and runs a user-configured script
  on change. Also registers an `IpcHandler` (`target: "compositeExample"`) exposing a
  `runHook` call, so you can trigger the hook over IPC.
- **Bar widget** — cycles emojis in the bar; click the pill for an emoji picker popout
  that copies to the clipboard.
- **Desktop widget** — an analog/digital clock you can drag and resize on the desktop.

## Usage

1. Copy this directory into `$CONFIGPATH/dms/plugins/`.
2. Settings → Plugins → **Scan for Plugins**, then enable **Composite Example**.
   (Composite plugins respect the enable toggle — unlike a pure `desktop` plugin they
   do not auto-load, because they also carry a daemon.)
3. Add the bar widget via Settings → Appearance → DankBar Layout.
4. Place the desktop clock via Settings → Desktop Widgets.

## Notes

- The daemon surface is instantiated once and lives for as long as the plugin is
  enabled. The bar and desktop surfaces are instantiated per bar/placement per screen.
- Cross-surface runtime state (not needed here) is best shared via
  `PluginService.getGlobalVar` / `setGlobalVar` or the daemon instance, since each
  surface is a separate object.
- `requires_dms` is `>=1.5.0` because the `components` multi-surface manifest is only
  understood by DMS 1.5.0 and later.
