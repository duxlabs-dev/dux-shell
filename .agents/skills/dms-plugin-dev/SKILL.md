---
name: dms-plugin-dev
description: >
  Develop plugins for Dux Shell (DMS), a QML-based Linux desktop shell built on
  Quickshell. Supports widget (bar, dock + Control Center), daemon (background service),
  launcher (search + actions), desktop (draggable desktop widgets), dash (dash tab),
  dashCard (dash overview card), and composite (multi-surface) plugins. Covers manifest
  creation, QML component development, startup checks,
  settings UI, data persistence, theme integration, PopoutService usage, IPC runtime
  discovery, and external command execution. Use when the user wants to create, modify,
  or debug a DMS plugin, or asks about the DMS plugin API.
compatibility: Designed for Claude Code (or similar products)
metadata:
  author: Dux Shell
  version: "1.2"
  domain: qml-desktop-development
  framework: Dux Shell
  languages: qml, javascript
allowed-tools: Bash Read Write Edit
---

# Dux Shell Plugin Development

## Overview

DMS plugins extend the desktop shell with bar and dock widgets, background services, launcher
integrations, desktop widgets, and dash tabs and cards. Plugins are QML components discovered from
`~/.config/dms/plugins/`.

**Minimum plugin structure:**

```
~/.config/dms/plugins/YourPlugin/
  plugin.json        # Required: manifest with metadata
  YourComponent.qml  # Required: main QML component
  YourSettings.qml   # Optional: settings UI
  *.js               # Optional: JavaScript utilities
```

**Plugin registry:** Community plugins are available at https://plugins.duxlabs.dev/

**Plugin types:**

| Type        | Purpose                        | Base Component             | Bar/dock pills | CC integration |
|-------------|--------------------------------|----------------------------|----------------|----------------|
| `widget`    | Bar or dock widget + popout    | `PluginComponent`          | Yes            | Yes            |
| `daemon`    | Background service             | `PluginComponent` (no UI)  | No             | Optional       |
| `launcher`  | Searchable items in launcher   | `Item`                     | No             | No             |
| `desktop`   | Draggable desktop widget       | `DesktopPluginComponent`   | No             | No             |
| `dash`      | Tab in the dash popout         | `DashTabComponent`         | No             | No             |
| `dashCard`  | Card in the dash overview grid | `DashCardComponent`        | No             | No             |
| `composite` | Multi-surface plugin           | One component per surface  | Optional       | Optional       |

## Step 1: Determine Plugin Type

Choose the type based on what the plugin does:

- **Shows in the bar or a dock?** - Use `widget`. Displays a pill in DankBar or a dock (same
  component), optionally opens a popout or an attached dock panel, optionally integrates with
  Control Center.
- **Runs in background only?** - Use `daemon`. No visible UI, reacts to events (wallpaper
  changes, notifications, battery level, etc.).
- **Provides searchable/actionable items?** - Use `launcher`. Items appear in the DMS launcher
  with trigger-based filtering (e.g., type `=` for calculator, `:` for emoji).
- **Shows on the desktop background?** - Use `desktop`. Draggable, resizable widget on the
  desktop layer.
- **Full page in the dash?** - Use `dash`. A tab in the dash popout, id `plugin_<pluginId>`.
- **Small tile on the dash overview?** - Use `dashCard`. A resizable card in the overview grid.
- **Needs multiple surfaces?** - Use `composite`. A single plugin that registers any combination
  of the above (e.g., a daemon + bar widget + desktop widget). Each surface gets its own
  QML component file.

## Step 2: Create the Manifest

Create `plugin.json` in your plugin directory. See [plugin-manifest-reference.md](references/plugin-manifest-reference.md) for the full schema.

**Minimal manifest:**

```json
{
    "id": "yourPlugin",
    "name": "Your Plugin Name",
    "description": "Brief description of what your plugin does",
    "version": "1.0.0",
    "author": "Your Name",
    "type": "widget",
    "capabilities": ["your-capability"],
    "component": "./YourWidget.qml"
}
```

**With settings, startup check, and permissions:**

```json
{
    "id": "yourPlugin",
    "name": "Your Plugin Name",
    "description": "Brief description",
    "version": "1.0.0",
    "author": "Your Name",
    "type": "widget",
    "capabilities": ["your-capability"],
    "component": "./YourWidget.qml",
    "icon": "extension",
    "settings": "./Settings.qml",
    "startupCheck": "./StartupCheck.qml",
    "requires_dms": ">=0.1.0",
    "dependencies": ["mytool"],
    "permissions": ["settings_read", "settings_write"]
}
```

**Composite plugin (multi-surface):**

```json
{
    "id": "myComposite",
    "name": "My Composite Plugin",
    "description": "Daemon + widget + desktop from one plugin",
    "version": "1.0.0",
    "author": "Your Name",
    "type": "composite",
    "capabilities": ["daemon", "dankbar-widget", "desktop-widget"],
    "icon": "extension",
    "components": {
        "daemon": "./MyDaemon.qml",
        "widget": "./MyBarWidget.qml",
        "desktop": "./MyDesktopWidget.qml"
    },
    "settings": "./Settings.qml",
    "permissions": ["settings_read", "settings_write"]
}
```

**Standalone dash tab or card:** same single file form, `"type": "dash"` or `"type": "dashCard"`
plus `"component"`. A tab and a card together (or with a bar widget) use `components` with the
keys `dash` and `dashCard`. Both accept an optional `dash` block for labels, card size and
options. See [dash-plugin-guide.md](references/dash-plugin-guide.md).

**Key rules:**
- `id` must be camelCase, matching pattern `^[a-zA-Z][a-zA-Z0-9]*$`
- `version` must be semver (e.g., `1.0.0`)
- Provide either `component` (single-surface) or `components` (multi-surface), not both
- `component` / component paths must start with `./` and end with `.qml`
- `type: "launcher"` (or a `components` object with a `launcher` key) requires a `trigger` field
- `settings_write` permission is **required** if the plugin has a settings component
- `dependencies` replaces the deprecated `requires` field

## Step 3: Create the Main Component

### Widget

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    property var popoutService: null

    horizontalBarPill: Component {
        StyledRect {
            width: label.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            StyledText {
                id: label
                anchors.centerIn: parent
                text: "Hello"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: label.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            StyledText {
                id: label
                anchors.centerIn: parent
                text: "Hi"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                rotation: 90
            }
        }
    }
}
```

See [widget-plugin-guide.md](references/widget-plugin-guide.md) for popouts, CC integration, and advanced features.

### Launcher

```qml
import QtQuick
import qs.Services

Item {
    id: root

    property var pluginService: null
    property string trigger: "#"

    signal itemsChanged()

    function getItems(query) {
        const items = [
            { name: "Item One", icon: "material:star", comment: "Description",
              action: "toast:Hello!", categories: ["MyPlugin"] }
        ]
        if (!query) return items
        const q = query.toLowerCase()
        return items.filter(i => i.name.toLowerCase().includes(q))
    }

    function executeItem(item) {
        const [type, ...rest] = item.action.split(":")
        const data = rest.join(":")
        if (type === "toast") ToastService?.showInfo(data)
        else if (type === "copy") Quickshell.execDetached(["dms", "cl", "copy", data])
    }
}
```

See [launcher-plugin-guide.md](references/launcher-plugin-guide.md) for triggers, icon types, context menus, and image tiles.

### Desktop

```qml
import QtQuick
import qs.Common

Item {
    id: root

    property var pluginService: null
    property string pluginId: ""
    property bool editMode: false
    property real widgetWidth: 200
    property real widgetHeight: 200
    property real minWidth: 150
    property real minHeight: 150

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        opacity: 0.85
        border.color: root.editMode ? Theme.primary : "transparent"
        border.width: root.editMode ? 2 : 0

        Text {
            anchors.centerIn: parent
            text: "Desktop Widget"
            color: Theme.surfaceText
        }
    }
}
```

See [desktop-plugin-guide.md](references/desktop-plugin-guide.md) for sizing, persistence, and edit mode.

### Daemon

```qml
import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    property var popoutService: null

    Connections {
        target: SessionData
        function onSomeSignal() {
            console.log("Event received")
        }
    }
}
```

See [daemon-plugin-guide.md](references/daemon-plugin-guide.md) for event-driven patterns and process execution.

### Dash Tab

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Modules.DankDash

DashTabComponent {
    id: root

    property date now: new Date()

    implicitHeight: DashMetrics.tabMinHeight

    Timer {
        interval: 1000
        repeat: true
        running: root.live
        onTriggered: root.now = new Date()
    }

    StyledText {
        anchors.centerIn: parent
        text: root.now.toLocaleTimeString(I18n.locale())
        color: Theme.surfaceText
    }
}
```

### Dash Card

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

DashCardComponent {
    id: root

    tone: options.tone ?? ""

    StyledText {
        anchors.centerIn: parent
        text: I18n.trFor("myPlugin", "Hello")
        color: root.contentColor
    }
}
```

Gate timers and animations on `live`; the dash content stays alive after the popout closes.
Cards must lay out for every size in their manifest range. Use the card colors (`accentColor`,
`contentColor`, `mutedColor`) so tones work. See [dash-plugin-guide.md](references/dash-plugin-guide.md).

### Composite

For composite plugins, create a separate QML file per surface. Each surface uses the same
base component as the corresponding single-surface type (PluginComponent for widget/daemon,
Item for launcher, etc.). All surfaces share the same `pluginId` and `pluginService`.

```
MyCompositePlugin/
  plugin.json
  MyBarWidget.qml      # PluginComponent (widget surface)
  MyDaemon.qml         # PluginComponent (daemon surface)
  MyDesktopWidget.qml  # Item with desktop widget properties
  Settings.qml         # Shared settings for all surfaces
```

`pluginService.availablePlugins[pluginId].surfaces` lists the surfaces a plugin registered.

## Step 4: Add Startup Check (Optional)

Gate plugin activation on dependency checks by providing a `startupCheck` component. This
runs before the plugin loads and blocks activation if a required tool or condition is missing.

Create a `StartupCheck.qml` (non-visual QtObject):

```qml
import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand("myPlugin.depCheck", ["sh", "-c", "command -v mytool"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            done({
                "title": I18n.tr("mytool is required"),
                "details": I18n.tr("Install 'mytool' and re-enable this plugin.")
            });
        });
    }
}
```

The `done` callback accepts:
- `null` - allow activation
- A string - block with a short error message
- `{ title, details }` - block with a title and expandable details body

A synchronous variant (no `done` parameter, return the result directly) is also supported.

Failed checks show a toast error and store the error in `pluginService.pluginLoadErrors`.

Add to your manifest:
```json
{
    "startupCheck": "./StartupCheck.qml",
    "dependencies": ["mytool"]
}
```

## Step 5: Add Settings (Optional)

Wrap settings in `PluginSettings` with your `pluginId`. All settings auto-save and auto-load.

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "yourPlugin"

    StringSetting {
        settingKey: "apiKey"
        label: "API Key"
        description: "Your API key"
        placeholder: "sk-..."
    }

    ToggleSetting {
        settingKey: "enabled"
        label: "Enable Feature"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "interval"
        label: "Refresh Interval"
        options: [
            { label: "1 min", value: "60" },
            { label: "5 min", value: "300" }
        ]
        defaultValue: "300"
    }
}
```

**Available setting components:** StringSetting, ToggleSetting, SelectionSetting, SliderSetting, ColorSetting, ListSetting, ListSettingWithInput.

See [settings-components-reference.md](references/settings-components-reference.md) for full property lists.

**Important:** Your plugin must declare `"permissions": ["settings_write"]` in plugin.json, or the settings UI will show an error.

## Step 6: Use Data Persistence

Three tiers of persistence:

| API | Persisted | Use case |
|-----|-----------|----------|
| `pluginService.savePluginData(id, key, val)` / `loadPluginData(id, key, default)` | Yes (settings.json) | User preferences, config |
| `pluginService.savePluginState(id, key, val)` / `loadPluginState(id, key, default)` | Yes (separate state file) | Runtime state, history, cache |
| `PluginGlobalVar { varName; defaultValue; value; set() }` | No (runtime only) | Cross-instance shared state |
| `pluginService.getPluginPath(id)` | N/A | Get the plugin's installation directory path |

- `pluginData` is a reactive property on PluginComponent, auto-loaded from settings
- React to settings changes with `Connections { target: pluginService; function onPluginDataChanged(id) { ... } }`
- Global vars sync across all instances (multi-monitor, multiple bar sections)

See [data-persistence-guide.md](references/data-persistence-guide.md) for details and examples.

## Step 7: Theme Integration

Always use `Theme.*` properties from `qs.Common` - never hardcode colors or sizes.

**Essential properties:**
- Colors: `Theme.surfaceContainerHigh`, `Theme.surfaceText`, `Theme.primary`, `Theme.onPrimary`
- Fonts: `Theme.fontSizeSmall` (12), `Theme.fontSizeMedium` (14), `Theme.fontSizeLarge` (16), `Theme.fontSizeXLarge` (20)
- Spacing: `Theme.spacingXS`, `Theme.spacingS`, `Theme.spacingM`, `Theme.spacingL`, `Theme.spacingXL`
- Radius: `Theme.cornerRadius`, `Theme.cornerRadiusSmall`, `Theme.cornerRadiusLarge`
- Icons: `Theme.iconSizeSmall` (16), `Theme.iconSize` (24), `Theme.iconSizeLarge` (32)

**Common widgets from `qs.DCommon.Widgets`:** `StyledText`, `StyledRect`, `DIcon`, `DButton`, `DToggle`, `DTextField`, `DSlider`, `DGridView`, `CachingImage`. The old `Dank*` names in `qs.Widgets` are deprecated.

See [theme-reference.md](references/theme-reference.md) for the complete property list.

## Step 8: Add Popout Content (Widgets Only)

Add a popout that opens when the bar pill is clicked:

```qml
PluginComponent {
    popoutWidth: 400
    popoutHeight: 300

    popoutContent: Component {
        PopoutComponent {
            headerText: "My Plugin"
            detailsText: "Optional subtitle"

            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledText {
                    text: "Content here"
                    color: Theme.surfaceText
                }
            }
        }
    }

    horizontalBarPill: Component { /* ... */ }
    verticalBarPill: Component { /* ... */ }
}
```

**PopoutComponent properties:** `headerText`, `detailsText`, `closePopout()` (auto-injected), `headerHeight` (readonly), `detailsHeight` (readonly).

Calculate available content height: `popoutHeight - headerHeight - detailsHeight - spacing`

## Step 9: Control Center Integration (Widgets Only)

Add your widget to the Control Center grid:

```qml
PluginComponent {
    ccWidgetIcon: "toggle_on"
    ccWidgetPrimaryText: "My Feature"
    ccWidgetSecondaryText: isActive ? "On" : "Off"
    ccWidgetIsActive: isActive

    onCcWidgetToggled: {
        isActive = !isActive
        pluginService?.savePluginData(pluginId, "active", isActive)
    }

    // Optional: expandable detail panel (for CompoundPill)
    ccDetailContent: Component {
        Rectangle {
            implicitHeight: 200
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadius
        }
    }
}
```

**CC sizing:** 25% width = SmallToggleButton (icon only), 50% width = ToggleButton or CompoundPill (if ccDetailContent is defined).

## Step 10: External Commands and Clipboard

**Run commands and capture output:**

```qml
import qs.Common

Proc.runCommand(
    "myPlugin.fetch",
    ["curl", "-s", "https://api.example.com/data"],
    (stdout, exitCode) => {
        if (exitCode === 0) processData(stdout)
    },
    500  // debounce ms
)
```

**Fire-and-forget (clipboard, notifications):**

```qml
import Quickshell

Quickshell.execDetached(["dms", "cl", "copy", textToCopy])
```

**Long-running processes:** Use the `Process` QML component from `Quickshell.Io` with `StdioCollector`.

**Shell commands with pipes:** `["sh", "-c", "ps aux | grep foo"]`

**Do NOT use** `globalThis.clipboard` or browser JavaScript APIs - they don't exist in the QML runtime.

## Translations (Optional)

Ship per-locale files in a `translations/` directory; DMS loads the one matching the active locale and re-reads it on locale changes:

```
MyPlugin/
└── translations/
    ├── es.json
    └── zh_CN.json
```

File names follow DMS locale naming (`es.json`, `pt.json`, `zh_CN.json`); resolution tries the exact tag, then the hyphenated form, then the bare language. No `en.json` - the QML terms are the English strings.

Each file maps the English term to its translation, using the term as its own context bucket:

```json
{
  "Cycle Speed": {
    "Cycle Speed": "Velocidad de ciclo"
  }
}
```

In QML, call `I18n.trFor` with the plugin id as a literal string matching `plugin.json`:

```qml
text: I18n.trFor("myPlugin", "Cycle Speed")
```

Lookup order: plugin file, then the global DMS catalog, then the English term. `ExampleEmojiPlugin` in `quickshell/PLUGINS/` demonstrates the full setup. Registry plugins can apply for central POEditor translation via the registry's CONTRIBUTING guide.

## Step 11: Validate and Test

1. Validate `plugin.json` against the schema at [assets/plugin-schema.json](assets/plugin-schema.json)
2. Run the shell with verbose output: `qs -v -p $CONFIGPATH/quickshell/dms/shell.qml`
3. Open Settings > Plugins > Scan for Plugins
4. Enable your plugin and add it to the DankBar layout, a dock, or the dash (tabs show up on their own; add cards from the dash edit mode)

**Runtime plugin discovery via IPC:**

Plugins can be scanned, rescanned, and reloaded at runtime without restarting the shell:

```bash
dms ipc plugin-scan scan          # Trigger a full rescan of all plugin directories
dms ipc plugin-scan rescan <id>   # Force rescan of a specific plugin
dms ipc plugin-scan reload <id>   # Force reload of a loaded plugin
dms ipc plugin-scan list          # List all known plugins (TSV: id, loaded, type, name)
dms ipc plugin-scan status <id>   # Get status of a specific plugin (TSV: loaded, type, error)
```

Plugin IDs are validated against `^[a-zA-Z0-9_\-:]{1,64}$`.

**Common issues:**
- Plugin not detected: check plugin.json syntax with `jq . plugin.json`
- Widget not showing: ensure it's enabled AND added to a DankBar section
- Settings error: verify `settings_write` permission is declared
- Data not persisting: check pluginService injection and permissions
- Startup check failing: check `pluginService.pluginLoadErrors` or run `dms ipc plugin-scan status <id>`

## Common Mistakes

1. **Missing `settings_write` permission** - Settings UI shows error without it
2. **Missing `property var popoutService: null`** - Must declare for injection to work
3. **Missing vertical bar pill** - Widget disappears when bar is on left/right edge
4. **Hardcoded colors** - Use `Theme.*` properties, not hex values
5. **Using `globalThis.clipboard`** - Does not exist; use `Quickshell.execDetached(["dms", "cl", "copy", text])`
6. **Wrong Theme property names** - `Theme.fontSizeS` does not exist, use `Theme.fontSizeSmall`
7. **Wrong import for Quickshell** - Use `import Quickshell` (not `import QtQuick` for execDetached)
8. **Forgetting `categories` in launcher items** - Items won't display without it
9. **Not handling null pluginService** - Always use optional chaining or null checks
10. **Using `PluginComponent` for launchers** - Launchers use plain `Item`, not `PluginComponent`
11. **Using `requires` instead of `dependencies`** - `requires` is deprecated; use `dependencies`
12. **Providing both `component` and `components`** - Use one or the other, not both
13. **Missing `trigger` on composite with launcher surface** - Still required when `components` has a `launcher` key
14. **Using `"type": "widget"` for a dash tab** - Dash surfaces need `"type": "dash"` / `"dashCard"` or a `components` key
15. **Timers in dash tabs or cards that ignore `live`** - The dash content outlives the popout; gate on `live`
16. **Reading `dash.options` from a bar widget** - `options` only reach dash surfaces; share values through `settings` and `pluginData`
17. **Raw theme colors in a dash card** - Use `accentColor` / `contentColor` / `mutedColor` so the card follows its tone

## Quick Reference: Imports

**Widget / Daemon:**
```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
```

**Launcher:**
```qml
import QtQuick
import qs.Services
```

**Desktop:**
```qml
import QtQuick
import qs.Common
```

**Dash tab / card:**
```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Modules.DankDash          // DashMetrics, DashWidgetGrid
import qs.Modules.DankDash.Overview // Card, for tiles inside a tab
```

**For clipboard/exec:** `import Quickshell`
**For processes:** `import Quickshell.Io`
**For networking:** `import Quickshell.Networking`
**For toast notifications:** access `ToastService` from `qs.Services`

## Quick Reference: File Naming

- **Directory name:** PascalCase (e.g., `MyAwesomePlugin/`)
- **Plugin ID:** camelCase (e.g., `myAwesomePlugin`)
- **QML files:** PascalCase (e.g., `MyWidget.qml`, `Settings.qml`)
- **Component paths in manifest:** relative with `./` prefix (e.g., `"./MyWidget.qml"`)
- **JS utility files:** camelCase (e.g., `utils.js`, `apiAdapter.js`)

## Reference Files

Load these on demand for detailed API documentation:

- [plugin-manifest-reference.md](references/plugin-manifest-reference.md) - Complete plugin.json field reference and JSON schema
- [widget-plugin-guide.md](references/widget-plugin-guide.md) - PluginComponent, bar and dock pills, attached dock panels, popouts, click actions, CC integration
- [dash-plugin-guide.md](references/dash-plugin-guide.md) - DashTabComponent, DashCardComponent, DashWidgetGrid, dash options, card sizing
- [launcher-plugin-guide.md](references/launcher-plugin-guide.md) - getItems/executeItem, triggers, icon types, context menus, tile view
- [desktop-plugin-guide.md](references/desktop-plugin-guide.md) - DesktopPluginComponent, sizing, edit mode, position persistence
- [daemon-plugin-guide.md](references/daemon-plugin-guide.md) - Event-driven background services, process execution
- [settings-components-reference.md](references/settings-components-reference.md) - All 7 setting components with complete property lists
- [theme-reference.md](references/theme-reference.md) - Theme colors, spacing, fonts, radii, common patterns
- [data-persistence-guide.md](references/data-persistence-guide.md) - pluginData, state API, global variables
- [popout-service-reference.md](references/popout-service-reference.md) - PopoutService API for controlling shell popouts and modals
- [advanced-patterns.md](references/advanced-patterns.md) - Variants, JS utilities, qmldir, IPC, multi-file plugins
