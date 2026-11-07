pragma ComponentBehavior: Bound

import QtQuick
import qs.Common

// Shared by every island; bubble motion follows the shell's reduce-motion setting.
SettingsCard {
    id: root

    property string keyPrefix: "island"

    iconName: "bubble_chart"
    title: I18n.tr("Bubbles", "island settings: bubbles card title")
    settingKey: root.keyPrefix + "Bubbles"
    tags: ["island", "bubbles", "bubble", "volume", "brightness", "osd", "notification"]

    SettingsToggleRow {
        settingKey: root.keyPrefix + "LevelBubbles"
        tags: ["island", "bubbles", "volume", "brightness", "microphone", "osd"]
        text: I18n.tr("Always show levels in a bubble", "island settings: volume, brightness and mic changes go beside the island")
        description: I18n.tr("Volume, brightness and microphone changes appear beside the island instead of inside it", "island settings: level bubbles description")
        checked: SettingsData.islandLevelBubbles
        onToggled: checked => SettingsData.set("islandLevelBubbles", checked)
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "BriefBubbles"
        tags: ["island", "bubbles", "brief", "caps", "lock", "power", "profile", "idle", "inhibitor"]
        text: I18n.tr("Always show brief info in a bubble", "island settings: caps lock, power profile and idle inhibitor changes go beside the island")
        description: I18n.tr("Caps lock, power profile and idle inhibitor changes appear beside the island instead of inside it", "island settings: brief info bubbles description")
        checked: SettingsData.islandBriefBubbles
        onToggled: checked => SettingsData.set("islandBriefBubbles", checked)
    }

    SettingsSliderRow {
        settingKey: root.keyPrefix + "BubbleMotion"
        tags: ["island", "bubbles", "motion", "animation", "intensity", "bounce", "expressive"]
        text: I18n.tr("Motion intensity", "island settings: how much the bubbles lean, stretch and bounce")
        description: I18n.tr("How much the bubbles lean, stretch and bounce as they move", "island settings: bubble motion intensity description")
        unit: "%"
        minimum: 0
        maximum: 150
        step: 10
        value: SettingsData.islandBubbleMotion
        onSliderValueChanged: value => SettingsData.set("islandBubbleMotion", value)
    }

    SettingsDropdownRow {
        readonly property var dialValues: ["wave", "lean"]

        settingKey: root.keyPrefix + "BubbleDialStyle"
        tags: ["island", "bubbles", "volume", "level", "animation", "wave", "lean"]
        text: I18n.tr("Level animation", "island settings: how a bubble moves while a level such as the volume is being set")
        options: [I18n.tr("Wave", "island settings: level animation option, the bubble fills like a liquid"), I18n.tr("Lean", "island settings: level animation option, the bubble tips and stretches")]
        currentValue: options[Math.max(0, dialValues.indexOf(SettingsData.islandBubbleDialStyle))]
        onValueChanged: value => SettingsData.set("islandBubbleDialStyle", dialValues[options.indexOf(value)] ?? "wave")
    }

    SettingsDropdownRow {
        readonly property var hopValues: ["jelly", "liquid", "pivot"]

        settingKey: root.keyPrefix + "BubbleLauncherTransition"
        tags: ["island", "bubbles", "launcher", "transition", "animation", "jelly", "liquid", "pivot"]
        text: I18n.tr("Launcher transition", "island settings: how every bubble moves beside the open launcher")
        options: [I18n.tr("Jelly", "island settings: launcher transition option, the bubble wobbles as it moves"), I18n.tr("Liquid", "island settings: launcher transition option, the bubble splits at its icon, a thread snaps, a bridge merges the parts again"), I18n.tr("Pivot", "island settings: launcher transition option, the bubble turns a quarter round its icon")]
        currentValue: options[Math.max(0, hopValues.indexOf(SettingsData.islandBubbleLauncherTransition))]
        onValueChanged: value => SettingsData.set("islandBubbleLauncherTransition", hopValues[options.indexOf(value)] ?? "liquid")
    }

    SettingsDropdownRow {
        readonly property var cornerValues: ["island", "round"]

        settingKey: root.keyPrefix + "BubbleCorners"
        tags: ["island", "bubbles", "corners", "radius", "notch", "pill", "shape"]
        text: I18n.tr("Bubble corners", "island settings: the corner shape of the bubbles beside the island")
        description: I18n.tr("Like the island follows its style, Notch included", "island settings: bubble corners description")
        options: [I18n.tr("Like the island", "island settings: bubble corners option, the island's radius and edge"), I18n.tr("Round", "island settings: bubble corners option, round pills")]
        currentValue: options[Math.max(0, cornerValues.indexOf(SettingsData.islandBubbleCorners))]
        onValueChanged: value => SettingsData.set("islandBubbleCorners", cornerValues[options.indexOf(value)] ?? "island")
    }

    SettingsDropdownRow {
        readonly property var styleValues: ["flat", "tonal"]

        settingKey: root.keyPrefix + "BubbleShapeStyle"
        tags: ["island", "bubbles", "shape", "style", "color", "tonal"]
        text: I18n.tr("Shape style", "island settings: how the shape behind a bubble's icon is colored")
        options: [I18n.tr("Filled", "island settings: shape style option, the shape filled with the app type's color"), I18n.tr("Tone on tone", "island settings: shape style option, a shape a shade off the bubble, only the icon in color")]
        currentValue: options[Math.max(0, styleValues.indexOf(SettingsData.islandBubbleShapeStyle))]
        onValueChanged: value => SettingsData.set("islandBubbleShapeStyle", styleValues[options.indexOf(value)] ?? "flat")
    }

    SettingsDropdownRow {
        readonly property var toneValues: ["theme"].concat(Theme.availableMatugenSchemes.map(s => s.value))

        settingKey: root.keyPrefix + "BubbleShapeTone"
        tags: ["island", "bubbles", "shape", "tone", "color", "scheme", "matugen"]
        text: I18n.tr("Shape tone", "island settings: which color scheme the bubble shapes take their colors from")
        description: I18n.tr("Colors per app type from a color scheme of your wallpaper", "island settings: shape tone description")
        options: [I18n.tr("As the theme", "island settings: shape tone option, the theme's own colors")].concat(Theme.availableMatugenSchemes.map(s => s.label))
        currentValue: options[Math.max(0, toneValues.indexOf(SettingsData.islandBubbleShapeTone))]
        onValueChanged: value => SettingsData.set("islandBubbleShapeTone", toneValues[options.indexOf(value)] ?? "theme")
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "BubbleOutline"
        tags: ["island", "bubbles", "outline", "border", "stroke", "color"]
        text: I18n.tr("Outline the bubbles", "island settings: draw a colored line around the bubbles")
        description: I18n.tr("A thin line around the bubbles beside the island", "island settings: bubble outline description")
        checked: SettingsData.islandBubbleOutline
        onToggled: checked => SettingsData.set("islandBubbleOutline", checked)
    }

    SettingsSliderRow {
        settingKey: root.keyPrefix + "BubbleOutlineWidth"
        tags: ["island", "bubbles", "outline", "border", "width", "thickness"]
        text: I18n.tr("Outline width", "island settings: bubble outline thickness slider")
        unit: "px"
        minimum: 1
        maximum: 4
        step: 1
        value: SettingsData.islandBubbleOutlineWidth
        visible: SettingsData.islandBubbleOutline
        onSliderValueChanged: value => SettingsData.set("islandBubbleOutlineWidth", value)
    }

    SettingsSliderRow {
        settingKey: root.keyPrefix + "BubbleOutlineOpacity"
        tags: ["island", "bubbles", "outline", "border", "opacity", "transparency"]
        text: I18n.tr("Outline opacity", "island settings: bubble outline opacity slider")
        unit: "%"
        minimum: 10
        maximum: 100
        step: 5
        value: SettingsData.islandBubbleOutlineOpacity
        visible: SettingsData.islandBubbleOutline
        onSliderValueChanged: value => SettingsData.set("islandBubbleOutlineOpacity", value)
    }

    SettingsDropdownRow {
        readonly property var colorValues: ["type", "accent"]

        settingKey: root.keyPrefix + "BubbleOutlineColor"
        tags: ["island", "bubbles", "outline", "border", "color", "accent"]
        text: I18n.tr("Outline color", "island settings: bubble outline color dropdown")
        options: [I18n.tr("Color of the app type", "island settings: bubble outline color option, the tone of messages, system, media or alerts"), I18n.tr("Theme accent", "island settings: bubble outline color option, the theme's accent")]
        currentValue: options[Math.max(0, colorValues.indexOf(SettingsData.islandBubbleOutlineColor))]
        visible: SettingsData.islandBubbleOutline
        onValueChanged: value => SettingsData.set("islandBubbleOutlineColor", colorValues[options.indexOf(value)] ?? "type")
    }
}
