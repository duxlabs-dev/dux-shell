import QtCore
import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    readonly property var log: Log.scoped("CompositorLayoutTab")
    property var parentModal: null

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property string xrayConflictSource: ""

    ConfigInclude {
        id: layoutInclude
        includeKind: "layout"
        onFixed: SettingsData.updateCompositorLayout()
    }

    function checkXrayConflicts() {
        if (!CompositorService.isNiri)
            return;
        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        const script = `cd "${configDir}/niri" 2>/dev/null || exit 0
files="config.kdl"
for f in $(sed -nE 's/^[[:space:]]*include[[:space:]]+"([^"]+)".*/\\1/p' config.kdl 2>/dev/null); do
    case "$f" in dms/*|/*dms/*) continue ;; esac
    [ -f "$f" ] && files="$files $f"
done
awk '$1 == "xray" { print FILENAME ":" FNR; exit }' $files 2>/dev/null`;

        Proc.runCommand("check-xray-conflict", ["sh", "-c", script], (output, exitCode) => {
            xrayConflictSource = exitCode === 0 ? output.trim() : "";
        });
    }

    Component.onCompleted: checkXrayConflicts()

    SettingsPage {
        id: layoutColumn

        IncludeSetupBanner {
            include: layoutInclude
            visibleCondition: layoutInclude.compositorSupported
        }

        StyledRect {
            width: parent.width
            height: xrayConflictRow.implicitHeight + Theme.spacingL * 2
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.primary, 0.15)
            border.color: Theme.withAlpha(Theme.primary, 0.3)
            border.width: Theme.outlineWidth
            visible: root.xrayConflictSource !== ""

            Row {
                id: xrayConflictRow
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                DIcon {
                    name: "warning"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    width: parent.width - Theme.iconSize - Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("An xray rule at %1 may conflict with the Xray settings below", "compositor layout warning, %1 is a config location").arg(root.xrayConflictSource)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }
        }

        SettingsCard {
            width: parent.width
            tags: ["niri", "layout", "gaps", "radius", "window", "border"]
            title: I18n.tr("Layout overrides")
            settingKey: "niriLayout"
            iconName: "layers"
            visible: CompositorService.isNiri

            SettingsButtonGroupRow {
                tags: ["niri", "gaps", "override", "unmanaged"]
                settingKey: "niriLayoutGapsMode"
                resetKeys: ["niriLayoutGapsOverride"]
                text: I18n.tr("Gaps", "noun, window gaps mode in compositor layout settings")
                description: I18n.tr("Auto follows bar spacing, Off keeps your %1 config", "gaps mode description, %1 is the compositor name").arg("niri")
                model: [I18n.tr("Auto"), I18n.tr("Custom"), I18n.tr("Off")]
                currentIndex: {
                    if (SettingsData.niriLayoutGapsOverride === -2)
                        return 2;
                    return SettingsData.niriLayoutGapsOverride >= 0 ? 1 : 0;
                }
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    switch (index) {
                    case 1:
                        SettingsData.set("niriLayoutGapsOverride", Math.max(4, (SettingsData.getPrimaryBarConfig()?.spacing ?? 4)));
                        return;
                    case 2:
                        SettingsData.set("niriLayoutGapsOverride", -2);
                        return;
                    default:
                        SettingsData.set("niriLayoutGapsOverride", -1);
                    }
                }
            }

            SettingsSliderRow {
                tags: ["niri", "gaps", "override"]
                settingKey: "niriLayoutGapsOverride"
                resetKeys: []
                text: I18n.tr("Window gaps")
                visible: SettingsData.niriLayoutGapsOverride >= 0
                value: Math.max(0, SettingsData.niriLayoutGapsOverride)
                minimum: 0
                maximum: 50
                unit: "px"
                onSliderValueChanged: newValue => SettingsData.set("niriLayoutGapsOverride", newValue)
            }

            SettingsControlledBy {
                target: "surfaces"
                parentModal: root.parentModal
                section: "windowRadius"
                settingLabel: I18n.tr("Window radius")
                reason: Math.round(Theme.windowRadius) + "px"
            }

            SettingsToggleSliderRow {
                tags: ["niri", "border", "override", "focus-ring"]
                settingKey: "niriLayoutBorderSizeEnabled"
                text: I18n.tr("Override border size")
                checked: SettingsData.niriLayoutBorderSize >= 0
                value: Math.max(0, SettingsData.niriLayoutBorderSize)
                minimum: 0
                maximum: 10
                unit: "px"
                onToggled: checked => SettingsData.set("niriLayoutBorderSize", checked ? 2 : -1)
                onSliderValueChanged: newValue => SettingsData.set("niriLayoutBorderSize", newValue)
            }

            SettingsToggleRow {
                visible: CompositorService.isNiri
                tags: ["niri", "xray", "blur", "background-effect", "performance"]
                settingKey: "niriLayoutXrayEnabled"
                text: I18n.tr("Xray blur")
                description: I18n.tr("Blurred surfaces show the wallpaper, not the windows beneath")
                checked: NiriService.layoutXrayEnabled
                onToggled: checked => NiriService.setLayoutXray(checked)
            }

            SettingsToggleRow {
                visible: CompositorService.isNiri && !SettingsData.connectedFrameModeActive
                tags: ["niri", "xray", "bar", "frame", "performance"]
                settingKey: "niriLayoutBarXrayEnabled"
                text: SettingsData.frameEnabled ? I18n.tr("Frame xray") : I18n.tr("Bar xray")
                description: I18n.tr("Blur against the wallpaper even with xray off")
                checked: NiriService.layoutBarXrayEnabled
                onToggled: checked => NiriService.setLayoutBarXray(checked)
            }
        }

        SettingsCard {
            width: parent.width
            tags: ["compositor", "toast"]
            title: I18n.tr("Notifications")
            settingKey: "compositorNotifications"
            iconName: "notifications"
            visible: CompositorService.isNiri || CompositorService.isMango

            SettingsToggleRow {
                tags: ["compositor", "toast", "reload"]
                settingKey: "showConfigReloadToast"
                text: I18n.tr("Show \"config reloaded\" toast")
                checked: SessionData.showConfigReloadToast
                onToggled: checked => SessionData.showConfigReloadToast = checked
            }
        }

        SettingsCard {
            width: parent.width
            tags: ["niri", "overview", "window", "focus", "launch", "launcher", "dock", "settings"]
            title: I18n.tr("Overview")
            settingKey: "niriOverview"
            iconName: "overview"
            visible: CompositorService.isNiri

            SettingsToggleRow {
                tags: ["niri", "overview", "window", "focus", "launch", "launcher", "dock", "settings"]
                settingKey: "closeNiriOverviewOnWindowFocus"
                text: I18n.tr("Close on window focus")
                description: I18n.tr("Leaves the overview when DMS launches an app or focuses a window", "niri overview close on window focus toggle description")
                checked: SettingsData.closeNiriOverviewOnWindowFocus
                onToggled: checked => SettingsData.set("closeNiriOverviewOnWindowFocus", checked)
            }
        }

        SettingsCard {
            id: hyprTilingCard
            width: parent.width
            tags: ["hyprland", "layout", "tiling", "dwindle", "master", "scrolling", "general:layout"]
            title: I18n.tr("Tiling layout", "Hyprland settings card title")
            settingKey: "hyprlandTilingLayout"
            iconName: "view_quilt"
            visible: CompositorService.isHyprland

            readonly property var layoutIds: ["", "dwindle", "master", "scrolling"]

            SettingsButtonGroupRow {
                tags: ["hyprland", "layout", "tiling", "dwindle", "master", "scrolling"]
                settingKey: "hyprlandTilingLayout"
                text: I18n.tr("Layout")
                model: [I18n.tr("Off"), I18n.tr("Dwindle", "Hyprland tiling layout name"), I18n.tr("Master", "Hyprland tiling layout name"), I18n.tr("Scrolling", "Hyprland tiling layout name")]
                currentIndex: Math.max(0, hyprTilingCard.layoutIds.indexOf(SettingsData.hyprlandTilingLayout))
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("hyprlandTilingLayout", hyprTilingCard.layoutIds[index]);
                }
            }

            SettingsToggleRow {
                tags: ["hyprland", "dwindle", "preserve", "split"]
                settingKey: "hyprlandDwindlePreserveSplit"
                visible: SettingsData.hyprlandTilingLayout === "dwindle"
                text: I18n.tr("Preserve split", "Hyprland dwindle layout toggle")
                description: I18n.tr("Split direction stays fixed when the container resizes", "Hyprland preserve split toggle description")
                checked: SettingsData.hyprlandDwindlePreserveSplit
                onToggled: checked => SettingsData.set("hyprlandDwindlePreserveSplit", checked)
            }

            SettingsToggleRow {
                tags: ["hyprland", "dwindle", "smart", "split", "cursor"]
                settingKey: "hyprlandDwindleSmartSplit"
                visible: SettingsData.hyprlandTilingLayout === "dwindle"
                text: I18n.tr("Smart split", "Hyprland dwindle layout toggle")
                description: I18n.tr("Split direction follows the cursor position in the window", "Hyprland smart split toggle description")
                checked: SettingsData.hyprlandDwindleSmartSplit
                onToggled: checked => SettingsData.set("hyprlandDwindleSmartSplit", checked)
            }

            SettingsButtonGroupRow {
                tags: ["hyprland", "dwindle", "force", "split", "direction"]
                settingKey: "hyprlandDwindleForceSplit"
                visible: SettingsData.hyprlandTilingLayout === "dwindle"
                text: I18n.tr("Force split", "Hyprland dwindle layout dropdown, which side new windows split to")
                model: [I18n.tr("Follow mouse", "Hyprland force split option, the split side follows the pointer"), I18n.tr("Left"), I18n.tr("Right")]
                currentIndex: SettingsData.hyprlandDwindleForceSplit
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("hyprlandDwindleForceSplit", index);
                }
            }

            SettingsDropdownRow {
                readonly property var ids: ["left", "right", "top", "bottom", "center"]
                tags: ["hyprland", "master", "orientation", "position"]
                settingKey: "hyprlandMasterOrientation"
                visible: SettingsData.hyprlandTilingLayout === "master"
                text: I18n.tr("Master position", "Hyprland master layout dropdown, where the master window sits")
                options: [I18n.tr("Left"), I18n.tr("Right"), I18n.tr("Top"), I18n.tr("Bottom"), I18n.tr("Center")]
                currentValue: options[Math.max(0, ids.indexOf(SettingsData.hyprlandMasterOrientation))]
                onValueChanged: value => SettingsData.set("hyprlandMasterOrientation", ids[Math.max(0, options.indexOf(value))])
            }

            SettingsButtonGroupRow {
                readonly property var ids: ["slave", "master", "inherit"]
                tags: ["hyprland", "master", "new", "window", "status", "slave"]
                settingKey: "hyprlandMasterNewStatus"
                visible: SettingsData.hyprlandTilingLayout === "master"
                text: I18n.tr("New windows", "Hyprland master layout dropdown, where new windows go")
                model: [I18n.tr("Stack", "Hyprland master layout option, new windows join the stack"), I18n.tr("Master", "Hyprland tiling layout name"), I18n.tr("Inherit")]
                currentIndex: Math.max(0, ids.indexOf(SettingsData.hyprlandMasterNewStatus))
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("hyprlandMasterNewStatus", ids[index]);
                }
            }

            SettingsToggleRow {
                tags: ["hyprland", "master", "new", "top", "stack"]
                settingKey: "hyprlandMasterNewOnTop"
                visible: SettingsData.hyprlandTilingLayout === "master"
                text: I18n.tr("New windows on top of the stack", "Hyprland master layout toggle")
                checked: SettingsData.hyprlandMasterNewOnTop
                onToggled: checked => SettingsData.set("hyprlandMasterNewOnTop", checked)
            }

            SettingsSliderRow {
                tags: ["hyprland", "master", "size", "mfact", "ratio"]
                settingKey: "hyprlandMasterSize"
                visible: SettingsData.hyprlandTilingLayout === "master"
                text: I18n.tr("Master size", "Hyprland master layout slider, share of the screen the master window takes")
                value: SettingsData.hyprlandMasterSize
                minimum: 10
                maximum: 90
                onSliderValueChanged: newValue => SettingsData.set("hyprlandMasterSize", newValue)
            }

            SettingsButtonGroupRow {
                readonly property var ids: ["right", "left", "down", "up"]
                tags: ["hyprland", "scrolling", "direction"]
                settingKey: "hyprlandScrollingDirection"
                visible: SettingsData.hyprlandTilingLayout === "scrolling"
                text: I18n.tr("Direction")
                model: [I18n.tr("Right"), I18n.tr("Left"), I18n.tr("Down", "Hyprland scrolling layout direction"), I18n.tr("Up", "Hyprland scrolling layout direction")]
                currentIndex: Math.max(0, ids.indexOf(SettingsData.hyprlandScrollingDirection))
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("hyprlandScrollingDirection", ids[index]);
                }
            }

            SettingsSliderRow {
                tags: ["hyprland", "scrolling", "column", "width"]
                settingKey: "hyprlandScrollingColumnWidth"
                visible: SettingsData.hyprlandTilingLayout === "scrolling"
                text: I18n.tr("Column Width")
                value: SettingsData.hyprlandScrollingColumnWidth
                minimum: 10
                maximum: 100
                onSliderValueChanged: newValue => SettingsData.set("hyprlandScrollingColumnWidth", newValue)
            }

            SettingsToggleRow {
                tags: ["hyprland", "scrolling", "fullscreen", "single", "column"]
                settingKey: "hyprlandScrollingFullscreenOneColumn"
                visible: SettingsData.hyprlandTilingLayout === "scrolling"
                text: I18n.tr("Fullscreen single column", "Hyprland scrolling layout toggle, a lone column fills the screen")
                checked: SettingsData.hyprlandScrollingFullscreenOneColumn
                onToggled: checked => SettingsData.set("hyprlandScrollingFullscreenOneColumn", checked)
            }

            SettingsDropdownRow {
                tags: ["hyprland", "scrolling", "follow", "focus", "scroll", "click", "follow_focus"]
                settingKey: "hyprlandScrollingFollowFocus"
                visible: SettingsData.hyprlandTilingLayout === "scrolling"
                text: I18n.tr("Follow focus")
                options: {
                    const modes = [I18n.tr("Off"), I18n.tr("On")];
                    if (HyprlandService.hyprIntModes())
                        modes.push(I18n.tr("Not on click", "Hyprland scrolling follow focus option, focus scrolls the view but clicking a window does not"));
                    return modes;
                }
                currentValue: options[Math.min(SettingsData.hyprlandScrollingFollowFocus, options.length - 1)] ?? ""
                onValueChanged: value => {
                    const index = options.indexOf(value);
                    if (index < 0)
                        return;
                    SettingsData.set("hyprlandScrollingFollowFocus", index);
                }
            }
        }

        SettingsCard {
            width: parent.width
            tags: ["hyprland", "layout", "gaps", "radius", "window", "border", "rounding"]
            title: I18n.tr("Layout overrides")
            settingKey: "hyprlandLayout"
            iconName: "crop_square"
            visible: CompositorService.isHyprland

            SettingsButtonGroupRow {
                tags: ["hyprland", "gaps", "override", "inner", "outer", "unmanaged"]
                settingKey: "hyprlandLayoutGapsMode"
                resetKeys: ["hyprlandLayoutGapsOverride"]
                text: I18n.tr("Gaps")
                model: [I18n.tr("Auto"), I18n.tr("Custom"), I18n.tr("Off")]
                currentIndex: {
                    if (SettingsData.hyprlandLayoutGapsOverride === -2)
                        return 2;
                    return SettingsData.hyprlandLayoutGapsOverride >= 0 ? 1 : 0;
                }
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    switch (index) {
                    case 1:
                        SettingsData.set("hyprlandLayoutGapsOverride", Math.max(4, (SettingsData.getPrimaryBarConfig()?.spacing ?? 4)));
                        return;
                    case 2:
                        SettingsData.set("hyprlandLayoutGapsOverride", -2);
                        return;
                    default:
                        SettingsData.set("hyprlandLayoutGapsOverride", -1);
                    }
                }
            }

            SettingsSliderRow {
                tags: ["hyprland", "gaps", "override", "inner", "gaps_in"]
                settingKey: "hyprlandLayoutGapsOverride"
                resetKeys: []
                text: I18n.tr("Inner gaps")
                visible: SettingsData.hyprlandLayoutGapsOverride >= 0
                value: Math.max(0, SettingsData.hyprlandLayoutGapsOverride)
                minimum: 0
                maximum: 50
                unit: "px"
                onSliderValueChanged: newValue => SettingsData.set("hyprlandLayoutGapsOverride", newValue)
            }

            SettingsSliderRow {
                tags: ["hyprland", "gaps", "override", "outer", "edge", "gaps_out"]
                settingKey: "hyprlandLayoutGapsOutOverride"
                text: I18n.tr("Outer gaps")
                visible: SettingsData.hyprlandLayoutGapsOverride >= 0
                value: SettingsData.hyprlandLayoutGapsOutOverride >= 0 ? SettingsData.hyprlandLayoutGapsOutOverride : Math.max(0, SettingsData.hyprlandLayoutGapsOverride)
                minimum: 0
                maximum: 50
                unit: "px"
                onSliderValueChanged: newValue => SettingsData.set("hyprlandLayoutGapsOutOverride", newValue)
            }

            SettingsControlledBy {
                target: "surfaces"
                parentModal: root.parentModal
                section: "windowRadius"
                settingLabel: I18n.tr("Window radius")
                reason: Math.round(Theme.windowRadius) + "px"
            }

            SettingsToggleSliderRow {
                tags: ["hyprland", "border", "override", "border_size"]
                settingKey: "hyprlandLayoutBorderSizeEnabled"
                text: I18n.tr("Override border size")
                checked: SettingsData.hyprlandLayoutBorderSize >= 0
                value: Math.max(0, SettingsData.hyprlandLayoutBorderSize)
                minimum: 0
                maximum: 10
                unit: "px"
                onToggled: checked => SettingsData.set("hyprlandLayoutBorderSize", checked ? 2 : -1)
                onSliderValueChanged: newValue => SettingsData.set("hyprlandLayoutBorderSize", newValue)
            }

            SettingsToggleSliderRow {
                tags: ["hyprland", "resize", "border", "mouse", "drag", "grab", "area", "extend_border_grab_area"]
                settingKey: "hyprlandResizeOnBorder"
                valueKeys: ["hyprlandBorderGrabArea"]
                text: I18n.tr("Resize on border")
                checked: SettingsData.hyprlandResizeOnBorder
                value: SettingsData.hyprlandBorderGrabArea
                minimum: 0
                maximum: 100
                unit: "px"
                onToggled: checked => SettingsData.set("hyprlandResizeOnBorder", checked)
                onSliderValueChanged: newValue => SettingsData.set("hyprlandBorderGrabArea", newValue)
            }

            SettingsToggleRow {
                tags: ["hyprland", "drag", "float", "center", "cursor", "mouse", "drag_center_window"]
                settingKey: "hyprlandDragCenterWindow"
                visible: HyprlandService.hyprSupports("binds:drag_center_window")
                text: I18n.tr("Center dragged windows", "Hyprland toggle, a tiled or fullscreen window dragged loose centers on the cursor")
                description: I18n.tr("A tiled or fullscreen window dragged into floating centers on the cursor")
                checked: SettingsData.hyprlandDragCenterWindow
                onToggled: checked => SettingsData.set("hyprlandDragCenterWindow", checked)
            }

            SettingsSliderRow {
                tags: ["hyprland", "opacity", "transparency", "window"]
                settingKey: "hyprlandWindowOpacity"
                text: I18n.tr("Window opacity", "Hyprland opacity applied to app windows")
                value: SettingsData.hyprlandWindowOpacity
                minimum: 10
                maximum: 100
                unit: "%"
                onSliderValueChanged: newValue => SettingsData.set("hyprlandWindowOpacity", newValue)
            }

            SettingsToggleRow {
                visible: CompositorService.isHyprland
                tags: ["hyprland", "xray", "blur", "background-effect", "performance"]
                settingKey: "hyprlandLayoutXrayEnabled"
                text: I18n.tr("Xray blur")
                description: I18n.tr("Blurred surfaces show the wallpaper, not the windows beneath")
                checked: HyprlandService.layoutXrayEnabled
                onToggled: checked => HyprlandService.setLayoutXray(checked)
            }

            SettingsToggleRow {
                visible: CompositorService.isHyprland && !SettingsData.connectedFrameModeActive
                tags: ["hyprland", "xray", "bar", "frame", "performance"]
                settingKey: "hyprlandLayoutBarXrayEnabled"
                text: SettingsData.frameEnabled ? I18n.tr("Frame xray") : I18n.tr("Bar xray")
                description: I18n.tr("Blur against the wallpaper even with xray off")
                checked: HyprlandService.layoutBarXrayEnabled
                onToggled: checked => HyprlandService.setLayoutBarXray(checked)
            }
        }

        SettingsCard {
            id: hyprEffectsCard
            width: parent.width
            tags: ["hyprland", "effects", "blur", "glow", "wobble", "motion", "decoration"]
            title: I18n.tr("Visual effects")
            settingKey: "hyprlandEffects"
            iconName: "auto_awesome"
            visible: CompositorService.isHyprland && (HyprlandService.hyprSupports("decoration:blur:variant") || HyprlandService.hyprSupports("decoration:blur:proportional") || HyprlandService.hyprSupports("decoration:glow:enabled") || HyprlandService.hyprSupports("decoration:wobble:enabled") || HyprlandService.hyprSupports("decoration:motion_blur:enabled"))

            readonly property var blurVariantIds: ["kawase", "frost", "ripple", "drops", "water", "fluid_jar", "prism", "heat_shimmer", "acrylic", "aurora", "haze"]

            SettingsDropdownRow {
                tags: ["hyprland", "blur", "variant", "style", "acrylic", "aurora", "frost", "glass"]
                settingKey: "hyprlandBlurVariant"
                visible: HyprlandService.hyprSupports("decoration:blur:variant")
                text: I18n.tr("Blur")
                description: I18n.tr("Styles outside of Default use more GPU", "Hyprland blur variant dropdown description")
                options: [I18n.tr("Default"), I18n.tr("Frost", "Hyprland blur variant"), I18n.tr("Ripple", "Hyprland blur variant"), I18n.tr("Drops", "Hyprland blur variant"), I18n.tr("Water", "Hyprland blur variant"), I18n.tr("Fluid jar", "Hyprland blur variant"), I18n.tr("Prism", "Hyprland blur variant"), I18n.tr("Heat shimmer", "Hyprland blur variant"), I18n.tr("Acrylic", "Hyprland blur variant"), I18n.tr("Aurora", "Hyprland blur variant"), I18n.tr("Haze", "Hyprland blur variant")]
                currentValue: options[Math.max(0, hyprEffectsCard.blurVariantIds.indexOf(SettingsData.hyprlandBlurVariant))]
                onValueChanged: value => SettingsData.set("hyprlandBlurVariant", hyprEffectsCard.blurVariantIds[Math.max(0, options.indexOf(value))])
            }

            SettingsToggleRow {
                tags: ["hyprland", "blur", "proportional", "opacity", "transparency"]
                settingKey: "hyprlandBlurProportional"
                visible: HyprlandService.hyprSupports("decoration:blur:proportional")
                text: I18n.tr("Blur follows opacity", "Hyprland toggle, blur strength scales with how opaque each pixel is")
                description: I18n.tr("More transparent areas get less blur")
                checked: SettingsData.hyprlandBlurProportional
                onToggled: checked => SettingsData.set("hyprlandBlurProportional", checked)
            }

            SettingsSliderRow {
                tags: ["hyprland", "blur", "drops", "speed", "animation"]
                settingKey: "hyprlandBlurDropsSpeed"
                visible: SettingsData.hyprlandBlurVariant === "drops" && HyprlandService.hyprSupports("decoration:blur:drops:speed")
                text: I18n.tr("Speed")
                description: I18n.tr("0 stops the animation and saves GPU", "Hyprland animated blur speed slider description")
                value: SettingsData.hyprlandBlurDropsSpeed
                minimum: 0
                maximum: 10
                onSliderValueChanged: newValue => SettingsData.set("hyprlandBlurDropsSpeed", newValue)
            }

            SettingsSliderRow {
                tags: ["hyprland", "blur", "heat", "shimmer", "speed", "animation"]
                settingKey: "hyprlandBlurHeatShimmerSpeed"
                visible: SettingsData.hyprlandBlurVariant === "heat_shimmer" && HyprlandService.hyprSupports("decoration:blur:heat_shimmer:speed")
                text: I18n.tr("Speed")
                description: I18n.tr("0 stops the animation and saves GPU", "Hyprland animated blur speed slider description")
                value: SettingsData.hyprlandBlurHeatShimmerSpeed
                minimum: 0
                maximum: 10
                onSliderValueChanged: newValue => SettingsData.set("hyprlandBlurHeatShimmerSpeed", newValue)
            }

            SettingsSliderRow {
                tags: ["hyprland", "blur", "ripple", "strength", "refraction"]
                settingKey: "hyprlandBlurRippleStrength"
                visible: SettingsData.hyprlandBlurVariant === "ripple"
                text: I18n.tr("Refraction", "Hyprland blur slider, how far ripple or water waves bend the backdrop")
                value: SettingsData.hyprlandBlurRippleStrength
                minimum: 0
                maximum: 32
                unit: "px"
                onSliderValueChanged: newValue => SettingsData.set("hyprlandBlurRippleStrength", newValue)
            }

            SettingsSliderRow {
                tags: ["hyprland", "blur", "water", "strength", "refraction"]
                settingKey: "hyprlandBlurWaterStrength"
                visible: SettingsData.hyprlandBlurVariant === "water"
                text: I18n.tr("Refraction", "Hyprland blur slider, how far ripple or water waves bend the backdrop")
                value: SettingsData.hyprlandBlurWaterStrength
                minimum: 0
                maximum: 32
                unit: "px"
                onSliderValueChanged: newValue => SettingsData.set("hyprlandBlurWaterStrength", newValue)
            }

            SettingsSliderRow {
                tags: ["hyprland", "blur", "acrylic", "clarity"]
                settingKey: "hyprlandBlurAcrylicClarity"
                visible: SettingsData.hyprlandBlurVariant === "acrylic"
                text: I18n.tr("Clarity", "Hyprland acrylic blur slider, how much sharp backdrop shows through")
                value: SettingsData.hyprlandBlurAcrylicClarity
                minimum: 0
                maximum: 100
                unit: "%"
                onSliderValueChanged: newValue => SettingsData.set("hyprlandBlurAcrylicClarity", newValue)
            }

            SettingsSliderRow {
                tags: ["hyprland", "blur", "aurora", "intensity"]
                settingKey: "hyprlandBlurAuroraIntensity"
                visible: SettingsData.hyprlandBlurVariant === "aurora"
                text: I18n.tr("Intensity")
                value: SettingsData.hyprlandBlurAuroraIntensity
                minimum: 0
                maximum: 100
                unit: "%"
                onSliderValueChanged: newValue => SettingsData.set("hyprlandBlurAuroraIntensity", newValue)
            }

            SettingsSliderRow {
                tags: ["hyprland", "blur", "aurora", "speed", "animation"]
                settingKey: "hyprlandBlurAuroraSpeed"
                visible: SettingsData.hyprlandBlurVariant === "aurora"
                text: I18n.tr("Speed")
                value: SettingsData.hyprlandBlurAuroraSpeed
                minimum: 0
                maximum: 10
                onSliderValueChanged: newValue => SettingsData.set("hyprlandBlurAuroraSpeed", newValue)
            }

            SettingsSliderRow {
                tags: ["hyprland", "blur", "haze", "intensity", "sheen"]
                settingKey: "hyprlandBlurHazeIntensity"
                visible: SettingsData.hyprlandBlurVariant === "haze"
                text: I18n.tr("Intensity")
                value: SettingsData.hyprlandBlurHazeIntensity
                minimum: 0
                maximum: 100
                unit: "%"
                onSliderValueChanged: newValue => SettingsData.set("hyprlandBlurHazeIntensity", newValue)
            }

            SettingsSliderRow {
                tags: ["hyprland", "blur", "haze", "iridescence", "color"]
                settingKey: "hyprlandBlurHazeIridescence"
                visible: SettingsData.hyprlandBlurVariant === "haze"
                text: I18n.tr("Iridescence", "Hyprland haze blur slider, strength of the pearlescent color shift")
                value: SettingsData.hyprlandBlurHazeIridescence
                minimum: 0
                maximum: 100
                unit: "%"
                onSliderValueChanged: newValue => SettingsData.set("hyprlandBlurHazeIridescence", newValue)
            }

            SettingsToggleSliderRow {
                tags: ["hyprland", "glow", "inner", "range"]
                settingKey: "hyprlandGlowEnabled"
                valueKeys: ["hyprlandGlowRange"]
                visible: HyprlandService.hyprSupports("decoration:glow:enabled")
                text: I18n.tr("Glow", "Hyprland toggle, inner glow along window edges in the theme color")
                checked: SettingsData.hyprlandGlowEnabled
                value: SettingsData.hyprlandGlowRange
                minimum: 1
                maximum: 50
                unit: "px"
                onToggled: checked => SettingsData.set("hyprlandGlowEnabled", checked)
                onSliderValueChanged: newValue => SettingsData.set("hyprlandGlowRange", newValue)
            }

            SettingsSliderRow {
                tags: ["hyprland", "glow", "falloff", "render_power"]
                settingKey: "hyprlandGlowRenderPower"
                visible: SettingsData.hyprlandGlowEnabled && HyprlandService.hyprSupports("decoration:glow:enabled")
                text: I18n.tr("Glow falloff", "Hyprland slider, higher values fade the glow faster")
                value: SettingsData.hyprlandGlowRenderPower
                minimum: 1
                maximum: 4
                onSliderValueChanged: newValue => SettingsData.set("hyprlandGlowRenderPower", newValue)
            }

            SettingsToggleSliderRow {
                tags: ["hyprland", "wobble", "wobbly", "windows", "intensity"]
                settingKey: "hyprlandWobbleEnabled"
                valueKeys: ["hyprlandWobbleIntensity"]
                visible: HyprlandService.hyprSupports("decoration:wobble:enabled")
                text: I18n.tr("Wobbly windows", "Hyprland toggle, windows flex while moving and resizing")
                checked: SettingsData.hyprlandWobbleEnabled
                value: SettingsData.hyprlandWobbleIntensity
                minimum: 0
                maximum: 200
                unit: "%"
                onToggled: checked => SettingsData.set("hyprlandWobbleEnabled", checked)
                onSliderValueChanged: newValue => SettingsData.set("hyprlandWobbleIntensity", newValue)
            }

            SettingsSliderRow {
                tags: ["hyprland", "wobble", "stiffness", "spring"]
                settingKey: "hyprlandWobbleStiffness"
                visible: SettingsData.hyprlandWobbleEnabled && HyprlandService.hyprSupports("decoration:wobble:enabled")
                text: I18n.tr("Wobble stiffness", "Hyprland slider, higher values settle wobbly windows faster")
                value: SettingsData.hyprlandWobbleStiffness
                minimum: 10
                maximum: 1000
                onSliderValueChanged: newValue => SettingsData.set("hyprlandWobbleStiffness", newValue)
            }

            SettingsToggleSliderRow {
                tags: ["hyprland", "motion", "blur", "samples", "move", "resize"]
                settingKey: "hyprlandMotionBlurEnabled"
                valueKeys: ["hyprlandMotionBlurSamples"]
                visible: HyprlandService.hyprSupports("decoration:motion_blur:enabled")
                text: I18n.tr("Motion blur", "Hyprland toggle, blur windows while they move or resize")
                description: I18n.tr("More samples look smoother and cost more GPU", "Hyprland motion blur sample count description")
                checked: SettingsData.hyprlandMotionBlurEnabled
                value: SettingsData.hyprlandMotionBlurSamples
                minimum: 1
                maximum: 64
                onToggled: checked => SettingsData.set("hyprlandMotionBlurEnabled", checked)
                onSliderValueChanged: newValue => SettingsData.set("hyprlandMotionBlurSamples", newValue)
            }
        }

        SettingsCard {
            width: parent.width
            tags: ["hyprland", "group", "groupbar", "tabs"]
            title: I18n.tr("Window groups", "Hyprland settings card title, tabbed window groups")
            settingKey: "hyprlandGroupbar"
            iconName: "tab"
            visible: CompositorService.isHyprland

            SettingsToggleRow {
                tags: ["hyprland", "groupbar", "blur"]
                settingKey: "hyprlandGroupbarBlur"
                text: I18n.tr("Background blur")
                checked: SettingsData.hyprlandGroupbarBlur
                onToggled: checked => SettingsData.set("hyprlandGroupbarBlur", checked)
            }

            SettingsSliderRow {
                tags: ["hyprland", "groupbar", "text", "padding", "text_padding"]
                settingKey: "hyprlandGroupbarTextPadding"
                text: I18n.tr("Title padding", "Hyprland groupbar slider, horizontal padding around tab titles")
                value: SettingsData.hyprlandGroupbarTextPadding
                minimum: 0
                maximum: 22
                unit: "px"
                onSliderValueChanged: newValue => SettingsData.set("hyprlandGroupbarTextPadding", newValue)
            }

            SettingsToggleRow {
                tags: ["hyprland", "groupbar", "middle", "click", "close"]
                settingKey: "hyprlandGroupbarMiddleClickClose"
                text: I18n.tr("Middle click closes", "Hyprland groupbar toggle, middle clicking a tab closes that window")
                checked: SettingsData.hyprlandGroupbarMiddleClickClose
                onToggled: checked => SettingsData.set("hyprlandGroupbarMiddleClickClose", checked)
            }

            SettingsToggleRow {
                tags: ["hyprland", "groupbar", "single", "hide", "disable_when_only"]
                settingKey: "hyprlandGroupbarDisableWhenOnly"
                visible: HyprlandService.hyprSupports("group:groupbar:disable_when_only")
                text: I18n.tr("Hide with one window", "Hyprland groupbar toggle, no tab bar when the group holds a single window")
                checked: SettingsData.hyprlandGroupbarDisableWhenOnly
                onToggled: checked => SettingsData.set("hyprlandGroupbarDisableWhenOnly", checked)
            }
        }

        SettingsCard {
            width: parent.width
            tags: ["hyprland", "behavior", "workspace", "fullscreen", "bell", "binds", "misc"]
            title: I18n.tr("Behavior")
            settingKey: "hyprlandBehavior"
            iconName: "tune"
            visible: CompositorService.isHyprland && (HyprlandService.hyprSupports("binds:workspace_back_and_forth") || HyprlandService.hyprSupports("misc:exit_window_retains_fullscreen") || HyprlandService.hyprSupports("misc:bell_sound"))

            SettingsDropdownRow {
                tags: ["hyprland", "workspace", "back", "forth", "previous", "toggle", "workspace_back_and_forth"]
                settingKey: "hyprlandWorkspaceBackAndForth"
                visible: HyprlandService.hyprSupports("binds:workspace_back_and_forth")
                text: I18n.tr("Workspace back and forth", "Hyprland option, switching to the current workspace goes to the previous one")
                description: I18n.tr("Switching to the current workspace returns to the previous one")
                options: HyprlandService.hyprIntModes() ? [I18n.tr("Off"), I18n.tr("All displays"), I18n.tr("Per display", "Hyprland workspace back and forth option, each display remembers its own previous workspace")] : [I18n.tr("Off"), I18n.tr("On")]
                currentValue: options[Math.min(SettingsData.hyprlandWorkspaceBackAndForth, options.length - 1)] ?? ""
                onValueChanged: value => {
                    const index = options.indexOf(value);
                    if (index < 0)
                        return;
                    SettingsData.set("hyprlandWorkspaceBackAndForth", index);
                }
            }

            SettingsDropdownRow {
                tags: ["hyprland", "fullscreen", "close", "exit", "retain", "group", "exit_window_retains_fullscreen"]
                settingKey: "hyprlandExitWindowRetainsFullscreen"
                visible: HyprlandService.hyprSupports("misc:exit_window_retains_fullscreen")
                text: I18n.tr("Keep fullscreen on close", "Hyprland option, closing a fullscreen window makes the next focused window fullscreen")
                options: HyprlandService.hyprIntModes() ? [I18n.tr("Off"), I18n.tr("On"), I18n.tr("Only in groups", "Hyprland keep fullscreen on close option, only inside tabbed window groups"), I18n.tr("Only outside groups", "Hyprland keep fullscreen on close option, only for windows not in a tabbed group")] : [I18n.tr("Off"), I18n.tr("On")]
                currentValue: options[Math.min(SettingsData.hyprlandExitWindowRetainsFullscreen, options.length - 1)] ?? ""
                onValueChanged: value => {
                    const index = options.indexOf(value);
                    if (index < 0)
                        return;
                    SettingsData.set("hyprlandExitWindowRetainsFullscreen", index);
                }
            }

            SettingsToggleRow {
                tags: ["hyprland", "bell", "sound", "beep", "mute", "bell_sound"]
                settingKey: "hyprlandBellSound"
                visible: HyprlandService.hyprSupports("misc:bell_sound")
                text: I18n.tr("System bell", "Hyprland toggle, play a sound when an app rings the terminal bell")
                checked: SettingsData.hyprlandBellSound !== "" && SettingsData.hyprlandBellSound !== "none"
                onToggled: checked => SettingsData.set("hyprlandBellSound", checked ? "default" : "")
            }
        }

        SettingsCard {
            width: parent.width
            tags: ["mangowc", "mango", "dwl", "layout", "gaps", "radius", "window", "border"]
            title: I18n.tr("Layout overrides")
            settingKey: "mangoLayout"
            iconName: "crop_square"
            visible: CompositorService.isMango

            SettingsButtonGroupRow {
                tags: ["mangowc", "mango", "gaps", "override", "inner", "outer", "unmanaged"]
                settingKey: "mangoLayoutGapsMode"
                resetKeys: ["mangoLayoutGapsOverride"]
                text: I18n.tr("Gaps")
                description: I18n.tr("Auto follows bar spacing, Off keeps your %1 config").arg("MangoWC")
                model: [I18n.tr("Auto"), I18n.tr("Custom"), I18n.tr("Off")]
                currentIndex: {
                    if (SettingsData.mangoLayoutGapsOverride === -2)
                        return 2;
                    return SettingsData.mangoLayoutGapsOverride >= 0 ? 1 : 0;
                }
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    switch (index) {
                    case 1:
                        SettingsData.set("mangoLayoutGapsOverride", Math.max(4, (SettingsData.getPrimaryBarConfig()?.spacing ?? 4)));
                        return;
                    case 2:
                        SettingsData.set("mangoLayoutGapsOverride", -2);
                        return;
                    default:
                        SettingsData.set("mangoLayoutGapsOverride", -1);
                    }
                }
            }

            SettingsSliderRow {
                tags: ["mangowc", "mango", "gaps", "override", "inner", "gap_inner_horizontal", "gap_inner_vertical", "gappih", "gappiv"]
                settingKey: "mangoLayoutGapsOverride"
                resetKeys: []
                text: I18n.tr("Inner gaps")
                visible: SettingsData.mangoLayoutGapsOverride >= 0
                value: Math.max(0, SettingsData.mangoLayoutGapsOverride)
                minimum: 0
                maximum: 50
                unit: "px"
                onSliderValueChanged: newValue => SettingsData.set("mangoLayoutGapsOverride", newValue)
            }

            SettingsSliderRow {
                tags: ["mangowc", "mango", "gaps", "override", "outer", "edge", "gap_outer_horizontal", "gap_outer_vertical", "gappoh", "gappov"]
                settingKey: "mangoLayoutGapsOutOverride"
                text: I18n.tr("Outer gaps")
                visible: SettingsData.mangoLayoutGapsOverride >= 0
                value: SettingsData.mangoLayoutGapsOutOverride >= 0 ? SettingsData.mangoLayoutGapsOutOverride : Math.max(0, SettingsData.mangoLayoutGapsOverride)
                minimum: 0
                maximum: 50
                unit: "px"
                onSliderValueChanged: newValue => SettingsData.set("mangoLayoutGapsOutOverride", newValue)
            }

            SettingsControlledBy {
                target: "surfaces"
                parentModal: root.parentModal
                section: "windowRadius"
                settingLabel: I18n.tr("Window radius")
                reason: Math.round(Theme.windowRadius) + "px"
            }

            SettingsToggleSliderRow {
                tags: ["mangowc", "mango", "border", "override", "border_px", "borderpx"]
                settingKey: "mangoLayoutBorderSizeEnabled"
                text: I18n.tr("Override border size")
                checked: SettingsData.mangoLayoutBorderSize >= 0
                value: Math.max(0, SettingsData.mangoLayoutBorderSize)
                minimum: 0
                maximum: 10
                unit: "px"
                onToggled: checked => SettingsData.set("mangoLayoutBorderSize", checked ? 2 : -1)
                onSliderValueChanged: newValue => SettingsData.set("mangoLayoutBorderSize", newValue)
            }
        }
    }
}
