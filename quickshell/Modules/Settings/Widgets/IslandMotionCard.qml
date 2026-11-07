import QtQuick
import qs.Common

SettingsCard {
    id: root

    required property var store
    property string keyPrefix: "island"

    iconName: "animation"
    title: I18n.tr("Motion", "island settings: spring motion card title")
    settingKey: root.keyPrefix + "Motion"
    tags: ["island", "motion", "spring", "animation"]

    SettingsSliderRow {
        settingKey: root.keyPrefix + "SpringStiffness"
        tags: ["island", "motion", "spring", "stiffness", "animation"]
        resetStore: root.store
        resetKeys: ["islandSpringStiffness"]
        text: I18n.tr("Spring stiffness", "island settings: spring stiffness slider")
        unit: ""
        minimum: 100
        maximum: 1200
        step: 10
        value: Math.round(root.store.setting("islandSpringStiffness"))
        enabled: !SettingsData.reduceMotion
        onSliderDragFinished: finalValue => root.store.apply("islandSpringStiffness", finalValue)
    }

    SettingsSliderRow {
        settingKey: root.keyPrefix + "SpringDamping"
        tags: ["island", "motion", "spring", "damping", "bounce", "animation"]
        resetStore: root.store
        resetKeys: ["islandSpringDamping"]
        text: I18n.tr("Spring damping", "island settings: spring damping slider")
        unit: ""
        minimum: 10
        maximum: 100
        step: 1
        value: Math.round(root.store.setting("islandSpringDamping"))
        enabled: !SettingsData.reduceMotion
        onSliderDragFinished: finalValue => root.store.apply("islandSpringDamping", finalValue)
    }

    SettingsSliderRow {
        settingKey: root.keyPrefix + "SpringMass"
        tags: ["island", "motion", "spring", "mass", "inertia", "animation"]
        resetStore: root.store
        resetKeys: ["islandSpringMass"]
        text: I18n.tr("Spring mass", "island settings: spring mass slider")
        minimum: 25
        maximum: 300
        step: 5
        unit: ""
        decimals: 2
        value: Math.round(root.store.setting("islandSpringMass") * 100)
        enabled: !SettingsData.reduceMotion
        onSliderDragFinished: finalValue => root.store.apply("islandSpringMass", finalValue / 100)
    }
}
