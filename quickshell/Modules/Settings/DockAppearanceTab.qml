import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    DockSelectionState {
        id: dock
    }

    SettingsPage {
        SettingsCard {
            width: parent.width
            visible: dock.hasConfig
            iconName: "photo_size_select_large"
            title: I18n.tr("Size")
            settingKey: "dockSizing"
            tags: ["dock", "size", "icon", "spacing", "padding", "margin", "thickness"]

            SettingsSliderRow {
                settingKey: "dockIconSize"
                tags: ["dock", "icon", "size", "scale"]
                resetStore: dock
                resetKeys: ["iconSize"]
                text: I18n.tr("Icon size")
                value: dock.config?.iconSize ?? SettingsData.dockConfigDefaults().iconSize
                minimum: 24
                maximum: 96
                unit: "px"
                onSliderValueChanged: value => dock.setOption("iconSize", value)
            }

            SettingsSliderRow {
                settingKey: "dockItemSpacing"
                tags: ["dock", "spacing", "icon", "widget", "gap"]
                resetStore: dock
                resetKeys: ["itemSpacing"]
                text: I18n.tr("Spacing", "slider label, gap between dock items")
                value: dock.config?.itemSpacing ?? SettingsData.dockConfigDefaults().itemSpacing
                minimum: 0
                maximum: 32
                unit: "px"
                onSliderValueChanged: value => dock.setOption("itemSpacing", value)
            }

            SettingsSliderRow {
                settingKey: "dockSpacing"
                tags: ["dock", "spacing", "padding"]
                resetStore: dock
                resetKeys: ["spacing"]
                text: I18n.tr("Padding", "noun, spacing setting label")
                value: dock.config?.spacing ?? SettingsData.dockConfigDefaults().spacing
                minimum: 0
                maximum: 32
                unit: "px"
                onSliderValueChanged: value => dock.setOption("spacing", value)
            }

            SettingsSliderRow {
                settingKey: "dockMargin"
                tags: ["dock", "margin", "edge", "gap"]
                resetStore: dock
                resetKeys: ["margin"]
                text: I18n.tr("Margin", "slider label, gap between dock and screen edge")
                visible: !dock.connectedFrameModeActive
                value: dock.config?.margin ?? 8
                minimum: 0
                maximum: 100
                unit: "px"
                onSliderValueChanged: value => dock.setOption("margin", value)
            }
        }

        SettingsToggleCard {
            width: parent.width
            visible: dock.hasConfig
            iconName: "zoom_in"
            settingKey: "dockMagnification"
            tags: ["dock", "zoom", "magnification", "hover", "scale", "fisheye"]
            title: I18n.tr("Magnification", "dock setting: enlarge icons near the cursor")
            checked: dock.config?.magnification ?? false
            onToggled: checked => dock.setOption("magnification", checked)

            SettingsSliderRow {
                settingKey: "dockMagnificationScale"
                tags: ["dock", "zoom", "magnification", "scale"]
                resetStore: dock
                resetKeys: ["magnificationScale"]
                text: I18n.tr("Scale")
                value: dock.config?.magnificationScale ?? 130
                minimum: 105
                maximum: 160
                step: 5
                unit: "%"
                onSliderValueChanged: value => dock.setOption("magnificationScale", value)
            }

            SettingsDropdownRow {
                settingKey: "dockMagnificationProfile"
                tags: ["dock", "zoom", "magnification", "animation", "profile", "style", "curve"]
                resetStore: dock
                resetKeys: ["magnificationProfile"]
                text: I18n.tr("Animation style", "dock setting: magnification curve profile")
                currentValue: {
                    const profile = dock.config?.magnificationProfile ?? "parabolic";
                    switch (profile) {
                    case "cosine":
                        return I18n.tr("Cosine", "magnification animation profile");
                    case "gaussian":
                        return I18n.tr("Gaussian", "magnification animation profile");
                    default:
                        return I18n.tr("Parabolic", "magnification animation profile");
                    }
                }
                options: [I18n.tr("Parabolic", "magnification animation profile"), I18n.tr("Cosine", "magnification animation profile"), I18n.tr("Gaussian", "magnification animation profile")]
                onValueChanged: value => {
                    if (value === I18n.tr("Cosine", "magnification animation profile"))
                        dock.setOption("magnificationProfile", "cosine");
                    else if (value === I18n.tr("Gaussian", "magnification animation profile"))
                        dock.setOption("magnificationProfile", "gaussian");
                    else
                        dock.setOption("magnificationProfile", "parabolic");
                }
            }

            SettingsToggleRow {
                settingKey: "dockMagnificationExpand"
                tags: ["dock", "zoom", "magnification", "expand", "displace", "shift"]
                text: I18n.tr("Push neighboring icons", "dock setting: shift adjacent icons and expand dock to avoid overlap")
                checked: dock.config?.magnificationExpand ?? false
                onToggled: checked => dock.setOption("magnificationExpand", checked)
            }
        }

        SettingsCard {
            width: parent.width
            visible: dock.appsEntry !== null
            iconName: "auto_awesome"
            title: I18n.tr("Visual effects")
            settingKey: "dockVisualEffects"
            tags: ["dock", "indicator", "running", "active", "colorize", "highlight"]

            SettingsToggleRow {
                text: I18n.tr("Indicators")
                checked: !dock.appsValue("appsDockHideIndicators")
                onToggled: checked => dock.setAppsOption("appsDockHideIndicators", !checked)
            }

            SettingsButtonGroupRow {
                resetStore: dock
                resetKeys: ["indicatorStyle"]
                text: I18n.tr("Indicator style")
                enabled: !dock.appsValue("appsDockHideIndicators")
                model: [I18n.tr("Circle", "dock indicator style option"), I18n.tr("Line", "dock indicator style option")]
                buttonPadding: Theme.spacingS
                currentIndex: dock.config?.indicatorStyle === "circle" ? 0 : 1
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    dock.setOption("indicatorStyle", index === 0 ? "circle" : "line");
                }
            }

            SettingsToggleRow {
                text: I18n.tr("Colorize active")
                checked: dock.appsValue("appsDockColorizeActive")
                onToggled: checked => dock.setAppsOption("appsDockColorizeActive", checked)
            }

            ColorDropdownRow {
                resetStore: dock.apps
                resetKeys: ["appsDockActiveColorMode"]
                text: I18n.tr("Active color")
                enabled: dock.appsValue("appsDockColorizeActive")
                options: [({
                            "value": "primary",
                            "label": I18n.tr("Primary")
                        }), ({
                            "value": "secondary",
                            "label": I18n.tr("Secondary")
                        }), ({
                            "value": "primaryContainer",
                            "label": I18n.tr("Primary Container")
                        }), ({
                            "value": "error",
                            "label": I18n.tr("Error")
                        }), ({
                            "value": "success",
                            "label": I18n.tr("Success", "noun, theme color name in active color dropdown")
                        })]
                currentMode: dock.appsValue("appsDockActiveColorMode")
                onModeSelected: mode => dock.setAppsOption("appsDockActiveColorMode", mode)
            }
        }

        SettingsToggleCard {
            width: parent.width
            visible: dock.hasConfig && !dock.connectedFrameModeActive
            iconName: "border_style"
            settingKey: "dockBorder"
            tags: ["dock", "border", "outline"]
            title: I18n.tr("Border")
            checked: dock.config?.borderEnabled ?? false
            onToggled: checked => dock.setOption("borderEnabled", checked)

            SettingsButtonGroupRow {
                resetStore: dock
                resetKeys: ["borderColor"]
                readonly property var colors: ["surfaceText", "secondary", "primary"]

                text: I18n.tr("Color", "noun, settings label for choosing a border, shadow or frame color")
                model: [I18n.tr("Surface", "color option"), I18n.tr("Secondary", "color option"), I18n.tr("Primary", "color option")]
                buttonPadding: Theme.spacingS
                minButtonWidth: 44
                textSize: Theme.fontSizeSmall
                currentIndex: Math.max(0, colors.indexOf(dock.config?.borderColor ?? "surfaceText"))
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    dock.setOption("borderColor", colors[index]);
                }
            }

            SettingsSliderRow {
                resetStore: dock
                resetKeys: ["borderOpacity"]
                text: I18n.tr("Opacity")
                value: Math.round((dock.config?.borderOpacity ?? 1) * 100)
                minimum: 0
                maximum: 100
                onSliderValueChanged: value => dock.setOption("borderOpacity", value / 100)
            }

            SettingsSliderRow {
                resetStore: dock
                resetKeys: ["borderThickness"]
                text: I18n.tr("Thickness", "slider label, border or outline width in pixels")
                value: dock.config?.borderThickness ?? 1
                minimum: 1
                maximum: 10
                unit: "px"
                onSliderValueChanged: value => dock.setOption("borderThickness", value)
            }
        }

        SettingsControlledBy {
            visible: dock.hasConfig && !dock.connectedFrameModeActive
            target: "surfaces"
            parentModal: root.parentModal
            section: "surfaceOpacity_dock_" + dock.selectedDockId
            settingLabel: I18n.tr("Opacity")
        }

        SettingsControlledBy {
            visible: dock.connectedFrameModeActive
            parentModal: root.parentModal
            section: "frameBorder"
            settingLabel: I18n.tr("Dock margin, opacity, and border")
            reason: I18n.tr("Managed by Frame in Connected Mode")
        }
    }
}
