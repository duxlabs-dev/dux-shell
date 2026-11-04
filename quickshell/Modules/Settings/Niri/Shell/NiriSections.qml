import QtQuick
import qs.Common

QtObject {
    readonly property var all: [
        {
            "id": "windows",
            "icon": "view_column",
            "text": I18n.tr("Windows", "niri page section")
        },
        {
            "id": "animations",
            "icon": "animation",
            "text": I18n.tr("Animations", "niri page section")
        },
        {
            "id": "workspaces",
            "icon": "space_dashboard",
            "text": I18n.tr("Workspaces", "niri page section")
        },
        {
            "id": "keybinds",
            "icon": "keyboard",
            "text": I18n.tr("Keybinds", "niri page section")
        },
        {
            "id": "gestures",
            "icon": "swipe",
            "text": I18n.tr("Gestures", "niri page section")
        },
        {
            "id": "input",
            "icon": "mouse",
            "text": I18n.tr("Input", "niri page section")
        },
        {
            "id": "startup",
            "icon": "rocket_launch",
            "text": I18n.tr("Startup", "niri page section"),
            "expertOnly": true
        },
        {
            "id": "advanced",
            "icon": "warning",
            "text": I18n.tr("Advanced", "niri page section"),
            "warn": true,
            "expertOnly": true
        }
    ]
}
