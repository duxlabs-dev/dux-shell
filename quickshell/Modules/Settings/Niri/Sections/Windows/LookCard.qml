import QtQuick
import qs.Common
import qs.Modules.Settings.Niri.Components
import "../../../../../Common/niri/sections/look.js" as Look

NiriCard {
    id: root

    icon: "palette"
    title: I18n.tr("Look", "niri page card")

    LookGapsRow {
        title: I18n.tr("Gaps")
        icon: "padding"
        tip: I18n.tr("Space around and between windows")
        kdlKey: "layout.gaps"
    }

    NiriSlider {
        settingKey: "look.gaps"
        dependsOn: "look.gaps"
        visible: value >= 0
        title: I18n.tr("Gap size")
        icon: "width_normal"
        kdlKey: "layout.gaps"
        from: Look.limits["look.gaps"].from
        to: Look.limits["look.gaps"].to
        stepSize: 2
        unit: " px"
    }

    NiriRow {
        settingKey: "look.ringOn"
        title: I18n.tr("Window focus ring")
        icon: "center_focus_strong"
        tip: I18n.tr("Drawn outside the active window")
        kdlKey: "layout.focus-ring"
    }

    NiriSlider {
        settingKey: "look.ringWidth"
        dependsOn: "look.ringOn"
        title: I18n.tr("Ring width")
        icon: "line_weight"
        tip: I18n.tr("One width for the ring and the border")
        kdlKey: "focus-ring.width"
        from: Look.limits["look.ringWidth"].from
        to: Look.limits["look.ringWidth"].to
        unit: " px"
        numValue: value < 0 ? 2 : Number(value)

        function format(v) {
            return (value < 0 ? 2 : v) + unit;
        }
    }

    NiriSwatches {
        settingKey: "look.ringColor"
        dependsOn: "look.ringOn"
        title: I18n.tr("Ring color")
        icon: "palette"
        tip: I18n.tr("From your DMS theme, or pick one")
        kdlKey: "focus-ring.active-color"
    }

    NiriRow {
        settingKey: "look.borderOn"
        title: I18n.tr("Window border")
        icon: "border_outer"
        tip: I18n.tr("Drawn inside every window, takes space")
        kdlKey: "layout.border"
    }

    NiriSlider {
        settingKey: "look.borderWidth"
        dependsOn: "look.borderOn"
        title: I18n.tr("Border width")
        icon: "line_weight"
        tip: I18n.tr("One width for the ring and the border")
        kdlKey: "border.width"
        from: Look.limits["look.borderWidth"].from
        to: Look.limits["look.borderWidth"].to
        unit: " px"
        numValue: value < 0 ? 2 : Number(value)

        function format(v) {
            return (value < 0 ? 2 : v) + unit;
        }
    }

    NiriSwatches {
        settingKey: "look.borderColor"
        dependsOn: "look.borderOn"
        title: I18n.tr("Border color")
        icon: "palette"
        kdlKey: "border.active-color"
    }

    LookRadiusRow {
        title: I18n.tr("Override window radius", "toggle: stop the window radius following the corner style setting")
        icon: "rounded_corner"
        tip: I18n.tr("Applied with a DMS window rule")
        kdlKey: "window-rule.geometry-corner-radius"
    }

    NiriSlider {
        settingKey: "look.radius"
        dependsOn: "look.radius"
        visible: value >= 0
        title: I18n.tr("Corner radius")
        kdlKey: "window-rule.geometry-corner-radius"
        from: Look.limits["look.radius"].from
        to: Look.limits["look.radius"].to
        stepSize: 2
        unit: " px"
    }

    NiriRow {
        settingKey: "look.shadowOn"
        title: I18n.tr("Window shadows")
        icon: "shadow"
        kdlKey: "layout.shadow"
    }

    NiriRow {
        settingKey: "look.blurOn"
        title: I18n.tr("Blur")
        icon: "blur_on"
        tip: I18n.tr("niri 26.04, behind see-through windows")
        kdlKey: "window-rule.background-effect"
    }

    NiriSlider {
        settingKey: "look.blurStrength"
        dependsOn: "look.blurOn"
        title: I18n.tr("Blur strength")
        icon: "blur_medium"
        tip: I18n.tr("Shared with the DMS background blur")
        kdlKey: "blur.offset"
        from: 16
        to: 160
        stepSize: 4
        unit: " px"

        function format(v) {
            return value > 0 ? v + unit : I18n.tr("Auto");
        }
    }

    NiriRow {
        visible: expert
        settingKey: "look.xray"
        title: I18n.tr("Xray blur")
        icon: "layers"
        tip: I18n.tr("Blurred surfaces show the wallpaper, not the windows beneath")
        kdlKey: "background-effect.xray"
    }

    NiriRow {
        visible: expert && !SettingsData.connectedFrameModeActive
        settingKey: "look.barXray"
        icon: "toolbar"
        title: SettingsData.frameEnabled ? I18n.tr("Frame xray") : I18n.tr("Bar xray")
        tip: I18n.tr("Blur against the wallpaper even with xray off")
        kdlKey: "layer-rule.background-effect.xray"
    }
}
