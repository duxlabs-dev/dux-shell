# Advanced Patterns

Patterns observed in production DMS plugins that go beyond the basics.

## Plugin Variants

Create multiple widget instances from a single plugin definition. Each variant has its own configuration.

### Manifest

No special manifest changes needed - the variant system is built into PluginComponent.

### Widget with Variant Support

```qml
PluginComponent {
    property string variantId: ""
    property var variantData: ({})

    property string displayText: variantData?.text || "Default"

    horizontalBarPill: Component {
        StyledRect {
            width: label.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness

            StyledText {
                id: label
                anchors.centerIn: parent
                text: root.displayText
            }
        }
    }
}
```

Widget format in bar config: `pluginId:variantId` (e.g., `exampleVariants:variant_1234567890`)

### Settings with Variant Management

```qml
PluginSettings {
    pluginId: "exampleVariants"

    // Variant creation UI
    DButton {
        text: "Add New Instance"
        onClicked: {
            var id = "variant_" + Date.now()
            root.createVariant(id, { name: "New Instance", text: "Hello" })
        }
    }

    // Per-variant configuration
    Repeater {
        model: root.variants
        delegate: Column {
            StringSetting {
                settingKey: modelData.id + "_text"
                label: modelData.name || modelData.id
            }
        }
    }
}
```

## JavaScript Utility Files

For complex logic, split into `.js` files:

### utils.js

```javascript
.pragma library

function formatDuration(ms) {
    if (ms < 60000) return "just now"
    if (ms < 3600000) return Math.floor(ms / 60000) + "m ago"
    return Math.floor(ms / 3600000) + "h ago"
}

function parseResponse(json) {
    try {
        return JSON.parse(json)
    } catch (e) {
        return null
    }
}
```

### Using in QML

```qml
import "utils.js" as Utils

Item {
    StyledText {
        text: Utils.formatDuration(Date.now() - timestamp)
    }
}
```

The `.pragma library` directive makes the JS file a shared singleton - it is loaded once and shared across all QML instances that import it.

## qmldir for Singleton Services

For plugins with internal singleton services:

### qmldir

```
singleton MyService 1.0 MyService.qml
```

### MyService.qml

```qml
pragma Singleton
import QtQuick

QtObject {
    property var cache: ({})

    function getData(key) {
        return cache[key] || null
    }

    function setData(key, value) {
        cache[key] = value
    }
}
```

### Using the singleton

```qml
import "." as Local

Item {
    Component.onCompleted: {
        Local.MyService.setData("key", "value")
    }
}
```

## Inline Component Declarations

Reusable sub-components defined inline:

```qml
Item {
    component StatusBadge: Rectangle {
        property string label: ""
        property color badgeColor: Theme.primary

        width: badgeText.implicitWidth + Theme.spacingM * 2
        height: 24
        radius: 12
        color: badgeColor

        StyledText {
            id: badgeText
            anchors.centerIn: parent
            text: label
            color: Theme.onPrimary
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    Row {
        spacing: Theme.spacingS
        StatusBadge { label: "Running"; badgeColor: Theme.success }
        StatusBadge { label: "Stopped"; badgeColor: Theme.error }
    }
}
```

## Multi-Provider Adapter Pattern

For plugins supporting multiple backends (AI providers, API services):

### apiAdapters.js

```javascript
.pragma library

function createAdapter(provider) {
    switch (provider) {
        case "openai": return {
            url: "https://api.openai.com/v1/chat/completions",
            headers: (key) => ({ "Authorization": "Bearer " + key }),
            formatRequest: (messages) => JSON.stringify({ model: "gpt-4", messages: messages }),
            parseResponse: (text) => JSON.parse(text).choices[0].message.content
        }
        case "anthropic": return {
            url: "https://api.anthropic.com/v1/messages",
            headers: (key) => ({ "x-api-key": key, "anthropic-version": "2023-06-01" }),
            formatRequest: (messages) => JSON.stringify({ model: "claude-sonnet-4-20250514", messages: messages }),
            parseResponse: (text) => JSON.parse(text).content[0].text
        }
        default: return null
    }
}
```

## IPC Integration

For plugins that respond to keyboard shortcuts or external commands:

```qml
PluginComponent {
    Connections {
        target: DMSIpc
        function onCommandReceived(command, args) {
            if (command === "myPlugin.toggle") {
                doToggle()
            } else if (command === "myPlugin.next") {
                goNext()
            }
        }
    }
}
```

External trigger: `dms ipc call myPlugin.toggle`

## Networking with Quickshell.Networking

For API calls using the built-in networking module:

```qml
import Quickshell.Networking

Item {
    NetworkRequest {
        id: request
        url: "https://api.example.com/data"
        method: "GET"

        onResponseReceived: (response) => {
            const data = JSON.parse(response.body)
            processData(data)
        }

        onErrorOccurred: (error) => {
            console.error("Network error:", error)
        }
    }

    function fetchData() {
        request.send()
    }
}
```

## Toast Notifications

Show user feedback:

```qml
import qs.Services

// Info toast
ToastService?.showInfo("Operation completed")

// With title
ToastService?.showInfo("Plugin Name", "Data refreshed successfully")
```

Always use optional chaining since ToastService may not be available in all contexts.

## Clipboard Operations

```qml
import Quickshell

function copyToClipboard(text) {
    Quickshell.execDetached(["dms", "cl", "copy", text])
    ToastService?.showInfo("Copied to clipboard")
}
```

Do NOT use `globalThis.clipboard`, `navigator.clipboard`, or any browser API - they do not exist in the QML runtime.

## Multi-File Plugin Architecture

Large plugins can be split across multiple files:

```
MyPlugin/
  plugin.json
  Main.qml           # Main widget component
  Settings.qml       # Settings UI
  DetailView.qml     # Popout detail view
  utils.js            # Utility functions
  apiAdapter.js       # API adapter layer
  qmldir              # Optional: singleton registrations
```

Import sibling files:

```qml
// In Main.qml
import "." as Local

Item {
    Loader {
        source: "DetailView.qml"
    }
}
```

## Performance Tips

1. Use `Proc.runCommand` with appropriate debounce for external commands
2. Pre-cache images and thumbnails for image-heavy plugins
3. Limit concurrent network requests
4. Use `Timer` with reasonable intervals (don't poll faster than needed)
5. Lazy-load heavy content (use `Loader` for complex popout content)
6. Avoid blocking the UI thread with synchronous operations
