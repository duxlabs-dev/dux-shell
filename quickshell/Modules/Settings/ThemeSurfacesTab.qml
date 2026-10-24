import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var parentModal: null
    readonly property bool followsSurfaces: SettingsData.floatingWindowSyncGlobal ?? true
    readonly property bool borderEnabled: SettingsData.blurBorderEnabled ?? false
    readonly property bool layerOutlineEnabled: (SettingsData.blurLayerOutlineOpacity ?? 0) > 0
    readonly property string windowRadiusKey: CompositorService.supportsLayoutConfig ? CompositorService.configKey + "LayoutRadiusOverride" : ""

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    Component.onCompleted: {
        BlurService.probe();
        CompositorService.refreshDmsWindowFloatingRule();
    }

    ConfigInclude {
        id: windowRulesInclude
        includeKind: "windowrules"
        procTag: "windowrules-include-theme"
        onFixed: {
            if (CompositorService.isMango)
                MangoService.reloadConfig();
            CompositorService.seedDmsWindowFloatingRule();
        }
    }

    ConfigInclude {
        id: niriLayoutInclude
        includeKind: "layout"
        procTag: "niri-layout-include-theme"
        autoCheck: CompositorService.isNiri
        onFixed: SettingsData.updateCompositorLayout()
    }

    readonly property var opacityTargets: {
        SettingsData.barConfigs;
        SettingsData.dockConfigs;
        const frameBarId = SettingsData.frameEnabled ? SettingsData.frameBarConfig?.id : undefined;
        const bars = SettingsData.barConfigs.filter(config => !SettingsData.isDotBarConfig(config)).map(config => ({
                    key: "bar:" + config.id,
                    kind: "bar",
                    id: config.id,
                    name: config.name || config.id,
                    enabled: config.enabled !== false,
                    override: config.followInterfaceStyle === false,
                    transparency: config.transparency ?? 1,
                    frame: config.id === frameBarId
                }));
        const docks = SettingsData.dockConfigs.map(config => ({
                    key: "dock:" + config.id,
                    kind: "dock",
                    id: config.id,
                    name: config.name,
                    enabled: config.enabled !== false,
                    override: config.followInterfaceStyle === false,
                    transparency: config.transparency ?? 1,
                    overlay: config.useOverlayLayer ?? false
                }));
        return bars.concat(docks);
    }

    function setOpacityOverride(target, patch) {
        if (target.kind === "bar") {
            SettingsData.updateBarConfig(target.id, patch);
            return;
        }
        SettingsData.updateDockConfig(target.id, patch);
    }

    function openSurfaceBorderColorPicker() {
        PopoutService.colorPickerModal.selectedColor = SettingsData.blurBorderCustomColor ?? "#ffffff";
        PopoutService.colorPickerModal.pickerTitle = I18n.tr("Surface Border Color");
        PopoutService.colorPickerModal.onColorSelectedCallback = function (color) {
            SettingsData.set("blurBorderCustomColor", color.toString());
        };
        PopoutService.colorPickerModal.open();
    }

    SettingsCard {
        tab: "theme"
        tags: ["surface", "popup", "transparency", "opacity", "modal", "corner", "radius", "blur", "background", "glass", "frosted", "shadow", "elevation", "foreground", "layers"]
        title: I18n.tr("Surfaces", "plural noun, settings title, shell surfaces like popouts and modals")
        settingKey: "surfaceStyling"

        SettingsSliderRow {
            tab: "theme"
            tags: ["surface", "popup", "transparency", "opacity", "modal"]
            settingKey: "popupTransparency"
            text: I18n.tr("Opacity")
            value: Math.round(SettingsData.popupTransparency * 100)
            minimum: 0
            maximum: 100
            onSliderValueChanged: newValue => SettingsData.set("popupTransparency", newValue / 100)
        }

        SettingsToggleSliderRow {
            tab: "theme"
            tags: ["foreground", "layers", "opacity", "transparency", "contrast", "cards", "surface", "blur", "glass", "frosted"]
            settingKey: "blurForegroundLayers"
            valueKeys: ["foregroundLayerTransparency"]
            text: I18n.tr("Foreground layers")
            checked: SettingsData.blurForegroundLayers ?? true
            value: Math.round((SettingsData.foregroundLayerTransparency ?? 1.0) * 100)
            minimum: 0
            maximum: 100
            onToggled: checked => SettingsData.set("blurForegroundLayers", checked)
            onSliderValueChanged: newValue => SettingsData.set("foregroundLayerTransparency", newValue / 100)
        }

        SettingsToggleSliderRow {
            tab: "theme"
            tags: ["foreground", "layers", "outline", "border", "opacity", "cards", "pills", "widgets", "notifications", "control center"]
            settingKey: "blurLayerOutline"
            text: I18n.tr("Layer outline")
            description: I18n.tr("Faint edge on cards, pills and widgets", "surface layer outline toggle description")
            checked: root.layerOutlineEnabled
            value: Math.round((SettingsData.blurLayerOutlineOpacity ?? 0) * 100)
            minimum: 1
            maximum: 40
            onToggled: checked => SettingsData.set("blurLayerOutlineOpacity", checked ? 0.12 : 0)
            onSliderValueChanged: newValue => SettingsData.set("blurLayerOutlineOpacity", newValue / 100)
        }

        SettingsToggleSliderRow {
            tab: "theme"
            tags: ["surface", "popup", "modal", "border", "outline", "edge", "color", "opacity"]
            settingKey: "blurBorderEnabled"
            accessoryKeys: ["blurBorderColor", "blurBorderCustomColor"]
            valueKeys: ["blurBorderOpacity"]
            text: I18n.tr("Border")
            description: I18n.tr("Edge around popups and modals", "surface border toggle description")
            checked: root.borderEnabled
            value: Math.round((SettingsData.blurBorderOpacity ?? 0.35) * 100)
            minimum: 0
            maximum: 100
            onToggled: checked => SettingsData.set("blurBorderEnabled", checked)
            onSliderValueChanged: newValue => SettingsData.set("blurBorderOpacity", newValue / 100)

            accessory: DDropdown {
                id: borderColorMenu
                visible: root.borderEnabled
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Border color")
                showLabel: false
                downKeyOpens: false
                triggerHeight: Theme.switchTrackHeight
                alignPopupRight: !I18n.isRtl
                options: [I18n.tr("Outline", "surface border color"), I18n.tr("Primary", "surface border color"), I18n.tr("Secondary", "surface border color"), I18n.tr("Text Color", "surface border color"), I18n.tr("Custom", "surface border color")]
                optionColorMap: ({
                        [I18n.tr("Outline", "surface border color")]: Theme.outline,
                        [I18n.tr("Primary", "surface border color")]: Theme.primary,
                        [I18n.tr("Secondary", "surface border color")]: Theme.secondary,
                        [I18n.tr("Text Color", "surface border color")]: Theme.surfaceText,
                        [I18n.tr("Custom", "surface border color")]: SettingsData.blurBorderCustomColor ?? "#ffffff"
                    })
                currentValue: {
                    switch (SettingsData.blurBorderColor) {
                    case "primary":
                        return I18n.tr("Primary", "surface border color");
                    case "secondary":
                        return I18n.tr("Secondary", "surface border color");
                    case "surfaceText":
                        return I18n.tr("Text Color", "surface border color");
                    case "custom":
                        return I18n.tr("Custom", "surface border color");
                    default:
                        return I18n.tr("Outline", "surface border color");
                    }
                }
                onValueChanged: value => {
                    switch (value) {
                    case I18n.tr("Primary", "surface border color"):
                        SettingsData.set("blurBorderColor", "primary");
                        return;
                    case I18n.tr("Secondary", "surface border color"):
                        SettingsData.set("blurBorderColor", "secondary");
                        return;
                    case I18n.tr("Text Color", "surface border color"):
                        SettingsData.set("blurBorderColor", "surfaceText");
                        return;
                    case I18n.tr("Custom", "surface border color"):
                        SettingsData.set("blurBorderColor", "custom");
                        root.openSurfaceBorderColorPicker();
                        return;
                    }
                    SettingsData.set("blurBorderColor", "outline");
                }
            }
        }

        SettingsControlledBy {
            visible: SettingsData.connectedFrameModeActive && root.borderEnabled
            parentModal: root.parentModal
            section: "frameBorder"
            settingLabel: I18n.tr("Border")
            reason: I18n.tr("Managed by Frame in Connected Mode")
        }

        SettingsToggleSliderRow {
            tab: "theme"
            tags: ["blur", "background", "transparency", "glass", "frosted", "strength", "radius", "size", "passes", "reach"]
            settingKey: "blurEnabled"
            valueKeys: ["blurStrength"]
            text: I18n.tr("Background blur")
            visible: BlurService.available
            checked: SettingsData.blurEnabled ?? false
            value: BlurService.strength
            minimum: 16
            maximum: 160
            unit: "px"
            onToggled: checked => {
                SettingsData.set("blurEnabled", checked);
                if (!checked || SettingsData.blurBorderSeeded)
                    return;
                SettingsData.set("blurBorderSeeded", true);
                SettingsData.set("blurBorderEnabled", true);
                SettingsSearchService.navigateToSection("blurBorderEnabled");
            }
            onSliderValueChanged: newValue => SettingsData.set("blurStrength", newValue)
        }

        SettingsNoteRow {
            visible: BlurService.probed && !BlurService.available
            noteIconName: "info"
            tint: Theme.surfaceVariantText
            tintBackground: Theme.surfaceVariantAlpha
            text: I18n.tr("Your compositor does not support ext-background blur")
        }

        SettingsNavRow {
            tab: "theme"
            tags: ["blur", "xray", "compositor", "layout"]
            settingKey: "blurXrayLink"
            visible: BlurService.available && (CompositorService.isNiri || CompositorService.isHyprland)
            title: I18n.tr("Xray options are in Compositor → Layout")
            onClicked: keyboard => root.parentModal?.navigateTo("compositor_layout", keyboard)
        }

        SettingsSplitRow {
            tab: "theme"
            tags: ["elevation", "shadow", "lift", "m3", "material"]
            settingKey: "m3ElevationLink"
            title: I18n.tr("Shadows")
            subtitle: SettingsTabs.page("surface_shadows")?.hint ?? ""
            resetKeys: ["m3ElevationEnabled"]
            checked: SettingsData.m3ElevationEnabled ?? true
            onNavigated: keyboard => root.parentModal?.navigateTo("surface_shadows", keyboard)
            onToggled: checked => SettingsData.set("m3ElevationEnabled", checked)
        }
    }

    SettingsCard {
        tab: "theme"
        tags: ["niri", "integration", "palette", "overview", "window", "focus"]
        title: I18n.tr("niri integration", "interface style settings section title")
        settingKey: "niriThemeIntegration"
        visible: CompositorService.isNiri

        IncludeSetupBanner {
            include: niriLayoutInclude
        }

        SettingsToggleRow {
            tab: "theme"
            tags: ["niri", "overview", "background", "backdrop", "palette"]
            settingKey: "niriOverviewBackgroundEnabled"
            text: I18n.tr("Overview background", "niri palette integration toggle")
            description: I18n.tr("Use Surface Container Highest from the DMS palette", "niri overview background integration description")
            enabled: niriLayoutInclude.included
            checked: SettingsData.niriOverviewBackgroundEnabled
            onToggled: checked => SettingsData.set("niriOverviewBackgroundEnabled", checked)
        }

        SettingsToggleRow {
            tab: "theme"
            tags: ["niri", "window", "focus", "border", "accent", "palette"]
            settingKey: "niriActiveWindowColorEnabled"
            text: I18n.tr("Active window outline", "niri palette integration toggle")
            description: I18n.tr("Use Primary from the DMS palette", "niri active window color integration description")
            enabled: niriLayoutInclude.included
            checked: SettingsData.niriActiveWindowColorEnabled
            onToggled: checked => SettingsData.set("niriActiveWindowColorEnabled", checked)
        }
    }

    SettingsCard {
        tab: "theme"
        tags: ["corner", "radius", "rounded", "square", "fixed", "material", "shape", "window"]
        title: I18n.tr("Corners")
        settingKey: "surfaceCorners"

        SettingsButtonGroupRow {
            tab: "theme"
            tags: ["corner", "radius", "rounded", "square", "fixed", "material", "shape"]
            settingKey: "radiusMode"
            text: I18n.tr("Corner style")
            model: [I18n.tr("Material scale", "corner style: Material shape scale with a strength slider"), I18n.tr("Fixed", "corner style: one radius for every corner")]
            currentIndex: SettingsData.radiusMode === "fixed" ? 1 : 0
            onSelectionChanged: (index, selected) => {
                if (selected)
                    SettingsData.set("radiusMode", index === 1 ? "fixed" : "scale");
            }
        }

        SettingsSliderRow {
            tab: "theme"
            tags: ["corner", "radius", "rounded", "square", "strength"]
            settingKey: "radiusStrength"
            visible: SettingsData.radiusMode !== "fixed"
            text: I18n.tr("Radius strength", "global component corner rounding")
            description: I18n.tr("50 uses Material shapes. Lower values reduce rounding; higher values increase it.", "radius strength slider description")
            minimumLabel: I18n.tr("Square")
            value: SettingsData.radiusStrength
            minimum: 0
            maximum: 100
            unit: ""
            onSliderValueChanged: newValue => SettingsData.set("radiusStrength", newValue)
        }

        SettingsSliderRow {
            tab: "theme"
            tags: ["corner", "radius", "rounded", "square", "fixed"]
            settingKey: "fixedRadius"
            visible: SettingsData.radiusMode === "fixed"
            text: I18n.tr("Corner radius")
            minimumLabel: I18n.tr("Square")
            value: SettingsData.fixedRadius
            minimum: 0
            maximum: 32
            unit: "px"
            onSliderValueChanged: newValue => SettingsData.set("fixedRadius", newValue)
        }

        SettingsToggleSliderRow {
            tab: "theme"
            tags: ["window", "corner", "radius", "match", "follow", "link", "strength", "rounded", "popout", "menu", "modal", "compositor", "niri", "hyprland", "mango"]
            settingKey: "windowRadius"
            text: I18n.tr("Override window radius", "toggle: stop the window radius following the corner style setting")
            visible: root.windowRadiusKey !== ""
            checked: Theme.compositorRadiusOverride >= 0
            value: Theme.windowRadius
            minimum: 0
            maximum: 64
            unit: "px"
            onToggled: checked => SettingsData.set(root.windowRadiusKey, checked ? Math.round(Theme.windowRadius) : -1)
            onSliderDragFinished: finalValue => SettingsData.set(root.windowRadiusKey, finalValue)
        }
    }

    Repeater {
        model: [
            {
                kind: "bar",
                title: I18n.tr("Bars"),
                settingKey: "barOpacityOverrides"
            },
            {
                kind: "dock",
                title: I18n.tr("Docks"),
                settingKey: "dockOpacityOverrides"
            }
        ]

        SettingsCard {
            id: targetCard

            required property var modelData
            readonly property var targets: root.opacityTargets.filter(target => target.kind === modelData.kind)
            readonly property var activeTargets: targets.filter(target => target.enabled)
            readonly property var hiddenTargets: targets.filter(target => !target.enabled)
            // String keys: a config edit must not rebuild the row holding the focused control
            readonly property string activeKeys: activeTargets.map(target => target.key).join("\n")
            readonly property string hiddenKeys: hiddenTargets.map(target => target.key).join("\n")
            property bool showHidden: false

            tab: "theme"
            tags: ["surface", "opacity", "transparency", modelData.kind, "override"]
            title: modelData.title
            settingKey: modelData.settingKey
            visible: targets.length > 0

            SettingsControlledBy {
                visible: targetCard.modelData.kind === "dock" && SettingsData.connectedFrameModeActive && targetCard.activeTargets.some(target => !target.overlay)
                parentModal: root.parentModal
                section: "frameSurfaceOpacity"
                settingLabel: I18n.tr("Opacity")
                reason: I18n.tr("Managed by Frame in Connected Mode")
            }

            Repeater {
                model: targetCard.activeKeys ? targetCard.activeKeys.split("\n") : []
                delegate: opacityTargetRow
            }

            SettingsRow {
                tab: "theme"
                tags: ["surface", "opacity", "transparency", targetCard.modelData.kind, "hidden", "disabled"]
                title: I18n.tr("Hidden (%1)", "island settings: hidden groups divider, %1 is count").arg(targetCard.hiddenTargets.length)
                iconName: "visibility_off"
                visible: targetCard.hiddenTargets.length > 0
                clickable: true
                onClicked: targetCard.showHidden = !targetCard.showHidden

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: targetCard.showHidden ? "expand_less" : "expand_more"
                    size: Theme.iconSize
                    color: Theme.onSurfaceVariant
                }
            }

            Repeater {
                model: targetCard.showHidden && targetCard.hiddenKeys ? targetCard.hiddenKeys.split("\n") : []
                delegate: opacityTargetRow
            }
        }
    }

    SettingsCard {
        tab: "theme"
        tags: ["floating", "window", "settings", "notepad", "authentication", "polkit", "opacity", "transparency", "foreground", "tile", "tiling", "override"]
        title: I18n.tr("Floating windows")
        settingKey: "floatingWindows"

        SettingsToggleCard {
            tab: "theme"
            tags: ["floating", "window", "sync", "global", "surface", "opacity", "override"]
            settingKey: "floatingWindowSyncGlobal"
            title: I18n.tr("Override", "verb, toggle to override the global setting for this item")
            checked: !root.followsSurfaces
            onToggled: checked => SettingsData.set("floatingWindowSyncGlobal", !checked)

            SettingsSliderRow {
                tab: "theme"
                tags: ["floating", "window", "opacity", "transparency", "settings", "notepad", "authentication", "polkit"]
                settingKey: "floatingWindowTransparency"
                text: I18n.tr("Opacity")
                value: Math.round(Theme.floatingWindowTransparency * 100)
                minimum: 0
                maximum: 100
                onSliderValueChanged: newValue => SettingsData.set("floatingWindowTransparency", newValue / 100)
            }

            SettingsToggleSliderRow {
                tab: "theme"
                tags: ["floating", "window", "foreground", "layers", "opacity", "transparency", "contrast", "cards", "blur", "glass"]
                settingKey: "floatingWindowForegroundLayers"
                valueKeys: ["floatingWindowForegroundTransparency"]
                text: I18n.tr("Foreground layers")
                checked: Theme.floatingWindowForegroundLayers
                value: Math.round(Theme.floatingWindowForegroundTransparency * 100)
                minimum: 0
                maximum: 100
                onToggled: checked => SettingsData.set("floatingWindowForegroundLayers", checked)
                onSliderValueChanged: newValue => SettingsData.set("floatingWindowForegroundTransparency", newValue / 100)
            }
        }

        SettingsToggleRow {
            tab: "theme"
            tags: ["floating", "window", "title", "bar", "header", "csd", "decoration", "compositor", "kwin", "controls"]
            settingKey: "floatingWindowTitleBars"
            text: I18n.tr("Title bars")
            description: I18n.tr("Off lets the compositor decorate DMS windows. Open windows update when reopened.", "theme floating windows section, title bars toggle description")
            checked: SettingsData.floatingWindowTitleBars
            onToggled: checked => SettingsData.set("floatingWindowTitleBars", checked)
        }

        SettingsToggleRow {
            tab: "theme"
            tags: ["floating", "window", "tile", "tiling", "compositor", "rule", "niri", "hyprland", "mango"]
            settingKey: "dmsWindowsFloating"
            text: I18n.tr("Open floating")
            description: I18n.tr("Adds a compositor window rule so DMS windows such as Settings open floating", "theme floating windows section, open floating toggle description")
            visible: windowRulesInclude.compositorSupported
            checked: CompositorService.dmsWindowFloatingActive
            modified: !checked
            onToggled: checked => {
                CompositorService.setDmsWindowFloatingRule(checked);
                if (checked)
                    windowRulesInclude.check();
            }
        }

        IncludeSetupBanner {
            include: windowRulesInclude
            visibleCondition: windowRulesInclude.compositorSupported && CompositorService.dmsWindowFloatingActive
        }
    }

    Component {
        id: opacityTargetRow

        SettingsToggleSliderRow {
            id: overrideRow

            required property string modelData
            readonly property var target: root.opacityTargets.find(entry => entry.key === modelData) ?? null

            tab: "theme"
            tags: ["surface", "opacity", "transparency", "bar", "dock", "override"]
            settingKey: "surfaceOpacity_" + modelData.replace(":", "_")
            text: target?.name ?? ""
            description: target?.frame ? I18n.tr("Frame") + " · " + I18n.tr("Override") : I18n.tr("Override")
            checked: target?.override ?? false
            value: Math.round((target?.transparency ?? 1) * 100)
            minimum: 0
            maximum: 100
            modified: target?.override ?? false
            valueModified: (target?.transparency ?? 1) !== 1
            onResetRequested: root.setOpacityOverride(target, {
                followInterfaceStyle: true,
                transparency: 1
            })
            onValueResetRequested: root.setOpacityOverride(target, {
                transparency: 1
            })
            onToggled: checked => root.setOpacityOverride(target, {
                    followInterfaceStyle: !checked
                })
            onSliderDragFinished: finalValue => root.setOpacityOverride(target, {
                    transparency: finalValue / 100
                })
        }
    }

    SettingsToggleCard {
        tab: "theme"
        tags: ["focus", "ring", "keyboard", "outline", "highlight"]
        settingKey: "focusRingEnabled"
        iconName: "center_focus_strong"
        title: I18n.tr("Focus ring")
        checked: SettingsData.focusRingEnabled
        onToggled: checked => SettingsData.set("focusRingEnabled", checked)

        SettingsSliderRow {
            tab: "theme"
            tags: ["focus", "ring", "thickness", "width"]
            settingKey: "focusRingWidth"
            text: I18n.tr("Thickness")
            value: Math.round(SettingsData.focusRingWidth * 10)
            minimum: 10
            maximum: 40
            step: 5
            decimals: 1
            unit: "px"
            onSliderValueChanged: newValue => SettingsData.set("focusRingWidth", newValue / 10)
        }

        SettingsDropdownRow {
            tab: "theme"
            tags: ["focus", "ring", "color"]
            settingKey: "focusRingColor"
            text: I18n.tr("Color")
            options: [I18n.tr("Primary", "surface border color"), I18n.tr("Secondary", "surface border color"), I18n.tr("Outline", "surface border color"), I18n.tr("Text Color", "surface border color")]
            optionColorMap: ({
                    [I18n.tr("Primary", "surface border color")]: Theme.primary,
                    [I18n.tr("Secondary", "surface border color")]: Theme.secondary,
                    [I18n.tr("Outline", "surface border color")]: Theme.outline,
                    [I18n.tr("Text Color", "surface border color")]: Theme.surfaceText
                })
            currentValue: {
                switch (SettingsData.focusRingColor) {
                case "secondary":
                    return I18n.tr("Secondary", "surface border color");
                case "outline":
                    return I18n.tr("Outline", "surface border color");
                case "surfaceText":
                    return I18n.tr("Text Color", "surface border color");
                default:
                    return I18n.tr("Primary", "surface border color");
                }
            }
            onValueChanged: value => {
                switch (value) {
                case I18n.tr("Secondary", "surface border color"):
                    SettingsData.set("focusRingColor", "secondary");
                    return;
                case I18n.tr("Outline", "surface border color"):
                    SettingsData.set("focusRingColor", "outline");
                    return;
                case I18n.tr("Text Color", "surface border color"):
                    SettingsData.set("focusRingColor", "surfaceText");
                    return;
                }
                SettingsData.set("focusRingColor", "primary");
            }
        }
    }

    SettingsToggleCard {
        tab: "theme"
        tags: ["scroll", "scrollbar", "scrollbars", "list", "page"]
        settingKey: "scrollbarsEnabled"
        iconName: "unfold_more"
        title: I18n.tr("Scrollbars", "theme settings toggle, show scrollbars on lists and pages")
        checked: SettingsData.scrollbarsEnabled
        onToggled: checked => SettingsData.set("scrollbarsEnabled", checked)
    }

    SettingsCard {
        tab: "theme"
        tags: ["button", "color", "accent"]
        title: I18n.tr("Colors")
        settingKey: "surfaceColors"

        SettingsDropdownRow {
            tab: "theme"
            tags: ["button", "color", "primary", "accent", "action"]
            settingKey: "buttonColorMode"
            text: I18n.tr("Button color")
            options: [I18n.tr("Primary", "button color option"), I18n.tr("Primary Container", "button color option"), I18n.tr("Secondary", "button color option"), I18n.tr("Surface Variant", "button color option")]
            optionColorMap: ({
                    [I18n.tr("Primary", "button color option")]: Theme.roleColor("primary"),
                    [I18n.tr("Primary Container", "button color option")]: Theme.roleColor("primaryContainer"),
                    [I18n.tr("Secondary", "button color option")]: Theme.roleColor("secondary"),
                    [I18n.tr("Surface Variant", "button color option")]: Theme.roleColor("surfaceVariant")
                })
            currentValue: {
                switch (SettingsData.buttonColorMode) {
                case "primaryContainer":
                    return I18n.tr("Primary Container", "button color option");
                case "secondary":
                    return I18n.tr("Secondary", "button color option");
                case "surfaceVariant":
                    return I18n.tr("Surface Variant", "button color option");
                default:
                    return I18n.tr("Primary", "button color option");
                }
            }
            onValueChanged: value => {
                switch (value) {
                case I18n.tr("Primary Container", "button color option"):
                    SettingsData.set("buttonColorMode", "primaryContainer");
                    return;
                case I18n.tr("Secondary", "button color option"):
                    SettingsData.set("buttonColorMode", "secondary");
                    return;
                case I18n.tr("Surface Variant", "button color option"):
                    SettingsData.set("buttonColorMode", "surfaceVariant");
                    return;
                }
                SettingsData.set("buttonColorMode", "primary");
            }
        }

        SettingsSliderRow {
            tab: "theme"
            tags: ["container", "accent", "color", "saturation", "tint", "pastel", "primary", "card"]
            settingKey: "containerSaturation"
            text: I18n.tr("Container saturation", "theme setting, saturation of tinted accent containers")
            description: I18n.tr("Tinted cards and badges across the shell", "container saturation setting description")
            value: SettingsData.containerSaturation
            minimum: 0
            maximum: 200
            step: 5
            onSliderValueChanged: newValue => SettingsData.set("containerSaturation", newValue)
        }
    }

    SettingsCard {
        tab: "theme"
        tags: ["control center", "icon", "scale", "size", "tile"]
        title: I18n.tr("Control Center", "Control Center")
        settingKey: "controlCenterIcons"

        SettingsDropdownRow {
            tab: "theme"
            tags: ["control", "center", "tile", "button", "color", "active"]
            settingKey: "controlCenterTileColorMode"
            text: I18n.tr("Tile color", "control center tile color dropdown label")
            options: [I18n.tr("Primary", "tile color option"), I18n.tr("Primary Container", "tile color option"), I18n.tr("Secondary", "tile color option"), I18n.tr("Surface Variant", "tile color option")]
            optionColorMap: ({
                    [I18n.tr("Primary", "tile color option")]: Theme.roleColor("primary"),
                    [I18n.tr("Primary Container", "tile color option")]: Theme.roleColor("primaryContainer"),
                    [I18n.tr("Secondary", "tile color option")]: Theme.roleColor("secondary"),
                    [I18n.tr("Surface Variant", "tile color option")]: Theme.roleColor("surfaceVariant")
                })
            currentValue: {
                switch (SettingsData.controlCenterTileColorMode) {
                case "primaryContainer":
                    return I18n.tr("Primary Container", "tile color option");
                case "secondary":
                    return I18n.tr("Secondary", "tile color option");
                case "surfaceVariant":
                    return I18n.tr("Surface Variant", "tile color option");
                default:
                    return I18n.tr("Primary", "tile color option");
                }
            }
            onValueChanged: value => {
                switch (value) {
                case I18n.tr("Primary Container", "tile color option"):
                    SettingsData.set("controlCenterTileColorMode", "primaryContainer");
                    return;
                case I18n.tr("Secondary", "tile color option"):
                    SettingsData.set("controlCenterTileColorMode", "secondary");
                    return;
                case I18n.tr("Surface Variant", "tile color option"):
                    SettingsData.set("controlCenterTileColorMode", "surfaceVariant");
                    return;
                }
                SettingsData.set("controlCenterTileColorMode", "primary");
            }
        }

        SettingsSliderRow {
            tab: "theme"
            tags: ["control", "center", "icon", "scale", "size", "tile", "header"]
            settingKey: "controlCenterIconScale"
            text: I18n.tr("Icon scale")
            minimum: 50
            maximum: 150
            step: 5
            unit: ""
            decimals: 2
            value: Math.round(SettingsData.controlCenterIconScale * 100)
            onSliderValueChanged: value => SettingsData.set("controlCenterIconScale", value / 100)
        }
    }
}
