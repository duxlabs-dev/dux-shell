pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import "../../../Common/IslandActivities.js" as IslandActivities

SettingsCard {
    id: root

    required property var store
    property string keyPrefix: "island"

    readonly property string iconMotion: root.store.setting("islandActivityIconMotion")
    // "" keeps the island's own surface; the dropdown needs a non-empty key for it.
    readonly property var surfaceRoleValues: IslandActivities.SURFACE_ROLES.map(role => role || "default")
    readonly property var surfaceRoleLabels: ({
            "default": I18n.tr("Default"),
            "hostSurface": I18n.tr("Host"),
            "cardSurface": I18n.tr("Cards"),
            "chipSurface": I18n.tr("Chip", "surface role"),
            "chipSurfaceNested": I18n.tr("Nested chip", "surface role"),
            "primaryContainer": I18n.tr("Primary Container", "workspace color option"),
            "secondaryContainer": I18n.tr("Secondary Container", "workspace color option"),
            "tertiaryContainer": I18n.tr("Tertiary Container", "workspace color option")
        })
    readonly property var surfaceRoleColors: ({
            "hostSurface": Theme.hostSurface,
            "cardSurface": Theme.cardSurface,
            "chipSurface": Theme.chipSurface,
            "chipSurfaceNested": Theme.chipSurfaceNested,
            "primaryContainer": Theme.primaryContainer,
            "secondaryContainer": Theme.secondaryContainer,
            "tertiaryContainer": Theme.tertiaryContainer
        })

    iconName: "palette"
    title: I18n.tr("Appearance", "island settings: shape, colour and opacity card title")
    settingKey: root.keyPrefix + "ActivityAppearance"
    tags: ["island", "appearance", "color", "colour", "opacity", "shape", "pill"]

    SettingsToggleRow {
        settingKey: root.keyPrefix + "PillShape"
        tags: ["island", "pill", "shape", "rounded"]
        visible: !SettingsData.isDotBarConfig(root.store.config)
        resetStore: root.store
        resetKeys: ["islandPillShape"]
        text: I18n.tr("Pill shape", "island activity settings")
        description: I18n.tr("Use fully rounded ends for the collapsed island", "island activity settings")
        checked: root.store.setting("islandPillShape")
        onToggled: checked => root.store.apply("islandPillShape", checked)
    }

    SettingsDropdownRow {
        settingKey: root.keyPrefix + "CompactColor"
        tags: ["island", "color", "colour", "background", "collapsed", "compact"]
        resetStore: root.store
        resetKeys: ["islandCompactColor"]
        text: I18n.tr("Collapsed background", "island activity settings")
        description: I18n.tr("Theme colour behind the collapsed island", "island activity settings")
        optionValues: root.surfaceRoleValues
        options: root.surfaceRoleValues.map(role => root.surfaceRoleLabels[role])
        optionColorMap: root.surfaceRoleColors
        currentValue: IslandActivities.surfaceRole(root.store.setting("islandCompactColor")) || "default"
        onValueChanged: value => root.store.apply("islandCompactColor", value === "default" ? "" : value)
    }

    SettingsDropdownRow {
        settingKey: root.keyPrefix + "ExpandedColor"
        tags: ["island", "color", "colour", "background", "expanded"]
        resetStore: root.store
        resetKeys: ["islandExpandedColor"]
        text: I18n.tr("Expanded background", "island activity settings")
        description: I18n.tr("Theme colour behind the expanded island", "island activity settings")
        optionValues: root.surfaceRoleValues
        options: root.surfaceRoleValues.map(role => root.surfaceRoleLabels[role])
        optionColorMap: root.surfaceRoleColors
        currentValue: IslandActivities.surfaceRole(root.store.setting("islandExpandedColor")) || "default"
        onValueChanged: value => root.store.apply("islandExpandedColor", value === "default" ? "" : value)
    }

    SettingsToggleSliderRow {
        settingKey: root.keyPrefix + "ExpandedOpacity"
        tags: ["island", "opacity", "transparency", "expanded"]
        resetStore: root.store
        accessoryKeys: ["islandExpandedOpacity"]
        valueKeys: ["islandExpandedOpacity"]
        text: I18n.tr("Expanded opacity", "island activity settings: custom opacity for the expanded island")
        description: I18n.tr("Off matches the bar's opacity", "island activity settings: expanded opacity toggle description")
        checked: root.store.setting("islandExpandedOpacity") >= 0
        minimum: 0
        maximum: 100
        step: 5
        unit: "%"
        value: Math.round(Math.max(0, root.store.setting("islandExpandedOpacity")) * 100)
        onToggled: checked => root.store.apply("islandExpandedOpacity", checked ? 1 : -1)
        onSliderValueChanged: value => root.store.apply("islandExpandedOpacity", value / 100)
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "ActivityColors"
        tags: ["island", "activities", "color", "colour", "error", "warning"]
        resetStore: root.store
        resetKeys: ["islandActivityColors"]
        text: I18n.tr("Activity colors", "island activity settings")
        description: I18n.tr("Let activities tint their slot and highlight warnings and errors", "island activity settings")
        checked: root.store.setting("islandActivityColors")
        onToggled: checked => root.store.apply("islandActivityColors", checked)
    }

    SettingsDropdownRow {
        settingKey: root.keyPrefix + "ActivityIconMotion"
        tags: ["island", "activities", "icon", "animation", "motion", "wiggle", "pulse", "spin"]
        resetStore: root.store
        resetKeys: ["islandActivityIconMotion", "islandActivityIconMotionDuration", "islandActivityIconMotionIntensity"]
        text: I18n.tr("Activity icon animation", "island activity settings")
        description: I18n.tr("Moves an activity's icon to draw attention to it", "island activity settings: icon animation description")
        optionValues: ["activity", "none", "wiggle", "pulse", "spin"]
        options: [I18n.tr("Set by activity", "island activity settings"), I18n.tr("None", "island activity settings"), I18n.tr("Wiggle", "island activity settings"), I18n.tr("Pulse", "island activity settings"), I18n.tr("Spin", "island activity settings")]
        currentValue: root.iconMotion
        onValueChanged: value => root.store.apply("islandActivityIconMotion", value)
    }

    SettingsSliderRow {
        settingKey: root.keyPrefix + "ActivityIconMotionDuration"
        tags: ["island", "activities", "icon", "animation", "speed"]
        visible: root.iconMotion !== "none"
        resetStore: root.store
        resetKeys: ["islandActivityIconMotionDuration"]
        text: I18n.tr("Icon animation speed", "island activity settings")
        description: I18n.tr("Length of one animation cycle", "island activity settings: icon animation speed description")
        minimum: 250
        maximum: 1500
        step: 50
        unit: "ms"
        value: root.store.setting("islandActivityIconMotionDuration")
        onSliderValueChanged: value => root.store.apply("islandActivityIconMotionDuration", value)
    }

    // Spin always turns a full circle, so only wiggle and pulse have a strength.
    SettingsSliderRow {
        settingKey: root.keyPrefix + "ActivityIconMotionIntensity"
        tags: ["island", "activities", "icon", "animation", "intensity"]
        visible: root.iconMotion !== "none" && root.iconMotion !== "spin"
        resetStore: root.store
        resetKeys: ["islandActivityIconMotionIntensity"]
        text: I18n.tr("Icon animation intensity", "island activity settings")
        description: I18n.tr("How far a wiggle tilts or a pulse grows", "island activity settings: icon animation intensity description")
        minimum: 10
        maximum: 100
        step: 5
        unit: "%"
        value: root.store.setting("islandActivityIconMotionIntensity")
        onSliderValueChanged: value => root.store.apply("islandActivityIconMotionIntensity", value)
    }
}
