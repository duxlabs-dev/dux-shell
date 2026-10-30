.pragma library

const ACTION_TYPES = [
    {
        id: "dms",
        label: "DMS Action",
        icon: "widgets"
    },
    {
        id: "compositor",
        label: "Compositor",
        icon: "desktop_windows"
    },
    {
        id: "spawn",
        label: "Run Command",
        icon: "terminal"
    },
    {
        id: "shell",
        label: "Shell Command",
        icon: "code"
    }
];

const DMS_ACTIONS = [
    {
        id: "spawn dms ipc call spotlight toggle",
        label: "Default Launcher: Toggle"
    },
    {
        id: "spawn dms ipc call spotlight open",
        label: "Default Launcher: Open"
    },
    {
        id: "spawn dms ipc call spotlight close",
        label: "Default Launcher: Close"
    },
    {
        id: "spawn dms ipc call island toggle home",
        label: "DankIsland: Toggle"
    },
    {
        id: "spawn dms ipc call island open home",
        label: "DankIsland: Open Clock"
    },
    {
        id: "spawn dms ipc call island open media",
        label: "DankIsland: Open Media"
    },
    {
        id: "spawn dms ipc call island toggle media",
        label: "DankIsland: Toggle Media"
    },
    {
        id: "spawn dms ipc call island open launcher",
        label: "DankIsland: Open Launcher"
    },
    {
        id: "spawn dms ipc call island open controlcenter",
        label: "DankIsland: Open Control Center"
    },
    {
        id: "spawn dms ipc call island open wallpaper",
        label: "DankIsland: Open Wallpapers"
    },
    {
        id: "spawn dms ipc call island open weather",
        label: "DankIsland: Open Weather"
    },
    {
        id: "spawn dms ipc call island open notificationcenter",
        label: "DankIsland: Open Notification Center"
    },
    {
        id: "spawn dms ipc call island cycle",
        label: "DankIsland: Cycle Activity"
    },
    {
        id: "spawn dms ipc call island close",
        label: "DankIsland: Close"
    },
    {
        id: "spawn dms ipc call dot toggle home",
        label: "DankDot: Toggle"
    },
    {
        id: "spawn dms ipc call dot open home",
        label: "DankDot: Open Clock"
    },
    {
        id: "spawn dms ipc call dot open media",
        label: "DankDot: Open Media"
    },
    {
        id: "spawn dms ipc call dot open launcher",
        label: "DankDot: Open Launcher"
    },
    {
        id: "spawn dms ipc call dot open controlcenter",
        label: "DankDot: Open Control Center"
    },
    {
        id: "spawn dms ipc call dot open wallpaper",
        label: "DankDot: Open Wallpapers"
    },
    {
        id: "spawn dms ipc call dot open weather",
        label: "DankDot: Open Weather"
    },
    {
        id: "spawn dms ipc call dot open notificationcenter",
        label: "DankDot: Open Notification Center"
    },
    {
        id: "spawn dms ipc call dot cycle",
        label: "DankDot: Cycle Activity"
    },
    {
        id: "spawn dms ipc call dot close",
        label: "DankDot: Close"
    },
    {
        id: "spawn dms ipc call defaultApp browser",
        label: "Default Web Browser: Open"
    },
    {
        id: "spawn dms ipc call defaultApp fileManager",
        label: "Default File Manager: Open"
    },
    {
        id: "spawn dms ipc call defaultApp mail",
        label: "Default Mail: Open"
    },
    {
        id: "spawn dms ipc call defaultApp calendar",
        label: "Default Calendar: Open"
    },
    {
        id: "spawn dms ipc call defaultApp textEditor",
        label: "Default Text Editor: Open"
    },
    {
        id: "spawn dms ipc call defaultApp pdfReader",
        label: "Default PDF Reader: Open"
    },
    {
        id: "spawn dms ipc call defaultApp imageViewer",
        label: "Default Image Viewer: Open"
    },
    {
        id: "spawn dms ipc call defaultApp videoPlayer",
        label: "Default Video Player: Open"
    },
    {
        id: "spawn dms ipc call defaultApp musicPlayer",
        label: "Default Music Player: Open"
    },
    {
        id: "spawn dms ipc call spotlight-bar toggle",
        label: "Spotlight Bar: Toggle"
    },
    {
        id: "spawn dms ipc call spotlight-bar open",
        label: "Spotlight Bar: Open"
    },
    {
        id: "spawn dms ipc call spotlight-bar close",
        label: "Spotlight Bar: Close"
    },
    {
        id: "spawn dms ipc call clipboard toggle",
        label: "Clipboard: Toggle"
    },
    {
        id: "spawn dms ipc call clipboard open",
        label: "Clipboard: Open"
    },
    {
        id: "spawn dms ipc call clipboard close",
        label: "Clipboard: Close"
    },
    {
        id: "spawn dms ipc call notifications toggle",
        label: "Notifications: Toggle"
    },
    {
        id: "spawn dms ipc call notifications open",
        label: "Notifications: Open"
    },
    {
        id: "spawn dms ipc call notifications close",
        label: "Notifications: Close"
    },
    {
        id: "spawn dms ipc call processlist toggle",
        label: "Task Manager: Toggle"
    },
    {
        id: "spawn dms ipc call processlist open",
        label: "Task Manager: Open"
    },
    {
        id: "spawn dms ipc call processlist close",
        label: "Task Manager: Close"
    },
    {
        id: "spawn dms ipc call processlist focusOrToggle",
        label: "Task Manager: Focus or Toggle"
    },
    {
        id: "spawn dms ipc call settings toggle",
        label: "Settings: Toggle"
    },
    {
        id: "spawn dms ipc call settings open",
        label: "Settings: Open"
    },
    {
        id: "spawn dms ipc call settings close",
        label: "Settings: Close"
    },
    {
        id: "spawn dms ipc call settings focusOrToggle",
        label: "Settings: Focus or Toggle"
    },
    {
        id: "spawn dms ipc call powermenu toggle",
        label: "Power Menu: Toggle"
    },
    {
        id: "spawn dms ipc call powermenu open",
        label: "Power Menu: Open"
    },
    {
        id: "spawn dms ipc call powermenu close",
        label: "Power Menu: Close"
    },
    {
        id: "spawn dms ipc call control-center toggle",
        label: "Control Center: Toggle"
    },
    {
        id: "spawn dms ipc call control-center open",
        label: "Control Center: Open"
    },
    {
        id: "spawn dms ipc call control-center close",
        label: "Control Center: Close"
    },
    {
        id: "spawn dms ipc call notepad toggle",
        label: "Notepad: Toggle"
    },
    {
        id: "spawn dms ipc call notepad open",
        label: "Notepad: Open"
    },
    {
        id: "spawn dms ipc call notepad close",
        label: "Notepad: Close"
    },
    {
        id: "spawn dms ipc call notepad expand",
        label: "Notepad: Expand"
    },
    {
        id: "spawn dms ipc call notepad collapse",
        label: "Notepad: Collapse"
    },
    {
        id: "spawn dms ipc call notepad toggleExpand",
        label: "Notepad: Toggle Expand"
    },
    {
        id: "spawn dms ipc call dash toggle \"\"",
        label: "Dashboard: Toggle"
    },
    {
        id: "spawn dms ipc call dash open overview",
        label: "Dashboard: Overview"
    },
    {
        id: "spawn dms ipc call dash open media",
        label: "Dashboard: Media"
    },
    {
        id: "spawn dms ipc call dash open weather",
        label: "Dashboard: Weather"
    },
    {
        id: "spawn dms ipc call dash open wellbeing",
        label: "Dashboard: Digital Wellbeing"
    },
    {
        id: "spawn dms ipc call dankdash wallpaper",
        label: "Wallpaper Browser"
    },
    {
        id: "spawn dms ipc call file browse wallpaper",
        label: "File: Browse Wallpaper"
    },
    {
        id: "spawn dms ipc call file browse profile",
        label: "File: Browse Profile"
    },
    {
        id: "spawn dms ipc call color-picker toggle",
        label: "Color Picker: Toggle"
    },
    {
        id: "spawn dms ipc call color-picker open",
        label: "Color Picker: Open"
    },
    {
        id: "spawn dms ipc call color-picker close",
        label: "Color Picker: Close"
    },
    {
        id: "spawn dms ipc call keybinds toggle niri",
        label: "Keybinds Cheatsheet: Toggle",
        compositor: "niri"
    },
    {
        id: "spawn dms ipc call keybinds open niri",
        label: "Keybinds Cheatsheet: Open",
        compositor: "niri"
    },
    {
        id: "spawn dms ipc call keybinds close",
        label: "Keybinds Cheatsheet: Close"
    },
    {
        id: "spawn dms ipc call lock lock",
        label: "Lock Screen"
    },
    {
        id: "spawn dms ipc call lock lockAndOutputsOff",
        label: "Lock Screen & Outputs Off"
    },
    {
        id: "spawn dms ipc call lock demo",
        label: "Lock Screen: Demo"
    },
    {
        id: "spawn dms ipc call inhibit toggle",
        label: "Idle Inhibit: Toggle"
    },
    {
        id: "spawn dms ipc call inhibit enable",
        label: "Idle Inhibit: Enable"
    },
    {
        id: "spawn dms ipc call inhibit disable",
        label: "Idle Inhibit: Disable"
    },
    {
        id: "spawn dms ipc call audio increment 5",
        label: "Volume Up"
    },
    {
        id: "spawn dms ipc call audio increment 1",
        label: "Volume Up (1%)"
    },
    {
        id: "spawn dms ipc call audio increment 5",
        label: "Volume Up (5%)"
    },
    {
        id: "spawn dms ipc call audio increment 10",
        label: "Volume Up (10%)"
    },
    {
        id: "spawn dms ipc call audio decrement 5",
        label: "Volume Down"
    },
    {
        id: "spawn dms ipc call audio decrement 1",
        label: "Volume Down (1%)"
    },
    {
        id: "spawn dms ipc call audio decrement 5",
        label: "Volume Down (5%)"
    },
    {
        id: "spawn dms ipc call audio decrement 10",
        label: "Volume Down (10%)"
    },
    {
        id: "spawn dms ipc call mpris increment 5",
        label: "Player Volume Up (5%)"
    },
    {
        id: "spawn dms ipc call mpris decrement 5",
        label: "Player Volume Down (5%)"
    },
    {
        id: "spawn dms ipc call audio mute",
        label: "Volume Mute Toggle"
    },
    {
        id: "spawn dms ipc call mic mute",
        label: "Microphone Mute Toggle"
    },
    {
        id: "spawn dms ipc call audio cycleoutput",
        label: "Audio Output: Cycle"
    },
    {
        id: "spawn dms ipc call brightness increment 5 \"\"",
        label: "Brightness Up"
    },
    {
        id: "spawn dms ipc call brightness increment 1 \"\"",
        label: "Brightness Up (1%)"
    },
    {
        id: "spawn dms ipc call brightness increment 5 \"\"",
        label: "Brightness Up (5%)"
    },
    {
        id: "spawn dms ipc call brightness increment 10 \"\"",
        label: "Brightness Up (10%)"
    },
    {
        id: "spawn dms ipc call brightness decrement 5 \"\"",
        label: "Brightness Down"
    },
    {
        id: "spawn dms ipc call brightness decrement 1 \"\"",
        label: "Brightness Down (1%)"
    },
    {
        id: "spawn dms ipc call brightness decrement 5 \"\"",
        label: "Brightness Down (5%)"
    },
    {
        id: "spawn dms ipc call brightness decrement 10 \"\"",
        label: "Brightness Down (10%)"
    },
    {
        id: "spawn dms ipc call brightness toggleExponential \"\"",
        label: "Brightness: Toggle Exponential"
    },
    {
        id: "spawn dms ipc call theme toggle",
        label: "Theme: Toggle Light/Dark"
    },
    {
        id: "spawn dms ipc call theme light",
        label: "Theme: Light Mode"
    },
    {
        id: "spawn dms ipc call theme dark",
        label: "Theme: Dark Mode"
    },
    {
        id: "spawn dms ipc call night toggle",
        label: "Night Mode: Toggle"
    },
    {
        id: "spawn dms ipc call night enable",
        label: "Night Mode: Enable"
    },
    {
        id: "spawn dms ipc call night disable",
        label: "Night Mode: Disable"
    },
    {
        id: "spawn dms ipc call wellbeing toggle",
        label: "Screen Time Tracking: Toggle"
    },
    {
        id: "spawn dms ipc call bar toggle index 0",
        label: "Bar: Toggle (Primary)"
    },
    {
        id: "spawn dms ipc call bar reveal index 0",
        label: "Bar: Reveal (Primary)"
    },
    {
        id: "spawn dms ipc call bar hide index 0",
        label: "Bar: Hide (Primary)"
    },
    {
        id: "spawn dms ipc call bar toggleReveal index 0",
        label: "Bar: Toggle Autohide Reveal (Primary)"
    },
    {
        id: "spawn dms ipc call bar toggleAutoHide index 0",
        label: "Bar: Toggle Auto-Hide (Primary)"
    },
    {
        id: "spawn dms ipc call bar autoHide index 0",
        label: "Bar: Enable Auto-Hide (Primary)"
    },
    {
        id: "spawn dms ipc call bar manualHide index 0",
        label: "Bar: Disable Auto-Hide (Primary)"
    },
    {
        id: "spawn dms ipc call dock toggle",
        label: "Dock: Toggle"
    },
    {
        id: "spawn dms ipc call dock reveal",
        label: "Dock: Reveal"
    },
    {
        id: "spawn dms ipc call dock hide",
        label: "Dock: Hide"
    },
    {
        id: "spawn dms ipc call dock toggleAutoHide",
        label: "Dock: Toggle Auto-Hide"
    },
    {
        id: "spawn dms ipc call dock autoHide",
        label: "Dock: Enable Auto-Hide"
    },
    {
        id: "spawn dms ipc call dock manualHide",
        label: "Dock: Disable Auto-Hide"
    },
    {
        id: "spawn dms ipc call mpris playPause",
        label: "Media: Play/Pause"
    },
    {
        id: "spawn dms ipc call mpris play",
        label: "Media: Play"
    },
    {
        id: "spawn dms ipc call mpris pause",
        label: "Media: Pause"
    },
    {
        id: "spawn dms ipc call mpris previous",
        label: "Media: Previous Track"
    },
    {
        id: "spawn dms ipc call mpris next",
        label: "Media: Next Track"
    },
    {
        id: "spawn dms ipc call mpris stop",
        label: "Media: Stop"
    },
    {
        id: "spawn dms screenshot",
        label: "Screenshot: Region"
    },
    {
        id: "spawn dms screenshot full",
        label: "Screenshot: Full Screen"
    },
    {
        id: "spawn dms screenshot all",
        label: "Screenshot: All Screens"
    },
    {
        id: "spawn dms screenshot window",
        label: "Screenshot: Window"
    },
    {
        id: "spawn dms ipc call hypr toggleOverview",
        label: "Hyprland: Toggle Overview",
        compositor: "hyprland"
    },
    {
        id: "spawn dms ipc call hypr openOverview",
        label: "Hyprland: Open Overview",
        compositor: "hyprland"
    },
    {
        id: "spawn dms ipc call hypr closeOverview",
        label: "Hyprland: Close Overview",
        compositor: "hyprland"
    },
    {
        id: "spawn dms ipc call wallpaper next",
        label: "Wallpaper: Next"
    },
    {
        id: "spawn dms ipc call wallpaper prev",
        label: "Wallpaper: Previous"
    },
    {
        id: "spawn dms ipc call workspace-rename open",
        label: "Workspace: Rename"
    }
];

const NIRI_ACTIONS = {
    "Window": [
        {
            id: "close-window",
            label: "Close Window"
        },
        {
            id: "fullscreen-window",
            label: "Fullscreen"
        },
        {
            id: "maximize-column",
            label: "Maximize Column"
        },
        {
            id: "center-column",
            label: "Center Column"
        },
        {
            id: "center-visible-columns",
            label: "Center Visible Columns"
        },
        {
            id: "toggle-window-floating",
            label: "Toggle Floating"
        },
        {
            id: "switch-focus-between-floating-and-tiling",
            label: "Switch Floating/Tiling Focus"
        },
        {
            id: "switch-preset-column-width",
            label: "Cycle Column Width"
        },
        {
            id: "switch-preset-window-height",
            label: "Cycle Window Height"
        },
        {
            id: "set-column-width",
            label: "Set Column Width"
        },
        {
            id: "set-window-height",
            label: "Set Window Height"
        },
        {
            id: "reset-window-height",
            label: "Reset Window Height"
        },
        {
            id: "expand-column-to-available-width",
            label: "Expand to Available Width"
        },
        {
            id: "consume-or-expel-window-left",
            label: "Consume/Expel Left"
        },
        {
            id: "consume-or-expel-window-right",
            label: "Consume/Expel Right"
        },
        {
            id: "toggle-column-tabbed-display",
            label: "Toggle Tabbed"
        },
        {
            id: "toggle-window-rule-opacity",
            label: "Toggle Window Opacity"
        }
    ],
    "Focus": [
        {
            id: "focus-column-left",
            label: "Focus Left"
        },
        {
            id: "focus-column-right",
            label: "Focus Right"
        },
        {
            id: "focus-window-down",
            label: "Focus Down"
        },
        {
            id: "focus-window-up",
            label: "Focus Up"
        },
        {
            id: "focus-column-first",
            label: "Focus First Column"
        },
        {
            id: "focus-column-last",
            label: "Focus Last Column"
        }
    ],
    "Move": [
        {
            id: "move-column-left",
            label: "Move Left"
        },
        {
            id: "move-column-right",
            label: "Move Right"
        },
        {
            id: "move-window-down",
            label: "Move Down"
        },
        {
            id: "move-window-up",
            label: "Move Up"
        },
        {
            id: "move-column-to-first",
            label: "Move to First"
        },
        {
            id: "move-column-to-last",
            label: "Move to Last"
        }
    ],
    "Workspace": [
        {
            id: "focus-workspace-down",
            label: "Focus Workspace Down"
        },
        {
            id: "focus-workspace-up",
            label: "Focus Workspace Up"
        },
        {
            id: "focus-workspace-previous",
            label: "Focus Previous Workspace"
        },
        {
            id: "focus-workspace",
            label: "Focus Workspace (by index)"
        },
        {
            id: "move-column-to-workspace-down",
            label: "Move to Workspace Down"
        },
        {
            id: "move-column-to-workspace-up",
            label: "Move to Workspace Up"
        },
        {
            id: "move-column-to-workspace",
            label: "Move to Workspace (by index)"
        },
        {
            id: "move-workspace-down",
            label: "Move Workspace Down"
        },
        {
            id: "move-workspace-up",
            label: "Move Workspace Up"
        }
    ],
    "Monitor": [
        {
            id: "focus-monitor-left",
            label: "Focus Monitor Left"
        },
        {
            id: "focus-monitor-right",
            label: "Focus Monitor Right"
        },
        {
            id: "focus-monitor-down",
            label: "Focus Monitor Down"
        },
        {
            id: "focus-monitor-up",
            label: "Focus Monitor Up"
        },
        {
            id: "move-column-to-monitor-left",
            label: "Move Column to Monitor Left"
        },
        {
            id: "move-column-to-monitor-right",
            label: "Move Column to Monitor Right"
        },
        {
            id: "move-column-to-monitor-down",
            label: "Move Column to Monitor Down"
        },
        {
            id: "move-column-to-monitor-up",
            label: "Move Column to Monitor Up"
        },
        {
            id: "move-workspace-to-monitor-left",
            label: "Move Workspace to Monitor Left"
        },
        {
            id: "move-workspace-to-monitor-right",
            label: "Move Workspace to Monitor Right"
        },
        {
            id: "move-workspace-to-monitor-down",
            label: "Move Workspace to Monitor Down"
        },
        {
            id: "move-workspace-to-monitor-up",
            label: "Move Workspace to Monitor Up"
        },
        {
            id: "move-workspace-to-monitor-next",
            label: "Move Workspace to Next Monitor"
        },
        {
            id: "move-workspace-to-monitor-previous",
            label: "Move Workspace to Previous Monitor"
        }
    ],
    "Screenshot": [
        {
            id: "screenshot",
            label: "Screenshot (Interactive)"
        },
        {
            id: "screenshot-screen",
            label: "Screenshot Screen"
        },
        {
            id: "screenshot-window",
            label: "Screenshot Window"
        }
    ],
    "System": [
        {
            id: "toggle-overview",
            label: "Toggle Overview"
        },
        {
            id: "show-hotkey-overlay",
            label: "Show Hotkey Overlay"
        },
        {
            id: "do-screen-transition",
            label: "Screen Transition"
        },
        {
            id: "power-off-monitors",
            label: "Power Off Monitors"
        },
        {
            id: "power-on-monitors",
            label: "Power On Monitors"
        },
        {
            id: "toggle-keyboard-shortcuts-inhibit",
            label: "Toggle Shortcuts Inhibit"
        },
        {
            id: "toggle-touchpad",
            label: "Toggle Touchpad"
        },
        {
            id: "quit",
            label: "Quit niri"
        },
        {
            id: "suspend",
            label: "Suspend"
        }
    ],
    "Alt-Tab": [
        {
            id: "next-window",
            label: "Next Window"
        },
        {
            id: "previous-window",
            label: "Previous Window"
        },
        {
            id: "next-window filter=\"app-id\"",
            label: "Next Window (Same Application)"
        },
        {
            id: "previous-window filter=\"app-id\"",
            label: "Previous Window (Same Application)"
        }
    ]
};

const MANGOWC_ACTIONS = {
    "Window": [
        {
            id: "killclient",
            label: "Close Window"
        },
        {
            id: "focuslast",
            label: "Focus Last Window"
        },
        {
            id: "focusstack next",
            label: "Focus Next in Stack"
        },
        {
            id: "focusstack prev",
            label: "Focus Previous in Stack"
        },
        {
            id: "focusdir left",
            label: "Focus Left"
        },
        {
            id: "focusdir right",
            label: "Focus Right"
        },
        {
            id: "focusdir up",
            label: "Focus Up"
        },
        {
            id: "focusdir down",
            label: "Focus Down"
        },
        {
            id: "exchange_client left",
            label: "Swap Left"
        },
        {
            id: "exchange_client right",
            label: "Swap Right"
        },
        {
            id: "exchange_client up",
            label: "Swap Up"
        },
        {
            id: "exchange_client down",
            label: "Swap Down"
        },
        {
            id: "move_client left",
            label: "Move Left"
        },
        {
            id: "move_client right",
            label: "Move Right"
        },
        {
            id: "move_client up",
            label: "Move Up"
        },
        {
            id: "move_client down",
            label: "Move Down"
        },
        {
            id: "exchange_stack_client next",
            label: "Swap Next in Stack"
        },
        {
            id: "exchange_stack_client prev",
            label: "Swap Previous in Stack"
        },
        {
            id: "togglefloating",
            label: "Toggle Floating"
        },
        {
            id: "togglefullscreen",
            label: "Toggle Fullscreen"
        },
        {
            id: "togglefakefullscreen",
            label: "Toggle Fake Fullscreen"
        },
        {
            id: "togglemaximizescreen",
            label: "Toggle Maximize"
        },
        {
            id: "toggleglobal",
            label: "Toggle Global (Sticky)"
        },
        {
            id: "toggleoverlay",
            label: "Toggle Overlay"
        },
        {
            id: "minimized",
            label: "Minimize Window"
        },
        {
            id: "restore_minimized",
            label: "Restore Minimized"
        },
        {
            id: "toggle_render_border",
            label: "Toggle Border"
        },
        {
            id: "centerwin",
            label: "Center Window"
        },
        {
            id: "zoom",
            label: "Swap with Master"
        }
    ],
    "Move/Resize": [
        {
            id: "smartmovewin left",
            label: "Smart Move Left"
        },
        {
            id: "smartmovewin right",
            label: "Smart Move Right"
        },
        {
            id: "smartmovewin up",
            label: "Smart Move Up"
        },
        {
            id: "smartmovewin down",
            label: "Smart Move Down"
        },
        {
            id: "smartresizewin left",
            label: "Smart Resize Left"
        },
        {
            id: "smartresizewin right",
            label: "Smart Resize Right"
        },
        {
            id: "smartresizewin up",
            label: "Smart Resize Up"
        },
        {
            id: "smartresizewin down",
            label: "Smart Resize Down"
        },
        {
            id: "movewin",
            label: "Move Window (x,y)"
        },
        {
            id: "resizewin",
            label: "Resize Window (w,h)"
        }
    ],
    "Tags": [
        {
            id: "view",
            label: "View Tag"
        },
        {
            id: "viewtoleft",
            label: "View Left Tag"
        },
        {
            id: "viewtoright",
            label: "View Right Tag"
        },
        {
            id: "viewtoleft_have_client",
            label: "View Left (with client)"
        },
        {
            id: "viewtoright_have_client",
            label: "View Right (with client)"
        },
        {
            id: "viewcrossmon",
            label: "View Cross-Monitor"
        },
        {
            id: "tag",
            label: "Move to Tag"
        },
        {
            id: "tagsilent",
            label: "Move to Tag (silent)"
        },
        {
            id: "tagtoleft",
            label: "Move to Left Tag"
        },
        {
            id: "tagtoright",
            label: "Move to Right Tag"
        },
        {
            id: "tagcrossmon",
            label: "Move Cross-Monitor"
        },
        {
            id: "toggletag",
            label: "Toggle Tag on Window"
        },
        {
            id: "toggleview",
            label: "Toggle Tag View"
        },
        {
            id: "comboview",
            label: "Combo View Tags"
        }
    ],
    "Layout": [
        {
            id: "setlayout",
            label: "Set Layout"
        },
        {
            id: "switch_layout",
            label: "Cycle Layouts"
        },
        {
            id: "set_proportion",
            label: "Set Proportion"
        },
        {
            id: "switch_proportion_preset",
            label: "Cycle Proportion Presets"
        },
        {
            id: "incnmaster +1",
            label: "Increase Masters"
        },
        {
            id: "incnmaster -1",
            label: "Decrease Masters"
        },
        {
            id: "setmfact",
            label: "Set Master Factor"
        },
        {
            id: "incgaps",
            label: "Adjust Gaps"
        },
        {
            id: "togglegaps",
            label: "Toggle Gaps"
        }
    ],
    "Monitor": [
        {
            id: "focusmon left",
            label: "Focus Monitor Left"
        },
        {
            id: "focusmon right",
            label: "Focus Monitor Right"
        },
        {
            id: "focusmon up",
            label: "Focus Monitor Up"
        },
        {
            id: "focusmon down",
            label: "Focus Monitor Down"
        },
        {
            id: "tagmon left",
            label: "Move to Monitor Left"
        },
        {
            id: "tagmon right",
            label: "Move to Monitor Right"
        },
        {
            id: "tagmon up",
            label: "Move to Monitor Up"
        },
        {
            id: "tagmon down",
            label: "Move to Monitor Down"
        },
        {
            id: "disable_monitor",
            label: "Disable Monitor"
        },
        {
            id: "enable_monitor",
            label: "Enable Monitor"
        },
        {
            id: "toggle_monitor",
            label: "Toggle Monitor"
        },
        {
            id: "create_virtual_output",
            label: "Create Virtual Output"
        },
        {
            id: "destroy_all_virtual_output",
            label: "Destroy Virtual Outputs"
        }
    ],
    "Scratchpad": [
        {
            id: "toggle_scratchpad",
            label: "Toggle Scratchpad"
        },
        {
            id: "toggle_named_scratchpad",
            label: "Toggle Named Scratchpad"
        }
    ],
    "Overview": [
        {
            id: "toggleoverview",
            label: "Toggle Overview"
        }
    ],
    "System": [
        {
            id: "reload_config",
            label: "Reload Config"
        },
        {
            id: "quit",
            label: "Quit MangoWC"
        },
        {
            id: "setkeymode",
            label: "Set Keymode"
        },
        {
            id: "switch_keyboard_layout",
            label: "Switch Keyboard Layout"
        },
        {
            id: "setoption",
            label: "Set Option"
        },
        {
            id: "toggle_trackpad_enable",
            label: "Toggle Trackpad"
        }
    ]
};

const HYPRLAND_ACTIONS = {
    "Window": [
        {
            id: "killactive",
            label: "Close Window"
        },
        {
            id: "forcekillactive",
            label: "Force Kill Window"
        },
        {
            id: "closewindow",
            label: "Close Window (by selector)"
        },
        {
            id: "killwindow",
            label: "Kill Window (by selector)"
        },
        {
            id: "togglefloating",
            label: "Toggle Floating"
        },
        {
            id: "setfloating",
            label: "Set Floating"
        },
        {
            id: "settiled",
            label: "Set Tiled"
        },
        {
            id: "fullscreen",
            label: "Toggle Fullscreen"
        },
        {
            id: "fullscreen 1",
            label: "Toggle Maximize"
        },
        {
            id: "pseudo",
            label: "Toggle Pseudotile"
        },
        {
            id: "fullscreenstate",
            label: "Set Fullscreen State"
        },
        {
            id: "pin",
            label: "Pin Window"
        },
        {
            id: "centerwindow",
            label: "Center Window"
        },
        {
            id: "resizeactive",
            label: "Resize Active Window"
        },
        {
            id: "moveactive",
            label: "Move Active Window"
        },
        {
            id: "resizewindowpixel",
            label: "Resize Window (pixels)"
        },
        {
            id: "movewindowpixel",
            label: "Move Window (pixels)"
        },
        {
            id: "alterzorder",
            label: "Change Z-Order"
        },
        {
            id: "bringactivetotop",
            label: "Bring to Top"
        },
        {
            id: "setprop",
            label: "Set Window Property"
        },
        {
            id: "toggleswallow",
            label: "Toggle Swallow"
        }
    ],
    "Focus": [
        {
            id: "movefocus l",
            label: "Focus Left"
        },
        {
            id: "movefocus r",
            label: "Focus Right"
        },
        {
            id: "movefocus u",
            label: "Focus Up"
        },
        {
            id: "movefocus d",
            label: "Focus Down"
        },
        {
            id: "movefocus",
            label: "Move Focus (direction)"
        },
        {
            id: "cyclenext",
            label: "Cycle Next Window"
        },
        {
            id: "cyclenext prev",
            label: "Cycle Previous Window"
        },
        {
            id: "focuswindow",
            label: "Focus Window (by selector)"
        },
        {
            id: "focuscurrentorlast",
            label: "Focus Current or Last"
        },
        {
            id: "focusurgentorlast",
            label: "Focus Urgent or Last"
        }
    ],
    "Move": [
        {
            id: "movewindow l",
            label: "Move Window Left"
        },
        {
            id: "movewindow r",
            label: "Move Window Right"
        },
        {
            id: "movewindow u",
            label: "Move Window Up"
        },
        {
            id: "movewindow d",
            label: "Move Window Down"
        },
        {
            id: "movewindow",
            label: "Move Window (direction)"
        },
        {
            id: "swapwindow l",
            label: "Swap Left"
        },
        {
            id: "swapwindow r",
            label: "Swap Right"
        },
        {
            id: "swapwindow u",
            label: "Swap Up"
        },
        {
            id: "swapwindow d",
            label: "Swap Down"
        },
        {
            id: "swapwindow",
            label: "Swap Window (direction)"
        },
        {
            id: "swapnext",
            label: "Swap with Next"
        },
        {
            id: "swapnext prev",
            label: "Swap with Previous"
        },
        {
            id: "movecursortocorner",
            label: "Move Cursor to Corner"
        },
        {
            id: "movecursor",
            label: "Move Cursor (x,y)"
        }
    ],
    "Workspace": [
        {
            id: "workspace",
            label: "Focus Workspace"
        },
        {
            id: "workspace +1",
            label: "Next Workspace"
        },
        {
            id: "workspace -1",
            label: "Previous Workspace"
        },
        {
            id: "workspace e+1",
            label: "Next Open Workspace"
        },
        {
            id: "workspace e-1",
            label: "Previous Open Workspace"
        },
        {
            id: "workspace previous",
            label: "Previous Visited Workspace"
        },
        {
            id: "workspace previous_per_monitor",
            label: "Previous on Monitor"
        },
        {
            id: "workspace empty",
            label: "First Empty Workspace"
        },
        {
            id: "movetoworkspace",
            label: "Move to Workspace"
        },
        {
            id: "movetoworkspace +1",
            label: "Move to Next Workspace"
        },
        {
            id: "movetoworkspace -1",
            label: "Move to Previous Workspace"
        },
        {
            id: "movetoworkspacesilent",
            label: "Move to Workspace (silent)"
        },
        {
            id: "movetoworkspacesilent +1",
            label: "Move to Next (silent)"
        },
        {
            id: "movetoworkspacesilent -1",
            label: "Move to Previous (silent)"
        },
        {
            id: "togglespecialworkspace",
            label: "Toggle Special Workspace"
        },
        {
            id: "movetoworkspace +0",
            label: "Move Out of Special Workspace"
        },
        {
            id: "focusworkspaceoncurrentmonitor",
            label: "Focus Workspace on Current Monitor"
        },
        {
            id: "renameworkspace",
            label: "Rename Workspace"
        }
    ],
    "Monitor": [
        {
            id: "focusmonitor l",
            label: "Focus Monitor Left"
        },
        {
            id: "focusmonitor r",
            label: "Focus Monitor Right"
        },
        {
            id: "focusmonitor u",
            label: "Focus Monitor Up"
        },
        {
            id: "focusmonitor d",
            label: "Focus Monitor Down"
        },
        {
            id: "focusmonitor +1",
            label: "Focus Next Monitor"
        },
        {
            id: "focusmonitor -1",
            label: "Focus Previous Monitor"
        },
        {
            id: "focusmonitor",
            label: "Focus Monitor (by selector)"
        },
        {
            id: "movecurrentworkspacetomonitor",
            label: "Move Workspace to Monitor"
        },
        {
            id: "moveworkspacetomonitor",
            label: "Move Specific Workspace to Monitor"
        },
        {
            id: "swapactiveworkspaces",
            label: "Swap Active Workspaces"
        }
    ],
    "Groups": [
        {
            id: "togglegroup",
            label: "Toggle Group"
        },
        {
            id: "changegroupactive f",
            label: "Next in Group"
        },
        {
            id: "changegroupactive b",
            label: "Previous in Group"
        },
        {
            id: "changegroupactive",
            label: "Change Active in Group"
        },
        {
            id: "moveintogroup l",
            label: "Move into Group Left"
        },
        {
            id: "moveintogroup r",
            label: "Move into Group Right"
        },
        {
            id: "moveintogroup u",
            label: "Move into Group Up"
        },
        {
            id: "moveintogroup d",
            label: "Move into Group Down"
        },
        {
            id: "moveintoorcreategroup l",
            label: "Move into or Create Group Left"
        },
        {
            id: "moveintoorcreategroup r",
            label: "Move into or Create Group Right"
        },
        {
            id: "moveintoorcreategroup u",
            label: "Move into or Create Group Up"
        },
        {
            id: "moveintoorcreategroup d",
            label: "Move into or Create Group Down"
        },
        {
            id: "moveoutofgroup",
            label: "Move out of Group"
        },
        {
            id: "movewindoworgroup l",
            label: "Move Window/Group Left"
        },
        {
            id: "movewindoworgroup r",
            label: "Move Window/Group Right"
        },
        {
            id: "movewindoworgroup u",
            label: "Move Window/Group Up"
        },
        {
            id: "movewindoworgroup d",
            label: "Move Window/Group Down"
        },
        {
            id: "movegroupwindow f",
            label: "Swap Forward in Group"
        },
        {
            id: "movegroupwindow b",
            label: "Swap Backward in Group"
        },
        {
            id: "lockgroups lock",
            label: "Lock All Groups"
        },
        {
            id: "lockgroups unlock",
            label: "Unlock All Groups"
        },
        {
            id: "lockgroups toggle",
            label: "Toggle Groups Lock"
        },
        {
            id: "lockactivegroup lock",
            label: "Lock Active Group"
        },
        {
            id: "lockactivegroup unlock",
            label: "Unlock Active Group"
        },
        {
            id: "lockactivegroup toggle",
            label: "Toggle Active Group Lock"
        },
        {
            id: "denywindowfromgroup on",
            label: "Deny Window from Group"
        },
        {
            id: "denywindowfromgroup off",
            label: "Allow Window in Group"
        },
        {
            id: "denywindowfromgroup toggle",
            label: "Toggle Deny from Group"
        }
    ],
    "Layout": [
        {
            id: "splitratio",
            label: "Adjust Split Ratio"
        },
        {
            id: "layoutmsg",
            label: "Layout Message"
        },
        {
            id: "layoutmsg togglesplit",
            label: "Toggle Split (dwindle)"
        },
        {
            id: "layoutmsg swapsplit",
            label: "Swap Split (dwindle)"
        },
        {
            id: "layoutmsg rotatesplit",
            label: "Rotate Split (dwindle)"
        },
        {
            id: "layoutmsg preselect l",
            label: "Preselect Left (dwindle)"
        },
        {
            id: "layoutmsg preselect r",
            label: "Preselect Right (dwindle)"
        },
        {
            id: "layoutmsg preselect u",
            label: "Preselect Up (dwindle)"
        },
        {
            id: "layoutmsg preselect d",
            label: "Preselect Down (dwindle)"
        },
        {
            id: "layoutmsg movetoroot",
            label: "Move to Root (dwindle)"
        },
        {
            id: "layoutmsg swapwithmaster",
            label: "Swap with Master (master)"
        },
        {
            id: "layoutmsg focusmaster",
            label: "Focus Master (master)"
        },
        {
            id: "layoutmsg cyclenext",
            label: "Cycle Next (master)"
        },
        {
            id: "layoutmsg cycleprev",
            label: "Cycle Previous (master)"
        },
        {
            id: "layoutmsg swapnext",
            label: "Swap Next (master)"
        },
        {
            id: "layoutmsg swapprev",
            label: "Swap Previous (master)"
        },
        {
            id: "layoutmsg rollnext",
            label: "Roll Next (master)"
        },
        {
            id: "layoutmsg rollprev",
            label: "Roll Previous (master)"
        },
        {
            id: "layoutmsg addmaster",
            label: "Add Master (master)"
        },
        {
            id: "layoutmsg removemaster",
            label: "Remove Master (master)"
        },
        {
            id: "layoutmsg orientationnext",
            label: "Next Orientation (master)"
        },
        {
            id: "layoutmsg orientationprev",
            label: "Previous Orientation (master)"
        },
        {
            id: "layoutmsg orientationcycle",
            label: "Cycle Orientation (master)"
        },
        {
            id: "layoutmsg orientationleft",
            label: "Orientation Left (master)"
        },
        {
            id: "layoutmsg orientationright",
            label: "Orientation Right (master)"
        },
        {
            id: "layoutmsg orientationtop",
            label: "Orientation Top (master)"
        },
        {
            id: "layoutmsg orientationbottom",
            label: "Orientation Bottom (master)"
        },
        {
            id: "layoutmsg orientationcenter",
            label: "Orientation Center (master)"
        },
        {
            id: "layoutmsg center",
            label: "Center Column (scrolling)"
        },
        {
            id: "layoutmsg fit_into_view",
            label: "Fit Column into View (scrolling)"
        },
        {
            id: "layoutmsg consume",
            label: "Consume into Column (scrolling)"
        },
        {
            id: "layoutmsg expel",
            label: "Expel from Column (scrolling)"
        },
        {
            id: "layoutmsg consume_or_expel prev",
            label: "Consume or Expel Previous (scrolling)"
        },
        {
            id: "layoutmsg consume_or_expel next",
            label: "Consume or Expel Next (scrolling)"
        },
        {
            id: "layoutmsg promote",
            label: "Promote to Column (scrolling)"
        },
        {
            id: "layoutmsg inhibit_scroll",
            label: "Toggle Scroll Inhibit (scrolling)"
        },
        {
            id: "layoutmsg colresize +conf",
            label: "Next Column Width (scrolling)"
        },
        {
            id: "layoutmsg colresize -conf",
            label: "Previous Column Width (scrolling)"
        },
        {
            id: "layoutmsg swapcol l",
            label: "Swap Column Left (scrolling)"
        },
        {
            id: "layoutmsg swapcol r",
            label: "Swap Column Right (scrolling)"
        },
        {
            id: "layoutmsg move +col",
            label: "Scroll Next Column (scrolling)"
        },
        {
            id: "layoutmsg move -col",
            label: "Scroll Previous Column (scrolling)"
        }
    ],
    "System": [
        {
            id: "exit",
            label: "Exit Hyprland"
        },
        {
            id: "forcerendererreload",
            label: "Force Renderer Reload"
        },
        {
            id: "reloadconfig",
            label: "Reload Config"
        },
        {
            id: "dpms on",
            label: "DPMS On"
        },
        {
            id: "dpms off",
            label: "DPMS Off"
        },
        {
            id: "dpms toggle",
            label: "DPMS Toggle"
        },
        {
            id: "forceidle",
            label: "Force Idle"
        },
        {
            id: "releaseinputcapture",
            label: "Release Input Capture"
        },
        {
            id: "submap",
            label: "Enter Submap"
        },
        {
            id: "submap reset",
            label: "Reset Submap"
        },
        {
            id: "global",
            label: "Global Shortcut"
        },
        {
            id: "event",
            label: "Emit Custom Event"
        }
    ],
    "Pass-through": [
        {
            id: "pass",
            label: "Pass Key to Window"
        },
        {
            id: "sendshortcut",
            label: "Send Shortcut to Window"
        },
        {
            id: "sendkeystate",
            label: "Send Key State"
        }
    ]
};

const COMPOSITOR_ACTIONS = {
    niri: NIRI_ACTIONS,
    mangowc: MANGOWC_ACTIONS,
    hyprland: HYPRLAND_ACTIONS
};

const CATEGORY_ORDER = ["DMS", "Execute", "Workspace", "Tags", "Window", "Move/Resize", "Focus", "Move", "Layout", "Groups", "Monitor", "Scratchpad", "Screenshot", "System", "Pass-through", "Overview", "Alt-Tab", "Other"];

const NIRI_ACTION_ARGS = {
    "quit": {
        args: [
            {
                name: "skip-confirmation",
                type: "bool",
                label: "Skip confirmation"
            }
        ]
    },
    "do-screen-transition": {
        args: [
            {
                name: "delay-ms",
                type: "number",
                label: "Delay (ms)",
                placeholder: "250"
            }
        ]
    },
    "set-column-width": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Width",
                placeholder: "+10%, -10%, 50%"
            }
        ]
    },
    "set-window-height": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Height",
                placeholder: "+10%, -10%, 50%"
            }
        ]
    },
    "focus-workspace": {
        args: [
            {
                name: "index",
                type: "number",
                label: "Workspace",
                placeholder: "1, 2, 3..."
            }
        ]
    },
    "move-column-to-workspace": {
        args: [
            {
                name: "index",
                type: "number",
                label: "Workspace",
                placeholder: "1, 2, 3..."
            },
            {
                name: "focus",
                type: "bool",
                label: "Follow focus",
                default: false
            }
        ]
    },
    "move-column-to-workspace-down": {
        args: [
            {
                name: "focus",
                type: "bool",
                label: "Follow focus",
                default: false
            }
        ]
    },
    "move-column-to-workspace-up": {
        args: [
            {
                name: "focus",
                type: "bool",
                label: "Follow focus",
                default: false
            }
        ]
    },
    "screenshot": {
        args: [
            {
                name: "show-pointer",
                type: "bool",
                label: "Show pointer"
            }
        ]
    },
    "screenshot-screen": {
        args: [
            {
                name: "show-pointer",
                type: "bool",
                label: "Show pointer"
            },
            {
                name: "write-to-disk",
                type: "bool",
                label: "Save to disk"
            }
        ]
    },
    "screenshot-window": {
        args: [
            {
                name: "write-to-disk",
                type: "bool",
                label: "Save to disk"
            }
        ]
    }
};

const MANGOWC_ACTION_ARGS = {
    "view": {
        args: [
            {
                name: "tag",
                type: "number",
                label: "Tag",
                placeholder: "1-9"
            },
            {
                name: "monitor",
                type: "number",
                label: "Monitor",
                placeholder: "0",
                default: "0"
            }
        ]
    },
    "tag": {
        args: [
            {
                name: "tag",
                type: "number",
                label: "Tag",
                placeholder: "1-9"
            },
            {
                name: "monitor",
                type: "number",
                label: "Monitor",
                placeholder: "0",
                default: "0"
            }
        ]
    },
    "tagsilent": {
        args: [
            {
                name: "tag",
                type: "number",
                label: "Tag",
                placeholder: "1-9"
            },
            {
                name: "monitor",
                type: "number",
                label: "Monitor",
                placeholder: "0",
                default: "0"
            }
        ]
    },
    "toggletag": {
        args: [
            {
                name: "tag",
                type: "number",
                label: "Tag",
                placeholder: "1-9"
            },
            {
                name: "monitor",
                type: "number",
                label: "Monitor",
                placeholder: "0",
                default: "0"
            }
        ]
    },
    "toggleview": {
        args: [
            {
                name: "tag",
                type: "number",
                label: "Tag",
                placeholder: "1-9"
            },
            {
                name: "monitor",
                type: "number",
                label: "Monitor",
                placeholder: "0",
                default: "0"
            }
        ]
    },
    "comboview": {
        args: [
            {
                name: "tags",
                type: "text",
                label: "Tags",
                placeholder: "1,2,3"
            }
        ]
    },
    "setlayout": {
        args: [
            {
                name: "layout",
                type: "text",
                label: "Layout",
                placeholder: "tile, monocle, grid, deck"
            }
        ]
    },
    "set_proportion": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Proportion",
                placeholder: "0.5, +0.1, -0.1"
            }
        ]
    },
    "setmfact": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Factor",
                placeholder: "+0.05, -0.05"
            }
        ]
    },
    "incgaps": {
        args: [
            {
                name: "value",
                type: "number",
                label: "Amount",
                placeholder: "+5, -5"
            }
        ]
    },
    "movewin": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Position",
                placeholder: "x,y or +10,+10"
            }
        ]
    },
    "resizewin": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Size",
                placeholder: "w,h or +10,+10"
            }
        ]
    },
    "setkeymode": {
        args: [
            {
                name: "mode",
                type: "text",
                label: "Mode",
                placeholder: "default, custom"
            }
        ]
    },
    "setoption": {
        args: [
            {
                name: "option",
                type: "text",
                label: "Option",
                placeholder: "option_name value"
            }
        ]
    },
    "toggle_named_scratchpad": {
        args: [
            {
                name: "appid",
                type: "text",
                label: "App ID",
                placeholder: "Optional",
                emptyValue: "none"
            },
            {
                name: "title",
                type: "text",
                label: "Title",
                placeholder: "Optional",
                emptyValue: "none"
            },
            {
                name: "command",
                type: "text",
                label: "Command",
                placeholder: "Command"
            }
        ]
    },
    "incnmaster": {
        args: [
            {
                name: "value",
                type: "number",
                label: "Amount",
                placeholder: "+1, -1"
            }
        ]
    }
};

const HYPRLAND_ACTION_ARGS = {
    "workspace": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Workspace",
                placeholder: "1, +1, -1, name:..."
            }
        ]
    },
    "movetoworkspace": {
        args: [
            {
                name: "workspace",
                type: "text",
                label: "Workspace",
                placeholder: "1, +1, special:name"
            },
            {
                name: "window",
                type: "text",
                label: "Window (optional)",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "movetoworkspacesilent": {
        args: [
            {
                name: "workspace",
                type: "text",
                label: "Workspace",
                placeholder: "1, +1, special:name"
            },
            {
                name: "window",
                type: "text",
                label: "Window (optional)",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "focusworkspaceoncurrentmonitor": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Workspace",
                placeholder: "1, +1, name:..."
            }
        ]
    },
    "togglespecialworkspace": {
        args: [
            {
                name: "name",
                type: "text",
                label: "Name (optional)",
                placeholder: "scratchpad"
            }
        ]
    },
    "focusmonitor": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Monitor",
                placeholder: "l, r, +1, DP-1"
            }
        ]
    },
    "movecurrentworkspacetomonitor": {
        args: [
            {
                name: "monitor",
                type: "text",
                label: "Monitor",
                placeholder: "l, r, DP-1"
            }
        ]
    },
    "moveworkspacetomonitor": {
        args: [
            {
                name: "workspace",
                type: "text",
                label: "Workspace",
                placeholder: "1, name:..."
            },
            {
                name: "monitor",
                type: "text",
                label: "Monitor",
                placeholder: "DP-1"
            }
        ]
    },
    "swapactiveworkspaces": {
        args: [
            {
                name: "monitor1",
                type: "text",
                label: "Monitor 1",
                placeholder: "DP-1"
            },
            {
                name: "monitor2",
                type: "text",
                label: "Monitor 2",
                placeholder: "DP-2"
            }
        ]
    },
    "renameworkspace": {
        args: [
            {
                name: "id",
                type: "number",
                label: "Workspace ID",
                placeholder: "1"
            },
            {
                name: "name",
                type: "text",
                label: "New Name",
                placeholder: "work"
            }
        ]
    },
    "fullscreen": {
        args: [
            {
                name: "mode",
                type: "text",
                label: "Mode",
                placeholder: "0=fullscreen, 1=maximize"
            },
            {
                name: "action",
                type: "text",
                label: "Action",
                placeholder: "toggle, set, unset"
            }
        ]
    },
    "fullscreenstate": {
        args: [
            {
                name: "internal",
                type: "text",
                label: "Internal",
                placeholder: "-1, 0, 1, 2, 3"
            },
            {
                name: "client",
                type: "text",
                label: "Client",
                placeholder: "-1, 0, 1, 2, 3"
            }
        ]
    },
    "resizeactive": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Size",
                placeholder: "10 -10, 20% 0"
            }
        ]
    },
    "moveactive": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Position",
                placeholder: "10 -10, exact 100 100"
            }
        ]
    },
    "resizewindowpixel": {
        args: [
            {
                name: "size",
                type: "text",
                label: "Size",
                placeholder: "100 100"
            },
            {
                name: "window",
                type: "text",
                label: "Window",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "movewindowpixel": {
        args: [
            {
                name: "position",
                type: "text",
                label: "Position",
                placeholder: "100 100"
            },
            {
                name: "window",
                type: "text",
                label: "Window",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "splitratio": {
        args: [
            {
                name: "value",
                type: "text",
                label: "Ratio",
                placeholder: "+0.1, -0.1, exact 0.5"
            }
        ]
    },
    "closewindow": {
        args: [
            {
                name: "window",
                type: "text",
                label: "Window",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "killwindow": {
        args: [
            {
                name: "window",
                type: "text",
                label: "Window",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "focuswindow": {
        args: [
            {
                name: "window",
                type: "text",
                label: "Window",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "tagwindow": {
        args: [
            {
                name: "tag",
                type: "text",
                label: "Tag",
                placeholder: "+mytag, -mytag"
            },
            {
                name: "window",
                type: "text",
                label: "Window (optional)",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "alterzorder": {
        args: [
            {
                name: "zheight",
                type: "text",
                label: "Z-Height",
                placeholder: "top, bottom"
            },
            {
                name: "window",
                type: "text",
                label: "Window (optional)",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "setprop": {
        args: [
            {
                name: "window",
                type: "text",
                label: "Window",
                placeholder: "class:^(app)$"
            },
            {
                name: "property",
                type: "text",
                label: "Property",
                placeholder: "opaque, alpha..."
            },
            {
                name: "value",
                type: "text",
                label: "Value",
                placeholder: "1, toggle"
            }
        ]
    },
    "signal": {
        args: [
            {
                name: "signal",
                type: "number",
                label: "Signal",
                placeholder: "9"
            }
        ]
    },
    "signalwindow": {
        args: [
            {
                name: "window",
                type: "text",
                label: "Window",
                placeholder: "class:^(app)$"
            },
            {
                name: "signal",
                type: "number",
                label: "Signal",
                placeholder: "9"
            }
        ]
    },
    "submap": {
        args: [
            {
                name: "name",
                type: "text",
                label: "Submap Name",
                placeholder: "resize, reset"
            }
        ]
    },
    "global": {
        args: [
            {
                name: "name",
                type: "text",
                label: "Shortcut Name",
                placeholder: "app:action"
            }
        ]
    },
    "event": {
        args: [
            {
                name: "data",
                type: "text",
                label: "Event Data",
                placeholder: "custom data"
            }
        ]
    },
    "pass": {
        args: [
            {
                name: "window",
                type: "text",
                label: "Window",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "sendshortcut": {
        args: [
            {
                name: "mod",
                type: "text",
                label: "Modifier",
                placeholder: "SUPER, ALT"
            },
            {
                name: "key",
                type: "text",
                label: "Key",
                placeholder: "F4"
            },
            {
                name: "window",
                type: "text",
                label: "Window (optional)",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "sendkeystate": {
        args: [
            {
                name: "mod",
                type: "text",
                label: "Modifier",
                placeholder: "SUPER"
            },
            {
                name: "key",
                type: "text",
                label: "Key",
                placeholder: "a"
            },
            {
                name: "state",
                type: "text",
                label: "State",
                placeholder: "down, repeat, up"
            },
            {
                name: "window",
                type: "text",
                label: "Window",
                placeholder: "class:^(app)$"
            }
        ]
    },
    "forceidle": {
        args: [
            {
                name: "seconds",
                type: "number",
                label: "Seconds",
                placeholder: "300"
            }
        ]
    },
    "movecursortocorner": {
        args: [
            {
                name: "corner",
                type: "number",
                label: "Corner",
                placeholder: "0-3 (BL, BR, TR, TL)"
            }
        ]
    },
    "movecursor": {
        args: [
            {
                name: "x",
                type: "number",
                label: "X",
                placeholder: "100"
            },
            {
                name: "y",
                type: "number",
                label: "Y",
                placeholder: "100"
            }
        ]
    },
    "changegroupactive": {
        args: [
            {
                name: "direction",
                type: "text",
                label: "Direction/Index",
                placeholder: "f, b, or index"
            }
        ]
    },
    "movefocus": {
        args: [
            {
                name: "direction",
                type: "text",
                label: "Direction",
                placeholder: "l, r, u, d"
            }
        ]
    },
    "movewindow": {
        args: [
            {
                name: "direction",
                type: "text",
                label: "Direction/Monitor",
                placeholder: "l, r, mon:DP-1"
            }
        ]
    },
    "swapwindow": {
        args: [
            {
                name: "direction",
                type: "text",
                label: "Direction",
                placeholder: "l, r, u, d"
            }
        ]
    },
    "moveintogroup": {
        args: [
            {
                name: "direction",
                type: "text",
                label: "Direction",
                placeholder: "l, r, u, d"
            }
        ]
    },
    "moveintoorcreategroup": {
        args: [
            {
                name: "direction",
                type: "text",
                label: "Direction",
                placeholder: "l, r, u, d"
            }
        ]
    },
    "layoutmsg": {
        args: [
            {
                name: "message",
                type: "text",
                label: "Message",
                placeholder: "togglesplit, swapwithmaster, colresize +0.1"
            }
        ]
    },
    "movewindoworgroup": {
        args: [
            {
                name: "direction",
                type: "text",
                label: "Direction",
                placeholder: "l, r, u, d"
            }
        ]
    },
    "cyclenext": {
        args: [
            {
                name: "options",
                type: "text",
                label: "Options",
                placeholder: "prev, tiled, floating"
            }
        ]
    }
};

const ACTION_ARGS = {
    niri: NIRI_ACTION_ARGS,
    mangowc: MANGOWC_ACTION_ARGS,
    hyprland: HYPRLAND_ACTION_ARGS
};

const SCREENSHOT_FLAGS = [
    {
        name: "no-file",
        type: "flag",
        flag: "--no-file",
        label: "Save",
        inverted: true
    },
    {
        name: "no-clipboard",
        type: "flag",
        flag: "--no-clipboard",
        label: "Clipboard",
        inverted: true
    },
    {
        name: "cursor",
        type: "flag",
        flag: "--cursor=on",
        label: "Pointer"
    }
];

const DMS_ACTION_ARGS = {
    "audio increment": {
        base: "spawn dms ipc call audio increment",
        args: [
            {
                name: "amount",
                type: "number",
                label: "Amount %",
                placeholder: "5",
                default: "5"
            }
        ]
    },
    "audio decrement": {
        base: "spawn dms ipc call audio decrement",
        args: [
            {
                name: "amount",
                type: "number",
                label: "Amount %",
                placeholder: "5",
                default: "5"
            }
        ]
    },
    "player increment": {
        base: "spawn dms ipc call mpris increment",
        args: [
            {
                name: "amount",
                type: "number",
                label: "Amount %",
                placeholder: "5",
                default: "5"
            }
        ]
    },
    "player decrement": {
        base: "spawn dms ipc call mpris decrement",
        args: [
            {
                name: "amount",
                type: "number",
                label: "Amount %",
                placeholder: "5",
                default: "5"
            }
        ]
    },
    "brightness increment": {
        base: "spawn dms ipc call brightness increment",
        args: [
            {
                name: "amount",
                type: "number",
                label: "Amount %",
                placeholder: "5",
                default: "5"
            },
            {
                name: "device",
                type: "text",
                label: "Device",
                placeholder: "leave empty for default",
                default: ""
            }
        ]
    },
    "brightness decrement": {
        base: "spawn dms ipc call brightness decrement",
        args: [
            {
                name: "amount",
                type: "number",
                label: "Amount %",
                placeholder: "5",
                default: "5"
            },
            {
                name: "device",
                type: "text",
                label: "Device",
                placeholder: "leave empty for default",
                default: ""
            }
        ]
    },
    "brightness toggleExponential": {
        base: "spawn dms ipc call brightness toggleExponential",
        args: [
            {
                name: "device",
                type: "text",
                label: "Device",
                placeholder: "leave empty for default",
                default: ""
            }
        ]
    },
    "dash toggle": {
        base: "spawn dms ipc call dash toggle",
        args: [
            {
                name: "tab",
                type: "text",
                label: "Tab",
                placeholder: "overview, media, wallpaper, weather",
                default: ""
            }
        ]
    },
    "screenshot": {
        base: "spawn dms screenshot",
        args: SCREENSHOT_FLAGS
    },
    "screenshot full": {
        base: "spawn dms screenshot full",
        args: SCREENSHOT_FLAGS
    },
    "screenshot all": {
        base: "spawn dms screenshot all",
        args: SCREENSHOT_FLAGS
    },
    "screenshot window": {
        base: "spawn dms screenshot window",
        args: SCREENSHOT_FLAGS
    }
};

const DMS_AMOUNT_LABELS = {
    "audio increment": "Volume Up",
    "audio decrement": "Volume Down",
    "mpris increment": "Player Volume Up",
    "mpris decrement": "Player Volume Down",
    "brightness increment": "Brightness Up",
    "brightness decrement": "Brightness Down"
};

function getDmsAmountLabel(action) {
    var parsed = parseDmsActionArgs(action);
    var label = DMS_AMOUNT_LABELS[parsed.base];
    if (!label)
        return null;
    var amount = parsed.args?.amount;
    if (amount === undefined || amount === null || amount === "")
        return label;
    return label + " (" + amount + "%)";
}

function getActionTypes() {
    return ACTION_TYPES;
}

function getDmsActionArgs() {
    return DMS_ACTION_ARGS;
}

function getDmsActions(isNiri, isHyprland) {
    const result = [];
    for (let i = 0; i < DMS_ACTIONS.length; i++) {
        const action = DMS_ACTIONS[i];
        if (!action.compositor) {
            result.push(action);
            continue;
        }
        switch (action.compositor) {
        case "niri":
            if (isNiri)
                result.push(action);
            break;
        case "hyprland":
            if (isHyprland)
                result.push(action);
            break;
        }
    }
    return result;
}

function getCompositorCategories(compositor) {
    var actions = COMPOSITOR_ACTIONS[compositor];
    if (!actions)
        return [];
    return Object.keys(actions);
}

function getCompositorActions(compositor, category) {
    var actions = COMPOSITOR_ACTIONS[compositor];
    if (!actions)
        return [];
    return actions[category] || [];
}

function getCategoryOrder() {
    return CATEGORY_ORDER;
}

function findDmsAction(actionId) {
    for (let i = 0; i < DMS_ACTIONS.length; i++) {
        if (DMS_ACTIONS[i].id === actionId)
            return DMS_ACTIONS[i];
    }
    return null;
}

function findCompositorAction(compositor, actionId) {
    var actions = COMPOSITOR_ACTIONS[compositor];
    if (!actions)
        return null;
    for (const cat in actions) {
        const acts = actions[cat];
        for (let i = 0; i < acts.length; i++) {
            if (acts[i].id === actionId)
                return acts[i];
        }
    }
    return null;
}

function getActionLabel(action, compositor) {
    if (!action)
        return "";

    var amountLabel = getDmsAmountLabel(action);
    if (amountLabel)
        return amountLabel;

    var dmsAct = findDmsAction(action);
    if (dmsAct)
        return dmsAct.label;

    var dmsKey = findDmsArgKey(action);
    var baseAct = dmsKey ? findDmsAction(DMS_ACTION_ARGS[dmsKey].base) : null;
    if (baseAct)
        return baseAct.label;

    if (compositor) {
        var compAct = findCompositorAction(compositor, action);
        if (compAct)
            return compAct.label;
        var base = action.split(" ")[0];
        compAct = findCompositorAction(compositor, base);
        if (compAct) {
            var arg = action.slice(base.length).trim();
            if (arg && compAct.label.includes("(by index)")) {
                return compAct.label.replace("(by index)", arg).trim();
            }
            if (arg.includes("filter=") && arg.includes("app-id")) {
                return compAct.label + " (Same Application)";
            }
            return compAct.label;
        }
    }

    if (action.startsWith("spawn sh -c "))
        return action.slice(12).replace(/^["']|["']$/g, "");
    if (action.startsWith("spawn "))
        return action.slice(6);
    return action;
}

function getActionType(action) {
    if (!action)
        return "compositor";
    if (isDmsAction(action))
        return "dms";
    if (/^spawn \w+ -c /.test(action) || action.startsWith("spawn_shell ") || action.startsWith("spawn-sh "))
        return "shell";
    if (action.startsWith("spawn "))
        return "spawn";
    return "compositor";
}

function isDmsAction(action) {
    if (!action)
        return false;
    return action.startsWith("spawn dms ipc call ") || /^spawn dms screenshot( |$)/.test(action);
}

function isValidAction(action) {
    if (!action)
        return false;
    switch (action) {
    case "spawn":
    case "spawn ":
    case "spawn sh -c \"\"":
    case "spawn sh -c ''":
    case "spawn_shell":
    case "spawn_shell ":
    case "spawn-sh":
    case "spawn-sh ":
        return false;
    }
    return true;
}

function isKnownCompositorAction(compositor, action) {
    if (!action || !compositor)
        return false;
    var found = findCompositorAction(compositor, action);
    if (found)
        return true;
    var base = action.split(" ")[0];
    return findCompositorAction(compositor, base) !== null;
}

function buildSpawnAction(command, args) {
    if (!command)
        return "";
    let parts = [command];
    if (args && args.length > 0)
        parts = parts.concat(args.filter(function (a) {
            return a;
        }));
    return "spawn " + parts.join(" ");
}

function buildShellAction(compositor, shellCmd, shell) {
    if (!shellCmd)
        return "";
    if (compositor === "mangowc")
        return "spawn_shell " + shellCmd;
    var shellBin = shell || "sh";
    return "spawn " + shellBin + " -c \"" + shellCmd.replace(/"/g, "\\\"") + "\"";
}

function parseSpawnCommand(action) {
    if (!action || !action.startsWith("spawn "))
        return {
            command: "",
            args: []
        };
    const rest = action.slice(6);
    const parts = rest.split(" ").filter(function (p) {
        return p;
    });
    return {
        command: parts[0] || "",
        args: parts.slice(1)
    };
}

function parseShellCommand(action) {
    if (!action)
        return "";
    var match = action.match(/^spawn (\w+) -c (.+)$/);
    if (match) {
        var content = match[2];
        if ((content.startsWith('"') && content.endsWith('"')) || (content.startsWith("'") && content.endsWith("'")))
            content = content.slice(1, -1);
        return content.replace(/\\"/g, "\"");
    }
    if (action.startsWith("spawn_shell "))
        return action.slice(12);
    if (action.startsWith("spawn-sh ")) {
        var cmd = action.slice(9).trim();
        if ((cmd.startsWith('"') && cmd.endsWith('"')) || (cmd.startsWith("'") && cmd.endsWith("'")))
            cmd = cmd.slice(1, -1);
        return cmd;
    }
    return "";
}

function getShellFromAction(action) {
    if (!action)
        return "sh";
    var match = action.match(/^spawn (\w+) -c /);
    return match ? match[1] : "sh";
}

function getActionArgConfig(compositor, action) {
    if (!action)
        return null;

    var baseAction = action.split(" ")[0];
    var compositorArgs = ACTION_ARGS[compositor];
    if (compositorArgs && compositorArgs[baseAction])
        return {
            type: "compositor",
            base: baseAction,
            config: compositorArgs[baseAction]
        };

    var dmsKey = findDmsArgKey(action);
    if (dmsKey)
        return {
            type: "dms",
            base: dmsKey,
            config: DMS_ACTION_ARGS[dmsKey]
        };

    return null;
}

function findDmsArgKey(action) {
    var best = null;
    for (var key in DMS_ACTION_ARGS) {
        var base = DMS_ACTION_ARGS[key].base;
        if (action !== base && !action.startsWith(base + " "))
            continue;
        if (!best || base.length > DMS_ACTION_ARGS[best].base.length)
            best = key;
    }
    return best;
}

function parseCompositorActionArgs(compositor, action) {
    if (!action)
        return {
            base: "",
            args: {}
        };

    var parts = action.split(" ");
    var base = parts[0];
    var args = {};

    var compositorArgs = ACTION_ARGS[compositor];
    if (!compositorArgs || !compositorArgs[base])
        return {
            base: action,
            args: {}
        };

    var argConfig = compositorArgs[base];
    var argParts = parts.slice(1);

    switch (compositor) {
    case "niri":
        switch (base) {
        case "move-column-to-workspace":
            for (var i = 0; i < argParts.length; i++) {
                if (argParts[i] === "focus=true" || argParts[i] === "focus=false") {
                    args.focus = argParts[i] === "focus=true";
                } else if (!args.index) {
                    args.index = argParts[i];
                }
            }
            break;
        case "move-column-to-workspace-down":
        case "move-column-to-workspace-up":
            for (var k = 0; k < argParts.length; k++) {
                if (argParts[k] === "focus=true" || argParts[k] === "focus=false")
                    args.focus = argParts[k] === "focus=true";
            }
            break;
        default:
            for (var j = 0; j < argParts.length; j++) {
                var kv = argParts[j].split("=");
                if (kv.length === 2) {
                    switch (kv[1]) {
                    case "true":
                        args[kv[0]] = true;
                        break;
                    case "false":
                        args[kv[0]] = false;
                        break;
                    default:
                        args[kv[0]] = kv[1];
                    }
                } else {
                    args.value = args.value ? (args.value + " " + argParts[j]) : argParts[j];
                }
            }
        }
        break;
    case "mangowc":
        if (argConfig.args && argConfig.args.length > 0 && argParts.length > 0) {
            var paramStr = argParts.join(" ");
            var remaining = paramStr;

            for (var m = 0; m < argConfig.args.length; m++) {
                var argDef = argConfig.args[m];

                if (m === argConfig.args.length - 1) {
                    args[argDef.name] = remaining;
                    break;
                }

                var commaIdx = remaining.indexOf(",");
                if (commaIdx === -1) {
                    args[argDef.name] = remaining;
                    break;
                }

                args[argDef.name] = remaining.substring(0, commaIdx);
                remaining = remaining.substring(commaIdx + 1);
            }
        }
        break;
    case "hyprland":
        if (argConfig.args && argConfig.args.length > 0) {
            switch (base) {
            case "resizewindowpixel":
            case "movewindowpixel":
                var commaIdx = argParts.join(" ").indexOf(",");
                if (commaIdx !== -1) {
                    var fullStr = argParts.join(" ");
                    args[argConfig.args[0].name] = fullStr.substring(0, commaIdx);
                    args[argConfig.args[1].name] = fullStr.substring(commaIdx + 1);
                } else if (argParts.length > 0) {
                    args[argConfig.args[0].name] = argParts.join(" ");
                }
                break;
            case "movetoworkspace":
            case "movetoworkspacesilent":
            case "tagwindow":
            case "alterzorder":
                if (argParts.length >= 2) {
                    args[argConfig.args[0].name] = argParts[0];
                    args[argConfig.args[1].name] = argParts.slice(1).join(" ");
                } else if (argParts.length === 1) {
                    args[argConfig.args[0].name] = argParts[0];
                }
                break;
            case "moveworkspacetomonitor":
            case "swapactiveworkspaces":
            case "renameworkspace":
            case "fullscreenstate":
            case "fullscreen":
            case "movecursor":
                if (argParts.length >= 2) {
                    args[argConfig.args[0].name] = argParts[0];
                    args[argConfig.args[1].name] = argParts[1];
                } else if (argParts.length === 1) {
                    args[argConfig.args[0].name] = argParts[0];
                }
                break;
            case "setprop":
                if (argParts.length >= 3) {
                    args.window = argParts[0];
                    args.property = argParts[1];
                    args.value = argParts.slice(2).join(" ");
                } else if (argParts.length === 2) {
                    args.window = argParts[0];
                    args.property = argParts[1];
                }
                break;
            case "sendshortcut":
                if (argParts.length >= 3) {
                    args.mod = argParts[0];
                    args.key = argParts[1];
                    args.window = argParts.slice(2).join(" ");
                } else if (argParts.length >= 2) {
                    args.mod = argParts[0];
                    args.key = argParts[1];
                }
                break;
            case "sendkeystate":
                if (argParts.length >= 4) {
                    args.mod = argParts[0];
                    args.key = argParts[1];
                    args.state = argParts[2];
                    args.window = argParts.slice(3).join(" ");
                }
                break;
            case "signalwindow":
                if (argParts.length >= 2) {
                    args.window = argParts[0];
                    args.signal = argParts[1];
                }
                break;
            default:
                if (argParts.length > 0) {
                    if (argConfig.args.length === 1) {
                        args[argConfig.args[0].name] = argParts.join(" ");
                    } else {
                        args.value = argParts.join(" ");
                    }
                }
            }
        }
        break;
    default:
        if (argParts.length > 0)
            args.value = argParts.join(" ");
    }

    return {
        base: base,
        args: args
    };
}

function buildCompositorAction(compositor, base, args) {
    if (!base)
        return "";

    var parts = [base];

    if (!args || Object.keys(args).length === 0)
        return base;

    switch (compositor) {
    case "niri":
        switch (base) {
        case "move-column-to-workspace":
            if (args.index)
                parts.push(args.index);
            if (args.focus === false)
                parts.push("focus=false");
            break;
        case "move-column-to-workspace-down":
        case "move-column-to-workspace-up":
            if (args.focus === false)
                parts.push("focus=false");
            break;
        default:
            if (args.value)
                parts.push(args.value);
            else if (args.index)
                parts.push(args.index);
            for (var prop in args) {
                switch (prop) {
                case "value":
                case "index":
                    continue;
                }
                var val = args[prop];
                if (val === true)
                    parts.push(prop + "=true");
                else if (val === false)
                    parts.push(prop + "=false");
                else if (val !== undefined && val !== null && val !== "")
                    parts.push(prop + "=" + val);
            }
        }
        break;
    case "mangowc":
        var compositorArgs = ACTION_ARGS.mangowc;
        if (compositorArgs && compositorArgs[base] && compositorArgs[base].args) {
            var argConfig = compositorArgs[base].args;
            var argValues = [];

            for (var i = 0; i < argConfig.length; i++) {
                var argDef = argConfig[i];
                var val = args[argDef.name];

                if (val === undefined || val === "") {
                    if (argDef.emptyValue !== undefined)
                        val = argDef.emptyValue;
                    else if (argDef.default !== undefined)
                        val = argDef.default;
                    else
                        val = "";
                }

                argValues.push(val);
            }

            while (argValues.length > 0 && argValues[argValues.length - 1] === "")
                argValues.pop();

            if (argValues.length > 0)
                parts.push(argValues.join(","));
        } else if (args.value) {
            parts.push(args.value);
        }
        break;
    case "hyprland":
        var hyprArgs = ACTION_ARGS.hyprland;
        if (hyprArgs && hyprArgs[base] && hyprArgs[base].args) {
            var hyprConfig = hyprArgs[base].args;
            switch (base) {
            case "resizewindowpixel":
            case "movewindowpixel":
                if (args[hyprConfig[0].name])
                    parts.push(args[hyprConfig[0].name]);
                if (args[hyprConfig[1].name])
                    parts[parts.length - 1] += "," + args[hyprConfig[1].name];
                break;
            case "setprop":
                if (args.window)
                    parts.push(args.window);
                if (args.property)
                    parts.push(args.property);
                if (args.value)
                    parts.push(args.value);
                break;
            case "sendshortcut":
                if (args.mod)
                    parts.push(args.mod);
                if (args.key)
                    parts.push(args.key);
                if (args.window)
                    parts.push(args.window);
                break;
            case "sendkeystate":
                if (args.mod)
                    parts.push(args.mod);
                if (args.key)
                    parts.push(args.key);
                if (args.state)
                    parts.push(args.state);
                if (args.window)
                    parts.push(args.window);
                break;
            case "signalwindow":
                if (args.window)
                    parts.push(args.window);
                if (args.signal)
                    parts.push(args.signal);
                break;
            default:
                for (var j = 0; j < hyprConfig.length; j++) {
                    var hVal = args[hyprConfig[j].name];
                    if (hVal !== undefined && hVal !== "")
                        parts.push(hVal);
                }
            }
        } else if (args.value) {
            parts.push(args.value);
        }
        break;
    default:
        if (args.value)
            parts.push(args.value);
    }

    return parts.join(" ");
}

function parseDmsActionArgs(action) {
    if (!action)
        return {
            base: "",
            args: {}
        };

    var key = findDmsArgKey(action);
    if (!key)
        return {
            base: action,
            args: {}
        };

    var config = DMS_ACTION_ARGS[key];
    var rest = action.slice(config.base.length).trim();
    var result = {
        base: key,
        args: {}
    };

    if (!rest)
        return result;

    var tokens = [];
    var current = "";
    var inQuotes = false;
    var hadQuotes = false;
    for (var i = 0; i < rest.length; i++) {
        var c = rest[i];
        switch (c) {
        case '"':
            inQuotes = !inQuotes;
            hadQuotes = true;
            break;
        case ' ':
            if (inQuotes) {
                current += c;
            } else if (current || hadQuotes) {
                tokens.push(current);
                current = "";
                hadQuotes = false;
            }
            break;
        default:
            current += c;
            break;
        }
    }
    if (current || hadQuotes)
        tokens.push(current);

    var positional = tokens.filter(t => !t.startsWith("--"));
    var p = 0;
    for (var j = 0; j < config.args.length; j++) {
        var argDef = config.args[j];
        if (argDef.type === "flag") {
            result.args[argDef.name] = tokens.indexOf(argDef.flag) !== -1;
            continue;
        }
        if (p >= positional.length)
            break;
        result.args[argDef.name] = positional[p++];
    }

    return result;
}

function buildDmsAction(baseKey, args) {
    var config = DMS_ACTION_ARGS[baseKey];
    if (!config)
        return "";

    var parts = [config.base];
    var positional = config.args.filter(a => a.type !== "flag");
    var flags = config.args.filter(a => a.type === "flag");

    for (var i = 0; i < positional.length; i++) {
        var argDef = positional[i];
        var value = args?.[argDef.name];
        if (value === undefined || value === null)
            value = argDef.default ?? "";

        if (argDef.type === "text" && value === "") {
            parts.push('""');
        } else if (value !== "") {
            parts.push(value);
        } else {
            break;
        }
    }

    for (var f = 0; f < flags.length; f++) {
        if (args?.[flags[f].name] === true)
            parts.push(flags[f].flag);
    }

    return parts.join(" ");
}
