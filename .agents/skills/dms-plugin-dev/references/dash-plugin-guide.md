# Dash Plugin Guide

The dash popout (`dms ipc call dash open`) holds tabs and an overview grid of cards. A plugin can add a tab (`dash` surface), a card (`dashCard` surface), or both. Built-in tabs and cards use the same registry (`quickshell/Modules/DankDash/DashRegistry.qml`).

Requires DMS 1.7 or later: set `"requires_dms": ">=1.7.0"`.

## Picking the manifest form

| Plugin provides | Manifest |
|-----------------|----------|
| Tab only | `"type": "dash"`, `"component": "./Tab.qml"` |
| Card only | `"type": "dashCard"`, `"component": "./Card.qml"` |
| Tab and card | `"type": "composite"`, `"components": { "dash": ..., "dashCard": ... }` |
| Dash plus bar/dock widget, daemon, ... | `"type": "composite"` with every surface in `components` |

Add the optional `dash` block for labels, card size and options (see plugin-manifest-reference.md, Dash Block).

## Rules that trip people up

- Only enabled plugins appear in the dash. There is no "disabled" placeholder.
- A plugin tab shows in the tab bar as soon as the plugin loads. Cards are never placed automatically; users add them in edit mode (three-dot menu, Edit, Add widget).
- Tab id is `plugin_<pluginId>`. Use it with `dms ipc call dash open plugin_<pluginId>` and `popoutService.toggleDankDash("plugin_" + pluginId, x, y, width, section, screen)`.
- A tab is created when it becomes current and destroyed when the user leaves it. The dash content stays alive after the popout closes, so gate every Timer, animation and service ref on `live`.
- Widths are grid columns (user picks 3 to 8, default 6). Rows are 96 px (`DashMetrics.gridRowUnit`). Cards must lay out for every size in `minW..maxW` x `minH..maxH`.
- `dash.options` values reach only the dash surfaces as `options.<key>`. A bar widget or daemon in the same plugin cannot read them; use a `settings` component and `pluginData` for values every surface needs.
- `widgets` is a reserved option key.
- Use `I18n.trFor("<plugin id literal>", "...")` for every string.

## Tab: DashTabComponent

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DankDash

DashTabComponent {
    id: root

    focusTarget: button
    implicitHeight: Math.max(DashMetrics.tabMinHeight, content.implicitHeight + Theme.spacingL * 2)
    menuActions: [
        {
            label: I18n.trFor("myPlugin", "Refresh"),
            iconName: "refresh",
            action: () => root.refresh()
        }
    ]

    function refresh() {
    }

    function restoreFocus() {
        button.forceActiveFocus(Qt.OtherFocusReason);
    }

    function handleKeyEvent(event) {
        if (event.key !== Qt.Key_R)
            return false;
        refresh();
        return true;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.live
        onTriggered: root.refresh()
    }

    Column {
        id: content
        anchors.centerIn: parent
        spacing: Theme.spacingM

        StyledText {
            text: root.options.compact ? "" : I18n.trFor("myPlugin", "Hello")
            color: Theme.surfaceText
        }

        DButton {
            id: button
            text: I18n.trFor("myPlugin", "Refresh")
            onClicked: root.refresh()
        }
    }
}
```

Injected: `pluginId`, `pluginService`, `popoutService`, `entryId`, `dashHost` (`dashVisible`, `requestTab(id)`, `editMode`), `editMode`, `live`. Also `targetScreen`, `active` and `rowBudget` when the tab declares them.

Base provides: `options`, `pluginData`, `getData(key, def)`, `setData(key, value)`.

Optional: `implicitHeight`, `focusTarget`, `restoreFocus()`, `handleKeyEvent(event)` (return true to consume; Tab, Ctrl+Tab, F6 and Ctrl+PgUp/PgDown are reserved), `blocksTabNavigation`, `menuActions`, `signal tabRequested(string id)`, `signal navFocusRequested`.

For tiles inside a tab, use `Card` from `qs.Modules.DankDash.Overview` so colors, radius and tones match the overview.

### Editable widgets in a tab

Assign a `DashWidgetGrid` (from `qs.Modules.DankDash`) to `widgetGrid` to get Edit, Add widget, Reset and Clear All:

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
            { id: "main", text: I18n.trFor("myPlugin", "Main"), icon: "star", component: mainWidget, w: 2, h: 2, minW: 1, minH: 1, maxW: 4, maxH: 3 }
        ]
    }

    Component {
        id: mainWidget
        Card {}
    }
}
```

The grid is 4 columns (2 when narrower than `Theme.smallBreakpoint`). `enabled: false` on a definition leaves it in the Add menu. The layout is saved in `dashOptions[entryId].widgets`.

## Card: DashCardComponent

```qml
import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Modules.DankDash

DashCardComponent {
    id: root

    readonly property bool wide: width >= DashMetrics.gridRowUnit * 2
    readonly property bool tall: height >= DashMetrics.gridRowUnit * 2

    tone: options.tone ?? ""

    SystemClock {
        id: clock
        enabled: root.live
        precision: SystemClock.Minutes
    }

    StyledText {
        anchors.centerIn: parent
        text: clock.date.toLocaleTimeString(I18n.locale(), "hh:mm")
        font.pixelSize: root.tall ? Theme.fontSizeDisplay : Theme.fontSizeXLarge
        color: root.accentColor
    }
}
```

Base (`Card`) provides: `pad`, `title`, `tone` (`""`, `"primary"`, `"secondary"`, `"tertiary"`), `containerColor`, `contentColor`, `accentColor`, `onAccentColor`, `mutedColor`, `chipColor`, `tinted`, `clickable`, `signal clicked`, `options`, `pluginData`, `getData`, `setData`.

Injected: `pluginId`, `pluginService`, `popoutService`, `entryId`; bound: `live` (overview visible), `interactive` (false in edit mode).

Clicks: when the plugin also has a tab, a click on a `clickable` card opens it. Set `opensTab: false` to handle the click yourself. Non-clickable cards are skipped by keyboard navigation unless `focusTarget` points at a child control.

Use the card colors, never raw `Theme.primary` or `Theme.surfaceText`, so tones work.

## Testing

```bash
dms ipc call plugins reload myPlugin
dms ipc call dash open plugin_myPlugin
```

Working examples in `quickshell/PLUGINS/`: `DashTabExample` (standalone tab), `DashCardExample` (standalone card), `DashCounterExample` (tab + card + bar/dock widget).
