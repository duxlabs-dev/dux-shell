pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components
import qs.Modules.Settings.Widgets
import "../../../../../Common/niri/sections/input.js" as InputSection
import "../../../../../Common/niri/keep.js" as Keep

NiriCard {
    id: root

    readonly property real fieldWidth: Theme.iconButtonSize * 4.5
    readonly property bool expert: NiriPageService.expert
    readonly property var switchOptions: [I18n.tr("Alt + Shift"), I18n.tr("Ctrl + Shift"), I18n.tr("Caps lock"), I18n.tr("Super + Space"), I18n.tr("Custom / None")]

    title: I18n.tr("Keyboard", "niri page input card")
    icon: "keyboard"

    NiriRow {
        id: layoutRow

        settingKey: "input.layouts"
        icon: "language"
        title: I18n.tr("Layout", "keyboard layout")
        tip: I18n.tr("Comma-separated layouts, like us,fr. A new layout goes back after %1 s unless you keep it.").arg(Keep.seconds)
        kdlKey: "input.keyboard.xkb.layout"
        controlWidth: caps.width + Theme.spacingS + root.fieldWidth

        Row {
            id: caps
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXXS
            Accessible.ignored: true

            Repeater {
                model: InputSection.topRow(SettingsData.keyboardLayouts).split("")

                DKeycap {
                    required property string modelData
                    text: modelData
                }
            }
        }

        DTextField {
            anchors.verticalCenter: parent.verticalCenter
            width: layoutRow.stacked ? Math.max(0, layoutRow.stackedControlWidth - caps.width - Theme.spacingS) : root.fieldWidth
            text: SettingsData.keyboardLayouts
            placeholderText: I18n.tr("System default", "keyboard layout field left empty")
            Accessible.name: layoutRow.title
            onEditingFinished: keeper.edit(layoutRow.settingKey, text.trim())
        }
    }

    NiriKeep {
        id: keeper
        risky: InputSection.risky
    }

    NiriRow {
        icon: "swap_horiz"
        title: I18n.tr("Switch layout shortcut")
        controlWidth: switchDropdown.width

        DDropdown {
            id: switchDropdown

            readonly property int index: {
                const group = InputSection.switchOf(SettingsData.keyboardOptions);
                return group ? InputSection.switchGroups.indexOf(group) : root.switchOptions.length - 1;
            }

            anchors.verticalCenter: parent.verticalCenter
            dropdownWidth: root.fieldWidth
            width: root.fieldWidth
            options: root.switchOptions
            currentValue: root.switchOptions[index]
            onValueChanged: value => {
                const index = root.switchOptions.indexOf(value);
                if (index < 0)
                    return;
                SettingsData.set("keyboardOptions", InputSection.withSwitch(SettingsData.keyboardOptions, InputSection.switchGroups[index] ?? ""));
            }
        }
    }

    NiriRow {
        id: delayRow

        settingKey: "input.repeatDelay"
        icon: "timer"
        title: I18n.tr("Repeat delay")
        tip: I18n.tr("How long to hold a key before it repeats")
        kdlKey: "input.keyboard.repeat-delay"
        controlWidth: delay.naturalWidth

        InputSliderControl {
            id: delay
            fillWidth: delayRow.stacked ? delayRow.stackedControlWidth : 0
            anchors.verticalCenter: parent.verticalCenter
            value: SettingsData.keyboardRepeatDelay
            fallback: 600
            from: 100
            to: 2000
            stepSize: 50
            unit: " ms"
            accessibleName: I18n.tr("Repeat delay")
            onMoved: v => SettingsData.set("keyboardRepeatDelay", v)
        }
    }

    NiriRow {
        id: rateRow

        settingKey: "input.repeatRate"
        icon: "speed"
        title: I18n.tr("Repeat rate")
        tip: I18n.tr("Characters per second while a key is held")
        kdlKey: "input.keyboard.repeat-rate"
        controlWidth: rate.naturalWidth

        InputSliderControl {
            id: rate
            fillWidth: rateRow.stacked ? rateRow.stackedControlWidth : 0
            anchors.verticalCenter: parent.verticalCenter
            value: SettingsData.keyboardRepeatRate
            fallback: 25
            from: 1
            to: 100
            unit: "/s"
            accessibleName: I18n.tr("Repeat rate")
            onMoved: v => SettingsData.set("keyboardRepeatRate", v)
        }
    }

    NiriRow {
        settingKey: "input.numlock"
        icon: "dialpad"
        title: I18n.tr("Num Lock at startup")
        kdlKey: "input.keyboard.numlock"
    }

    NiriSeg {
        settingKey: "input.trackLayout"
        icon: "bookmark"
        title: I18n.tr("Remember layout")
        kdlKey: "input.keyboard.track-layout"
        options: [
            {
                "value": "",
                "text": I18n.tr("Globally", "adverb, remember keyboard layout option, opposite of per window")
            },
            {
                "value": "window",
                "text": I18n.tr("Per window")
            }
        ]
    }

    Repeater {
        // Raw xkb fields: Expert only, and kept or reverted like the layout
        model: root.expert ? [
            {
                "key": "input.xkbOptions",
                "prop": "keyboardOptions",
                "icon": "tune",
                "title": I18n.tr("XKB options"),
                "kdl": "input.keyboard.xkb.options",
                "hint": "compose:ralt,ctrl:nocaps"
            },
            {
                "key": "input.variants",
                "prop": "keyboardVariants",
                "icon": "keyboard",
                "title": I18n.tr("Variant", "noun, xkb keyboard layout variant field label"),
                "kdl": "input.keyboard.xkb.variant",
                "hint": "colemak"
            },
            {
                "key": "input.model",
                "prop": "keyboardModel",
                "icon": "keyboard",
                "title": I18n.tr("Model", "noun, hardware model of keyboard, display or printer"),
                "kdl": "input.keyboard.xkb.model",
                "hint": "pc104"
            },
            {
                "key": "input.keymapFile",
                "prop": "keyboardKeymapFile",
                "icon": "description",
                "title": I18n.tr("Keymap file"),
                "kdl": "input.keyboard.xkb.file",
                "hint": "~/.config/keymap.xkb"
            }
        ] : []

        NiriRow {
            id: fieldRow

            required property var modelData

            settingKey: modelData.key
            icon: modelData.icon
            title: modelData.title
            kdlKey: modelData.kdl
            controlWidth: root.fieldWidth

            DTextField {
                anchors.verticalCenter: parent.verticalCenter
                width: fieldRow.stacked ? fieldRow.stackedControlWidth : root.fieldWidth
                text: SettingsData[fieldRow.modelData.prop]
                placeholderText: fieldRow.modelData.hint
                Accessible.name: fieldRow.title
                onEditingFinished: keeper.edit(fieldRow.settingKey, text.trim())
            }
        }
    }
}
