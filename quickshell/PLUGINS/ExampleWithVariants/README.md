# Example with Variants Plugin

This plugin demonstrates the dynamic variant system for Dux Shell plugins.

## What are Variants?

Variants allow a single plugin to create multiple widget instances with different configurations. Each variant appears as a separate widget option in the Bar Settings "Add Widget" menu.

## How It Works

### Plugin Architecture

1. **Single Component**: The plugin defines one widget component (`VariantWidget.qml`)
2. **Variant Data**: Each variant stores its configuration in plugin settings
3. **Dynamic Creation**: Variants are created through the plugin's settings UI
4. **Widget ID Format**: Variants use the format `pluginId:variantId` (e.g., `exampleVariants:variant_1234567890`)

### Widget Properties

Each variant widget receives:
- `pluginService`: Reference to PluginService
- `pluginId`: The base plugin ID (e.g., "exampleVariants")
- `variantId`: The specific variant ID (e.g., "variant_1234567890")
- `variantData`: The variant's configuration object

### Variant Configuration

This example stores:
```javascript
{
    id: "variant_1234567890",
    name: "My Variant",
    text: "Display Text",
    icon: "star",
    color: "#FF5722"
}
```

## Creating Your Own Variant Plugin

### 1. Widget Component

Create a widget that accepts variant data:

```qml
Rectangle {
    property var pluginService: null
    property string pluginId: ""
    property string variantId: ""
    property var variantData: null

    // Use variantData for configuration
    property string displayText: variantData?.text || "Default"
}
```

### 2. Settings Component

Provide UI to manage variants:

```qml
FocusScope {
    property var pluginService: null

    // Create variant
    pluginService.createPluginVariant(pluginId, variantName, variantConfig)

    // Remove variant
    pluginService.removePluginVariant(pluginId, variantId)

    // Update variant
    pluginService.updatePluginVariant(pluginId, variantId, variantConfig)

    // Get all variants
    var variants = pluginService.getPluginVariants(pluginId)
}
```

### 3. Plugin Manifest

Standard plugin manifest - no special configuration needed:

```json
{
    "id": "yourPlugin",
    "name": "Your Plugin",
    "component": "./Widget.qml",
    "settings": "./Settings.qml"
}
```

## Use Cases

- **Script Runner**: Multiple variants running different scripts
- **System Monitors**: Different monitoring targets (CPU, GPU, Network)
- **Quick Launchers**: Different apps or commands per variant
- **Custom Indicators**: Different data sources or APIs
- **Time Zones**: Multiple clocks for different time zones

## API Reference

### PluginService Functions

- `getPluginVariants(pluginId)`: Get all variants for a plugin
- `getAllPluginVariants()`: Get all variants across all plugins
- `createPluginVariant(pluginId, name, config)`: Create new variant
- `removePluginVariant(pluginId, variantId)`: Delete variant
- `updatePluginVariant(pluginId, variantId, config)`: Update variant
- `getPluginVariantData(pluginId, variantId)`: Get specific variant data

### Widget Properties

- `pluginId`: Base plugin identifier
- `variantId`: Variant identifier (null if no variant)
- `variantData`: Variant configuration object
- `pluginService`: PluginService reference
