pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/CompositorAnimations.js" as CompositorAnimations

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property string compositor: CompositorService.compositor
    readonly property string compositorName: CompositorService.displayName
    readonly property string preset: CompositorAnimations.normalizePreset(SettingsData.compositorAnimationPreset)
    readonly property var overrides: SettingsData.compositorAnimationOverrides
    readonly property var eff: CompositorAnimations.effective(compositor, preset, overrides)
    readonly property var groupList: CompositorAnimations.groups(compositor)
    readonly property var live: CompositorAnimations.controls(compositor, preset)
    readonly property bool isCustom: CompositorAnimations.isCustom(compositor, overrides)
    readonly property var presetLabels: [compositorName, "DMS", I18n.tr("Material")]
    readonly property var resetKeys: ["compositorAnimationOverrides", "compositorAnimationSlowdown", "compositorAnimationPreset"]
    readonly property string styleDescription: {
        if (isCustom)
            return I18n.tr("Custom, based on %1", "animation style description, %1 is the base style name").arg(presetLabels[CompositorAnimations.PRESETS.indexOf(preset)]);
        switch (preset) {
        case "stock":
            return I18n.tr("Stock %1 animations", "animation style description, %1 is the compositor name").arg(compositorName);
        case "material":
            return I18n.tr("M3 Expressive motion sized by surface", "animation style description");
        default:
            return I18n.tr("Quick with a slight bounce on movement", "animation style description");
        }
    }

    // No same-value guard: clicking the shown style rewrites a file that drifted
    function selectPreset(value) {
        SettingsData.set("compositorAnimationPreset", value);
        SettingsData.set("compositorAnimationOverrides", {});
    }

    // A release without movement must not turn the style Custom
    function setGroup(group, field, value) {
        if (value === eff[group]?.[field])
            return;
        SettingsData.set("compositorAnimationOverrides", CompositorAnimations.setOverride(compositor, preset, overrides, group, field, value));
    }

    function clearGroup(group) {
        SettingsData.set("compositorAnimationOverrides", CompositorAnimations.clearOverride(overrides, group));
    }

    function resetAll() {
        SettingsData.resetToDefault(resetKeys);
    }

    component GroupRow: SettingsRow {
        id: groupRow

        required property string group
        readonly property var values: root.eff[group] ?? null
        readonly property bool durationLive: root.live[group]?.duration ?? false
        readonly property bool bounceLive: root.live[group]?.bounce ?? false
        readonly property real cellMinWidth: Theme.iconButtonSize * 2 + SettingsMetrics.previewTileMinWidth

        visible: root.groupList.includes(group) && (durationLive || bounceLive)
        modified: values?.overridden ?? false
        resetByKeys: false
        onResetRequested: root.clearGroup(group)

        body: Grid {
            id: controls
            readonly property real cellWidth: columns === 1 ? width : (width - columnSpacing) / 2

            width: parent.width
            columns: !groupRow.durationLive || !groupRow.bounceLive || (width - columnSpacing) / 2 < groupRow.cellMinWidth ? 1 : 2
            columnSpacing: SettingsMetrics.rowContentSpacing
            rowSpacing: Theme.spacingM

            Column {
                width: controls.cellWidth
                spacing: Theme.spacingXS
                visible: groupRow.durationLive

                StyledText {
                    text: I18n.tr("Duration")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                SettingsSliderControl {
                    width: parent.width
                    accessibleName: groupRow.title + " " + I18n.tr("Duration")
                    value: groupRow.values?.duration ?? CompositorAnimations.DURATION_MIN
                    minimum: CompositorAnimations.DURATION_MIN
                    maximum: CompositorAnimations.DURATION_MAX
                    step: CompositorAnimations.DURATION_STEP
                    unit: "ms"
                    onSliderDragFinished: finalValue => root.setGroup(groupRow.group, "duration", finalValue)
                }
            }

            Column {
                width: controls.cellWidth
                spacing: Theme.spacingXS
                visible: groupRow.bounceLive

                StyledText {
                    text: I18n.tr("Bounce", "animation slider, how far motion overshoots")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                SettingsSliderControl {
                    width: parent.width
                    accessibleName: groupRow.title + " " + I18n.tr("Bounce", "animation slider, how far motion overshoots")
                    value: groupRow.values?.bounce ?? 0
                    minimum: 0
                    maximum: CompositorAnimations.BOUNCE_MAX
                    step: CompositorAnimations.BOUNCE_STEP
                    unit: "%"
                    onSliderDragFinished: finalValue => root.setGroup(groupRow.group, "bounce", finalValue)
                }
            }
        }
    }

    ConfigInclude {
        id: animationsInclude
        includeKind: "animations"
        onFixed: SettingsData.updateCompositorAnimations()
    }

    SettingsPage {
        IncludeSetupBanner {
            include: animationsInclude
            note: I18n.tr("DMS will then manage %1 animations and override animation settings in your config.", "animations include setup warning, %1 is the compositor name").arg(root.compositorName)
        }

        SettingsCard {
            width: parent.width
            tags: ["niri", "hyprland", "mango", "animations", "motion", "spring", "material", "expressive", "preset", "style", "slowdown", "speed"]
            title: I18n.tr("Animations")
            settingKey: "compositorAnimations"
            iconName: "animation"

            SettingsButtonGroupRow {
                tags: ["animations", "preset", "style", "material", "expressive", "stock", "custom", "window", "workspace"]
                settingKey: "compositorAnimationPreset"
                text: I18n.tr("Style")
                description: root.styleDescription
                model: root.presetLabels
                values: CompositorAnimations.PRESETS
                value: root.preset
                fallbackValue: "dms"
                modified: !SettingsData.isDefault(root.resetKeys)
                resetByKeys: false
                onResetRequested: root.resetAll()
                onValueSelected: value => root.selectPreset(value)
            }

            SettingsSliderRow {
                tags: ["animations", "slowdown", "speed", "duration", "motion"]
                settingKey: "compositorAnimationSlowdown"
                text: I18n.tr("Slowdown", "animation slider, global duration multiplier")
                value: Math.round(SettingsData.compositorAnimationSlowdown * 10)
                unit: "×"
                decimals: 1
                minimum: Math.round(CompositorAnimations.SLOWDOWN_MIN * 10)
                maximum: Math.round(CompositorAnimations.SLOWDOWN_MAX * 10)
                step: 1
                onSliderDragFinished: finalValue => SettingsData.set("compositorAnimationSlowdown", finalValue / 10)
            }
        }

        SettingsCard {
            width: parent.width
            tags: ["animations", "duration", "bounce", "overshoot", "spring", "custom", "window", "workspace", "popup"]
            title: I18n.tr("Advanced", "adjective, settings section title options")
            settingKey: "compositorAnimationOverrides"
            iconName: "tune"

            // Hidden with opacity, not visible, so the header keeps its height when it appears
            headerActions: DActionButton {
                readonly property bool active: root.isCustom
                iconName: "restart_alt"
                tooltipText: I18n.tr("Reset to %1", "animation groups reset button, %1 is the selected style name").arg(root.presetLabels[CompositorAnimations.PRESETS.indexOf(root.preset)])
                iconColor: Theme.surfaceVariantText
                opacity: active ? 1 : 0
                enabled: active
                Accessible.ignored: !active
                onClicked: SettingsData.set("compositorAnimationOverrides", {})
            }

            GroupRow {
                group: "open"
                tags: ["animations", "window", "open", "close", "duration", "bounce"]
                settingKey: "compositorAnimationOpen"
                iconName: "open_in_new"
                title: I18n.tr("Open and close", "animation group, windows opening and closing")
            }

            GroupRow {
                group: "movement"
                tags: ["animations", "window", "move", "resize", "column", "scroll", "duration", "bounce", "overshoot"]
                settingKey: "compositorAnimationMovement"
                iconName: "open_with"
                title: I18n.tr("Movement", "animation group, window move, resize and column scrolling")
            }

            GroupRow {
                group: "workspace"
                tags: ["animations", "workspace", "overview", "switch", "duration", "bounce", "overshoot"]
                settingKey: "compositorAnimationWorkspace"
                iconName: "overview"
                title: I18n.tr("Workspace")
            }

            GroupRow {
                group: "popups"
                tags: ["animations", "popup", "layer", "notification", "screenshot", "fade", "duration", "bounce"]
                settingKey: "compositorAnimationPopups"
                iconName: "web_asset"
                title: I18n.tr("Popups")
            }
        }
    }
}
