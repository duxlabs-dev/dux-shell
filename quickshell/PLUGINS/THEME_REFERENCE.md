# Theme Property Reference for Plugins

Quick reference for commonly used Theme properties in plugin development.

## Font Sizes

```qml
Theme.fontSizeSmall     // 12px (scaled)
Theme.fontSizeMedium    // 14px (scaled)
Theme.fontSizeLarge     // 16px (scaled)
Theme.fontSizeXLarge    // 20px (scaled)
```

**Note**: These are scaled by `SettingsData.fontScale`

## Icon Sizes

```qml
Theme.iconSizeSmall     // 16px
Theme.iconSize          // 24px (default)
Theme.iconSizeLarge     // 32px
```

## Spacing

```qml
Theme.spacingXS         // Extra small
Theme.spacingS          // Small
Theme.spacingM          // Medium
Theme.spacingL          // Large
Theme.spacingXL         // Extra large
```

## Border Radius

`Theme.radiusStrength` ranges from 0 to 100, with the Material baseline at 50. `Theme.cornerRadius` aliases `Theme.cornerRadiusM`. Small and large aliases use S and L.

```qml
Theme.cornerRadiusXS
Theme.cornerRadiusS
Theme.cornerRadiusM
Theme.cornerRadiusL
Theme.cornerRadiusLIncreased
Theme.cornerRadiusXL
Theme.cornerRadiusXLIncreased
Theme.cornerRadiusXXL
Theme.fullRadius(width, height)
Theme.buttonRadius(width, height, buttonHeight, pressed, true)
```

Use `fullRadius()` for pills and round controls so lower strength values reduce their rounding. `cornerRadiusFull` remains available for compatibility. See the shared [shape reference](../../dux-qml-common/SHAPES.md) for component baselines.

`Theme.buttonRadius(...)` follows the Interface style setting: Classic turns off pills and the press morph. Plugins that hand-roll control shapes can read `Theme.pillControls` and `Theme.shapeMorph` (both false in Classic).

## Colors

### Surface Colors
Pick the tier by what the surface sits on: a host floats over the desktop, a card sits in a host, a chip in a card, a nested chip in a chip.
```qml
Theme.hostSurface        // popout, desktop widget or panel background
Theme.cardSurface        // card inside a host
Theme.chipSurface        // chip, row or field inside a card
Theme.chipSurfaceNested  // chip inside a chip
```

Each tier follows the user's surface overrides; the raw `Theme.surfaceContainer*` palette does not, so keep it for swatches and previews. Plugin settings already sit on a card, so their boxes start at `chipSurface`. Wrap fills in `Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))` so they follow the foreground toggle and opacity. Outer floating windows use `Theme.floatingWindowSurface`. Pass raw surface colors to shared text fields; those widgets apply foreground opacity themselves. These roles need DMS 1.7 or newer, so set `"requires_dms": ">=1.7.0"` when you use them.

### Text Colors
```qml
Theme.onSurface         // Primary text on surface
Theme.onSurfaceVariant  // Secondary text on surface
Theme.outline           // Border/divider color
```

### Semantic Colors
```qml
Theme.primary
Theme.onPrimary
Theme.secondary
Theme.secondaryContainer
Theme.onSecondaryContainer
Theme.error
Theme.warning
Theme.success
```

### Special Functions
```qml
Theme.withAlpha(Theme.primary, Theme.stateLayerHover)
Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
```

## Common Patterns

### Icon with Text
```qml
DIcon {
    name: "icon_name"
    color: Theme.onSurface
    font.pixelSize: Theme.iconSize
}

StyledText {
    text: "Label"
    color: Theme.onSurface
    font.pixelSize: Theme.fontSizeMedium
}
```

### Container with Border
```qml
Rectangle {
    color: Theme.cardSurface
    radius: Theme.cornerRadius
    border.color: Theme.outlineVariant
    border.width: Theme.outlineWidth
}
```

### Hover Effect
`StateLayer` draws the hover, press and ripple layers over its parent and takes clicks.
```qml
Rectangle {
    color: Theme.chipSurface
    radius: Theme.cornerRadius

    StateLayer {
        anchors.fill: parent
        onClicked: root.activate()
    }
}
```

## Common Mistakes

❌ **Wrong**:
```qml
font.pixelSize: Theme.fontSizeS      // Property doesn't exist
font.pixelSize: Theme.iconSizeS       // Property doesn't exist
```

✅ **Correct**:
```qml
font.pixelSize: Theme.fontSizeSmall   // Use full name
font.pixelSize: Theme.iconSizeSmall   // Use full name
```

## Checking Available Properties

To see all available Theme properties, check `Common/Theme.qml` or use:

```bash
grep "property" Common/Theme.qml
```
