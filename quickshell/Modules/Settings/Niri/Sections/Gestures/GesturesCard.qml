pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Niri.Components

// Only the gestures niri has today (docs/wiki/Gestures.md), one card per device.
Flow {
    id: root

    component Group: NiriCard {
        default property alias tiles: list.data

        width: root.cell

        Column {
            id: list
            width: parent.width
            spacing: Theme.spacingS
        }
    }

    // The gesture hovered or focused; the stage in the side pane plays it.
    property string gesture: ""
    property string sentence: ""
    property int replays: 0

    component Tile: GestTile {
        id: tile

        onActiveChanged: {
            if (active) {
                root.sentence = sentence;
                root.gesture = gesture;
            } else if (root.gesture === gesture) {
                root.gesture = "";
            }
        }
        onPlayRequested: {
            root.sentence = sentence;
            root.gesture = gesture;
            root.replays++;
        }
    }

    // Three device groups: three lanes when they fit, one stacked lane below the fold, never
    // two, where the third group would sit orphaned on the left of an empty row.
    readonly property int columns: width >= Theme.iconButtonSize * 16.5 + spacing * 2 ? 3 : 1
    readonly property real cell: (width - spacing * (columns - 1)) / columns

    width: parent?.width ?? 0
    spacing: Theme.spacingM

    Group {
        icon: "trackpad_input"
        title: I18n.tr("Touchpad", "niri gestures device")

        Tile {
            gesture: "ws"
            title: I18n.tr("Workspaces", "niri gesture")
            hint: I18n.tr("3 fingers up or down", "niri gesture")
            sentence: I18n.tr("Swipe 3 fingers up or down", "niri gesture")
            arrow: "swap_vert"
        }
        Tile {
            gesture: "cols"
            title: I18n.tr("Columns", "niri gesture")
            hint: I18n.tr("3 fingers left or right", "niri gesture")
            sentence: I18n.tr("Swipe 3 fingers left or right", "niri gesture")
            arrow: "swap_horiz"
        }
        Tile {
            gesture: "ov"
            title: I18n.tr("Overview", "niri gesture")
            hint: I18n.tr("4 fingers up or down", "niri gesture")
            sentence: I18n.tr("Swipe 4 fingers up or down", "niri gesture")
            fingers: 4
            arrow: "swap_vert"
        }
    }

    Group {
        icon: "mouse"
        title: I18n.tr("Mouse", "niri gestures device")

        Tile {
            gesture: "move"
            title: I18n.tr("Move", "niri gesture")
            hint: I18n.tr("left drag", "niri gesture")
            sentence: I18n.tr("Hold Super, drag with the left button", "niri gesture")
            device: "mouse"
            part: "left"
            mod: true
        }
        Tile {
            gesture: "resize"
            title: I18n.tr("Resize", "niri gesture")
            hint: I18n.tr("right drag", "niri gesture")
            sentence: I18n.tr("Hold Super, drag with the right button", "niri gesture")
            device: "mouse"
            part: "right"
            mod: true
        }
        Tile {
            gesture: "view"
            title: I18n.tr("Scroll the view", "niri gesture")
            hint: I18n.tr("wheel or middle drag", "niri gesture")
            sentence: I18n.tr("Hold Super, turn the wheel or drag with the middle button", "niri gesture")
            device: "mouse"
            part: "wheel"
            mod: true
        }
    }

    Group {
        icon: "tablet_android"
        title: I18n.tr("Touchscreen", "niri gestures device")

        Tile {
            gesture: "tmove"
            title: I18n.tr("Move", "niri gesture")
            hint: I18n.tr("drag a finger", "niri gesture")
            sentence: I18n.tr("Hold Super, drag a finger", "niri gesture")
            device: "touch"
            part: "touch_app"
            mod: true
        }
        Tile {
            gesture: "float"
            title: I18n.tr("Float or tile", "niri gesture")
            hint: I18n.tr("While moving, tap a 2nd finger", "niri gesture")
            sentence: I18n.tr("While moving, tap a second finger", "niri gesture")
            device: "touch"
            part: "back_hand"
        }
    }
}
