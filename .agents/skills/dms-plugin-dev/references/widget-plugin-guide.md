# Widget Plugin Guide

Widgets display pills in DankBar and in docks (same component, no extra code), optionally open popouts, and can integrate with the Control Center.

## Base Component

Widgets use `PluginComponent` from `qs.Modules.Plugins`.

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    property var popoutService: null

    horizontalBarPill: Component { /* ... */ }
    verticalBarPill: Component { /* ... */ }
    popoutContent: Component { /* ... */ }
    popoutWidth: 400
    popoutHeight: 300
}
```

## Injected Properties

These are automatically set by the plugin host:

| Property | Type | Description |
|----------|------|-------------|
| `axis` | object | Bar axis info (horizontal/vertical) |
| `section` | string | Bar section: `"left"`, `"center"`, or `"right"` |
| `parentScreen` | object | Screen reference for multi-monitor |
| `widgetThickness` | real | Widget size perpendicular to bar edge |
| `barThickness` | real | Bar thickness parallel to edge |
| `pluginId` | string | This plugin's ID |
| `pluginService` | object | PluginService reference |
| `pluginData` | object | Reactive plugin settings data |
| `surfaceContext` | object | The host surface: `kind` (`"bar"` or `"dock"`), `id`, `screen`, `isVertical`, `thickness`, `live`, `editMode`, `inlineExpansion` |
| `widgetInstanceId` | string | This occurrence; the same widget can appear on several bars and docks |

## Bar Pills

Define `horizontalBarPill` (for top/bottom bars) and `verticalBarPill` (for left/right bars).

### Horizontal Bar Pill

```qml
horizontalBarPill: Component {
    StyledRect {
        width: content.implicitWidth + Theme.spacingM * 2
        height: parent.widgetThickness
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

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
}
```

### Vertical Bar Pill

```qml
verticalBarPill: Component {
    StyledRect {
        width: parent.widgetThickness
        height: content.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: content
            anchors.centerIn: parent
            spacing: Theme.spacingS

            DIcon {
                name: "star"
                color: Theme.surfaceText
                font.pixelSize: Theme.iconSizeSmall
            }
        }
    }
}
```

**Important:** Always define both pills. If a pill is missing, the widget disappears when the bar is on that orientation's edge.

## Popout Content

Open a popout window when the bar pill is clicked:

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
                    font.pixelSize: Theme.fontSizeMedium
                }
            }
        }
    }
}
```

**PopoutComponent properties:**

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `headerText` | string | `""` | Main header (bold, large). Hidden if empty. |
| `detailsText` | string | `""` | Subtitle below header. Hidden if empty. |
| `closePopout` | function | (injected) | Call to close the popout programmatically. |
| `headerHeight` | int | (readonly) | Height of header area (0 if hidden). |
| `detailsHeight` | int | (readonly) | Height of details area (0 if hidden). |

**Content sizing:** Content children render below the header/details. Calculate available height: `popoutHeight - headerHeight - detailsHeight - spacing`

## Custom Click Actions

Override the default popout behavior:

```qml
PluginComponent {
    // Simple no-args handler
    pillClickAction: () => {
        popoutService?.toggleControlCenter()
    }

    // With position params (x, y, width, section, screen)
    pillClickAction: (x, y, width, section, screen) => {
        popoutService?.toggleControlCenter(x, y, width, section, screen)
    }

    pillRightClickAction: () => {
        popoutService?.openSettings()
    }
}
```

## Control Center Integration

Add CC properties to show your widget in the Control Center grid:

```qml
PluginComponent {
    ccWidgetIcon: "toggle_on"
    ccWidgetPrimaryText: "Feature Name"
    ccWidgetSecondaryText: isActive ? "Active" : "Off"
    ccWidgetIsActive: isActive

    onCcWidgetToggled: {
        isActive = !isActive
        pluginService?.savePluginData(pluginId, "active", isActive)
    }
}
```

**CC properties:**

| Property | Type | Description |
|----------|------|-------------|
| `ccWidgetIcon` | string | Material icon name |
| `ccWidgetPrimaryText` | string | Main label |
| `ccWidgetSecondaryText` | string | Subtitle / status text |
| `ccWidgetIsActive` | bool | Active state (changes styling) |

**CC signals:**

| Signal | When fired |
|--------|-----------|
| `ccWidgetToggled()` | Icon area clicked |
| `ccWidgetExpanded()` | Expand area clicked (CompoundPill only) |

**CC sizing rules:**
- 25% width - SmallToggleButton (icon only)
- 50% width - ToggleButton (no detail) or CompoundPill (with ccDetailContent)
- Users can resize in CC edit mode

### Detail Content (CompoundPill)

Add an expandable panel below the CC widget:

```qml
ccDetailContent: Component {
    Rectangle {
        implicitHeight: 200
        color: Theme.surfaceContainerHigh
        radius: Theme.cornerRadius

        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            // Detail UI here
        }
    }
}
```

## Visibility Control

Conditionally show/hide the bar pill:

```qml
PluginComponent {
    visibilityCommand: "pgrep -x myapp"
    visibilityInterval: 5  // seconds between checks
}
```

**Bar reveal optimization:** The visibility timer automatically pauses while the bar is hidden (auto-hide mode) and resumes checks when the bar is revealed. This is handled via the internal `_barRevealed` property - no plugin code needed. Plugins using `visibilityCommand` with `visibilityInterval` benefit from this automatically.

## Docks

Users add any loaded widget plugin to a dock from the dock's edit mode or Settings > Dock > Apps & widgets. Nothing in the manifest is needed.

- Define both `horizontalBarPill` and `verticalBarPill`; docks sit on any edge.
- Size icons with `root.iconSize` and text with `Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)`. The dock hands its own thickness and scale in those properties.
- Gate timers and animations on `surfaceLive` (host visible and `visibilityCommand` passing). Docks auto-hide.
- Don't assume one instance. Use `widgetInstanceId` if an instance needs its own state.

Optional attached panel: set `attachedContent: Component { ... }`. When the dock's "Open widgets" setting is Inline (`surfaceContext.inlineExpansion`), a click grows the dock and shows the panel next to the apps. With Popout (the default) the normal `popoutContent` opens instead; a widget with no popout still expands inline. Bars always use `popoutContent`. A `pillClickAction` always wins over both.

```qml
PluginComponent {
    id: root

    attachedContent: Component {
        Column {
            padding: Theme.spacingM
            spacing: Theme.spacingM

            DButton {
                text: I18n.trFor("myPlugin", "Close")
                onClicked: root.surfaceContext.dismissExpansion()
            }
        }
    }
}
```

The panel spans the dock's length and grows up to 320 px away from the edge (at most half the screen). The plugin cannot size it. `attachedActive` is true while this widget owns the panel. Escape closes it. See `quickshell/PLUGINS/AttachedPanelExample` and `quickshell/PLUGINS/SURFACE_WIDGETS.md`.

## Popout Namespace

For plugins with multiple popout instances, use `layerNamespacePlugin` to isolate popout state:

```qml
PluginComponent {
    layerNamespacePlugin: "my-plugin"
}
```

The shell prefixes it, so the popout's namespace becomes `dms:plugins:my-plugin`.

## Reading Plugin Data

Access saved settings reactively via the injected `pluginData`:

```qml
PluginComponent {
    property string displayText: pluginData?.text || "Default"

    Connections {
        target: pluginService
        function onPluginDataChanged(changedId) {
            if (changedId === pluginId)
                displayText = pluginService.loadPluginData(pluginId, "text", "Default")
        }
    }
}
```

## Complete Example

Based on the ExampleEmojiPlugin pattern:

```qml
import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root
    property var popoutService: null

    property var emojis: ["star", "heart", "smile"]
    property int currentIndex: 0

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: currentIndex = (currentIndex + 1) % emojis.length
    }

    popoutWidth: 350
    popoutHeight: 400

    horizontalBarPill: Component {
        StyledRect {
            width: label.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            StyledText {
                id: label
                anchors.centerIn: parent
                text: root.emojis[root.currentIndex]
                font.pixelSize: Theme.fontSizeLarge
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
                text: root.emojis[root.currentIndex]
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            headerText: "Emoji Picker"

            DGridView {
                width: parent.width
                height: 300
                cellWidth: 50
                cellHeight: 50
                model: root.emojis

                delegate: Rectangle {
                    width: 48
                    height: 48
                    radius: Theme.cornerRadius
                    color: mouseArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: 24
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            Quickshell.execDetached(["dms", "cl", "copy", modelData])
                            ToastService?.showInfo("Copied " + modelData)
                        }
                    }
                }
            }
        }
    }
}
```
