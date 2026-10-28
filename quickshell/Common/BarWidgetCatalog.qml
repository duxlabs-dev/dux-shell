pragma Singleton

import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root

    readonly property var widgets: [
        {
            "id": "layout",
            "text": I18n.tr("Layout"),
            "description": I18n.tr("Display and switch MangoWC layouts"),
            "icon": "view_quilt",
            "section": "left"
        },
        {
            "id": "launcherButton",
            "text": I18n.tr("App launcher"),
            "description": I18n.tr("Quick access to application launcher"),
            "icon": "apps",
            "section": "left"
        },
        {
            "id": "workspaceSwitcher",
            "text": I18n.tr("Workspace switcher"),
            "description": I18n.tr("Shows current workspace and allows switching"),
            "icon": "view_module",
            "section": "left"
        },
        {
            "id": "focusedWindow",
            "text": I18n.tr("Focused window"),
            "description": I18n.tr("Display currently focused application title"),
            "icon": "window",
            "section": "left"
        },
        {
            "id": "runningApps",
            "text": I18n.tr("Running apps"),
            "description": I18n.tr("Shows all running applications with focus indication"),
            "icon": "apps",
            "section": "left"
        },
        {
            "id": "appsDock",
            "text": I18n.tr("Apps dock"),
            "description": I18n.tr("Pinned and running apps with drag-and-drop"),
            "icon": "dock_to_bottom",
            "section": "left"
        },
        {
            "id": "island",
            "text": I18n.tr("Island"),
            "description": I18n.tr("Live activities that grow out of the bar", "bar widget catalog: island widget description"),
            "icon": "blur_on",
            "section": "center",
            "single": true,
            "barOnly": true
        },
        {
            "id": "clock",
            "text": I18n.tr("Clock"),
            "description": I18n.tr("Current time and date display"),
            "icon": "schedule",
            "section": "center"
        },
        {
            "id": "weather",
            "text": I18n.tr("Weather"),
            "description": I18n.tr("Current weather conditions and temperature"),
            "icon": "wb_sunny",
            "section": "center"
        },
        {
            "id": "music",
            "text": I18n.tr("Media"),
            "description": I18n.tr("Now playing and media controls"),
            "icon": "music_note",
            "section": "center"
        },
        {
            "id": "clipboard",
            "text": I18n.tr("Clipboard manager"),
            "description": I18n.tr("Access clipboard history"),
            "icon": "content_paste",
            "section": "right"
        },
        {
            "id": "cpuUsage",
            "text": I18n.tr("CPU usage"),
            "description": I18n.tr("CPU usage indicator"),
            "icon": "memory",
            "section": "right"
        },
        {
            "id": "memUsage",
            "text": I18n.tr("Memory usage"),
            "description": I18n.tr("Memory usage indicator"),
            "icon": "developer_board",
            "section": "right"
        },
        {
            "id": "diskUsage",
            "text": I18n.tr("Disk usage"),
            "description": I18n.tr("Percentage"),
            "icon": "storage",
            "section": "right"
        },
        {
            "id": "cpuTemp",
            "text": I18n.tr("CPU temperature"),
            "description": I18n.tr("CPU temperature display"),
            "icon": "device_thermostat",
            "section": "right"
        },
        {
            "id": "gpuTemp",
            "text": I18n.tr("GPU temperature"),
            "description": I18n.tr("GPU temperature display"),
            "icon": "auto_awesome_mosaic",
            "section": "right"
        },
        {
            "id": "systemTray",
            "text": I18n.tr("System tray"),
            "description": I18n.tr("System notification area icons"),
            "icon": "notifications",
            "section": "right"
        },
        {
            "id": "privacyIndicator",
            "text": I18n.tr("Privacy indicator"),
            "description": I18n.tr("Shows when microphone, camera, or screen sharing is active"),
            "icon": "privacy_tip",
            "section": "right"
        },
        {
            "id": "controlCenterButton",
            "text": I18n.tr("Control Center"),
            "description": I18n.tr("Access to system controls and settings"),
            "icon": "settings",
            "section": "right"
        },
        {
            "id": "notificationButton",
            "text": I18n.tr("Notification Center"),
            "description": I18n.tr("Access to notifications and do not disturb"),
            "icon": "notifications",
            "section": "right"
        },
        {
            "id": "battery",
            "text": I18n.tr("Battery"),
            "description": I18n.tr("Battery and power management"),
            "icon": "battery_std",
            "section": "right"
        },
        {
            "id": "vpn",
            "text": I18n.tr("VPN", "virtual private network, widget and page title"),
            "description": I18n.tr("VPN status and quick connect"),
            "icon": "vpn_lock",
            "section": "right"
        },
        {
            "id": "idleInhibitor",
            "text": I18n.tr("Idle inhibitor", "feature that keeps the session from going idle"),
            "description": I18n.tr("Prevent screen timeout"),
            "icon": "local_cafe",
            "section": "right"
        },
        {
            "id": "capsLockIndicator",
            "text": I18n.tr("Caps Lock indicator"),
            "description": I18n.tr("Shows when caps lock is active"),
            "icon": "shift_lock",
            "section": "right"
        },
        {
            "id": "spacer",
            "text": I18n.tr("Spacer", "bar widget name, empty space between widgets"),
            "description": I18n.tr("Customizable empty space"),
            "icon": "more_horiz",
            "section": "right"
        },
        {
            "id": "separator",
            "text": I18n.tr("Separator", "bar widget name, visual divider between widgets"),
            "description": I18n.tr("Visual divider between widgets"),
            "icon": "remove",
            "section": "right"
        },
        {
            "id": "network_speed_monitor",
            "text": I18n.tr("Network speed monitor"),
            "description": I18n.tr("Network download and upload speed display"),
            "icon": "network_check",
            "section": "right"
        },
        {
            "id": "keyboard_layout_name",
            "text": I18n.tr("Keyboard layout"),
            "description": I18n.tr("Displays the active keyboard layout and allows switching"),
            "icon": "keyboard",
            "section": "right"
        },
        {
            "id": "notepadButton",
            "text": I18n.tr("Notepad"),
            "description": I18n.tr("Quick access to notepad"),
            "icon": "assignment",
            "section": "right"
        },
        {
            "id": "colorPicker",
            "text": I18n.tr("Color Picker"),
            "description": I18n.tr("Quick access to color picker"),
            "icon": "palette",
            "section": "right"
        },
        {
            "id": "systemUpdate",
            "text": I18n.tr("System update"),
            "description": I18n.tr("Check for system updates"),
            "icon": "update",
            "section": "right"
        },
        {
            "id": "powerMenuButton",
            "text": I18n.tr("Power", "noun, power menu widget name, shutdown and reboot actions"),
            "description": I18n.tr("Display the power system menu"),
            "icon": "power_settings_new",
            "section": "right"
        }
    ]

    readonly property var optionFiles: ({
            "launcherButton": "LauncherButtonOptions.qml",
            "workspaceSwitcher": "WorkspaceSwitcherOptions.qml",
            "clock": "ClockOptions.qml",
            "music": "MusicOptions.qml",
            "focusedWindow": "FocusedWindowOptions.qml",
            "runningApps": "RunningAppsOptions.qml",
            "appsDock": "AppsDockOptions.qml",
            "systemTray": "SystemTrayOptions.qml",
            "battery": "BatteryOptions.qml",
            "controlCenterButton": "ControlCenterOptions.qml",
            "privacyIndicator": "PrivacyOptions.qml",
            "keyboard_layout_name": "KeyboardLayoutOptions.qml",
            "cpuUsage": "SystemMonitorOptions.qml",
            "cpuTemp": "SystemMonitorOptions.qml",
            "memUsage": "SystemMonitorOptions.qml",
            "gpuTemp": "SystemMonitorOptions.qml",
            "diskUsage": "SystemMonitorOptions.qml",
            "network_speed_monitor": "NetworkMonitorOptions.qml",
            "systemUpdate": "SystemUpdateOptions.qml",
            "island": "IslandOptions.qml"
        })

    function get(id) {
        return widgets.find(widget => widget.id === id) ?? null;
    }

    function optionsFile(id) {
        return optionFiles[id] ?? "";
    }

    function hasOptions(id) {
        return optionFiles[id] !== undefined;
    }

    // Every widget reaches the general options page (placement); spacers and separators configure inline on their row.
    function configurable(item) {
        return !!item?.pluginId || !["spacer", "separator"].includes(item?.id);
    }
}
