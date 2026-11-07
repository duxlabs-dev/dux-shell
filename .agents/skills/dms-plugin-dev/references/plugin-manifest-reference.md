# Plugin Manifest Reference (plugin.json)

## Required Fields

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `id` | string | Unique plugin identifier | camelCase, pattern `^[a-zA-Z][a-zA-Z0-9]*$` |
| `name` | string | Human-readable name | Non-empty |
| `description` | string | Short description (shown in UI) | Non-empty |
| `version` | string | Semantic version | Pattern `^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$` |
| `author` | string | Creator name or email | Non-empty |
| `type` | string | Plugin type | One of: `widget`, `daemon`, `launcher`, `desktop`, `dash`, `dashCard`, `composite` |
| `capabilities` | array | Plugin capabilities | At least 1 string item |

One of `component` or `components` is required (not both):

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `component` | string | Path to main QML file (single-surface plugins) | Must start with `./`, end with `.qml` |
| `components` | object | Map of surface name to QML path (multi-surface plugins) | At least 1 entry; keys: `widget`, `desktop`, `daemon`, `launcher`, `dash`, `dashCard`, `island`, `islandSystem` |

## Conditional Requirements

| Condition | Required Field | Description |
|-----------|---------------|-------------|
| `type: "launcher"` | `trigger` | Trigger string for launcher activation (e.g., `=`, `#`, `!`) |
| `components` has `launcher` key | `trigger` | Same requirement applies to composite plugins with a launcher surface |

## Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `icon` | string | Material Design icon name (displayed in plugin list UI) |
| `settings` | string | Path to settings QML file (must start with `./`, end with `.qml`) |
| `startupCheck` | string | Path to a QtObject component that gates plugin activation via a `check(done)` function (must start with `./`, end with `.qml`). See Startup Check section below. |
| `requires_dms` | string | Minimum DMS version (e.g., `>=0.1.18`), pattern `^(>=?\|<=?\|=\|>\|<)\d+\.\d+\.\d+$` |
| `dependencies` | array | System tool dependencies (e.g., `["curl", "jq"]`). Registry metadata. |
| `requires` | array | Deprecated alias for `dependencies` |
| `permissions` | array | Required permissions |
| `trigger` | string | Launcher trigger string (required for launcher type) |
| `dash` | object | Dash tab label, overview card size range and dash options. See Dash Block below. |

## Permissions

| Permission | Description | Enforced |
|------------|-------------|----------|
| `settings_read` | Read plugin configuration | No (not currently enforced) |
| `settings_write` | Write plugin configuration / use PluginSettings | **Yes** |
| `process` | Execute system commands | No (not currently enforced) |
| `network` | Network access | No (not currently enforced) |

If your plugin has a `settings` component but does not declare `settings_write`, users will see an error instead of the settings UI.

## Capabilities

Capabilities are free-form strings that describe what the plugin does. Common values:

- `dankbar-widget` - general bar widget
- `control-center` - integrates with Control Center
- `monitoring` - system/service monitoring
- `launcher` - launcher search provider
- `desktop-widget` - desktop background widget
- `dash-tab` - dash tab
- `dash-card` - dash overview card
- `ai` - AI/LLM integration
- `slideout` - uses slideout panel

## Startup Check

The `startupCheck` field points to a non-visual `QtObject` component that gates plugin activation on dependency checks. The component must expose a `check(done)` function:

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
- `{ title, details }` - block with a title and expandable details

A synchronous variant (no `done` parameter, return the result directly) is also supported.

Failed startup checks show a toast error and store the error in `pluginService.pluginLoadErrors`.

## Components (Composite Plugins)

The `components` field maps surface names to QML paths, allowing a single plugin to register multiple surfaces:

```json
{
    "id": "myComposite",
    "name": "My Composite Plugin",
    "description": "Daemon + widget + desktop from one plugin",
    "version": "1.0.0",
    "author": "Developer Name",
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

Valid surface keys: `widget`, `desktop`, `daemon`, `launcher`, `dash`, `dashCard`, `island`, `islandSystem`. Provide any subset. Each surface is loaded independently in the appropriate registry.

## Dash Block

Plugins with a `dash` or `dashCard` surface can describe them in a `dash` object. Everything is optional.

```json
"dash": {
    "icon": "timer",
    "title": "Stopwatch",
    "card": { "title": "Progress", "icon": "hourglass_bottom", "w": 2, "h": 1, "minW": 1, "minH": 1, "maxW": 4, "maxH": 2 },
    "options": [
        { "key": "compact", "text": "Compact layout", "type": "toggle", "def": false, "description": "Hide the secondary line" },
        { "key": "style", "text": "Style", "type": "choice", "def": "bars", "choices": [{ "value": "bars", "text": "Bars" }, { "value": "dots", "text": "Dots" }] },
        { "key": "limit", "text": "Items", "type": "number", "def": 5, "min": 1, "max": 20, "step": 1 }
    ]
}
```

| Field | Description |
|-------|-------------|
| `icon`, `title` | Tab icon and label. Fall back to the top-level `icon` and `name` |
| `card.title`, `card.icon` | Card name and icon in the Add widget menu. Fall back to the tab label and icon |
| `card.w`, `card.h` | Default size in grid cells. Columns are 3 to 8 (default 6), rows are 96 px |
| `card.minW` .. `card.maxH` | Resize range. Widths clamp to the user's column count; heights have no fixed limit |
| `options` | Rows in the dash options sheet and Settings > Dashboard. Read as `options.<key>` in the tab and card. Types: `toggle`, `choice`, `number`. `widgets` is a reserved key |

## Dash Examples

Standalone tab and standalone card use the single file form:

```json
{
    "id": "dashTabExample",
    "name": "Stopwatch Example",
    "description": "A standalone dash tab",
    "version": "1.0.0",
    "author": "Developer Name",
    "type": "dash",
    "capabilities": ["dash-tab"],
    "component": "./StopwatchTab.qml",
    "dash": { "title": "Stopwatch" },
    "requires_dms": ">=1.7.0"
}
```

```json
{
    "id": "dashCardExample",
    "name": "Progress Example",
    "description": "A standalone overview card",
    "version": "1.0.0",
    "author": "Developer Name",
    "type": "dashCard",
    "capabilities": ["dash-card"],
    "component": "./ProgressCard.qml",
    "dash": { "card": { "w": 2, "h": 1, "maxW": 4, "maxH": 2 } },
    "requires_dms": ">=1.7.0"
}
```

A tab plus a card, or dash surfaces plus a bar widget, use `components` with `"type": "composite"`.

## Island Block

The `island` surface is the face of the plugin's activities in the island: the plugin asks for one with
`IslandActivityService.request(pluginId, options)` (a token, or `""` when refused; the log says why). It shows on the
focused screen's island, or on `options.screen`; `"*"` means every island there is at request time, so a screen plugged
in later does not get it. The `islandSystem` surface draws one of the shell's own faces instead of the shell, once the `islandSystemFaces` setting maps
that face to the plugin (`{"volume": "<pluginId>"}`). Both are optional; neither works for a plugin listed in the
`islandPluginsBlocked` setting.

An `island` object describes them. Everything is optional.

```json
"island": {
    "notifyApp": "Spotify",
    "systemFaces": ["volume", "charging"]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `notifyApp` | string | The app whose do not disturb exceptions apply to the plugin's activity (default: the plugin's id) |
| `systemFaces` | string[] | The shell faces its `islandSystem` surface can draw |

## Complete Example

```json
{
    "id": "myPlugin",
    "name": "My Plugin",
    "description": "A sample plugin demonstrating all fields",
    "version": "1.0.0",
    "author": "Developer Name",
    "type": "widget",
    "capabilities": ["dankbar-widget", "control-center"],
    "component": "./MyWidget.qml",
    "icon": "extension",
    "settings": "./Settings.qml",
    "startupCheck": "./StartupCheck.qml",
    "requires_dms": ">=0.1.18",
    "dependencies": ["curl", "jq"],
    "permissions": ["settings_read", "settings_write", "process", "network"]
}
```

## Launcher Example

```json
{
    "id": "myLauncher",
    "name": "My Launcher",
    "description": "Search and execute custom actions",
    "version": "1.0.0",
    "author": "Developer Name",
    "type": "launcher",
    "capabilities": ["launcher"],
    "component": "./MyLauncher.qml",
    "trigger": "#",
    "icon": "search",
    "settings": "./Settings.qml",
    "requires_dms": ">=0.1.18",
    "permissions": ["settings_read", "settings_write"]
}
```

## JSON Schema

The complete JSON schema is available at `assets/plugin-schema.json` in this skill. Validate with:

```bash
# Using python
python3 -c "
import json, jsonschema
schema = json.load(open('path/to/plugin-schema.json'))
manifest = json.load(open('plugin.json'))
jsonschema.validate(manifest, schema)
print('Valid!')
"

# Using jq (syntax check only)
jq . plugin.json
```

## Additional Properties

The schema allows additional properties (`"additionalProperties": true`), so plugins can include custom fields. Common custom fields seen in production plugins:

- `viewMode` - launcher display mode (`"tile"` for image grids)
- `viewModeEnforced` - lock launcher to specific view mode (`true`/`false`)
