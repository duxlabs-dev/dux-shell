# Popout Control Example Plugin

This example plugin demonstrates:
- Using `PopoutService` to trigger positioned popouts and modals
- Using `pillClickAction` with position parameters
- Using `PluginSettings` with dropdown selection
- Dynamic widget text based on settings

The `pillClickAction` receives position parameters `(x, y, width, section, screen)` which are passed to PopoutService functions to properly position popouts relative to the widget.

## PopoutService API

The `PopoutService` is automatically injected into plugin widgets and daemons as `popoutService`. It provides access to all shell popouts and modals.

### Available Popouts

#### Control Center
```qml
popoutService.openControlCenter()
popoutService.closeControlCenter()
popoutService.toggleControlCenter()
```

#### Notification Center
```qml
popoutService.openNotificationCenter()
popoutService.closeNotificationCenter()
popoutService.toggleNotificationCenter()
```

#### App Drawer
```qml
popoutService.openAppDrawer()
popoutService.closeAppDrawer()
popoutService.toggleAppDrawer()
```

#### Process List (Popout)
```qml
popoutService.openProcessList()
popoutService.closeProcessList()
popoutService.toggleProcessList()
```

#### DankDash
```qml
popoutService.openDankDash(tabIndex)    // tabIndex: 0=Calendar, 1=Media, 2=Weather
popoutService.closeDankDash()
popoutService.toggleDankDash(tabIndex)
```

#### Battery Popout
```qml
popoutService.openBattery()
popoutService.closeBattery()
popoutService.toggleBattery()
```

#### VPN Popout
```qml
popoutService.openVpn()
popoutService.closeVpn()
popoutService.toggleVpn()
```

#### System Update Popout
```qml
popoutService.openSystemUpdate()
popoutService.closeSystemUpdate()
popoutService.toggleSystemUpdate()
```

### Available Modals

#### Settings Modal
```qml
popoutService.openSettings()
popoutService.closeSettings()
```

#### Clipboard History Modal
```qml
popoutService.openClipboardHistory()
popoutService.closeClipboardHistory()
```

#### Launcher Modal
```qml
popoutService.openDankLauncherV2()
popoutService.closeDankLauncherV2()
popoutService.toggleDankLauncherV2()
```

#### Power Menu Modal
```qml
popoutService.openPowerMenu()
popoutService.closePowerMenu()
popoutService.togglePowerMenu()
```

#### Process List Modal (fullscreen)
```qml
popoutService.showProcessListModal()
popoutService.hideProcessListModal()
popoutService.toggleProcessListModal()
```

#### Color Picker Modal
```qml
popoutService.showColorPicker()
popoutService.hideColorPicker()
```

#### Notification Modal
```qml
popoutService.showNotificationModal()
popoutService.hideNotificationModal()
```

#### WiFi Password Modal
```qml
popoutService.showWifiPasswordModal()
popoutService.hideWifiPasswordModal()
```

#### Network Info Modal
```qml
popoutService.showNetworkInfoModal()
popoutService.hideNetworkInfoModal()
```

#### Notepad Slideout
```qml
popoutService.openNotepad()
popoutService.closeNotepad()
popoutService.toggleNotepad()
```

## Usage in Plugins

### Widget Plugins

```qml
import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property var popoutService: null  // REQUIRED: Must declare for injection

    MouseArea {
        anchors.fill: parent
        onClicked: {
            popoutService?.toggleControlCenter()
        }
    }
}
```

### Daemon Plugins

```qml
import QtQuick
import qs.Services

Item {
    id: root

    property var popoutService: null  // REQUIRED: Must declare for injection

    Connections {
        target: NotificationService
        function onNotificationReceived() {
            popoutService?.openNotificationCenter()
        }
    }
}
```

**Important**: The `popoutService` property **must** be declared in your plugin component. Without it, you'll get errors like:
```
Error: Cannot assign to non-existent property "popoutService"
```

## Example Use Cases

1. **Custom Launcher**: Create a widget that opens the app drawer
2. **Quick Settings**: Toggle control center from a custom button
3. **Notification Manager**: Open notification center on new notifications
4. **System Monitor**: Open process list on high CPU usage
5. **Power Management**: Trigger power menu from a custom widget

## Installation

1. Copy the plugin directory to `~/.config/dms/plugins/`
2. Open Settings → Plugins
3. Click "Scan for Plugins"
4. Enable "Popout Control Example"
5. Add `popoutControlExample` to your DankBar widget list

## Notes

- The `popoutService` property is automatically injected - no manual setup required
- Always use optional chaining (`?.`) when calling methods to handle null cases
- Popouts are lazily loaded - first access may activate the loader
- Some popouts require specific system features to be available
