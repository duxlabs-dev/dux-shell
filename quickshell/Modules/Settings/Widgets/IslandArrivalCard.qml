pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import "../../../Common/IslandArrival.js" as Arrival

// Shared by every island: how an info arriving in the island grows, bounces and takes colour.
SettingsCard {
    id: root

    property string keyPrefix: "island"
    property bool shown: true

    readonly property var bounceLabels: [I18n.tr("None", "island settings: arrival bounce option"), I18n.tr("Light", "island settings: arrival bounce option"), I18n.tr("Medium", "island settings: arrival bounce option"), I18n.tr("Strong", "island settings: arrival bounce option")]
    readonly property var tintLabels: [I18n.tr("None", "island settings: arrival tint option"), I18n.tr("Light", "island settings: arrival tint option"), I18n.tr("Normal", "island settings: arrival tint option"), I18n.tr("Strong", "island settings: arrival tint option")]
    readonly property var tierLabels: [I18n.tr("Brief info", "island settings: arrival tier, a 2 s info such as caps lock"), I18n.tr("Notification", "island settings: arrival tier, notifications and glances"), I18n.tr("Important", "island settings: arrival tier, a call or a critical alert")]

    function setTier(key, tier, name) {
        const list = (SettingsData[key] ?? []).slice();
        const defaults = key === "islandArrivalBounce" ? Arrival.defaultBounce : Arrival.defaultTint;
        for (let i = 0; i < defaults.length; i++)
            list[i] = list[i] ?? defaults[i];
        list[tier] = name;
        SettingsData.set(key, list);
    }

    iconName: "animation"
    title: I18n.tr("Arrival of info", "island settings: arrival card title")
    settingKey: root.keyPrefix + "Arrival"
    tags: ["island", "arrival", "notification", "animation", "bounce", "tint", "burst", "countdown"]
    visible: root.shown

    SettingsDropdownRow {
        readonly property var styleValues: Arrival.styles

        settingKey: root.keyPrefix + "ArrivalStyle"
        tags: ["island", "arrival", "notification", "animation", "style"]
        text: I18n.tr("Arrival of info", "island settings: how the island grows when an info arrives")
        description: I18n.tr("Step and bounce opens a card with more detail, then folds to compact", "island settings: arrival style description")
        options: [I18n.tr("Step and bounce", "island settings: arrival style option, a detailed card that bounces and takes colour"), I18n.tr("Bounce", "island settings: arrival style option, the island bounces and takes colour"), I18n.tr("Breath", "island settings: arrival style option, one quiet breath, no bounce, no colour")]
        currentValue: options[Math.max(0, styleValues.indexOf(SettingsData.islandArrivalStyle))]
        onValueChanged: value => SettingsData.set("islandArrivalStyle", styleValues[options.indexOf(value)] ?? "bc")
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "ArrivalWheel"
        tags: ["island", "arrival", "wheel", "scroll", "touchpad", "burst"]
        text: I18n.tr("Scroll through infos", "island settings: the wheel turns the pages of the infos open in the island")
        description: I18n.tr("The wheel or touchpad over the open island goes from one info to the next", "island settings: arrival wheel description")
        checked: SettingsData.islandArrivalWheel
        onToggled: checked => SettingsData.set("islandArrivalWheel", checked)
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "ArrivalWheelDirection"
        tags: ["island", "arrival", "wheel", "scroll", "direction", "natural", "inverted"]
        visible: SettingsData.islandArrivalWheel
        text: I18n.tr("Reverse scroll direction", "island settings: the wheel turns the pages of the infos the other way")
        checked: SettingsData.islandArrivalWheelInverted
        onToggled: checked => SettingsData.set("islandArrivalWheelInverted", checked)
    }

    component TierRow: SettingsDropdownRow {
        id: row

        required property int tier
        // "islandArrivalBounce" or "islandArrivalTint"
        required property string key
        readonly property bool bounce: row.key === "islandArrivalBounce"
        readonly property var names: row.bounce ? Arrival.bounceNames : Arrival.tintNames
        readonly property var defaults: row.bounce ? Arrival.defaultBounce : Arrival.defaultTint

        settingKey: root.keyPrefix + (row.bounce ? "ArrivalBounce" : "ArrivalTint") + row.tier
        // A tier's name is one long word: wrapped beside a narrow window's dropdown, it would run under the dropdown.
        singleLineTitle: true
        tags: ["island", "arrival", row.bounce ? "bounce" : "tint", row.bounce ? "spring" : "color"]
        visible: SettingsData.islandArrivalStyle !== "a"
        text: (row.bounce ? I18n.tr("Bounce: %1", "island settings: arrival bounce for one tier") : I18n.tr("Tint: %1", "island settings: arrival tint for one tier")).arg(root.tierLabels[row.tier])
        options: row.bounce ? root.bounceLabels : root.tintLabels
        currentValue: options[Math.max(0, row.names.indexOf((SettingsData[row.key] ?? [])[row.tier] ?? row.defaults[row.tier]))]
        onValueChanged: value => root.setTier(row.key, row.tier, row.names[options.indexOf(value)] ?? row.defaults[row.tier])
    }

    TierRow {
        key: "islandArrivalBounce"
        tier: 0
    }
    TierRow {
        key: "islandArrivalBounce"
        tier: 1
    }
    TierRow {
        key: "islandArrivalBounce"
        tier: 2
    }
    TierRow {
        key: "islandArrivalTint"
        tier: 0
    }
    TierRow {
        key: "islandArrivalTint"
        tier: 1
    }
    TierRow {
        key: "islandArrivalTint"
        tier: 2
    }
}
