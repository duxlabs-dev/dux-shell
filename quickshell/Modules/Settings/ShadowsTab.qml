import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    function openShadowColorPicker() {
        PopoutService.colorPickerModal.selectedColor = SettingsData.m3ElevationCustomColor ?? "#000000";
        PopoutService.colorPickerModal.pickerTitle = I18n.tr("Shadow Color");
        PopoutService.colorPickerModal.onColorSelectedCallback = function (color) {
            SettingsData.set("m3ElevationCustomColor", color.toString());
        };
        PopoutService.colorPickerModal.show();
    }

    BarSelectionState {
        id: bar
    }

    SettingsPage {
        SettingsToggleCard {
            tab: "theme"
            tags: ["elevation", "shadow", "lift", "m3", "material", "intensity", "blur", "opacity", "color", "direction", "light"]
            settingKey: "m3ElevationEnabled"
            title: I18n.tr("Shadows", "noun, settings page name and toggle for surface shadows")
            checked: SettingsData.m3ElevationEnabled ?? true
            onToggled: checked => SettingsData.set("m3ElevationEnabled", checked)

            SettingsSliderRow {
                tab: "theme"
                tags: ["elevation", "shadow", "intensity", "blur", "m3"]
                settingKey: "m3ElevationIntensity"
                text: I18n.tr("Intensity")
                value: SettingsData.m3ElevationIntensity ?? 12
                minimum: 0
                maximum: 100
                unit: ""
                onSliderValueChanged: newValue => SettingsData.set("m3ElevationIntensity", newValue)
            }

            SettingsSliderRow {
                tab: "theme"
                tags: ["elevation", "shadow", "opacity", "transparency", "m3"]
                settingKey: "m3ElevationOpacity"
                text: I18n.tr("Opacity")
                value: SettingsData.m3ElevationOpacity ?? 30
                minimum: 0
                maximum: 100
                onSliderValueChanged: newValue => SettingsData.set("m3ElevationOpacity", newValue)
            }

            SettingsDropdownRow {
                tab: "theme"
                tags: ["elevation", "shadow", "color", "m3"]
                settingKey: "m3ElevationColorMode"
                resetKeys: ["m3ElevationColorMode", "m3ElevationCustomColor"]
                text: I18n.tr("Color")
                options: [I18n.tr("Default (Black)", "shadow color option"), I18n.tr("Text Color", "shadow color option"), I18n.tr("Primary", "shadow color option"), I18n.tr("Surface Variant", "shadow color option"), I18n.tr("Custom", "shadow color option")]
                optionColorMap: ({
                        [I18n.tr("Default (Black)", "shadow color option")]: "#000000",
                        [I18n.tr("Text Color", "shadow color option")]: Theme.surfaceText,
                        [I18n.tr("Primary", "shadow color option")]: Theme.primary,
                        [I18n.tr("Surface Variant", "shadow color option")]: Theme.surfaceVariant,
                        [I18n.tr("Custom", "shadow color option")]: SettingsData.m3ElevationCustomColor ?? "#000000"
                    })
                currentValue: {
                    switch (SettingsData.m3ElevationColorMode) {
                    case "text":
                        return I18n.tr("Text Color", "shadow color option");
                    case "primary":
                        return I18n.tr("Primary", "shadow color option");
                    case "surfaceVariant":
                        return I18n.tr("Surface Variant", "shadow color option");
                    case "custom":
                        return I18n.tr("Custom", "shadow color option");
                    default:
                        return I18n.tr("Default (Black)", "shadow color option");
                    }
                }
                onValueChanged: value => {
                    switch (value) {
                    case I18n.tr("Primary", "shadow color option"):
                        SettingsData.set("m3ElevationColorMode", "primary");
                        return;
                    case I18n.tr("Surface Variant", "shadow color option"):
                        SettingsData.set("m3ElevationColorMode", "surfaceVariant");
                        return;
                    case I18n.tr("Text Color", "shadow color option"):
                        SettingsData.set("m3ElevationColorMode", "text");
                        return;
                    case I18n.tr("Custom", "shadow color option"):
                        SettingsData.set("m3ElevationColorMode", "custom");
                        root.openShadowColorPicker();
                        return;
                    }
                    SettingsData.set("m3ElevationColorMode", "default");
                }
            }

            SettingsRow {
                title: I18n.tr("Custom color")
                visible: SettingsData.m3ElevationColorMode === "custom"
                resetKeys: ["m3ElevationCustomColor"]
                clickable: true
                onClicked: root.openShadowColorPicker()

                DColorSwatch {
                    width: Theme.iconSizeMedium
                    height: width
                    swatchColor: SettingsData.m3ElevationCustomColor ?? "#000000"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            SettingsDropdownRow {
                tab: "theme"
                tags: ["elevation", "shadow", "direction", "light", "advanced", "m3"]
                settingKey: "m3ElevationLightDirection"
                text: I18n.tr("Light direction")
                options: [I18n.tr("Auto (Bar-aware)", "shadow direction option"), I18n.tr("Top (Default)", "shadow direction option"), I18n.tr("Top Left", "shadow direction option"), I18n.tr("Top Right", "shadow direction option"), I18n.tr("Bottom", "shadow direction option")]
                currentValue: {
                    switch (SettingsData.m3ElevationLightDirection) {
                    case "autoBar":
                        return I18n.tr("Auto (Bar-aware)", "shadow direction option");
                    case "topLeft":
                        return I18n.tr("Top Left", "shadow direction option");
                    case "topRight":
                        return I18n.tr("Top Right", "shadow direction option");
                    case "bottom":
                        return I18n.tr("Bottom", "shadow direction option");
                    default:
                        return I18n.tr("Top (Default)", "shadow direction option");
                    }
                }
                onValueChanged: value => {
                    switch (value) {
                    case I18n.tr("Auto (Bar-aware)", "shadow direction option"):
                        SettingsData.set("m3ElevationLightDirection", "autoBar");
                        return;
                    case I18n.tr("Top Left", "shadow direction option"):
                        SettingsData.set("m3ElevationLightDirection", "topLeft");
                        return;
                    case I18n.tr("Top Right", "shadow direction option"):
                        SettingsData.set("m3ElevationLightDirection", "topRight");
                        return;
                    case I18n.tr("Bottom", "shadow direction option"):
                        SettingsData.set("m3ElevationLightDirection", "bottom");
                        return;
                    }
                    SettingsData.set("m3ElevationLightDirection", "top");
                }
            }
        }

        SettingsCard {
            tab: "theme"
            tags: ["elevation", "shadow", "modal", "dialog", "popout", "popup", "osd", "bar", "panel", "m3"]
            title: I18n.tr("Apply to")
            settingKey: "m3ElevationTargets"

            SettingsToggleRow {
                tab: "theme"
                tags: ["elevation", "shadow", "modal", "dialog", "m3"]
                settingKey: "modalElevationEnabled"
                text: I18n.tr("Modals")
                enabled: SettingsData.m3ElevationEnabled ?? true
                checked: SettingsData.modalElevationEnabled ?? true
                onToggled: checked => SettingsData.set("modalElevationEnabled", checked)
            }

            SettingsToggleRow {
                tab: "theme"
                tags: ["elevation", "shadow", "popout", "popup", "osd", "dropdown", "m3"]
                settingKey: "popoutElevationEnabled"
                text: I18n.tr("Popouts")
                enabled: SettingsData.m3ElevationEnabled ?? true
                checked: SettingsData.popoutElevationEnabled ?? true
                onToggled: checked => SettingsData.set("popoutElevationEnabled", checked)
            }

            SettingsToggleRow {
                tab: "theme"
                tags: ["elevation", "shadow", "notification", "popup", "m3"]
                settingKey: "notificationPopupShadowEnabled"
                text: I18n.tr("Notifications")
                enabled: SettingsData.m3ElevationEnabled ?? true
                checked: SettingsData.notificationPopupShadowEnabled
                onToggled: checked => SettingsData.set("notificationPopupShadowEnabled", checked)
            }

            SettingsToggleRow {
                tab: "theme"
                tags: ["elevation", "shadow", "bar", "panel", "navigation", "m3"]
                settingKey: "barElevationEnabled"
                text: I18n.tr("Bars")
                enabled: SettingsData.m3ElevationEnabled ?? true
                checked: SettingsData.barElevationEnabled ?? true
                onToggled: checked => SettingsData.set("barElevationEnabled", checked)
            }
        }

        SettingsCard {
            id: shadowCard
            tab: "theme"
            tags: ["elevation", "shadow", "bar", "override", "custom", "m3"]
            iconName: "toolbar"
            title: I18n.tr("Bar")
            settingKey: "barShadow"
            visible: bars.length > 0

            readonly property var bars: SettingsData.barConfigs.filter(config => !SettingsData.isIslandBarConfig(config))
            readonly property bool shadowActive: (bar.selectedBarConfig?.shadowIntensity ?? 0) > 0
            readonly property string directionSource: bar.selectedBarConfig?.shadowDirectionMode ?? "inherit"

            SettingsDropdownRow {
                text: I18n.tr("Bar")
                visible: shadowCard.bars.length > 1
                options: shadowCard.bars.map(config => config.name || config.id)
                currentValue: bar.selectedBarConfig?.name || bar.selectedBarConfig?.id || ""
                onValueChanged: value => bar.select(shadowCard.bars.find(config => (config.name || config.id) === value)?.id ?? bar.selectedBarId)
            }

            SettingsControlledBy {
                visible: bar.selectedBarFrameSanitized
                parentModal: root.parentModal
                section: "frameBorder"
                settingLabel: I18n.tr("Bar")
                reason: I18n.tr("Disabled by Frame Mode")
            }

            SettingsToggleCard {
                tags: ["shadow", "override", "custom"]
                title: I18n.tr("Override")
                enabled: !bar.selectedBarFrameSanitized
                checked: shadowCard.shadowActive
                onToggled: checked => {
                    if (checked) {
                        SettingsData.updateBarConfig(bar.selectedBarId, {
                            shadowIntensity: 12,
                            shadowOpacity: 60
                        });
                    } else {
                        SettingsData.updateBarConfig(bar.selectedBarId, {
                            shadowIntensity: 0
                        });
                    }
                }

                SettingsSliderRow {
                    tags: ["shadow", "blur", "radius"]
                    text: I18n.tr("Intensity", "shadow intensity slider")
                    minimum: 0
                    maximum: 100
                    unit: ""
                    value: bar.selectedBarConfig?.shadowIntensity ?? 0
                    onSliderValueChanged: newValue => SettingsData.updateBarConfig(bar.selectedBarId, {
                            shadowIntensity: newValue
                        })
                }

                SettingsSliderRow {
                    text: I18n.tr("Opacity")
                    resetStore: bar
                    resetKeys: ["shadowOpacity"]
                    minimum: 10
                    maximum: 100
                    value: bar.selectedBarConfig?.shadowOpacity ?? 60
                    onSliderValueChanged: newValue => SettingsData.updateBarConfig(bar.selectedBarId, {
                            shadowOpacity: newValue
                        })
                }

                SettingsDropdownRow {
                    text: I18n.tr("Direction source", "bar shadow direction source")
                    settingKey: "barShadowDirectionSource"
                    resetStore: bar
                    resetKeys: ["shadowDirectionMode"]
                    options: [I18n.tr("Inherit Global (Default)", "bar shadow direction source option"), I18n.tr("Auto (Bar-aware)", "bar shadow direction source option"), I18n.tr("Manual", "bar shadow direction source option")]
                    currentValue: {
                        switch (shadowCard.directionSource) {
                        case "autoBar":
                            return I18n.tr("Auto (Bar-aware)", "bar shadow direction source option");
                        case "manual":
                            return I18n.tr("Manual", "bar shadow direction source option");
                        default:
                            return I18n.tr("Inherit Global (Default)", "bar shadow direction source option");
                        }
                    }
                    onValueChanged: value => {
                        let mode = "inherit";
                        switch (value) {
                        case I18n.tr("Auto (Bar-aware)", "bar shadow direction source option"):
                            mode = "autoBar";
                            break;
                        case I18n.tr("Manual", "bar shadow direction source option"):
                            mode = "manual";
                            break;
                        }
                        SettingsData.updateBarConfig(bar.selectedBarId, {
                            shadowDirectionMode: mode
                        });
                    }
                }

                SettingsDropdownRow {
                    visible: shadowCard.directionSource === "manual"
                    text: I18n.tr("Direction", "bar manual shadow direction")
                    settingKey: "barShadowDirectionManual"
                    resetStore: bar
                    resetKeys: ["shadowDirection"]
                    options: [I18n.tr("Top", "shadow direction option"), I18n.tr("Top Left", "shadow direction option"), I18n.tr("Top Right", "shadow direction option"), I18n.tr("Bottom", "shadow direction option")]
                    currentValue: {
                        switch (bar.selectedBarConfig?.shadowDirection) {
                        case "topLeft":
                            return I18n.tr("Top Left", "shadow direction option");
                        case "topRight":
                            return I18n.tr("Top Right", "shadow direction option");
                        case "bottom":
                            return I18n.tr("Bottom", "shadow direction option");
                        default:
                            return I18n.tr("Top", "shadow direction option");
                        }
                    }
                    onValueChanged: value => {
                        let direction = "top";
                        switch (value) {
                        case I18n.tr("Top Left", "shadow direction option"):
                            direction = "topLeft";
                            break;
                        case I18n.tr("Top Right", "shadow direction option"):
                            direction = "topRight";
                            break;
                        case I18n.tr("Bottom", "shadow direction option"):
                            direction = "bottom";
                            break;
                        }
                        SettingsData.updateBarConfig(bar.selectedBarId, {
                            shadowDirection: direction
                        });
                    }
                }

                ColorDropdownRow {
                    tags: ["shadow", "color", "custom"]
                    settingKey: "barShadowColor"
                    resetStore: bar
                    resetKeys: ["shadowColorMode", "shadowCustomColor"]
                    text: I18n.tr("Color")
                    pickerTitle: I18n.tr("Color")
                    options: [
                        {
                            "value": "default",
                            "label": I18n.tr("Default (Black)"),
                            "previewColor": "#000000"
                        },
                        {
                            "value": "surface",
                            "label": I18n.tr("Surface", "shadow color option"),
                            "previewColor": Theme.surface
                        },
                        {
                            "value": "primary",
                            "label": I18n.tr("Primary")
                        },
                        {
                            "value": "secondary",
                            "label": I18n.tr("Secondary")
                        },
                        {
                            "value": "custom",
                            "label": I18n.tr("Custom")
                        }
                    ]
                    currentMode: bar.selectedBarConfig?.shadowColorMode || "default"
                    customColor: bar.selectedBarConfig?.shadowCustomColor ?? "#000000"
                    onModeSelected: mode => SettingsData.updateBarConfig(bar.selectedBarId, {
                            shadowColorMode: mode
                        })
                    onCustomColorSelected: selectedColor => SettingsData.updateBarConfig(bar.selectedBarId, {
                            shadowCustomColor: selectedColor.toString()
                        })
                }
            }
        }
    }
}
