# Theme Property Reference

All theme properties are accessed via the `Theme` singleton from `qs.Common`. Always use these instead of hardcoded values.

## Font Sizes

```qml
Theme.fontSizeSmall     // 12px (scaled by SettingsData.fontScale)
Theme.fontSizeMedium    // 14px (scaled)
Theme.fontSizeLarge     // 16px (scaled)
Theme.fontSizeXLarge    // 20px (scaled)
```

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

```qml
Theme.cornerRadius      // Standard
Theme.cornerRadiusSmall // Smaller
Theme.cornerRadiusLarge // Larger
```

## Surface Colors

```qml
Theme.surface
Theme.surfaceContainerLow
Theme.surfaceContainer
Theme.surfaceContainerHigh
Theme.surfaceContainerHighest
```

## Text Colors

```qml
Theme.onSurface          // Primary text on surface
Theme.onSurfaceVariant   // Secondary text on surface
Theme.surfaceText        // Alias for primary surface text
Theme.surfaceVariantText // Alias for secondary surface text
Theme.outline            // Border/divider color
```

## Semantic Colors

```qml
Theme.primary
Theme.onPrimary
Theme.secondary
Theme.onSecondary
Theme.error
Theme.errorHover
Theme.errorText
Theme.warning
Theme.success
```

## Special Functions

```qml
Theme.popupBackground()  // Popup background with proper opacity
```

## Common Widget Patterns

### Icon with Text

```qml
import qs.Widgets
import qs.DCommon.Widgets

Row {
    spacing: Theme.spacingS

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
}
```

### Container with Border

```qml
Rectangle {
    color: Theme.surfaceContainerHigh
    radius: Theme.cornerRadius
    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.08)
    border.width: 1
}
```

### Hover Effect

```qml
Rectangle {
    id: container
    color: Theme.surfaceContainerHigh

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: container.color = Qt.lighter(Theme.surfaceContainerHigh, 1.1)
        onExited: container.color = Theme.surfaceContainerHigh
    }
}
```

### Clickable Pill

```qml
StyledRect {
    width: content.implicitWidth + Theme.spacingM * 2
    height: parent.widgetThickness
    radius: Theme.cornerRadius
    color: mouseArea.containsMouse
        ? Qt.lighter(Theme.surfaceContainerHigh, 1.1)
        : Theme.surfaceContainerHigh

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.spacingS

        DIcon {
            name: "star"
            color: Theme.surfaceText
            font.pixelSize: Theme.iconSize
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: "Label"
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
```

## Common Mistakes

**Wrong property names** (these do NOT exist):
```qml
Theme.fontSizeS        // Use Theme.fontSizeSmall
Theme.iconSizeS        // Use Theme.iconSizeSmall
Theme.spacingSmall     // Use Theme.spacingS
Theme.borderRadius     // Use Theme.cornerRadius
```

**Hardcoded values** (do NOT do this):
```qml
color: "#1e1e1e"       // Use Theme.surfaceContainerHigh
color: "white"         // Use Theme.surfaceText
font.pixelSize: 14     // Use Theme.fontSizeMedium
```

## Available Widgets from qs.Widgets

| Widget | Description |
|--------|-------------|
| `StyledText` | Themed text with proper color defaults |
| `StyledRect` | Themed rectangle |
| `DIcon` | Material Symbols icon renderer |
| `DankNFIcon` | Nerd Font icon renderer |
| `DButton` | Themed button |
| `DToggle` | Toggle switch |
| `DTextField` | Text input field |
| `DSlider` | Slider control |
| `DDropdown` | Dropdown menu |
| `DGridView` | Grid layout view |
| `DListView` | List layout view |
| `DFlickable` | Scrollable container |
| `DTabBar` | Tab bar navigation |
| `DankCollapsibleSection` | Collapsible content section |
| `DankTooltip` | Hover tooltip |
| `DankNumberStepper` | Number +/- control |
| `DankFilterChips` | Filter chip row |
| `CachingImage` | Image with disk cache |
| `NumericText` | Fixed-width numeric display |

## Checking All Properties

```bash
grep "property" Common/Theme.qml
```
