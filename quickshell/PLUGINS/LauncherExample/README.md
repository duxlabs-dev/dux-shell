# LauncherExample Plugin

A demonstration plugin that showcases the DMS launcher plugin system capabilities.

## Purpose

This plugin serves as a comprehensive example for developers creating launcher plugins for DMS. It demonstrates:

- **Plugin Structure**: Proper manifest, launcher, and settings components
- **Trigger System**: Customizable trigger strings for plugin activation (including empty triggers)
- **Item Management**: Providing searchable items to the launcher
- **Action Execution**: Handling different types of actions (toast, copy, script)
- **Settings Integration**: Configurable plugin settings with persistence

## Features

### Example Items
- **Test Items 1-3**: Demonstrate toast notifications
- **Copy Action**: Shows clipboard integration
- **Script Action**: Demonstrates command execution

### Trigger System
- **Default Trigger**: `#` (configurable in settings)
- **Empty Trigger Option**: Items can always be visible without needing a trigger
- **Usage**: Type `#` in launcher to filter to this plugin (when trigger is set)
- **Search**: Type `# test` to search within plugin items

### Action Types
- `toast:message` - Shows toast notification
- `copy:text` - Copies text to clipboard
- `script:command` - Executes shell command (demo only)

## File Structure

```
PLUGINS/LauncherExample/
├── plugin.json                    # Plugin manifest
├── LauncherExampleLauncher.qml    # Main launcher component
├── LauncherExampleSettings.qml    # Settings interface
└── README.md                      # This documentation
```

## Installation

1. **Plugin Directory**: Copy to `~/.config/dms/plugins/LauncherExample`
2. **Enable Plugin**: Settings → Plugins → Enable "LauncherExample"
3. **Configure**: Set custom trigger in plugin settings if desired

## Usage

### With Trigger (Default)
1. Open launcher (Ctrl+Space or launcher button)
2. Type `#` to activate plugin trigger
3. Browse available items or add search terms
4. Press Enter to execute selected item

### Without Trigger (Empty Trigger Mode)
1. Enable "No trigger (always show)" in plugin settings
2. Open launcher - plugin items are always visible
3. Search works normally with plugin items included
4. Press Enter to execute selected item

### Search Examples
- `#` - Show all plugin items (with trigger enabled)
- `# test` - Show items matching "test"
- `# copy` - Show items matching "copy"
- `test` - Show all items matching "test" (with empty trigger enabled)

## Developer Guide

### Plugin Contract

**Launcher Component Requirements**:
```qml
// Required properties
property var pluginService: null
property string trigger: "#"

// Required signals
signal itemsChanged()

// Required functions
function getItems(query): array
function executeItem(item): void

// Optional functions (for Shift+Enter paste support)
function getPasteText(item): string|null
function getPasteArgs(item): array|null
```

**Item Structure**:
```javascript
{
    name: "Item Name",           // Display name
    icon: "icon_name",           // Icon (optional, see Icon Types below)
    comment: "Description",      // Subtitle text
    action: "type:data",         // Action to execute
    categories: ["PluginName"]   // Category array
}
```

**Icon Types**:

The `icon` field supports four formats:

1. **Material Design Icons** - Use `material:` prefix:
   ```javascript
   icon: "material:lightbulb"  // Material Symbols Rounded font
   ```
   Examples: `material:star`, `material:favorite`, `material:settings`

2. **Unicode/Emoji Icons** - Use `unicode:` prefix:
   ```javascript
   icon: "unicode:🚀"  // Unicode character or emoji
   ```
   Display any Unicode character or emoji as the icon. Examples: `unicode:😀`, `unicode:⚡`, `unicode:🎨`

3. **Desktop Theme Icons** - Use icon name directly:
   ```javascript
   icon: "firefox"  // Uses system icon theme
   ```
   Examples: `firefox`, `chrome`, `folder`, `text-editor`

4. **No Icon** - Omit the `icon` field entirely:
   ```javascript
   {
       name: "😀  Grinning Face",
       // No icon field
       comment: "Copy emoji",
       action: "copy:😀",
       categories: ["MyPlugin"]
   }
   ```
   When icon is omitted, the launcher hides the icon area and displays only text

**Action Format**: `type:data` where:
- `type` - Action handler (toast, copy, script, etc.)
- `data` - Action-specific data

### Settings Integration
```qml
// Save setting
pluginService.savePluginData("pluginId", "key", value)

// Load setting
pluginService.loadPluginData("pluginId", "key", defaultValue)
```

### Trigger Configuration

The trigger can be configured in two ways:

1. **Empty Trigger** (No Trigger Mode):
   - Check "No trigger (always show)" in settings
   - Saves `trigger: ""` and `noTrigger: true`
   - Items always appear in launcher alongside regular apps

2. **Custom Trigger**:
   - Enter any string (e.g., `#`, `!`, `@`, `!ex`)
   - Uncheck "No trigger" checkbox
   - Items only appear when trigger is typed

### Manifest Structure
```json
{
    "id": "launcherExample",
    "name": "LauncherExample",
    "type": "launcher",
    "capabilities": ["launcher"],
    "component": "./LauncherExampleLauncher.qml",
    "settings": "./LauncherExampleSettings.qml",
    "permissions": ["settings_read", "settings_write"]
}
```

Note: The `trigger` field in the manifest is optional and serves as the default trigger value.

## Extending This Plugin

### Adding New Items
```qml
function getItems(query) {
    return [
        {
            name: "My Item",
            icon: "custom_icon",
            comment: "Does something cool",
            action: "custom:action_data",
            categories: ["LauncherExample"]
        }
    ]
}
```

### Adding New Actions
```qml
function executeItem(item) {
    const actionParts = item.action.split(":")
    const actionType = actionParts[0]
    const actionData = actionParts.slice(1).join(":")

    switch (actionType) {
        case "custom":
            handleCustomAction(actionData)
            break
    }
}
```

### Custom Trigger Logic
```qml
Component.onCompleted: {
    if (pluginService) {
        trigger = pluginService.loadPluginData("launcherExample", "trigger", "#")
    }
}

onTriggerChanged: {
    if (pluginService) {
        pluginService.savePluginData("launcherExample", "trigger", trigger)
    }
}
```

## Best Practices

1. **Unique Triggers**: Choose triggers that don't conflict with other plugins
2. **Clear Descriptions**: Write helpful item comments
3. **Error Handling**: Gracefully handle action failures
4. **Performance**: Return results quickly in getItems()
5. **Cleanup**: Destroy temporary objects in executeItem()
6. **Empty Trigger Support**: Consider if your plugin should support empty trigger mode

## Testing

Test the plugin by:
1. Installing and enabling in DMS
2. Testing with trigger enabled
3. Testing with empty trigger (no trigger mode)
4. Trying each action type
5. Testing search functionality
6. Verifying settings persistence

This plugin provides a solid foundation for building more sophisticated launcher plugins with custom functionality!
