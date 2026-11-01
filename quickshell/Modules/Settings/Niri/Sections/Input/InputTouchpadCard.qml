pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components
import qs.Modules.Settings.Widgets

// One card for the pointer devices, as the mockup: its rows (tap, natural scrolling,
// focus follows mouse, pointer jumps to focus, speed) in Simple, the rest of what a
// touchpad or a mouse has in Expert.
NiriCard {
    id: root

    readonly property var profiles: [
        {
            "value": "default",
            "text": I18n.tr("Default")
        },
        {
            "value": "flat",
            "text": I18n.tr("Flat", "adjective, pointer acceleration profile option")
        },
        {
            "value": "adaptive",
            "text": I18n.tr("Adaptive", "adjective, pointer acceleration profile option")
        }
    ]
    readonly property var scrollMethods: ["default", "two-finger", "edge", "no-scroll", "on-button-down"]
    readonly property var scrollMethodNames: [I18n.tr("Default"), I18n.tr("Two-finger", "touchpad scroll method option"), I18n.tr("Edge", "noun, touchpad scroll method option, scroll along the pad edge"), I18n.tr("No scroll"), I18n.tr("On button down")]

    title: I18n.tr("Touchpad and mouse", "niri page input card")
    icon: "touchpad_mouse"

    Flow {
        id: tiles

        // Two tiles: two columns when they fit, never more, so no slot stays empty on their row
        readonly property int columns: Math.min(2, Math.max(1, Math.floor((width + Theme.spacingS) / (Theme.iconButtonSize * 4.25 + Theme.spacingS))))
        readonly property real tileWidth: (width - Theme.spacingS * (columns - 1)) / columns

        width: parent.width
        spacing: Theme.spacingS
        bottomPadding: Theme.spacingS

        NiriTile {
            id: tapTile
            width: tiles.tileWidth
            settingKey: "input.tap"
            title: I18n.tr("Tap to click")
            kdlKey: "input.touchpad.tap"

            InputTileArt {
                kind: "tap"
                on: tapTile.on
                hovered: tapTile.hovered
            }
        }

        NiriTile {
            id: naturalTile
            width: tiles.tileWidth
            settingKey: "input.touchpadNatural"
            title: I18n.tr("Natural scrolling")
            tip: I18n.tr("Content follows your fingers, like on a phone")
            kdlKey: "input.touchpad.natural-scroll"

            InputTileArt {
                kind: "natural"
                on: naturalTile.on
                hovered: naturalTile.hovered
            }
        }
    }

    // focusFollowsMouse is an int (-1 unset, 0 off, 1 on), which NiriRow cannot toggle, so it is its own row.
    NiriRow {
        id: followRow

        readonly property bool following: SettingsData.focusFollowsMouse === 1

        settingKey: "input.focusFollowsMouse"
        icon: "arrow_selector_tool"
        title: I18n.tr("Focus follows mouse", "Toggle that focuses a window when the pointer moves over it")
        tip: I18n.tr("The window under the pointer gets the focus")
        kdlKey: "input.focus-follows-mouse"
        tryValue: following ? 0 : 1

        DToggle {
            anchors.verticalCenter: parent.verticalCenter
            checked: followRow.following
            Accessible.name: followRow.title
            onToggled: checked => SettingsData.set("focusFollowsMouse", checked ? 1 : 0)
        }
    }

    NiriTile {
        id: warpTile

        width: parent.width
        settingKey: "input.warp"
        title: I18n.tr("Pointer jumps to focus")
        tip: I18n.tr("When the keyboard focuses a window, the pointer moves into it")
        kdlKey: "input.warp-mouse-to-focus"

        InputTileArt {
            kind: "warp"
            on: warpTile.on
            hovered: warpTile.hovered
        }
    }

    NiriSlider {
        settingKey: "input.touchpadSpeed"
        icon: "speed"
        title: I18n.tr("Pointer speed")
        kdlKey: "input.touchpad.accel-speed"
        from: -1
        to: 1
        stepSize: 0.1
        decimals: 1
    }

    Column {
        width: parent.width
        spacing: Theme.spacingXXS
        visible: NiriPageService.expert

        NiriSeg {
            settingKey: "input.touchpadProfile"
            icon: "trending_up"
            title: I18n.tr("Acceleration profile")
            kdlKey: "input.touchpad.accel-profile"
            options: root.profiles
        }

        NiriSlider {
            settingKey: "input.touchpadScroll"
            icon: "swap_vert"
            title: I18n.tr("Scroll speed")
            kdlKey: "input.touchpad.scroll-factor"
            from: 0.1
            to: 3
            stepSize: 0.1
            decimals: 1
            unit: "×"
        }

        NiriRow {
            settingKey: "input.tapDrag"
            icon: "drag_pan"
            title: I18n.tr("Tap and drag")
            kdlKey: "input.touchpad.drag"
        }

        NiriRow {
            settingKey: "input.dragLock"
            dependsOn: "input.tapDrag"
            icon: "lock"
            title: I18n.tr("Drag lock")
            tip: I18n.tr("Lifting the finger briefly does not drop what you drag")
            kdlKey: "input.touchpad.drag-lock"
        }

        NiriRow {
            settingKey: "input.dwt"
            icon: "keyboard_hide"
            title: I18n.tr("Disable while typing")
            kdlKey: "input.touchpad.dwt"
        }

        NiriRow {
            settingKey: "input.dwtExternal"
            icon: "mouse"
            title: I18n.tr("Disable with external mouse")
            kdlKey: "input.touchpad.disabled-on-external-mouse"
        }

        NiriSeg {
            settingKey: "input.clickMethod"
            icon: "ads_click"
            title: I18n.tr("Click method", "Rules by which touchpad input determines left, right and middle click")
            kdlKey: "input.touchpad.click-method"
            options: [
                {
                    "value": "default",
                    "text": I18n.tr("Default")
                },
                {
                    "value": "button-areas",
                    "text": I18n.tr("Button areas", "Touchpad click method: click type is determined by finger position")
                },
                {
                    "value": "clickfinger",
                    "text": I18n.tr("Clickfinger", "Touchpad click method: click type is determined by finger count")
                }
            ]
        }

        NiriRow {
            id: methodRow

            settingKey: "input.touchpadScrollMethod"
            icon: "unfold_more"
            title: I18n.tr("Scroll method")
            kdlKey: "input.touchpad.scroll-method"
            controlWidth: methodDropdown.width

            DDropdown {
                id: methodDropdown
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconButtonSize * 4.5
                dropdownWidth: width
                options: root.scrollMethodNames
                currentValue: root.scrollMethodNames[Math.max(0, root.scrollMethods.indexOf(SettingsData.touchpadScrollMethod))]
                onValueChanged: value => {
                    const index = root.scrollMethodNames.indexOf(value);
                    if (index >= 0)
                        SettingsData.set("touchpadScrollMethod", root.scrollMethods[index]);
                }
            }
        }

        NiriRow {
            settingKey: "input.touchpadMiddle"
            icon: "mouse"
            title: I18n.tr("Middle click emulation")
            kdlKey: "input.touchpad.middle-emulation"
        }

        InputMouseRows {
            profiles: root.profiles
        }
    }
}
