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
        procTag: "input-include-mouse"
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
            visible: CompositorService.supportsInputConfig
            tags: ["mouse", "input", "sensitivity", "acceleration", "pointer"]
            title: I18n.tr("Mouse", "mouse input settings card title")
            settingKey: "mouseSettings"
            iconName: "mouse"

            SettingsToggleRow {
                // Only Hyprland can report the live mode; untouched niri and Mango show their defaults
                readonly property int inheritedMode: CompositorService.isHyprland ? HyprlandService.followMouseMode : CompositorService.isMango ? 1 : 0
                visible: CompositorService.supportsInputConfig && (!CompositorService.isHyprland || HyprlandService.hyprSupports("input:follow_mouse"))
                enabled: inputInclude.included && (!CompositorService.isHyprland || (HyprlandService.luaConfigActive && HyprlandService.followMouseMode >= 0))
                tags: ["mouse", "focus", "follow", "pointer", "window", "sloppy"]
                settingKey: "focusFollowsMouse"
                resetKeys: ["focusFollowsMouse"]
                text: I18n.tr("Focus follows mouse", "Toggle that focuses a window when the pointer moves over it")
                checked: (SettingsData.focusFollowsMouse < 0 ? inheritedMode : SettingsData.focusFollowsMouse) === 1
                onToggled: checked => SettingsData.set("focusFollowsMouse", checked ? 1 : 0)
            }

            SettingsToggleRow {
                visible: CompositorService.isHyprland && HyprlandService.hyprSupports("input:swallow_focus_click")
                tags: ["mouse", "focus", "click", "swallow", "window", "swallow_focus_click"]
                settingKey: "hyprlandSwallowFocusClick"
                text: I18n.tr("Swallow focus click", "Hyprland toggle, the click that focuses a window is not passed to the app")
                description: I18n.tr("The click that focuses a window does not reach the app")
                checked: SettingsData.hyprlandSwallowFocusClick
                onToggled: checked => SettingsData.set("hyprlandSwallowFocusClick", checked)
            }

            SettingsSliderRow {
                tags: ["mouse", "sensitivity", "speed", "accel"]
                settingKey: "mouseAccelSpeed"
                text: I18n.tr("Pointer speed")
                value: Math.round(SettingsData.mouseAccelSpeed * 10)
                unit: ""
                decimals: 1
                minimum: -10
                maximum: 10
                step: 1
                onSliderValueChanged: newValue => SettingsData.set("mouseAccelSpeed", newValue / 10.0)
            }

            SettingsToggleRow {
                tags: ["mouse", "natural", "scroll", "direction"]
                settingKey: "mouseNaturalScroll"
                text: I18n.tr("Natural scrolling")
                checked: SettingsData.mouseNaturalScroll
                onToggled: checked => SettingsData.set("mouseNaturalScroll", checked)
            }

            SettingsSliderRow {
                tags: ["mouse", "scroll", "speed", "factor"]
                settingKey: "mouseScrollFactor"
                text: I18n.tr("Scroll speed")
                value: Math.round(SettingsData.mouseScrollFactor * 10)
                unit: "×"
                decimals: 1
                minimum: 1
                maximum: 30
                step: 1
                onSliderValueChanged: newValue => SettingsData.set("mouseScrollFactor", newValue / 10.0)
            }

            SettingsToggleRow {
                tags: ["mouse", "left", "handed", "button", "swap"]
                settingKey: "mouseLeftHanded"
                text: I18n.tr("Left-handed", "mouse toggle, swap primary and secondary buttons")
                checked: SettingsData.mouseLeftHanded
                onToggled: checked => SettingsData.set("mouseLeftHanded", checked)
            }

            SettingsButtonGroupRow {
                tags: ["mouse", "acceleration", "profile"]
                settingKey: "mouseAccelProfile"
                text: I18n.tr("Acceleration profile")
                model: [I18n.tr("Default"), I18n.tr("Flat", "adjective, pointer acceleration profile option"), I18n.tr("Adaptive", "adjective, pointer acceleration profile option")]
                currentIndex: {
                    if (SettingsData.mouseAccelProfile === "flat")
                        return 1;
                    if (SettingsData.mouseAccelProfile === "adaptive")
                        return 2;
                    return 0;
                }
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    const profiles = ["default", "flat", "adaptive"];
                    SettingsData.set("mouseAccelProfile", profiles[index]);
                }
            }

            SettingsDropdownRow {
                id: mouseScrollMethodRow

                readonly property var methods: ["default", "no-scroll", "on-button-down"]

                tags: ["mouse", "scroll", "method"]
                settingKey: "mouseScrollMethod"
                text: I18n.tr("Scroll method")
                options: [I18n.tr("Default"), I18n.tr("No scroll"), I18n.tr("On button down")]
                currentValue: options[Math.max(0, methods.indexOf(SettingsData.mouseScrollMethod))]
                onValueChanged: value => {
                    const index = mouseScrollMethodRow.options.indexOf(value);
                    if (index < 0)
                        return;
                    SettingsData.set("mouseScrollMethod", mouseScrollMethodRow.methods[index]);
                }
            }

            SettingsToggleRow {
                visible: CompositorService.isNiri || CompositorService.isMango
                tags: ["mouse", "middle", "click", "emulation"]
                settingKey: "mouseMiddleEmulation"
                text: I18n.tr("Middle click emulation")
                checked: SettingsData.mouseMiddleEmulation
                onToggled: checked => SettingsData.set("mouseMiddleEmulation", checked)
            }
        }

        SettingsCard {
            width: parent.width
            visible: CompositorService.supportsInputConfig
            tags: ["touchpad", "input", "sensitivity", "tap", "click", "natural"]
            title: I18n.tr("Touchpad", "touchpad input settings card title")
            settingKey: "touchpadSettings"
            iconName: "trackpad_input_2"

            SettingsToggleRow {
                tags: ["touchpad", "tap", "click"]
                settingKey: "touchpadTapToClick"
                text: I18n.tr("Tap to click")
                checked: SettingsData.touchpadTapToClick
                onToggled: checked => SettingsData.set("touchpadTapToClick", checked)
            }

            SettingsSliderRow {
                tags: ["touchpad", "sensitivity", "speed", "accel"]
                settingKey: "touchpadAccelSpeed"
                text: I18n.tr("Pointer speed")
                value: Math.round(SettingsData.touchpadAccelSpeed * 10)
                unit: ""
                decimals: 1
                minimum: -10
                maximum: 10
                step: 1
                onSliderValueChanged: newValue => SettingsData.set("touchpadAccelSpeed", newValue / 10.0)
            }

            SettingsToggleRow {
                tags: ["touchpad", "natural", "scroll", "direction"]
                settingKey: "touchpadNaturalScroll"
                text: I18n.tr("Natural scrolling")
                checked: SettingsData.touchpadNaturalScroll
                onToggled: checked => SettingsData.set("touchpadNaturalScroll", checked)
            }

            SettingsSliderRow {
                tags: ["touchpad", "scroll", "speed", "factor"]
                settingKey: "touchpadScrollFactor"
                text: I18n.tr("Scroll speed")
                value: Math.round(SettingsData.touchpadScrollFactor * 10)
                unit: "×"
                decimals: 1
                minimum: 1
                maximum: 30
                step: 1
                onSliderValueChanged: newValue => SettingsData.set("touchpadScrollFactor", newValue / 10.0)
            }

            SettingsToggleRow {
                tags: ["touchpad", "tap", "drag"]
                settingKey: "touchpadTapAndDrag"
                text: I18n.tr("Tap and drag")
                checked: SettingsData.touchpadTapAndDrag
                onToggled: checked => SettingsData.set("touchpadTapAndDrag", checked)
            }

            SettingsToggleRow {
                tags: ["touchpad", "drag", "lock"]
                settingKey: "touchpadDragLock"
                text: I18n.tr("Drag lock")
                checked: SettingsData.touchpadDragLock
                onToggled: checked => SettingsData.set("touchpadDragLock", checked)
            }

            SettingsButtonGroupRow {
                tags: ["touchpad", "acceleration", "profile"]
                settingKey: "touchpadAccelProfile"
                text: I18n.tr("Acceleration profile")
                model: [I18n.tr("Default"), I18n.tr("Flat"), I18n.tr("Adaptive")]
                currentIndex: {
                    if (SettingsData.touchpadAccelProfile === "flat")
                        return 1;
                    if (SettingsData.touchpadAccelProfile === "adaptive")
                        return 2;
                    return 0;
                }
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    const profiles = ["default", "flat", "adaptive"];
                    SettingsData.set("touchpadAccelProfile", profiles[index]);
                }
            }

            SettingsDropdownRow {
                id: touchpadScrollMethodRow

                readonly property var methods: ["default", "two-finger", "edge", "no-scroll", "on-button-down"]

                tags: ["touchpad", "scroll", "method"]
                settingKey: "touchpadScrollMethod"
                text: I18n.tr("Scroll method")
                options: [I18n.tr("Default"), I18n.tr("Two-finger", "touchpad scroll method option"), I18n.tr("Edge", "noun, touchpad scroll method option, scroll along the pad edge"), I18n.tr("No scroll"), I18n.tr("On button down")]
                currentValue: options[Math.max(0, methods.indexOf(SettingsData.touchpadScrollMethod))]
                onValueChanged: value => {
                    const index = touchpadScrollMethodRow.options.indexOf(value);
                    if (index < 0)
                        return;
                    SettingsData.set("touchpadScrollMethod", touchpadScrollMethodRow.methods[index]);
                }
            }

            SettingsDropdownRow {
                id: touchpadClickMethodRow

                readonly property var methods: ["default", "button-areas", "clickfinger"]

                tags: ["touchpad", "click", "method"]
                settingKey: "touchpadClickMethod"
                text: I18n.tr("Click method", "Rules by which touchpad input determines left, right and middle click")
                options: [I18n.tr("Default"), I18n.tr("Button areas", "Touchpad click method: click type is determined by finger position"), I18n.tr("Clickfinger", "Touchpad click method: click type is determined by finger count")]
                currentValue: options[Math.max(0, methods.indexOf(SettingsData.touchpadClickMethod))]
                onValueChanged: value => {
                    const index = touchpadClickMethodRow.options.indexOf(value);
                    if (index < 0)
                        return;
                    SettingsData.set("touchpadClickMethod", touchpadClickMethodRow.methods[index]);
                }
            }

            SettingsToggleRow {
                tags: ["touchpad", "disable", "typing", "dwt"]
                settingKey: "touchpadDisableWhileTyping"
                text: I18n.tr("Disable while typing")
                checked: SettingsData.touchpadDisableWhileTyping
                onToggled: checked => SettingsData.set("touchpadDisableWhileTyping", checked)
            }

            SettingsToggleRow {
                visible: CompositorService.isNiri || CompositorService.isMango
                tags: ["touchpad", "disable", "external", "mouse"]
                settingKey: "touchpadDisableOnExternalMouse"
                text: I18n.tr("Disable with external mouse")
                checked: SettingsData.touchpadDisableOnExternalMouse
                onToggled: checked => SettingsData.set("touchpadDisableOnExternalMouse", checked)
            }

            SettingsToggleRow {
                tags: ["touchpad", "middle", "click", "emulation"]
                settingKey: "touchpadMiddleEmulation"
                text: I18n.tr("Middle click emulation")
                checked: SettingsData.touchpadMiddleEmulation
                onToggled: checked => SettingsData.set("touchpadMiddleEmulation", checked)
            }
        }

        SettingsCard {
            width: parent.width
            visible: CompositorService.isHyprland && HyprlandService.hyprSupports("input:tablet:enabled")
            tags: ["tablet", "pen", "stylus", "drawing", "input"]
            title: I18n.tr("Tablet", "drawing tablet input settings card title")
            settingKey: "tabletSettings"
            iconName: "stylus"

            SettingsToggleRow {
                tags: ["tablet", "pen", "stylus", "drawing", "enable", "disable"]
                settingKey: "hyprlandTabletEnabled"
                text: I18n.tr("Tablet input", "Hyprland toggle, accept input from drawing tablets")
                checked: SettingsData.hyprlandTabletEnabled
                onToggled: checked => SettingsData.set("hyprlandTabletEnabled", checked)
            }
        }
    }
}
