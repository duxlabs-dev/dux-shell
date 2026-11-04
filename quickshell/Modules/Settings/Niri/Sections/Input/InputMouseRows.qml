import QtQuick
import qs.Common
import qs.Modules.Settings.Niri.Components

// The mouse rows of the Expert column, titled as the search lists them so the touchpad twins read apart
Column {
    id: root

    // The acceleration profile options, shared with the touchpad row
    required property var profiles

    width: parent.width
    spacing: Theme.spacingXXS

    NiriRow {
        settingKey: "input.mouseNatural"
        icon: "swipe_vertical"
        title: I18n.tr("Mouse natural scrolling")
        kdlKey: "input.mouse.natural-scroll"
    }

    NiriSlider {
        settingKey: "input.mouseSpeed"
        icon: "speed"
        title: I18n.tr("Mouse pointer speed")
        kdlKey: "input.mouse.accel-speed"
        from: -1
        to: 1
        stepSize: 0.1
        decimals: 1
    }

    NiriSeg {
        settingKey: "input.mouseProfile"
        icon: "trending_up"
        title: I18n.tr("Mouse acceleration profile")
        kdlKey: "input.mouse.accel-profile"
        options: root.profiles
    }

    NiriSlider {
        settingKey: "input.mouseScroll"
        icon: "swap_vert"
        title: I18n.tr("Mouse scroll speed")
        kdlKey: "input.mouse.scroll-factor"
        from: 0.1
        to: 3
        stepSize: 0.1
        decimals: 1
        unit: "×"
    }

    NiriRow {
        settingKey: "input.leftHanded"
        icon: "front_hand"
        title: I18n.tr("Left-handed", "mouse toggle, swap primary and secondary buttons")
        kdlKey: "input.mouse.left-handed"
    }

    NiriSeg {
        settingKey: "input.mouseScrollMethod"
        icon: "unfold_more"
        title: I18n.tr("Mouse scroll method")
        kdlKey: "input.mouse.scroll-method"
        options: [
            {
                "value": "default",
                "text": I18n.tr("Default")
            },
            {
                "value": "no-scroll",
                "text": I18n.tr("No scroll")
            },
            {
                "value": "on-button-down",
                "text": I18n.tr("On button down")
            }
        ]
    }

    NiriRow {
        settingKey: "input.mouseMiddle"
        icon: "mouse"
        title: I18n.tr("Mouse middle click emulation")
        kdlKey: "input.mouse.middle-emulation"
    }
}
