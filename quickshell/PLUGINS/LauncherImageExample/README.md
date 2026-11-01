# LauncherImageExample

Example launcher plugin demonstrating tile mode with URL-based images.

## Features

- **Tile Mode**: Uses `viewMode: "tile"` in plugin.json to display results as image tiles
- **Enforced View Mode**: Uses `viewModeEnforced: true` to lock the view to tile mode (users cannot change it)
- **URL Images**: Demonstrates using `imageUrl` property for remote images

## Usage

1. Open the launcher (DankLauncherV2)
2. Type `img` to activate the plugin
3. Browse Dux Shell screenshots in tile view

## Plugin Configuration

```json
{
  "viewMode": "tile",
  "viewModeEnforced": true
}
```

- `viewMode`: Sets the default view mode ("list", "grid", or "tile")
- `viewModeEnforced`: When true, users cannot switch view modes for this plugin

## Item Data Structure

To display images in tile mode, set `imageUrl` directly on the item:

```javascript
{
    name: "Image Title",
    icon: "material:image",
    comment: "Image description",
    categories: ["Category"],
    imageUrl: "https://example.com/image.png"
}
```

The `imageUrl` property supports remote URLs or local files, use `file://` prefix for local files.
