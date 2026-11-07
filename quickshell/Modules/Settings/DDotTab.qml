import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import qs.Modals.FileBrowser
import qs.Modules.DIsland
import qs.Services
import qs.Modules.Settings.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property var paletteValues: ["default", "bright", "dim"]

    readonly property IslandSettingsStore dot: IslandSettingsStore {
        barId: SettingsData.dotBarConfig?.id ?? ""
    }

    readonly property bool highContrast: dot.setting("islandHighContrast")
    readonly property bool paletteTinted: ["bright", "dim"].includes(dot.setting("islandPalette"))
    readonly property var iconModes: ["icon", "os", "dank", "compositor", "custom"]
    readonly property string iconMode: dot.setting("islandFreeIconMode")
    readonly property string iconColor: dot.setting("islandFreeIconColor")
    readonly property bool iconColorCustom: iconColor !== "" && iconColor !== "primary" && iconColor !== "surface"
    readonly property string compositorLabel: CompositorService.displayName || I18n.tr("Compositor")

    // A screen with no stored entry already sits at the default centre.
    function resetDotPosition() {
        for (const screen of Quickshell.screens) {
            const key = IslandHostRegistry.key(screen.name, root.dot.barId);
            if (SessionData.islandFreePositions[key])
                SessionData.setIslandFreePosition(key, 0.5, 0.5);
        }
    }

    FileBrowserModal {
        id: iconFileBrowser

        browserTitle: I18n.tr("Select Dot Icon")
        bucket: "logo"
        filters: ["*.svg", "*.png", "*.jpg", "*.jpeg", "*.webp"]
        onAccepted: paths => root.dot.apply("islandFreeIconPath", paths[0])
    }

    SettingsPage {
        SettingsCard {
            settingKey: "dotSize"
            tags: ["dot", "dankdot", "size", "diameter", "idle", "fade"]
            iconName: "blur_on"
            title: I18n.tr("General")

            SettingsSliderRow {
                settingKey: "islandFreeSize"
                tags: ["dot", "size", "diameter"]
                resetStore: dot
                resetKeys: ["islandFreeSize"]
                text: I18n.tr("Size")
                unit: "px"
                minimum: 24
                maximum: 160
                step: 1
                value: dot.setting("islandFreeSize")
                onSliderDragFinished: finalValue => dot.apply("islandFreeSize", finalValue)
            }

            SettingsButtonGroupRow {
                settingKey: "dotIcon"
                tags: ["dot", "icon", "symbol", "logo", "face"]
                resetStore: root.dot
                resetKeys: ["islandFreeIconMode"]
                text: I18n.tr("Icon")
                buttonPadding: Theme.spacingS
                minButtonWidth: 44
                textSize: Theme.fontSizeSmall
                model: [I18n.tr("Symbol"), I18n.tr("OS Logo"), "Dux", root.compositorLabel, I18n.tr("Custom")]
                values: root.iconModes
                value: root.iconMode
                fallbackValue: "icon"
                onValueSelected: value => root.dot.apply("islandFreeIconMode", value)
            }

            SettingsRow {
                settingKey: "dotIconSymbol"
                tags: ["dot", "icon", "symbol", "glyph"]
                resetStore: root.dot
                resetKeys: ["islandFreeIcon"]
                title: I18n.tr("Symbol")
                visible: root.iconMode === "icon"

                DIconPicker {
                    anchors.verticalCenter: parent.verticalCenter
                    currentIcon: root.dot.setting("islandFreeIcon")
                    onIconSelected: iconName => root.dot.apply("islandFreeIcon", iconName)
                }
            }

            SettingsTextFieldRow {
                settingKey: "dotIconImage"
                tags: ["dot", "icon", "image", "custom", "file", "logo"]
                resetStore: root.dot
                resetKeys: ["islandFreeIconPath"]
                text: I18n.tr("Custom")
                visible: root.iconMode === "custom"
                placeholderText: I18n.tr("Select an image file...")
                value: root.dot.setting("islandFreeIconPath")
                onEditingFinished: value => root.dot.apply("islandFreeIconPath", value.trim())

                actions: DActionButton {
                    iconName: "folder_open"
                    Accessible.name: I18n.tr("Select Dot Icon")
                    onClicked: iconFileBrowser.open()
                }
            }

            ColorDropdownRow {
                settingKey: "dotIconColor"
                tags: ["dot", "icon", "color", "tint", "logo"]
                resetStore: root.dot
                resetKeys: ["islandFreeIconColor"]
                text: I18n.tr("Color override")
                options: [({
                            "value": "",
                            "label": I18n.tr("Default")
                        }), ({
                            "value": "primary",
                            "label": I18n.tr("Primary")
                        }), ({
                            "value": "surface",
                            "label": I18n.tr("Surface", "color option")
                        }), ({
                            "value": "custom",
                            "label": I18n.tr("Custom")
                        })]
                currentMode: root.iconColorCustom ? "custom" : root.iconColor
                customColor: root.iconColorCustom ? root.iconColor : Theme.primary
                pickerTitle: I18n.tr("Color override")
                onModeSelected: mode => {
                    if (mode !== "custom") {
                        root.dot.apply("islandFreeIconColor", mode);
                        return;
                    }
                    if (!root.iconColorCustom)
                        root.dot.apply("islandFreeIconColor", Theme.primary.toString());
                }
                onCustomColorSelected: selectedColor => root.dot.apply("islandFreeIconColor", selectedColor.toString())
            }

            SettingsSliderRow {
                settingKey: "dotEdgeMargin"
                tags: ["dot", "edge", "margin", "gap"]
                resetStore: dot
                resetKeys: ["islandFreeEdgeMargin"]
                text: I18n.tr("Edge margin", "island settings: gap kept from the display edge")
                unit: "px"
                minimum: 0
                maximum: 64
                step: 1
                value: dot.setting("islandFreeEdgeMargin")
                onSliderDragFinished: finalValue => dot.apply("islandFreeEdgeMargin", finalValue)
            }

            SettingsSliderRow {
                settingKey: "islandFreeIdleDelay"
                tags: ["dot", "idle", "delay", "fade", "timeout"]
                resetStore: dot
                resetKeys: ["islandFreeIdleDelay"]
                text: I18n.tr("Idle delay", "island settings: time before the dot fades, 0 disables idling")
                unit: "ms"
                minimumLabel: I18n.tr("Off")
                minimum: 0
                maximum: 30000
                step: 500
                value: dot.setting("islandFreeIdleDelay")
                onSliderDragFinished: finalValue => dot.apply("islandFreeIdleDelay", finalValue)
            }

            SettingsSliderRow {
                settingKey: "islandFreeIdleScale"
                tags: ["dot", "idle", "shrink", "scale"]
                resetStore: dot
                resetKeys: ["islandFreeIdleScale"]
                text: I18n.tr("Idle size", "island settings: how far the dot shrinks while idle")
                unit: "%"
                minimum: 20
                maximum: 100
                step: 1
                value: Math.round(dot.setting("islandFreeIdleScale") * 100)
                enabled: dot.setting("islandFreeIdleDelay") > 0
                onSliderDragFinished: finalValue => dot.apply("islandFreeIdleScale", finalValue / 100)
            }

            SettingsSliderRow {
                settingKey: "islandFreeIdleOpacity"
                tags: ["dot", "idle", "opacity", "fade"]
                resetStore: dot
                resetKeys: ["islandFreeIdleOpacity"]
                text: I18n.tr("Idle opacity", "island settings: dot opacity while idle")
                unit: "%"
                minimum: 5
                maximum: 100
                step: 1
                value: Math.round(dot.setting("islandFreeIdleOpacity") * 100)
                enabled: dot.setting("islandFreeIdleDelay") > 0
                onSliderDragFinished: finalValue => dot.apply("islandFreeIdleOpacity", finalValue / 100)
            }

            SettingsRow {
                settingKey: "dotResetPosition"
                tags: ["dot", "position", "center", "reset", "move"]
                iconName: "drag_pan"
                title: I18n.tr("Reset Position")
                clickable: true
                onClicked: root.resetDotPosition()
            }
        }

        SettingsCard {
            iconName: "palette"
            title: I18n.tr("Surface")
            settingKey: "dotSurface"
            tags: ["dot", "background", "color", "opacity", "palette", "contrast"]

            SurfaceColorRow {
                settingKey: "dotSurfaceColor"
                tags: ["dot", "background", "color", "surface"]
                resetStore: dot
                resetKeys: ["surfaceColor", "surfaceCustomColor"]
                text: I18n.tr("Background")
                enabled: !root.highContrast && !root.paletteTinted
                defaultColor: Theme.hostSurface
                currentMode: dot.config?.surfaceColor ?? "default"
                customColor: dot.config?.surfaceCustomColor ?? SettingsData.barConfigDefault("surfaceCustomColor")
                pickerTitle: I18n.tr("Background")
                onModeSelected: mode => dot.apply("surfaceColor", mode)
                onCustomColorSelected: selectedColor => dot.apply("surfaceCustomColor", selectedColor.toString())
            }

            SettingsSliderRow {
                settingKey: "dotOpacity"
                tags: ["dot", "opacity", "transparency", "background"]
                resetStore: dot
                resetKeys: ["transparency"]
                text: I18n.tr("Opacity")
                enabled: !root.highContrast
                minimum: 0
                maximum: 100
                step: 1
                value: Math.round(SettingsData.barTransparency(dot.config) * 100)
                onSliderDragFinished: finalValue => SettingsData.updateBarConfig(dot.config.id, {
                        followInterfaceStyle: false,
                        transparency: finalValue / 100
                    })
            }

            SettingsButtonGroupRow {
                settingKey: "dotPalette"
                tags: ["dot", "palette", "surface", "bright", "dim"]
                resetStore: dot
                resetKeys: ["islandPalette"]
                text: I18n.tr("Palette", "island settings: surface tone choice")
                model: [I18n.tr("Default", "island settings: default surface tone"), I18n.tr("Bright", "island settings: bright surface tone"), I18n.tr("Dim", "island settings: dim surface tone")]
                values: root.paletteValues
                enabled: !root.highContrast
                value: dot.setting("islandPalette")
                fallbackValue: "default"
                onValueSelected: value => dot.apply("islandPalette", value)
            }

            SettingsToggleRow {
                settingKey: "dotHighContrast"
                tags: ["dot", "contrast", "accessibility", "outline"]
                resetStore: root.dot
                resetKeys: ["islandHighContrast"]
                text: I18n.tr("High contrast", "island settings: high contrast toggle")
                checked: dot.setting("islandHighContrast")
                onToggled: checked => dot.apply("islandHighContrast", checked)
            }
        }

        SettingsCard {
            iconName: "display_settings"
            title: I18n.tr("Displays")
            settingKey: "dotDisplays"
            tags: ["dot", "display", "monitor", "screen"]

            SettingsDisplayPicker {
                displayPreferences: dot.config?.screenPreferences || ["all"]
                emptyMeansAll: false
                allowEmpty: true
                showLastDisplay: true
                showOnLastDisplay: dot.config?.showOnLastDisplay ?? true
                preferencesHandler: prefs => dot.apply("screenPreferences", prefs)
                onLastDisplayToggled: checked => dot.apply("showOnLastDisplay", checked)
            }
        }

        IslandBehaviorCard {
            store: dot
            keyPrefix: "dot"
            docked: false
            isDot: true
        }

        IslandNotificationsCard {
            store: dot
            keyPrefix: "dot"
            badgeGated: false
        }

        IslandMotionCard {
            store: dot
            keyPrefix: "dot"
        }
    }
}
