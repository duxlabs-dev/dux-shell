# Plugin System

Extend DMS with dynamically loaded QML components: bar and dock widgets, Control Center tiles, dash tabs and overview cards, desktop widgets, launcher providers and background daemons.

## Plugin Registry

Browse and discover community plugins at **https://plugins.duxlabs.dev/**

## Overview

Plugins are discovered from `~/.config/dms/plugins/` and managed by PluginService. One plugin can provide a single surface or several (see [Composite Plugins](#composite-plugins)).

## Architecture

### Core Components

1. **PluginService** (`Services/PluginService.qml`)
   - Singleton service managing plugin lifecycle
   - Discovers plugins from `$CONFIGPATH/dms/plugins/`
   - Handles loading, unloading, and state management
   - Provides data persistence for plugin settings

2. **Plugins hub** (`Modules/Settings/PluginsHubHeader.qml`, `Modules/Settings/PluginsManageTab.qml`)
   - UI for managing available plugins and registries

3. **Plugin settings page** (`Modules/Settings/PluginSettingsPage.qml`)
   - Loads a plugin's settings component through `PluginSettingsHost`

4. **Bar and dock integration** (`Modules/SurfaceWidgets/SurfaceWidgetFactory.qml`, `SurfaceWidgetHost.qml`)
   - Renders plugin widgets in bars and docks with the same component
   - Merges plugin components with built-in widgets
   - Supports every bar and dock edge

5. **Dash integration** (`Modules/DDash/DashRegistry.qml`)
   - Lists built-in and plugin tabs and overview cards
   - Hosts plugin tabs in `DashTabHost.qml` and cards in `Overview/DashCardSlot.qml`

Many widgets are implemented in the shared [dux-qml-common](https://github.com/duxlabs-dev/dux-qml-common) library and re-exported by DMS. Plugins should keep importing `qs.Common`, `qs.Services`, `qs.Widgets`, and `qs.Modules.Plugins` — these remain the supported plugin API and are unaffected by where a widget is implemented.

## Plugin Structure

Each plugin must be a directory in `$CONFIGPATH/dms/plugins/` containing:

```
$CONFIGPATH/dms/plugins/YourPlugin/
├── plugin.json          # Required: Plugin manifest
├── YourWidget.qml       # Required: Widget component
├── YourSettings.qml     # Optional: Settings UI
├── *.js                 # Optional: JavaScript utilities
└── translations/        # Optional: per-locale translation files (see Translations)
```

### Plugin Manifest (plugin.json)

The manifest file defines plugin metadata and configuration.

**JSON Schema:** See `plugin-schema.json` for the complete specification and validation schema.

```json
{
    "id": "yourPlugin",
    "name": "Your Plugin Name",
    "description": "Brief description of what your plugin does",
    "version": "1.0.0",
    "author": "Your Name",
    "type": "widget",
    "capabilities": ["thing-my-plugin-does"],
    "component": "./YourWidget.qml",
    "icon": "material_icon_name",
    "settings": "./YourSettings.qml",
    "requires_dms": ">=0.1.0",
    "requires": ["some-system-tool"],
    "permissions": [
        "settings_read",
        "settings_write"
    ]
}
```

**Required Fields:**
- `id`: Unique plugin identifier (camelCase, no spaces)
- `name`: Human-readable plugin name
- `description`: Short description of plugin functionality (displayed in UI)
- `version`: Semantic version string (e.g., "1.0.0")
- `author`: Plugin creator name or email
- `type`: Plugin type - "widget", "daemon", "launcher", "desktop", "dash", "dashCard", or "composite" (with `components`)
- `capabilities`: Array of plugin capabilities  (e.g., ["dankbar-widget"], ["control-center"], ["monitoring"])
- `component`: Relative path to main QML component file, or `components` for a multi-surface plugin

**Required for Launcher Type:**
- `trigger`: Trigger string for launcher activation (e.g., "=", "#", "!")

**Optional Fields:**
- `icon`: Material Design icon name (displayed in UI)
- `settings`: Path to settings component (enables settings UI)
- `requires_dms`: Minimum DMS version requirement (e.g., ">=0.1.18", ">0.1.0")
- `requires`: Array of required system tools/dependencies (e.g., ["curl", "jq"])
- `permissions`: Required DMS permissions (e.g., ["settings_read", "settings_write"])

**Permissions:**

The plugin system enforces permissions when settings are accessed:
- `settings_read`: Required to read plugin settings (currently not enforced)
- `settings_write`: **Required** to use PluginSettings component and save settings

If your plugin includes a settings component but doesn't declare `settings_write` permission, users will see an error message instead of the settings UI.

### Widget Component

The main widget component uses the **PluginComponent** wrapper which provides automatic property injection and bar integration:

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    // Define horizontal bar pill, for top and bottom DankBar positions (optional)
    horizontalBarPill: Component {
        StyledRect {
            width: content.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.chipSurface

            StyledText {
                id: content
                anchors.centerIn: parent
                text: "Hello World"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    // Define vertical bar pill, for left and right DankBar positions (optional)
    verticalBarPill: Component {
        // Same as horizontal but optimized for vertical layout
    }

    // Define popout content, opens when clicking the bar pill (optional)
    popoutContent: Component {
        PopoutComponent {
            headerText: "My Plugin"
            detailsText: "Optional description text goes here"

            // Your popout content goes here
            Column {
                width: parent.width
                spacing: Theme.spacingM

                StyledText {
                    text: "Popout Content"
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.surfaceText
                }
            }
        }
    }

    // Popout dimensions (required if popoutContent is set)
    popoutWidth: 400
    popoutHeight: 300
}
```

**PluginComponent Properties (automatically injected):**
- `axis`: Bar axis information (horizontal/vertical)
- `section`: Bar section ("left", "center", "right")
- `parentScreen`: Screen reference for multi-monitor support
- `widgetThickness`: Recommended widget size perpendicular to bar
- `barThickness`: Bar thickness parallel to edge

**Component Options:**
- `horizontalBarPill`: Component shown in horizontal bars
- `verticalBarPill`: Component shown in vertical bars
- `popoutContent`: Optional popout window content
- `popoutWidth`: Popout window width
- `popoutHeight`: Popout window height
- `pillClickAction`: Custom click handler function (overrides popout)
- `pillRightClickAction`: Custom right click handler function

### Control Center Integration

Add your plugin to Control Center by defining CC properties:

```qml
PluginComponent {
    ccWidgetIcon: "toggle_on"
    ccWidgetPrimaryText: "My Feature"
    ccWidgetSecondaryText: isEnabled ? "Active" : "Inactive"
    ccWidgetIsActive: isEnabled

    onCcWidgetToggled: {
        isEnabled = !isEnabled
        if (pluginService) {
            pluginService.savePluginData("myPlugin", "isEnabled", isEnabled)
        }
    }

    ccDetailContent: Component {
        Rectangle {
            implicitHeight: 200
            color: Theme.foregroundColor(Theme.cardSurface)
            radius: Theme.cornerRadius
            // Your detail UI here
        }
    }

    horizontalBarPill: Component { /* ... */ }
}
```

**CC Properties:**
- `ccWidgetIcon`: Material icon name
- `ccWidgetPrimaryText`: Main label
- `ccWidgetSecondaryText`: Subtitle/status
- `ccWidgetIsActive`: Active state styling
- `ccWidgetIsToggle`: Whether the icon toggles state; set false for action-only tiles
- `ccExpandedContent`: Optional inline controls for larger tiles
- `ccExpandedMinimumHeight`: Minimum height for inline controls, default `Theme.listItemHeight`
- `ccFooterContent`: Accepted but ignored; the footer strip is gone and users shrink tiles to half-height pills instead
- `ccDetailContent`: Optional detail page

**Signals:**
- `ccWidgetToggled()`: Fired when icon clicked
- `ccWidgetExpanded()`: Fired when opening the detail page

**Widget sizing:**

The grid uses square cells, with eight columns by default. A standard strip is
4×1; a 2×2 tile is square. Users resize tiles and the panel in edit mode. Panel
width and tile height are limited by the current screen, independently of each
other. Saved spans are retained when displaying a tile on a smaller screen.
The standard tile adapts its icon and labels automatically. Larger tiles can load
`ccExpandedContent` below the header when enough space is available.

Use `CcTileContent` from `qs.Modules.ControlCenter.Widgets` for inline content.
Its `tile` is supplied by the host. It exposes `columns`, `rows`, `live`,
`contentColor`, and `subtitleColor`; `width` and `height` are the available space.
Content is disabled in edit mode and destroyed when the Control Center closes or
shrinks below the minimum size. Keep persistent state in the plugin instance.

```qml
ccExpandedContent: Component {
    CcTileContent {
        DButton {
            maximumWidth: parent.width
            text: I18n.trFor("myPlugin", "Run")
            onClicked: root.runAction()
        }
    }
}
```

Existing plugins need no changes to use the standard responsive tile. Custom
inline controls must fit their allocated space and gate ongoing work on `live`.

**Custom Click Actions:**

Override default popout with `pillClickAction` and `pillRightClickAction`:

```qml
pillClickAction: () => {
    Process.exec("bash", ["-c", "notify-send 'Clicked!'"])
}

// Or with position params: (x, y, width, section, screen)
pillClickAction: (x, y, width, section, screen) => {
    popoutService?.toggleControlCenter(x, y, width, section, screen)
}

pillRightClickAction: () => {
    Process.exec("bash", ["-c", "notify-send 'Right clicked!'"])
}

pillRightClickAction: (x, y, width, section, screen) => {
    popoutService?.toggleControlCenter(x, y, width, section, screen)
}
```

The PluginComponent automatically handles:
- Bar orientation detection
- Click handlers for popouts
- Proper positioning and anchoring
- Theme integration

### PopoutComponent

PopoutComponent provides a consistent header/content layout for plugin popouts:

```qml
import qs.Modules.Plugins
import qs.DCommon.Widgets

PopoutComponent {
    headerText: "Header Title"        // Main header text (bold, large)
    detailsText: "Description text"   // Optional description (smaller, gray)

    // Access to exposed properties for dynamic sizing
    readonly property int headerHeight    // Height of header area
    readonly property int detailsHeight   // Height of description area

    // Your content here - use parent.width for full width
    // Calculate available height: root.popoutHeight - headerHeight - detailsHeight - spacing
    DGridView {
        width: parent.width
        height: parent.height
        // ...
    }
}
```

**PopoutComponent Properties:**
- `headerText`: Main header text (optional, hidden if empty)
- `detailsText`: Description text below header (optional, hidden if empty)
- `closePopout`: Function to close popout (auto-injected by PluginPopout)
- `headerHeight`: Readonly height of header (0 if not visible)
- `detailsHeight`: Readonly height of description (0 if not visible)

The component automatically handles spacing and layout. Content children are rendered below the description with proper padding.

### Settings Component

Optional settings UI loaded inline in the PluginsTab accordion interface. Use the simplified settings API with auto-storage components:

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "yourPlugin"

    StringSetting {
        settingKey: "apiKey"
        label: "API Key"
        description: "Your API key for accessing the service"
        placeholder: "Enter API key..."
    }

    ToggleSetting {
        settingKey: "notifications"
        label: "Enable Notifications"
        description: "Show desktop notifications for updates"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "updateInterval"
        label: "Update Interval"
        description: "How often to refresh data"
        options: [
            {label: "1 minute", value: "60"},
            {label: "5 minutes", value: "300"},
            {label: "15 minutes", value: "900"}
        ]
        defaultValue: "300"
    }

    ListSetting {
        id: itemList
        settingKey: "items"
        label: "Saved Items"
        description: "List of configured items"
        delegate: Component {
            StyledRect {
                width: parent.width
                height: 40
                radius: Theme.cornerRadius
                color: Theme.chipSurface

                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: Theme.surfaceText
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    width: 60
                    height: 28
                    color: removeArea.containsMouse ? Theme.errorHover : Theme.error
                    radius: Theme.cornerRadius

                    StyledText {
                        anchors.centerIn: parent
                        text: "Remove"
                        color: Theme.errorText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: removeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: itemList.removeItem(index)
                    }
                }
            }
        }
    }
}
```

**Available Setting Components:**

All settings automatically save on change and load on component creation.

**How Default Values Work:**

Each setting component has a `defaultValue` property that is used when no saved value exists. Define sensible defaults in your settings UI:

```qml
StringSetting {
    settingKey: "apiKey"
    defaultValue: ""  // Empty string if no key saved
}

ToggleSetting {
    settingKey: "enabled"
    defaultValue: true  // Enabled by default
}

ListSettingWithInput {
    settingKey: "locations"
    defaultValue: []  // Empty array if no locations saved
}
```

1. **PluginSettings** - Root wrapper for all plugin settings
   - `pluginId`: Your plugin ID (required)
   - Auto-handles storage and provides saveValue/loadValue to children
   - Place all other setting components inside this wrapper

2. **StringSetting** - Text input field
   - `settingKey`: Storage key (required)
   - `label`: Display label (required)
   - `description`: Help text (optional)
   - `placeholder`: Input placeholder (optional)
   - `defaultValue`: Default value (optional, default: `""`)
   - Layout: Vertical stack (label, description, input field)

3. **ToggleSetting** - Boolean toggle switch
   - `settingKey`: Storage key (required)
   - `label`: Display label (required)
   - `description`: Help text (optional)
   - `defaultValue`: Default boolean (optional, default: `false`)
   - Layout: Horizontal (label/description left, toggle right)

4. **SelectionSetting** - Dropdown menu
   - `settingKey`: Storage key (required)
   - `label`: Display label (required)
   - `description`: Help text (optional)
   - `options`: Array of `{label, value}` objects or simple strings (required)
   - `defaultValue`: Default value (optional, default: `""`)
   - Layout: Horizontal (label/description left, dropdown right)
   - Stores the `value` field, displays the `label` field

5. **ListSetting** - Manage list of items (manual add/remove)
   - `settingKey`: Storage key (required)
   - `label`: Display label (required)
   - `description`: Help text (optional)
   - `defaultValue`: Default array (optional, default: `[]`)
   - `delegate`: Custom item delegate Component (optional)
   - `addItem(item)`: Add item to list
   - `removeItem(index)`: Remove item from list
   - Use when you need custom UI for adding items

6. **ListSettingWithInput** - Complete list management with built-in form
   - `settingKey`: Storage key (required)
   - `label`: Display label (required)
   - `description`: Help text (optional)
   - `defaultValue`: Default array (optional, default: `[]`)
   - `fields`: Array of field definitions (required)
     - `id`: Field ID in saved object (required)
     - `label`: Column header text (required)
     - `placeholder`: Input placeholder (optional)
     - `width`: Column width in pixels (optional, default 200)
     - `required`: Must have value to add (optional, default false)
     - `default`: Default value if empty (optional)
   - Automatically generates:
     - Column headers from field labels
     - Input fields with placeholders
     - Add button with validation
     - List display showing all field values
     - Remove buttons for each item
   - Best for collecting structured data (servers, locations, etc.)

**Complete Settings Example:**

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "myPlugin"

    StyledText {
        width: parent.width
        text: "General Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StringSetting {
        settingKey: "apiKey"
        label: "API Key"
        description: "Your service API key"
        placeholder: "sk-..."
        defaultValue: ""
    }

    ToggleSetting {
        settingKey: "enabled"
        label: "Enable Feature"
        description: "Turn this feature on or off"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "theme"
        label: "Theme"
        description: "Choose your preferred theme"
        options: [
            {label: "Dark", value: "dark"},
            {label: "Light", value: "light"},
            {label: "Auto", value: "auto"}
        ]
        defaultValue: "dark"
    }

    ListSettingWithInput {
        settingKey: "locations"
        label: "Locations"
        description: "Track multiple locations"
        defaultValue: []
        fields: [
            {id: "name", label: "Name", placeholder: "Home", width: 150, required: true},
            {id: "timezone", label: "Timezone", placeholder: "America/New_York", width: 200, required: true}
        ]
    }
}
```

**Key Benefits:**
- Zero boilerplate - just define your settings
- Automatic persistence to `settings.json`
- Clean, consistent UI across all plugins
- No manual `pluginService` calls needed
- Proper layout and spacing handled automatically

## Translations

Plugins ship their own translations. Drop a `translations/` directory next to `plugin.json`, wrap your strings in `I18n.trFor()`, done — nothing needs to change in the DMS repo, and users get your translations just by installing the plugin.

```
YourPlugin/
├── plugin.json
├── YourWidget.qml
└── translations/
    ├── es.json
    ├── fr.json
    └── zh_CN.json
```

DMS loads the file matching the user's locale when it discovers the plugin, and re-reads it whenever the locale changes. No restart, no registration call.

### Marking Strings

Wrap every user-facing string in `I18n.trFor()`, with your plugin id as the first argument:

```qml
import qs.Common

StyledText {
    text: I18n.trFor("yourPlugin", "Cycle Speed")
}
```

Placeholders work the same as anywhere else in DMS:

```qml
ToastService.showInfo(I18n.trFor("yourPlugin", "Copied %1 to clipboard").arg(item))
```

Lookup order is: your plugin's translation file → the global DMS catalog → the English term itself. Strings DMS already translates ("Settings", "Close", etc.) resolve from the global catalog for free, and anything untranslated renders as your English text instead of breaking.

Two rules:

- The plugin id must be a **literal string** that exactly matches `id` in your `plugin.json`. The string extraction tooling for central translation reads call sites — a variable there means your strings never get extracted.
- `I18n.trFor` doesn't exist on DMS versions without plugin translation support, and calling a missing function in QML is a TypeError, not a silent no-op. Bump `requires_dms` when you adopt it.

Plain `I18n.tr()` still works inside plugins, but it only checks the global catalog — it will never see your `translations/` files.

### Translation Files

One JSON file per locale. Top-level keys are context buckets; unless you have a reason to do otherwise, use the English term as its own bucket:

```json
{
    "Cycle Speed": {
        "Cycle Speed": "Velocidad de ciclo"
    },
    "Copied %1 to clipboard": {
        "Copied %1 to clipboard": "%1 copiado al portapapeles"
    }
}
```

There is no `en.json` — the strings in your QML are the English source. Translate what you want, skip what you don't; missing terms fall through the lookup order above.

File names match what DMS ships in its own catalog (`es.json`, `pt.json`, `zh_CN.json`, ...), but you're not limited to that list — resolution is driven by the user's locale. For a user on `zh_CN`, DMS tries `zh_CN.json`, then `zh-CN.json`, then `zh.json`, and uses the first one that exists.

### Testing

1. Reload after editing a file: `dms ipc call plugins reload yourPlugin`
2. Switch languages in Settings → Locale — plugin strings retranslate live along with the rest of the shell
3. Broken JSON logs a `bad plugin translations` warning in shell output and falls back to English

`ExampleEmojiPlugin` is a complete working example — `trFor` calls in the widget and settings, plus `es.json` and `fr.json`.

### Central Translation via POEditor

Plugins in the [plugin registry](https://github.com/duxlabs-dev/dux-plugin-registry) can apply to join the DankPlugins POEditor project, translated by the same community that translates DMS itself. Approved plugins get every `I18n.trFor()` string uploaded under a `<pluginId>:` context, so your "Auto" and another plugin's "Auto" are separate terms with separate translations. Finished translations come back to the plugin repo as PRs to `translations/`, in the file format above. See the registry's CONTRIBUTING guide for the application process.

Strings you wrap in plain `I18n.tr()` are not uploaded. They resolve from the shell catalog only, which is the right choice for terms DMS already has ("Cancel", "Settings"). A term DMS does not have stays English, and the sync warns about it.

## PluginService API

### Properties

```qml
PluginService.pluginDirectory: string
// Path to plugins directory ($CONFIGPATH/dms/plugins)

PluginService.availablePlugins: object
// Map of all discovered plugins {pluginId: pluginInfo}

PluginService.loadedPlugins: object
// Map of currently loaded plugins {pluginId: pluginInfo}

PluginService.pluginWidgetComponents: object
// Map of loaded widget components {pluginId: Component}
```

### Functions

```qml
// Plugin Management
PluginService.loadPlugin(pluginId: string): bool
PluginService.unloadPlugin(pluginId: string): bool
PluginService.reloadPlugin(pluginId: string): bool
PluginService.enablePlugin(pluginId: string, onResult?: (ok: bool, error: string) => void): bool
PluginService.disablePlugin(pluginId: string): bool

// Plugin Discovery
PluginService.scanPlugins(): void
PluginService.getAvailablePlugins(): array
PluginService.getLoadedPlugins(): array
PluginService.isPluginLoaded(pluginId: string): bool
PluginService.getWidgetComponents(): object

// Launcher Actions - see the Launcher Actions section
PluginService.registerActions(pluginId: string, actions: array): {registered: int, errors: array}
PluginService.unregisterActions(pluginId: string): void

// Data Persistence
PluginService.savePluginData(pluginId: string, key: string, value: any): bool
PluginService.loadPluginData(pluginId: string, key: string, defaultValue: any): any

// Global Variables - Shared state across all plugin instances
PluginService.getGlobalVar(pluginId: string, varName: string, defaultValue: any): any
PluginService.setGlobalVar(pluginId: string, varName: string, value: any): void
```

### Signals

```qml
PluginService.pluginLoaded(pluginId: string)
PluginService.pluginUnloaded(pluginId: string)
PluginService.pluginLoadFailed(pluginId: string, error: string)
PluginService.globalVarChanged(pluginId: string, varName: string)
```

## Startup Check (Dependency Gate)

A plugin may optionally gate activation behind a dependency check. Point the manifest's `startupCheck` field at a small, **non-visual** component (a `QtObject` - it must not render in the graphics scene):

```json
{
    "startupCheck": "./StartupCheck.qml",
    "dependencies": ["boregard"]
}
```

The component exposes a `check` function that runs before the plugin loads, both on manual enable and on auto-load at startup. Call `done(null)` to allow activation, or `done(error)` to block it. The error can be a short string (title only) or an object with an expandable `details` body for long-form instructions:

```qml
import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand("myPlugin.depCheck", ["which", "boregard"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null)
                return
            }
            done({
                title: I18n.tr("boregard is required"),
                details: I18n.tr("Install it from https://duxlabs.dev, then re-enable this plugin.")
            })
        })
    }
}
```

A synchronous variant is supported too - declare `check()` with no argument and return the result directly. When the check fails the enable toggle reverts and the error is shown as a toast (the `details` are expandable, and any `http(s)` URL in them becomes a clickable link). A check that fails to load, has no `check` function, or throws blocks activation the same way, with its error as the message. The check also runs again on reload. Plugins without a `startupCheck` are unaffected. See `ExampleStartupCheck` for a complete plugin; the last error per plugin is available at `PluginService.pluginLoadErrors[pluginId]`.

## Plugin Global Variables

Plugins can share state across multiple instances using global variables. This is useful when you have the same widget displayed on multiple monitors or multiple instances of the same widget on different bars.

### Why Use Global Variables?

Unlike regular properties which are scoped to each component instance, global variables are synchronized across all instances of your plugin. This enables:

- **Multi-monitor consistency**: Same data displayed across all monitors
- **Multi-instance widgets**: Multiple instances of the same widget sharing state
- **Cross-component communication**: Share data between widget and settings components

### Using PluginGlobalVar

The `PluginGlobalVar` helper component provides reactive global variable access:

```qml
import QtQuick
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    PluginGlobalVar {
        id: globalCounter
        varName: "counter"
        defaultValue: 0
    }

    horizontalBarPill: Component {
        StyledRect {
            width: content.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.chipSurface

            StyledText {
                id: content
                anchors.centerIn: parent
                text: "Count: " + globalCounter.value
                color: Theme.surfaceText
            }

            MouseArea {
                anchors.fill: parent
                onClicked: globalCounter.set(globalCounter.value + 1)
            }
        }
    }
}
```

**PluginGlobalVar Properties:**
- `varName` (required): Name of the global variable
- `defaultValue` (optional): Default value if not set
- `value` (readonly): Current value of the global variable

**PluginGlobalVar Methods:**
- `set(newValue)`: Update the global variable (triggers reactivity across all instances)

### Using PluginService API Directly

For more control, use the PluginService API directly:

```qml
import QtQuick
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    property int counter: PluginService.getGlobalVar("myPlugin", "counter", 0)

    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId === "myPlugin" && varName === "counter") {
                counter = PluginService.getGlobalVar("myPlugin", "counter", 0)
            }
        }
    }

    horizontalBarPill: Component {
        StyledRect {
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    const current = PluginService.getGlobalVar("myPlugin", "counter", 0)
                    PluginService.setGlobalVar("myPlugin", "counter", current + 1)
                }
            }
        }
    }
}
```

### Global Variables vs Settings

**Global Variables** (`getGlobalVar`/`setGlobalVar`):
- Runtime state only (not persisted to disk)
- Synchronized across all plugin instances
- Changes trigger `globalVarChanged` signal for reactivity
- Use for: counters, current selection, temporary UI state

**Settings** (`savePluginData`/`loadPluginData`):
- Persisted to `settings.json` across sessions
- Loaded once per plugin instance
- Use for: user preferences, API keys, configuration

### Important Notes

1. **Reactivity**: Global variables are reactive - all instances update when a value changes
2. **Namespacing**: Variables are namespaced by plugin ID to avoid conflicts
3. **Type Safety**: Values can be any QML/JavaScript type (numbers, strings, objects, arrays)
4. **Not Persistent**: Global variables are cleared when the shell restarts (use settings for persistence)
5. **Performance**: Efficient for frequent updates - changes only trigger updates for the specific variable

## Creating a Plugin

### Step 1: Create Plugin Directory

```bash
mkdir -p $CONFIGPATH/dms/plugins/MyPlugin
cd $CONFIGPATH/dms/plugins/MyPlugin
```

### Step 2: Create Manifest

Create `plugin.json`:

```json
{
    "id": "myPlugin",
    "name": "My Plugin",
    "description": "A sample plugin",
    "version": "1.0.0",
    "author": "Your Name",
    "type": "widget",
    "capabilities": ["my-functionality"],
    "component": "./MyWidget.qml",
    "icon": "extension",
    "settings": "./MySettings.qml",
    "requires_dms": ">=0.1.0",
    "permissions": ["settings_read", "settings_write"]
}
```

### Step 3: Create Widget Component

Create `MyWidget.qml`:

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    horizontalBarPill: Component {
        StyledRect {
            width: textItem.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.chipSurface

            StyledText {
                id: textItem
                anchors.centerIn: parent
                text: "Hello World"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: textItem.implicitWidth + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.chipSurface

            StyledText {
                id: textItem
                anchors.centerIn: parent
                text: "Hello"
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                rotation: 90
            }
        }
    }
}
```

**Note:** Use `PluginComponent` wrapper for automatic property injection and bar integration. Define separate components for horizontal and vertical orientations.

### Step 4: Create Settings Component (Optional)

Create `MySettings.qml`:

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "myPlugin"

    StyledText {
        width: parent.width
        text: "Configure your plugin settings"
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "text"
        label: "Display Text"
        description: "Text shown in the bar widget"
        placeholder: "Hello World"
        defaultValue: "Hello World"
    }

    ToggleSetting {
        settingKey: "showIcon"
        label: "Show Icon"
        description: "Display an icon next to the text"
        defaultValue: true
    }
}
```

### Step 5: Enable Plugin

1. Run the shell: `qs -p $CONFIGPATH/quickshell/dms/shell.qml`
2. Open Settings (Ctrl+,)
3. Navigate to Plugins tab
4. Click "Scan for Plugins"
5. Enable your plugin with the toggle switch
6. Add the plugin to your DankBar configuration

## Adding Plugin to DankBar

After enabling a plugin, add it to the bar:

1. Open Settings → Appearance → DankBar Layout
2. Add a new widget entry with your plugin ID
3. Choose section (left, center, right)
4. Save and reload

Or edit `$CONFIGPATH/quickshell/dms/config.json`:

```json
{
    "dankBarLeftWidgets": [
        {"widgetId": "myPlugin", "enabled": true}
    ]
}
```

## Best Practices

1. **Use Existing Widgets**: Leverage `qs.DCommon.Widgets` components (DIcon, DToggle, etc.) for consistency
2. **Follow Theme**: Use `Theme` singleton for colors, spacing, and fonts
3. **Data Persistence**: Use PluginService data APIs instead of manual file operations
4. **Error Handling**: Gracefully handle missing dependencies and invalid data
5. **Performance**: Keep widgets lightweight, avoid long operations that block the UI loop
6. **Responsive Design**: Adapt to `compactMode` and different screen sizes
7. **Documentation**: Include README.md explaining plugin usage
8. **Versioning**: Use semantic versioning for updates
9. **Dependencies**: Document external library requirements

## Clipboard Access

Plugins that need to copy text to the clipboard should use the built-in `dms cl copy` command through Quickshell's `execDetached` function.

### Correct Method

Import Quickshell and use `execDetached` with `dms cl copy`:

```qml
import QtQuick
import Quickshell

Item {
    function copyToClipboard(text) {
        Quickshell.execDetached(["dms", "cl", "copy", text])
    }
}
```

### Example Usage

From the ExampleEmojiPlugin (EmojiWidget.qml):

```qml
MouseArea {
    onClicked: {
        Quickshell.execDetached(["dms", "cl", "copy", modelData])
        ToastService.showInfo("Copied " + modelData + " to clipboard")
        popoutColumn.closePopout()
    }
}
```

### Important Notes

1. **Do NOT** use `globalThis.clipboard` or similar JavaScript APIs - they don't exist in the QML runtime
2. **Always** import `Quickshell` at the top of your QML file
3. Consider showing a toast notification to confirm the copy action to users

### Dependencies

This method uses the built-in DMS clipboard functionality which has native Wayland support.

## Running External Commands

Plugins that need to execute external commands and capture their output should use the `Proc` singleton, which provides debounced command execution with automatic cleanup.

### Correct Method

Import the `Proc` singleton from `qs.Common` and use `runCommand`:

```qml
import QtQuick
import qs.Common

Item {
    function fetchData() {
        Proc.runCommand(
            "myPlugin.fetchData",
            ["curl", "-s", "https://api.example.com/data"],
            (stdout, exitCode) => {
                if (exitCode === 0) {
                    console.log("Success:", stdout)
                    processData(stdout)
                } else {
                    console.error("Command failed with exit code:", exitCode)
                }
            },
            100
        )
    }
}
```

### Function Signature

```qml
Proc.runCommand(id, command, callback, debounceMs)
```

**Parameters:**
- `id` (string): Unique identifier for this command. Used for debouncing - multiple calls with the same ID within the debounce window will only execute the last one
- `command` (array): Command and arguments as an array (e.g., `["sh", "-c", "echo hello"]`)
- `callback` (function): Callback function receiving `(stdout, exitCode)` when the command completes
  - `stdout` (string): Captured standard output from the command
  - `exitCode` (number): Exit code of the process (0 typically means success)
- `debounceMs` (number, optional): Debounce delay in milliseconds. Defaults to 50ms if not specified

### Key Features

1. **Automatic Cleanup**: Process objects are automatically destroyed after completion
2. **Debouncing**: Rapid successive calls with the same ID are debounced, only executing the last one
3. **Output Capture**: Automatically captures stdout for processing
4. **Error Handling**: Exit codes are passed to the callback for error detection

### Example Usage

#### Simple Command Execution

```qml
import QtQuick
import qs.Common

Item {
    function checkNetwork() {
        Proc.runCommand(
            "myPlugin.ping",
            ["ping", "-c", "1", "8.8.8.8"],
            (output, exitCode) => {
                if (exitCode === 0) {
                    console.log("Network is up")
                } else {
                    console.log("Network is down")
                }
            }
        )
    }
}
```

#### Parsing Command Output

```qml
import QtQuick
import qs.Common

Item {
    property var diskUsage: ({})

    function updateDiskUsage() {
        Proc.runCommand(
            "myPlugin.df",
            ["df", "-h", "/home"],
            (output, exitCode) => {
                if (exitCode === 0) {
                    const lines = output.trim().split("\n")
                    if (lines.length > 1) {
                        const parts = lines[1].split(/\s+/)
                        diskUsage = {
                            total: parts[1],
                            used: parts[2],
                            available: parts[3],
                            percent: parts[4]
                        }
                    }
                }
            }
        )
    }
}
```

#### Shell Commands with Pipes

```qml
import QtQuick
import qs.Common

Item {
    function getTopProcess() {
        Proc.runCommand(
            "myPlugin.topProcess",
            ["sh", "-c", "ps aux | sort -nrk 3,3 | head -n 1"],
            (output, exitCode) => {
                if (exitCode === 0) {
                    console.log("Top process:", output)
                }
            }
        )
    }
}
```

#### Debouncing Rapid Updates

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

Item {
    DTextField {
        id: searchField
        placeholderText: "Search files..."

        onTextChanged: {
            Proc.runCommand(
                "myPlugin.search",
                ["find", "/home", "-name", "*" + text + "*"],
                (output, exitCode) => {
                    if (exitCode === 0) {
                        updateSearchResults(output)
                    }
                },
                500
            )
        }
    }
}
```

### Important Notes

1. **Unique IDs**: Use descriptive, namespaced IDs (e.g., `"myPlugin.actionName"`) to avoid conflicts
2. **Debouncing**: Use appropriate debounce delays for your use case:
   - Fast updates (50-100ms): System monitoring, real-time data
   - User input (300-500ms): Search fields, text input processing
   - Network requests (500-1000ms): API calls, web scraping
3. **Error Handling**: Always check the exit code in your callback before processing output
4. **Shell Commands**: Use `["sh", "-c", "command"]` for complex shell commands with pipes or redirects
5. **Security**: Sanitize user input before passing to commands to prevent command injection
6. **Performance**: Avoid running expensive commands too frequently - use debouncing wisely

### Comparison with Other Methods

**Proc.runCommand** vs **Quickshell.execDetached**:
- Use `Proc.runCommand` when you need to capture output or check exit codes
- Use `Quickshell.execDetached` for fire-and-forget operations (like clipboard copy)

**Proc.runCommand** vs **Process component**:
- Use `Proc.runCommand` for simple, one-off command executions with automatic cleanup
- Use `Process` component for long-running processes or when you need fine-grained control

## Debugging

### Console Logging

View plugin logs:

```bash
qs -v -p $CONFIGPATH/quickshell/dms/shell.qml
```

Look for lines prefixed with:
- `PluginService:` - Service operations
- `PluginsTab:` - UI interactions
- `PluginsTab:` - Settings loading and accordion interface

### Common Issues

1. **Plugin Not Detected**
   - Check plugin.json syntax (use `jq` or JSON validator)
   - Verify directory is in `$CONFIGPATH/dms/plugins/`
   - Click "Scan for Plugins" in Settings

2. **Widget Not Displaying**
   - Ensure plugin is enabled in Settings
   - Add plugin ID to DankBar widget list
   - Check widget width/height properties

3. **Settings Not Loading**
   - Verify `settings` path in plugin.json
   - Check settings component for errors
   - Ensure plugin is enabled and loaded
   - Review PluginsTab console output for injection issues

4. **Data Not Persisting**
   - Confirm pluginService.savePluginData() calls (with injection)
   - Check `$CONFIGPATH/dms/settings.json` for pluginSettings data
   - Verify plugin has settings permissions
   - Ensure PluginService was properly injected into settings component

## Security Considerations

Plugins run with full QML runtime access. Only install plugins from trusted sources.

**Permissions System:**
- `settings_read`: Read plugin configuration (not currently enforced)
- `settings_write`: **Required** to use PluginSettings - write plugin configuration (enforced)
- `process`: Execute system commands (not currently enforced)
- `network`: Network access (not currently enforced)

Currently, only `settings_write` is enforced by the PluginSettings component.

## API Stability

The plugin API is currently **experimental**. Breaking changes may occur in minor version updates. Pin to specific DMS versions for production use.

**Roadmap:**
- Plugin marketplace/repository
- Sandboxed plugin execution
- Enhanced permission system
- Plugin update notifications
- Inter-plugin communication

## Launcher Plugins

Launcher plugins extend the DMS application launcher by adding custom searchable items with trigger-based filtering.

### Overview

Launcher plugins enable you to:
- Add custom items to the launcher/app drawer
- Use trigger strings for quick filtering (e.g., `!`, `#`, `@`)
- Execute custom actions when items are selected
- Provide searchable, categorized content
- Integrate seamlessly with the existing launcher

### Plugin Type Configuration

To create a launcher plugin, set the plugin type in `plugin.json`:

```json
{
    "id": "myLauncher",
    "name": "My Launcher Plugin",
    "description": "A custom launcher plugin for quick actions",
    "version": "1.0.0",
    "author": "Your Name",
    "type": "launcher",
    "capabilities": ["show-thing"],
    "component": "./MyLauncher.qml",
    "trigger": "#",
    "icon": "search",
    "settings": "./MySettings.qml",
    "requires_dms": ">=0.1.18",
    "permissions": ["settings_read", "settings_write"]
}
```

Launcher components are instantiated the first time the launcher asks them for items, not at shell startup or launcher open, so a plugin not allowed without a trigger is created once its trigger is typed or the launcher is filtered to it. Put background work (timers, processes, IPC handlers) in a daemon surface.

Launcher results use shared Expressive rows and tiles in every launcher style. The item and action contracts are unchanged. List rows use a second line when `comment` is present; image and window preview tiles remain supported. Plugins do not need to supply a visual delegate.

### Launcher Component Contract

Create `MyLauncher.qml` with the following interface:

```qml
import QtQuick
import qs.Services

Item {
    id: root

    // Required properties
    property var pluginService: null
    property string trigger: "#"

    // Required signals
    signal itemsChanged()

    // Required: Return array of launcher items
    function getItems(query) {
        return [
            {
                name: "Item Name",
                icon: "icon_name",
                comment: "Description",
                action: "type:data",
                categories: ["MyLauncher"]
            }
        ]
    }

    // Required: Execute item action
    function executeItem(item) {
        const [type, data] = item.action.split(":", 2)
        // Handle action based on type
    }

    Component.onCompleted: {
        if (pluginService) {
            trigger = pluginService.loadPluginData("myLauncher", "trigger", "#")
        }
    }
}
```

### Item Structure

Each item returned by `getItems()` must include:

- `name` (string): Display name shown in launcher
- `icon` (string, optional): Icon specification (see Icon Types below)
- `comment` (string): Description/subtitle text
- `action` (string): Action identifier in `type:data` format
- `categories` (array): Array containing your plugin name

### Icon Types

The `icon` field supports four formats:

**1. Material Design Icons** - Use the `material:` prefix:
```javascript
{
    name: "My Item",
    icon: "material:lightbulb",  // Material Symbols Rounded font
    comment: "Uses Material Design icon",
    action: "toast:Hello!",
    categories: ["MyPlugin"]
}
```
Available icons: Any icon from Material Symbols font (e.g., `lightbulb`, `star`, `favorite`, `settings`, `terminal`, `translate`, `sentiment_satisfied`)

**2. Unicode/Emoji Icons** - Use the `unicode:` prefix:
```javascript
{
    name: "Grinning Face",
    icon: "unicode:😀",  // Unicode character or emoji
    comment: "Copy emoji to clipboard",
    action: "copy:😀",
    categories: ["MyPlugin"]
}
```
Display any Unicode character or emoji as the icon. The character is rendered at 70-80% of the icon size with proper theming. Perfect for emoji pickers, symbol selectors, or character libraries.

**3. Desktop Theme Icons** - Use icon name directly:
```javascript
{
    name: "Firefox",
    icon: "firefox",  // Uses system icon theme
    comment: "Launches Firefox browser",
    action: "exec:firefox",
    categories: ["MyPlugin"]
}
```
Uses the user's installed icon theme. Common examples: `firefox`, `chrome`, `folder`, `text-editor`

**4. No Icon** - Omit the `icon` field entirely:
```javascript
{
    name: "😀  Grinning Face",
    // No icon field - emoji/unicode in name displays without icon area
    comment: "Copy emoji to clipboard",
    action: "copy:😀",
    categories: ["MyPlugin"]
}
```
When `icon` is omitted, the launcher shows the first letter of the item name in a themed circle.

### Trigger System

Triggers control when your plugin's items appear in the launcher:

**Empty Trigger Mode** (No trigger):
- Items always visible alongside regular apps
- Search includes your items automatically
- Configure by saving empty trigger: `trigger: ""`

**Custom Trigger Mode**:
- Items only appear when trigger is typed
- Example: Type `#` to show only your plugin's items
- Type `# query` to search within your plugin
- Configure any string: `#`, `!`, `@`, `!custom`, etc.

### Trigger Configuration in Settings

Provide a settings component with trigger configuration:

```qml
import QtQuick
import QtQuick.Controls
import qs.Widgets
import qs.DCommon.Widgets

FocusScope {
    id: root

    property var pluginService: null

    Column {
        spacing: 12

        CheckBox {
            id: noTriggerToggle
            text: "No trigger (always show)"
            checked: loadSettings("noTrigger", false)

            onCheckedChanged: {
                saveSettings("noTrigger", checked)
                if (checked) {
                    saveSettings("trigger", "")
                } else {
                    saveSettings("trigger", triggerField.text || "#")
                }
            }
        }

        DTextField {
            id: triggerField
            visible: !noTriggerToggle.checked
            text: loadSettings("trigger", "#")
            placeholderText: "#"

            onTextEdited: {
                saveSettings("trigger", text || "#")
            }
        }
    }

    function saveSettings(key, value) {
        if (pluginService) {
            pluginService.savePluginData("myLauncher", key, value)
        }
    }

    function loadSettings(key, defaultValue) {
        if (pluginService) {
            return pluginService.loadPluginData("myLauncher", key, defaultValue)
        }
        return defaultValue
    }
}
```

### Action Execution

Handle different action types in `executeItem()`:

```qml
function executeItem(item) {
    const actionParts = item.action.split(":")
    const actionType = actionParts[0]
    const actionData = actionParts.slice(1).join(":")

    switch (actionType) {
        case "toast":
            if (typeof ToastService !== "undefined") {
                ToastService.showInfo("Plugin", actionData)
            }
            break
        case "copy":
            // Copy to clipboard
            break
        case "script":
            // Execute command
            break
        default:
            console.warn("Unknown action:", actionType)
    }
}
```

### Search and Filtering

The launcher automatically handles search when:

**With empty trigger**:
- Your items appear in all searches
- No prefix needed

**With custom trigger**:
- Type trigger alone: Shows all your items
- Type trigger + query: Filters your items by query
- The query parameter is passed to your `getItems(query)` function

Example `getItems()` implementation:

```qml
function getItems(query) {
    const allItems = [
        {name: "Item 1", ...},
        {name: "Item 2", ...},
        {name: "Test Item", ...}
    ]

    if (!query || query.length === 0) {
        return allItems
    }

    const lowerQuery = query.toLowerCase()
    return allItems.filter(item => {
        return item.name.toLowerCase().includes(lowerQuery) ||
               item.comment.toLowerCase().includes(lowerQuery)
    })
}
```

### Integration Flow

1. User opens launcher
2. If empty trigger: Your items appear alongside apps
3. If custom trigger: User types trigger (e.g., `#`)
4. Launcher calls `getItems(query)` on your plugin
5. Your items displayed with your plugin's category
6. User selects item and presses Enter
7. Launcher calls `executeItem(item)` on your plugin

### Best Practices

1. **Unique Triggers**: Choose non-conflicting trigger strings
2. **Fast Response**: Return results quickly from `getItems()`
3. **Clear Names**: Use descriptive item names and comments
4. **Error Handling**: Gracefully handle failures in `executeItem()`
5. **Cleanup**: Destroy temporary objects after use
6. **Empty Trigger Support**: Consider if your plugin benefits from always being visible

### Example Plugin

See `PLUGINS/LauncherExample/` for a complete working example demonstrating:
- Trigger configuration (including empty trigger mode)
- Multiple action types (toast, copy, script)
- Search/filtering implementation
- Settings integration
- Proper error handling

## Launcher Actions

Any plugin surface can offer **actions** to the launcher and to semantic search: things the user runs by name ("start a timer", "turn on the living room lamp") rather than items the plugin lists under a trigger. The shell builds one catalog from its own actions and every plugin's; the launcher shows the matching rows with a state, and Enter runs the action. Plugin actions have the id `plugin:<pluginId>:<id>` and disappear when the plugin unloads or is disabled.

### Registering

Call `registerActions` once the surface is up (a daemon is the natural place) and again whenever the set changes. Each call replaces everything the plugin registered before; an empty list removes it all.

```qml
Component.onCompleted: {
    pluginService.registerActions(pluginId, [
        {
            id: "lamp.on",
            title: I18n.trFor("myPlugin", "Living room lamp"),
            text: "Living room lamp. Turn the lamp in the living room on or set its brightness; light, bulb, too dark, smart home.",
            keywords: ["lamp", "light", "lamba", "ışık"],
            icon: "lightbulb",
            params: [{ name: "percent", type: "percent", min: 0, max: 100 }],
            available: () => root.connected,
            state: () => root.lampOn ? I18n.trFor("myPlugin", "On") : I18n.trFor("myPlugin", "Off"),
            run: (values, query) => root.setLamp(values.percent === undefined ? 100 : values.percent)
        }
    ]);
}
```

`registerActions(pluginId, actions)` returns `{registered, errors}`. A malformed entry is skipped, named in `errors` and logged; the plugin's other actions still register.

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Letters, digits, `.`, `_`, `-`. Unique within the plugin. |
| `title` | yes | Shown in the row. Translate it with `I18n.trFor`. |
| `text` | yes | **English** description the search model embeds. Write it as: name, what it does, synonyms, the situation a user is in ("tired eyes", "flashlight"). A rich description matters far more than a short one; short ones outrank everything else for unrelated queries. |
| `keywords` | no | Extra words for the lexical side of the search, English and the languages you care about. |
| `icon` | no | Material icon name. Defaults to `extension`. |
| `params` | no | Numbers to extract from the typed text, see below. |
| `available` | no | Boolean, or a function returning one. Unavailable actions are hidden from search and never embedded. Default `true`. A throwing function counts as available. |
| `state` | no | String, or a function returning one, shown next to the title ("" shows nothing). |
| `run(values, query)` | yes | Called on Enter. `values` holds the extracted params, `query` the text as typed. Returning `false` or throwing shows a failure toast; anything else counts as success. |

The shell does not show a confirmation for a plugin action; give feedback yourself, for example with `ToastService`.

### Parameters

`params` is a list of `{name, type, min, max, unit, required, example}`. The shell reads the numbers out of the typed text, in Turkish and English, with or without diacritics, and clamps them to `min`/`max`:

| `type` | Understands |
|---|---|
| `percent` | `%40`, `40%`, `yüzde 40`, `forty percent`, `volume 40`, `sesi 80'e çıkar` |
| `int` | `3`, `3.`, `third`, `üçüncü`, `twenty five`, `yirmi beş` |
| `duration` | `15 dakika`, `15m`, `1h30m`, `1 saat 30 dk`, `half an hour`, `yarım saat`, `bir buçuk saat`; delivered in `unit` (`seconds`, `minutes` or `hours`, default minutes) |

A param the user did not type has no key in `values`. With `required: true` the shell refuses to run and tells the user to add a value, showing `example`. An action without `params` ignores any numbers.

### Lifecycle

`PluginService` emits `pluginUnloaded` when a plugin is unloaded, disabled, reloaded or removed, and the catalog drops that plugin's actions at once. A reload registers them again from your `Component.onCompleted`. `pluginService.unregisterActions(pluginId)` removes them earlier if you need to. The catalog's `revision` changes with every registration, removal and availability change, and the search index follows it.

### Example Plugin

See `PLUGINS/ActionsExample/` for a timer that registers a parameterised action and an action that is only available while a countdown runs.

## Desktop Plugins

Desktop plugins are widgets that appear directly on the desktop background layer. They can be dragged, resized, and positioned freely by the user.

### Overview

Desktop plugins enable you to:
- Display widgets on the desktop background
- Support drag-and-drop positioning
- Support resize via corner handles
- Persist position and size across sessions
- Provide settings for customization

### Plugin Type Configuration

To create a desktop plugin, set the plugin type in `plugin.json`:

```json
{
    "id": "myDesktopWidget",
    "name": "My Desktop Widget",
    "description": "A custom desktop widget",
    "version": "1.0.0",
    "author": "Your Name",
    "type": "desktop",
    "capabilities": ["desktop-widget"],
    "component": "./MyWidget.qml",
    "icon": "widgets",
    "settings": "./MySettings.qml",
    "permissions": ["settings_read", "settings_write"]
}
```

### Desktop Widget Component Contract

Create your widget component (`MyWidget.qml`) with the following interface:

```qml
import QtQuick
import qs.Common

Item {
    id: root

    // Injected properties (provided by DesktopPluginWrapper)
    property var pluginService: null
    property string pluginId: ""
    property bool editMode: false
    property real widgetWidth: 200
    property real widgetHeight: 200

    // Optional: Define minimum size constraints
    property real minWidth: 100
    property real minHeight: 100

    // Your widget content
    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.hostSurface
        opacity: 0.85

        // Widget content here
        Text {
            anchors.centerIn: parent
            text: "Hello Desktop!"
            color: Theme.surfaceText
        }
    }
}
```

### Injected Properties

Desktop widgets receive these properties automatically:

- `pluginService`: Reference to PluginService for data persistence
- `pluginId`: The plugin's unique identifier
- `editMode`: Boolean indicating if the user is in edit mode (dragging/resizing)
- `widgetWidth`: Current width of the widget container
- `widgetHeight`: Current height of the widget container

### Optional Properties

Define these properties on your widget to customize behavior:

- `minWidth`: Minimum allowed width (default: 100)
- `minHeight`: Minimum allowed height (default: 100)

### Runtime Resize API

Desktop widgets can resize their live surface at runtime without saving the new size to disk.

The wrapper exposes two functions on the widget instance:

- `requestResize(width, height)`: Applies a temporary surface size override
- `clearResize()`: Clears the temporary override and restores the normal persisted size

These are available as properties on `DesktopPluginComponent` and are passed through by `DesktopPluginWrapper` automatically.

```qml
import QtQuick
import qs.Common

Item {
    id: root

    function expandPreview() {
        if (requestResize) {
            requestResize(420, 260)
        }
    }

    function resetPreview() {
        if (clearResize) {
            clearResize()
        }
    }
}
```

Notes:
- This is a transient runtime resize only; it does not persist to `settings.json`
- The requested size must stay within the screen bounds and above `minWidth` / `minHeight`
- Use `clearResize()` when you want to return to the saved widget dimensions

### Loading and Saving Data

Use the injected `pluginService` to persist widget-specific data:

```qml
property string myValue: pluginService ? pluginService.loadPluginData(pluginId, "myValue", "default") : "default"

Connections {
    target: pluginService
    function onPluginDataChanged(changedPluginId) {
        if (changedPluginId !== pluginId) return;
        root.myValue = pluginService.loadPluginData(pluginId, "myValue", "default");
    }
}

function saveMyValue(value) {
    if (pluginService) {
        pluginService.savePluginData(pluginId, "myValue", value);
    }
}
```

### Position and Size Persistence

Position (`desktopX`, `desktopY`) and size (`desktopWidth`, `desktopHeight`) are automatically persisted by the `DesktopPluginWrapper`. You don't need to handle this in your widget.

### Edit Mode

When `editMode` is true, the user is repositioning or resizing the widget. You can use this to:
- Show visual indicators
- Disable interactive elements
- Display additional controls

```qml
Rectangle {
    anchors.fill: parent
    border.color: root.editMode ? Theme.primary : "transparent"
    border.width: root.editMode ? 2 : 0

    // Content that should be disabled during edit mode
    MouseArea {
        anchors.fill: parent
        enabled: !root.editMode
        onClicked: doSomething()
    }
}
```

### Settings Component

Create a settings component using `PluginSettings`:

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "myDesktopWidget"

    ToggleSetting {
        settingKey: "showBorder"
        label: "Show Border"
        description: "Display a border around the widget"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "theme"
        label: "Theme"
        options: [
            {label: "Light", value: "light"},
            {label: "Dark", value: "dark"}
        ]
        defaultValue: "dark"
    }
}
```

### User Interaction

Desktop widgets support:

1. **Drag**: Click and drag anywhere on the widget (when in edit mode)
2. **Resize**: Drag the bottom-right corner handle (when in edit mode)
3. **Edit Mode Toggle**: Click the edit button in the bottom-right corner of the screen

### Example Plugin

See `PLUGINS/ExampleDesktopClock/` for a complete working example demonstrating:
- Analog and digital clock styles
- Settings integration
- Responsive sizing
- Edit mode handling

## Dash Plugins

### Overview

The dash popout (`dms ipc call dash open`) is a set of entries. Each entry can have a tab, an overview card, or both. The built-ins (Overview, Media, Wallpapers, Weather, Notifications, Clock, Calendar, User, System Monitor, CPU, Memory, Network, Disk, Battery) are the same kind of entry as a plugin, they just ship enabled.

- `dash`: a full tab, built on `DashTabComponent`. Its id is `plugin_<pluginId>`, so `dms ipc call dash open plugin_dashTabExample` opens the example tab.
- `dashCard`: a card in the overview grid, built on `DashCardComponent`. The grid is 6 columns by default (users pick 3 to 8 in the Overview options) and rows are 96 px tall. Users drag the corner handle to any size inside the range the manifest allows.

Only enabled plugins show up. A disabled plugin has no tab, no card, no row under Settings → Dashboard and no entry in the Add widget menu. Its saved placement is kept, so re-enabling it puts the card back where it was.

A plugin tab is enabled in the tab bar as soon as the plugin loads. Users hide it under Settings → Dashboard → Tabs. Cards are never placed automatically: users add them from the dash (hover the selected page icon → click the pencil → Add widget). A plugin with both surfaces gets one interaction for free: clicking its card opens its tab, and a tab hidden from the bar opens as a detail page. It has a back button when enabled destinations exist; otherwise it opens standalone.

Both surfaces load lazily. A tab is created when it becomes current and destroyed when the user switches away. Cards are created with the overview grid. The dash content stays alive after the popout closes, so gate timers, animations and service refs on `live`.

### Plugin Type Configuration

A dash-only plugin uses the single file form like every other type:

```json
{
    "id": "dashTabExample",
    "name": "Stopwatch Example",
    "type": "dash",
    "capabilities": ["dash-tab"],
    "component": "./StopwatchTab.qml",
    "dash": { "title": "Stopwatch" }
}
```

```json
{
    "id": "dashCardExample",
    "name": "Progress Example",
    "type": "dashCard",
    "capabilities": ["dash-card"],
    "component": "./ProgressCard.qml",
    "dash": { "card": { "title": "Progress", "w": 2, "h": 1, "maxW": 4, "maxH": 2 } }
}
```

A plugin with a tab and a card, or dash surfaces plus a bar widget or daemon, uses `components`:

```json
{
    "id": "dashCounterExample",
    "type": "composite",
    "capabilities": ["dash-tab", "dash-card", "dankbar-widget"],
    "components": {
        "dash": "./CounterTab.qml",
        "dashCard": "./CounterCard.qml",
        "widget": "./CounterWidget.qml"
    },
    "dash": {
        "title": "Counter",
        "card": { "w": 2, "h": 1, "minW": 1, "minH": 1, "maxW": 3, "maxH": 2 }
    }
}
```

The `dash` block is optional. `icon` and `title` label the tab and fall back to the top-level `icon` and `name`. `card` names the card in the Add widget menu (`title`, `icon`, falling back to the tab label and icon), sets its default size in grid cells (`w`, `h`) and the range users may resize it within (`minW`, `minH`, `maxW`, `maxH`). Widths are clamped to the user's column count. Heights have no fixed limit, the screen bounds them at resize time. A card must lay itself out for every size in its range; the built-in cards switch layouts on their pixel size, and `Card` clips its content.

`options` declares user options for the plugin's dash surfaces. Each entry has a `key`, a `text` label (translated through the plugin catalog), a `type` and a default `def`. Toggles also take a `description`:

```json
"options": [
    { "key": "compact", "text": "Compact layout", "type": "toggle", "def": false, "description": "Hide the secondary line" },
    { "key": "style", "text": "Style", "type": "choice", "def": "bars", "choices": [{ "value": "bars", "text": "Bars" }, { "value": "dots", "text": "Dots" }] },
    { "key": "limit", "text": "Items", "type": "number", "def": 5, "min": 1, "max": 20, "step": 1 }
]
```

The dash shows these rows in an options sheet (the tune button on a card in edit mode, Options in a tab's edit-mode controls) and Settings → Dashboard lists the same rows. The tab and the card read the resolved values as `options.<key>` and re-evaluate when a value changes. Values live in `settings.json` under `dashOptions.plugin_<pluginId>`, apart from `pluginData`, and only non-default values are stored. Reset clears the declared keys only. `widgets` is reserved for the `DashWidgetGrid` layout and is ignored as an option key.

Set `"cardOnly": true` on an option that only the overview card reads. It stays on the card's sheet and in Settings, and the tab's sheet leaves it out.

`dash.options` only reach the dash surfaces. If a bar widget or daemon of the same plugin needs the value, use a `settings` component and `pluginData` instead.

### Dash Tab Contract

`DashTabComponent` (`Modules/Plugins/DashTabComponent.qml`) is an `Item` sized to the dash content area.

Injected by the host:

- `pluginId`, `pluginService`, `popoutService`
- `entryId`: the registry id (`plugin_<pluginId>`)
- `dashHost`: the popout, with `dashVisible`, `requestTab(id)` and `editMode`
- `editMode`: bound to the dash edit mode
- `live`: bound to "this tab is current and the dash is visible"
- `targetScreen`, `active` and `rowBudget` (the number of 96 px rows that fit on the screen), when the tab declares those properties

Provided by the base:

- `options`: the resolved values of the manifest `dash.options`
- `pluginData`: the plugin's persisted settings, refreshed on `pluginDataChanged`
- `getData(key, default)` / `setData(key, value)`
- `handleKeyEvent(event)`: override and return `true` to consume a key. The host asks the tab before its own handling (Ctrl+Tab and Ctrl+Shift+Tab stay reserved for switching tabs), so Escape can close a tab-local overlay before it closes the dash.

Optional on the tab:

- `implicitHeight`: the dash grows to fit it. The minimum is the overview grid height (`DashMetrics.tabMinHeight`)
- `focusTarget`: the item that receives focus when Down enters the tab content
- `restoreFocus()`: called when the dash opens on the tab or returns focus to it. Focus your content here with `Qt.OtherFocusReason` so no focus ring is drawn
- `blocksTabNavigation`: true while an editor or local control group needs native Tab traversal; false returns Tab to the dash navigation
- `menuActions`: actions shown in the Actions menu while editing the tab. Each action has `label`, `iconName`, `action`, and optional `visible` and `enabled`
- `signal tabRequested(string id)`: switch the dash to another tab (`"overview"`, `"media"`, `"wallpaper"`, `"weather"`, `"notifications"` or a `plugin_<id>`); a tab hidden from the bar opens as a detail page
- `signal navFocusRequested`: return focus to the dash navigation

Use `Card` from `qs.Modules.DDash.Overview` for tiles inside a tab so they pick up the same surface colors, radius and tones as the overview.

### Widgets inside a tab

Assign a `DashWidgetGrid` to `DashTabComponent.widgetGrid` to get the dash Edit, Add widget, Reset and Clear All actions for free. Bind the grid's `entryId`, `live` and `editMode` to the tab, and the tab's `implicitHeight` and `focusTarget` to the grid.

```qml
DashTabComponent {
    id: tab
    widgetGrid: grid
    implicitHeight: grid.implicitHeight
    focusTarget: grid.focusTarget

    DashWidgetGrid {
        id: grid
        width: parent.width
        entryId: tab.entryId
        live: tab.live
        editMode: tab.editMode
        definitions: [
            {id: "counter", text: I18n.trFor("yourPlugin", "Counter"), icon: "counter_1", component: counter, w: 2, h: 2, minW: 1, minH: 1, maxW: 4, maxH: 3}
        ]
    }

    Component {
        id: counter
        CounterWidget {}
    }
}
```

Import `qs.Modules.DDash` for the grid. Each definition has a stable `id`, a translated `text`, an `icon`, a QML `component`, default `w`/`h` and optional `minW`/`minH`/`maxW`/`maxH`. The grid is 4 columns wide (2 when narrower than `Theme.smallBreakpoint`), independent of the overview column count. Set `enabled: false` to leave a widget in the Add menu initially.

A definition can carry `options`, a list of option specs in the same shape as `dash.options` (`toggle`, `choice`, `number`). Build them with `DashRegistry.toggle(key, text, def)`, `DashRegistry.choice(key, text, def, choices)`, `DashRegistry.number(key, text, def, min, max, step, unit)` or `DashRegistry.toneOption(def)` for the shared Tone choice. In edit mode a widget with options shows an options button that opens them in a sheet. Each widget instance stores its own values, and the widget reads them from `widgetOptions` by key. `id`, `w`, `h`, `col` and `row` are reserved keys.

```qml
definitions: [
    {id: "counter", text: I18n.trFor("yourPlugin", "Counter"), icon: "counter_1", component: counter, w: 2, h: 2,
     options: [DashRegistry.toneOption("primary"), DashRegistry.toggle("compact", I18n.trFor("yourPlugin", "Compact"), false)]}
]
```

A widget that is not a `Card` can still follow a tone with `DankTone` from `qs.Widgets`. Set its `tone` and paint with `surfaceColor`, `contentColor`, `accentColor`, `onAccentColor`, `mutedColor` and `chipColor`. `tinted` is true for any tone but the surface one.

```qml
Rectangle {
    property var widgetOptions: ({})

    color: toneColors.surfaceColor

    DankTone {
        id: toneColors
        tone: widgetOptions.tone ?? ""
    }

    StyledText {
        text: "42"
        color: toneColors.contentColor
    }
}
```

The grid saves order, size and option values in `dashOptions[entryId].widgets`. Missing definitions keep their saved placement. A saved empty list stays empty; Reset restores the current defaults. Widgets receive `widgetId`, `widgetOptions` and a bound `live` value if they declare those properties. The grid unloads widget content when `live` is false. Edit mode offers drag ordering, a resize handle, removal and the options button.

### Dash Card Contract

`DashCardComponent` (`Modules/Plugins/DashCardComponent.qml`) derives from the overview `Card`: a tonal surface with `pad`, an optional `title` label, a `tone` (`""`, `"primary"`, `"secondary"` or `"tertiary"`) that tints the surface, the matching `containerColor`, `contentColor`, `accentColor`, `onAccentColor`, `mutedColor` and `chipColor`, the resolved `options`, and `clickable` for a state layer and a `clicked` signal. Children are placed inside the padded content area.

The host injects `pluginId`, `pluginService`, `popoutService` and `entryId`, and binds `live` (true while the overview is visible) and `interactive` (false while the user edits the grid). The base offers the same `pluginData`, `getData` and `setData` as the tab. When the plugin also has a tab, a click on a clickable card opens it; set `opensTab: false` to keep the click to yourself.

Cards expose `focusTarget`, `handleKeyEvent(event)` and `blocksTabNavigation`. Clickable cards focus themselves by default; set `focusTarget` to a child control instead, or leave a non-clickable card at `null` and keyboard navigation skips it.

Tab and Shift+Tab switch dash tabs while focus is on the dash navigation. The overview focuses the last focused card when it opens (calendar at first, remembered across opens) without a focus ring, and keys go straight to that card. Alt+Arrows or Alt+H/J/K/L move to the neighbouring card, Alt+Tab and Alt+Shift+Tab cycle cards, and the card that gains focus flashes a ring. On other tabs, Down enters the content. Inside content, Tab and Shift+Tab reach controls; Ctrl+Tab and Ctrl+Shift+Tab switch dash tabs from there. Escape closes local overlays first, then the dash.

Return `true` from `handleKeyEvent(event)` for handled keys, or `false` for the host to continue. The host passes local Tab and Backtab through this method before leaving a component. Set `blocksTabNavigation` while an editor needs native child-control traversal, then emit `navFocusRequested()` to return to navigation. Child `Keys` handlers can consume keys before the host sees them.

```qml
DashCardComponent {
    id: root
    clickable: true
    opensTab: false

    function handleKeyEvent(event) {
        switch (event.key) {
        case Qt.Key_Left:
            setData("count", Math.max(0, getData("count", 0) - 1));
            return true;
        case Qt.Key_Right:
            setData("count", getData("count", 0) + 1);
            return true;
        }
        return false;
    }
}
```

### Opening the dash from other surfaces

`popoutService.toggleDankDash(tabId, x, y, width, section, screen)` opens the dash on a tab. A bar or dock widget can wire it to its pill with the positioned `pillClickAction` form:

```qml
pillClickAction: (x, y, width, section, screen) => popoutService?.toggleDankDash("plugin_" + pluginId, x, y, width, section, screen)
```

### Example Plugins

- [DashTabExample](./DashTabExample/): standalone tab (`"type": "dash"`), plugin state, `live` gating, keys, menu actions, options
- [DashCardExample](./DashCardExample/): standalone card (`"type": "dashCard"`), responsive layout, tones, options
- [DashCounterExample](./DashCounterExample/): tab + card + bar/dock widget sharing one counter, `DashWidgetGrid`

## Composite Plugins

A single plugin can provide **multiple surfaces at once** — for example a background
daemon (for IPC / monitoring), a bar widget, and a desktop widget. Because each surface
has a different lifecycle (the daemon is instantiated once; bar and desktop widgets are
instantiated per bar/placement per screen), each surface is its own QML file.

### Plugin Type Configuration

Instead of a single `type` + `component`, declare a `components` map. Set `type` to
`composite` (any value works; `composite` is conventional):

```json
{
    "id": "myComposite",
    "name": "My Composite Plugin",
    "description": "A daemon plus a bar widget plus a desktop widget",
    "version": "1.0.0",
    "author": "Your Name",
    "type": "composite",
    "capabilities": ["daemon", "dankbar-widget", "desktop-widget"],
    "components": {
        "daemon":   "./MyDaemon.qml",
        "widget":   "./MyBarWidget.qml",
        "desktop":  "./MyDesktopWidget.qml",
        "launcher": "./MyLauncher.qml"
    },
    "trigger": "#",
    "settings": "./MySettings.qml",
    "requires_dms": ">=1.5.0",
    "permissions": ["settings_read", "settings_write"]
}
```

### Surfaces

Provide any subset of these keys in `components`:

| Surface | Component contract | Notes |
|---------|--------------------|-------|
| `widget` | `PluginComponent` (bar and dock pills + optional Control Center widget) | see [Widget Component](#widget-component) |
| `desktop` | `DesktopPluginComponent` (or an `Item` following the desktop contract) | see [Desktop Plugins](#desktop-plugins) |
| `daemon` | any `Item` exposing `pluginService` / `pluginId` | instantiated once; ideal for IPC handlers and background monitoring |
| `launcher` | launcher contract (`getItems` / `executeItem`) | requires `trigger` (or empty-trigger mode); see [Launcher Plugins](#launcher-plugins) |
| `dash` | `DashTabComponent` | a tab in the dashboard popout; see [Dash Plugins](#dash-plugins) |
| `dashCard` | `DashCardComponent` | a card in the dashboard overview grid; see [Dash Plugins](#dash-plugins) |

Each surface is loaded independently into its own registry, so the same plugin can show
up in the bar **and** on the desktop **and** run a daemon simultaneously.

### Shared State

Each surface is a separate object, so share runtime state through:

- `PluginService.getGlobalVar(pluginId, name, default)` / `setGlobalVar(...)` — reactive,
  in-process, namespaced per plugin (see [Plugin Global Variables](#plugin-global-variables)).
- The daemon instance — register `IpcHandler`s or expose data other surfaces read via
  global vars.
- `savePluginData` / `loadPluginData` for persisted settings (all surfaces of a plugin
  share one settings namespace, so one `settings` component configures them all).

### Settings, Enabling, and Backwards Compatibility

- Declare a single top-level `settings` component; it configures every surface.
- Composite plugins respect the **enable toggle** in Settings → Plugins (they are not
  auto-loaded). A pure `desktop` plugin still auto-loads for backwards compatibility.
- The legacy single `type` + `component` form is unchanged and fully supported — it is
  treated internally as a one-entry `components` map.

### Example Plugin

See `PLUGINS/ExampleCompositePlugin/` for a working composite that combines the
WallpaperWatcher daemon, the Emoji Cycler bar widget, and the Desktop Clock into one
plugin.

## Resources

- **Plugin Schema**: `plugin-schema.json` - JSON Schema for validation
- **Example Plugins**:
  - [Emoji Picker](./ExampleEmojiPlugin/)
  - [WorldClock](https://github.com/rochacbruno/WorldClock)
  - [LauncherExample](./LauncherExample/)
  - [Calculator](https://github.com/rochacbruno/DankCalculator)
  - [Desktop Clock](./ExampleDesktopClock/)
  - [Composite Example](./ExampleCompositePlugin/)
  - [Stopwatch tab](./DashTabExample/)
  - [Progress card](./DashCardExample/)
  - [Counter: tab, card and bar/dock widget](./DashCounterExample/)
  - [Attached dock panel](./AttachedPanelExample/)
- **PluginService**: `Services/PluginService.qml`
- **Settings UI**: `Modules/Settings/PluginSettingsPage.qml`
- **Bar and Dock Integration**: `Modules/SurfaceWidgets/SurfaceWidgetHost.qml`
- **Dash Integration**: `Modules/DDash/DashRegistry.qml`
- **Launcher Integration**: `Modals/DLauncherV2/Controller.qml`
- **Desktop Widget Integration**: `Modules/DesktopWidgetLayer.qml`
- **Theme Reference**: `Common/Theme.qml`
- **Widget Library**: `Widgets/`

## Contributing

Share your plugins with the community:

1. Create a public repository with your plugin
2. Validate your `plugin.json` against `plugin-schema.json`
3. Include comprehensive README.md
4. Add example screenshots
5. Document dependencies and permissions

For plugin system improvements, submit issues or PRs to the main DMS repository.

Widget plugins can also run in named docks. See the [surface widget contract](SURFACE_WIDGETS.md) and [attached panel example](AttachedPanelExample/).
