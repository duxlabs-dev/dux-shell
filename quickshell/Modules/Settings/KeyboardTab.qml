import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    ConfigInclude {
        id: inputInclude
        includeKind: "input"
        procTag: "input-include-keyboard"
        onFixed: SettingsData.updateCompositorInput()
    }

    SettingsPage {
        id: settingsColumn

        IncludeSetupBanner {
            include: inputInclude
            visibleCondition: CompositorService.supportsInputConfig
        }

        SettingsCard {
            width: parent.width
            tags: ["keyboard", "layout", "language", "input", "xkb"]
            title: I18n.tr("Layouts")
            settingKey: "keyboardLayoutsSettings"
            iconName: "keyboard"

            SettingsTextFieldRow {
                resetKeys: ["keyboardLayouts"]
                leftIconName: "keyboard"
                text: I18n.tr("Layouts", "noun plural, keyboard layouts card title and field label")
                description: I18n.tr("Comma-separated list of layout names. Leave empty to use the system keyboard settings.")
                value: SettingsData.keyboardLayouts
                placeholderText: "us,de"
                onValueEdited: value => SettingsData.set("keyboardLayouts", value)
            }

            SettingsDropdownRow {
                tags: ["keyboard", "layout", "switch", "shortcut", "xkb"]
                settingKey: "keyboardOptions"
                resetKeys: []
                text: I18n.tr("Switch layout shortcut")
                options: [I18n.tr("Alt + Shift"), I18n.tr("Both Shift keys"), I18n.tr("Caps lock"), I18n.tr("Custom / None")]
                description: currentValue === options[0] ? I18n.tr("Alt + Shift shortcuts in apps and keybinds stop working.") : ""
                currentValue: {
                    const opt = SettingsData.keyboardOptions;
                    if (opt.includes("grp:alt_shift_toggle"))
                        return options[0];
                    if (opt.includes("grp:shifts_toggle"))
                        return options[1];
                    if (opt.includes("grp:caps_toggle"))
                        return options[2];
                    return options[3];
                }
                onValueChanged: value => {
                    const idx = options.indexOf(value);
                    let opt = SettingsData.keyboardOptions.split(",").filter(o => !o.startsWith("grp:")).join(",");

                    let newGrp = "";
                    switch (idx) {
                    case 0:
                        newGrp = "grp:alt_shift_toggle";
                        break;
                    case 1:
                        newGrp = "grp:shifts_toggle";
                        break;
                    case 2:
                        newGrp = "grp:caps_toggle";
                        break;
                    }

                    if (newGrp)
                        opt = opt ? opt + "," + newGrp : newGrp;
                    SettingsData.set("keyboardOptions", opt);
                }
            }

            SettingsTextFieldRow {
                resetKeys: ["keyboardOptions"]
                leftIconName: "tune"
                text: I18n.tr("XKB options")
                description: I18n.tr("Advanced comma-separated libxkbcommon options.")
                value: SettingsData.keyboardOptions
                placeholderText: "compose:ralt,ctrl:nocaps"
                onValueEdited: value => SettingsData.set("keyboardOptions", value)
            }

            SettingsTextFieldRow {
                resetKeys: ["keyboardVariants"]
                leftIconName: "keyboard"
                text: I18n.tr("Variant", "noun, xkb keyboard layout variant field label")
                value: SettingsData.keyboardVariants
                placeholderText: "colemak"
                onValueEdited: value => SettingsData.set("keyboardVariants", value)
            }

            SettingsTextFieldRow {
                resetKeys: ["keyboardModel"]
                leftIconName: "keyboard"
                text: I18n.tr("Model", "noun, hardware model of keyboard, display or printer")
                value: SettingsData.keyboardModel
                placeholderText: "pc104"
                onValueEdited: value => SettingsData.set("keyboardModel", value)
            }

            SettingsTextFieldRow {
                visible: CompositorService.isNiri || CompositorService.isHyprland
                resetKeys: ["keyboardKeymapFile"]
                leftIconName: "description"
                text: I18n.tr("Keymap file")
                description: I18n.tr("Direct path to a .xkb keymap file. Overrides layouts/variants above.")
                value: SettingsData.keyboardKeymapFile
                placeholderText: "~/.config/keymap.xkb"
                onValueEdited: value => SettingsData.set("keyboardKeymapFile", value)
            }
        }

        SettingsCard {
            width: parent.width
            tags: ["keyboard", "repeat", "delay", "rate", "numlock", "behavior"]
            title: I18n.tr("Behavior")
            settingKey: "keyboardBehaviorSettings"
            iconName: "settings"

            SettingsButtonGroupRow {
                visible: CompositorService.isNiri
                tags: ["keyboard", "track", "layout"]
                settingKey: "keyboardTrackLayout"
                text: I18n.tr("Remember layout")
                model: [I18n.tr("Globally", "adverb, remember keyboard layout option, opposite of per window"), I18n.tr("Per window")]
                currentIndex: SettingsData.keyboardTrackLayout === "window" ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("keyboardTrackLayout", index === 1 ? "window" : "global");
                }
            }

            SettingsToggleRow {
                tags: ["keyboard", "numlock", "startup"]
                settingKey: "keyboardNumlock"
                text: I18n.tr("Num Lock at startup")
                checked: SettingsData.keyboardNumlock
                onToggled: checked => SettingsData.set("keyboardNumlock", checked)
            }

            SettingsSliderRow {
                tags: ["keyboard", "repeat", "delay", "speed"]
                settingKey: "keyboardRepeatDelay"
                text: I18n.tr("Repeat delay")
                value: SettingsData.keyboardRepeatDelay || 600
                minimum: 100
                maximum: 2000
                step: 50
                unit: "ms"
                onSliderValueChanged: newValue => SettingsData.set("keyboardRepeatDelay", newValue)
            }

            SettingsSliderRow {
                tags: ["keyboard", "repeat", "rate", "speed"]
                settingKey: "keyboardRepeatRate"
                text: I18n.tr("Repeat rate")
                value: SettingsData.keyboardRepeatRate || 25
                minimum: 1
                maximum: 100
                step: 1
                unit: "/s"
                onSliderValueChanged: newValue => SettingsData.set("keyboardRepeatRate", newValue)
            }
        }
    }
}
