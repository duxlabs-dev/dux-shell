# Data Persistence Guide

DMS plugins have three tiers of data persistence, each suited for different use cases.

## Tier 1: Plugin Data (Settings)

Persisted to `settings.json`. Use for user preferences and configuration.

### Saving

```qml
pluginService.savePluginData(pluginId, "key", value)
```

### Loading

```qml
var value = pluginService.loadPluginData(pluginId, "key", defaultValue)
```

### Reactive Access via pluginData

`PluginComponent` has a reactive `pluginData` property that auto-loads from settings:

```qml
PluginComponent {
    property string displayText: pluginData?.text || "Default"
    property bool showIcon: pluginData?.showIcon !== undefined ? pluginData.showIcon : true
}
```

### Reacting to Settings Changes

When settings are changed (e.g., from the settings UI), react with `Connections`:

```qml
Connections {
    target: pluginService
    function onPluginDataChanged(changedId) {
        if (changedId !== pluginId) return
        displayText = pluginService.loadPluginData(pluginId, "text", "Default")
        showIcon = pluginService.loadPluginData(pluginId, "showIcon", true)
    }
}
```

## Tier 2: Plugin State

Persisted to a separate state file. Use for runtime state that should survive restarts but is not user-configurable (history, cache, counters).

### Saving

```qml
pluginService.savePluginState(pluginId, "key", value)
```

### Loading

```qml
var state = pluginService.loadPluginState(pluginId, "key", defaultValue)
```

### Additional Methods

```qml
pluginService.clearPluginState(pluginId)
pluginService.removePluginStateKey(pluginId, "key")
```

### Example: Persistent History

```qml
Item {
    property var history: []

    Component.onCompleted: {
        history = pluginService?.loadPluginState(pluginId, "history", []) || []
    }

    function addToHistory(entry) {
        history.unshift({
            text: entry,
            timestamp: Date.now()
        })
        if (history.length > 100) history = history.slice(0, 100)
        pluginService?.savePluginState(pluginId, "history", history)
    }

    function clearHistory() {
        history = []
        pluginService?.removePluginStateKey(pluginId, "history")
    }
}
```

## Tier 3: Global Variables (Runtime Only)

NOT persisted. Shared across all instances of a plugin. Use for cross-instance state synchronization (multi-monitor consistency, multi-instance widgets).

### Using PluginGlobalVar Component

```qml
import qs.Modules.Plugins

PluginComponent {
    PluginGlobalVar {
        id: globalCounter
        varName: "counter"
        defaultValue: 0
    }

    horizontalBarPill: Component {
        StyledRect {
            // ...
            StyledText {
                text: "Count: " + globalCounter.value
            }

            MouseArea {
                onClicked: globalCounter.set(globalCounter.value + 1)
            }
        }
    }
}
```

**PluginGlobalVar properties:**

| Property | Type | Description |
|----------|------|-------------|
| `varName` | string | Required: name of the global variable |
| `defaultValue` | any | Optional: default if not set |
| `value` | any | Readonly: current value |

**Methods:**
- `set(newValue)` - update the value (triggers reactivity across all instances)

### Using PluginService API Directly

```qml
import qs.Services

property int counter: PluginService.getGlobalVar("myPlugin", "counter", 0)

Connections {
    target: PluginService
    function onGlobalVarChanged(pluginId, varName) {
        if (pluginId === "myPlugin" && varName === "counter") {
            counter = PluginService.getGlobalVar("myPlugin", "counter", 0)
        }
    }
}

function increment() {
    var current = PluginService.getGlobalVar("myPlugin", "counter", 0)
    PluginService.setGlobalVar("myPlugin", "counter", current + 1)
}
```

## Decision Matrix

| Need | API | Persisted | Scope |
|------|-----|-----------|-------|
| User preferences (API keys, themes, intervals) | `savePluginData` / `loadPluginData` | Yes (settings.json) | Per plugin |
| Runtime state (history, cache, counters) | `savePluginState` / `loadPluginState` | Yes (state file) | Per plugin |
| Cross-instance sync (multi-monitor data) | `PluginGlobalVar` or `getGlobalVar`/`setGlobalVar` | No (runtime only) | All instances |
| Quick reactive reads from settings | `pluginData` property | N/A (read-only) | Per instance |

## Plugin Path

Retrieve a plugin's installation directory at runtime:

```qml
var dir = pluginService.getPluginPath(pluginId)
```

Returns the absolute path to the plugin's directory (e.g., `~/.config/dms/plugins/MyPlugin`), or an empty string if the plugin is not found. Useful for loading bundled assets (images, data files) relative to the plugin's location.

## Important Notes

1. **pluginData is reactive** - bindings update automatically when data changes
2. **Global vars are NOT persistent** - they reset when the shell restarts
3. **State vs Data** - data is for user-facing settings, state is for internal runtime data
4. **Null safety** - always check `pluginService` is not null before calling methods
5. **Signal namespacing** - global var signals include `pluginId` to filter for your plugin
6. **Performance** - global vars are efficient for frequent updates; settings writes are batched
