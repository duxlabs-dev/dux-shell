# PopoutService for Plugins

## Overview

The `PopoutService` singleton provides plugins with access to all Dux Shell popouts and modals. It's automatically injected into plugin widgets and daemons, enabling them to control shell UI elements.

## Automatic Injection

The `popoutService` property is automatically injected into:

- Widget plugins (loaded in DankBar)
- Daemon plugins (background services)
- Plugin settings components

**Required**: Declare the property in your plugin component:

```qml
property var popoutService: null
```

**Note**: Without this declaration, the service cannot be injected and you'll see errors like `Cannot assign to non-existent property "popoutService"`

## API Reference

### Popouts (DankPopout-based)

| Component           | Open                       | Close                       | Toggle                       |
| ------------------- | -------------------------- | --------------------------- | ---------------------------- |
| Control Center      | `openControlCenter()`      | `closeControlCenter()`      | `toggleControlCenter()`      |
| Notification Center | `openNotificationCenter()` | `closeNotificationCenter()` | `toggleNotificationCenter()` |
| App Drawer          | `openAppDrawer()`          | `closeAppDrawer()`          | `toggleAppDrawer()`          |
| Process List        | `openProcessList()`        | `closeProcessList()`        | `toggleProcessList()`        |
| DankDash            | `openDankDash(tab)`        | `closeDankDash()`           | `toggleDankDash(tab)`        |
| Battery             | `openBattery()`            | `closeBattery()`            | `toggleBattery()`            |
| VPN                 | `openVpn()`                | `closeVpn()`                | `toggleVpn()`                |
| System Update       | `openSystemUpdate()`       | `closeSystemUpdate()`       | `toggleSystemUpdate()`       |

### Modals (DankModal-based)

| Modal              | Show                      | Hide                      | Notes                                              |
| ------------------ | ------------------------- | ------------------------- | -------------------------------------------------- |
| Settings           | `openSettings()`          | `closeSettings()`         | Full settings interface                            |
| Clipboard History  | `openClipboardHistory()`  | `closeClipboardHistory()` | Clipboard integration                              |
| Launcher           | `openDankLauncherV2()`       | `closeDankLauncherV2()`      | Command launcher, also has `toggleDankLauncherV2()`   |
| Power Menu         | `openPowerMenu()`         | `closePowerMenu()`        | Also has `togglePowerMenu()`                       |
| Process List Modal | `showProcessListModal()`  | `hideProcessListModal()`  | Fullscreen version, has `toggleProcessListModal()` |
| Color Picker       | `showColorPicker()`       | `hideColorPicker()`       | Theme color selection                              |
| Notification       | `showNotificationModal()` | `hideNotificationModal()` | Notification details                               |
| WiFi Password      | `showWifiPasswordModal()` | `hideWifiPasswordModal()` | Network authentication                             |
| Network Info       | `showNetworkInfoModal()`  | `hideNetworkInfoModal()`  | Network details                                    |

### Slideouts

| Component | Open            | Close            | Toggle            |
| --------- | --------------- | ---------------- | ----------------- |
| Notepad   | `openNotepad()` | `closeNotepad()` | `toggleNotepad()` |

## Usage Examples

### Simple Widget with Popout Control

```qml
import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property var popoutService: null

    width: 100
    height: 30
    color: Theme.chipSurface
    radius: Theme.cornerRadius

    MouseArea {
        anchors.fill: parent
        onClicked: popoutService?.toggleControlCenter()
    }

    StyledText {
        anchors.centerIn: parent
        text: "Settings"
    }
}
```

### Daemon with Event-Driven Popouts

```qml
import QtQuick
import qs.Services

Item {
    id: root

    property var popoutService: null

    Connections {
        target: NotificationService

        function onNotificationReceived(notification) {
            if (notification.urgency === "critical") {
                popoutService?.openNotificationCenter()
            }
        }
    }

    Connections {
        target: BatteryService

        function onPercentageChanged() {
            if (BatteryService.percentage < 10 && !BatteryService.isCharging) {
                popoutService?.openBattery()
            }
        }
    }
}
```

### Widget with Multiple Popout Options

```qml
import QtQuick
import QtQuick.Controls
import qs.Common

Rectangle {
    property var popoutService: null

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                contextMenu.popup()
            } else {
                popoutService?.toggleControlCenter()
            }
        }
    }

    Menu {
        id: contextMenu

        MenuItem {
            text: "Settings"
            onClicked: popoutService?.openSettings()
        }

        MenuItem {
            text: "Notifications"
            onClicked: popoutService?.toggleNotificationCenter()
        }

        MenuItem {
            text: "Power Menu"
            onClicked: popoutService?.openPowerMenu()
        }
    }
}
```

## Implementation Details

### Service Architecture

`PopoutService` is a singleton that holds references to popout instances:

```qml
// Services/PopoutService.qml
Singleton {
    id: root

    property var controlCenterPopout: null
    property var notificationCenterPopout: null
    // ... other popout references

    function toggleControlCenter() {
        controlCenterPopout?.toggle()
    }
    // ... other control functions
}
```

### Reference Assignment

References are assigned in `DMSShell.qml` when popouts are loaded:

```qml
LazyLoader {
    ControlCenterPopout {
        id: controlCenterPopout

        Component.onCompleted: {
            PopoutService.controlCenterPopout = controlCenterPopout
        }
    }
}
```

### Plugin Injection

The service is injected in three locations:

1. **DMSShell.qml** (daemon plugins):

```qml
Instantiator {
    delegate: Loader {
        onLoaded: {
            if (item) {
                item.popoutService = PopoutService
            }
        }
    }
}
```

2. **WidgetHost.qml** (widget plugins):

```qml
onLoaded: {
    if (item.popoutService !== undefined) {
        item.popoutService = PopoutService
    }
}
```

3. **CenterSection.qml** (center widgets):

```qml
onLoaded: {
    if (item.popoutService !== undefined) {
        item.popoutService = PopoutService
    }
}
```

4. **PluginsTab.qml** (settings):

```qml
onLoaded: {
    if (item && typeof PopoutService !== "undefined") {
        item.popoutService = PopoutService
    }
}
```

## Best Practices

1. **Use Optional Chaining**: Always use `?.` to handle null cases

   ```qml
   popoutService?.toggleControlCenter()
   ```

2. **Check Availability**: Some popouts may not be available

   ```qml
   if (popoutService && popoutService.controlCenterPopout) {
       popoutService.toggleControlCenter()
   }
   ```

3. **Lazy Loading**: First access may activate lazy loaders - this is normal

4. **Feature Detection**: Some popouts require specific features

   ```qml
   if (BatteryService.batteryAvailable) {
       popoutService?.openBattery()
   }
   ```

5. **User Intent**: Only trigger popouts based on user actions or critical events

## Example Plugin

See `PLUGINS/PopoutControlExample/` for a complete working example that demonstrates:

- Widget creation with popout controls
- Menu-based popout selection
- Proper service usage
- Error handling

## Limitations

- Popouts are shared across all plugins - avoid conflicts
- Some popouts may be compositor or feature-dependent
- Lazy-loaded popouts need activation before use
- Multi-monitor considerations apply to positioned popouts
