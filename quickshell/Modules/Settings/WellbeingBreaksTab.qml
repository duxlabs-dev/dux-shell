pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import "../DDash/Wellbeing/Wellbeing.js" as Wellbeing

Item {
    id: root

    property var parentModal: null

    readonly property bool breaksEnabled: SettingsData.wellbeingBreaksEnabled
    readonly property var planLabels: [I18n.tr("Light", "break plan option, short and frequent breaks", true), I18n.tr("Balanced"), I18n.tr("Focused", "break plan option, long stretches of work between breaks", true)]
    readonly property string plan: Wellbeing.matchingBreakPlan({
        "interval": SettingsData.wellbeingBreakInterval,
        "duration": SettingsData.wellbeingBreakDuration,
        "beforeLong": SettingsData.wellbeingBreaksBeforeLong,
        "longDuration": SettingsData.wellbeingLongBreakDuration,
        "warning": SettingsData.wellbeingBreakWarning
    })

    function applyPlan(plan) {
        SettingsData.set("wellbeingBreakInterval", plan.interval);
        SettingsData.set("wellbeingBreakDuration", plan.duration);
        SettingsData.set("wellbeingBreaksBeforeLong", plan.beforeLong);
        SettingsData.set("wellbeingLongBreakDuration", plan.longDuration);
        SettingsData.set("wellbeingBreakWarning", plan.warning);
    }

    SettingsPage {
        SettingsDeferred {
            SettingsCard {
                iconName: "timer"
                settingKey: "wellbeingBreakPlans"
                tab: "wellbeing_breaks"
                tags: ["wellbeing", "break", "plan", "preset"]

                SettingsToggleRow {
                    tab: "wellbeing_breaks"
                    tags: ["wellbeing", "break", "reminder", "rest", "eyes"]
                    settingKey: "wellbeingBreaksEnabled"
                    text: I18n.tr("Break reminders", "settings page title and main toggle, reminders to rest from the screen")
                    checked: root.breaksEnabled
                    onToggled: checked => SettingsData.set("wellbeingBreaksEnabled", checked)
                }

                SettingsButtonGroupRow {
                    tab: "wellbeing_breaks"
                    tags: ["wellbeing", "break", "plan", "preset", "light", "balanced", "focused"]
                    settingKey: "wellbeingBreakPlan"
                    enabled: root.breaksEnabled
                    text: I18n.tr("Break plan", "break reminder setting, a preset for the break schedule")
                    description: root.plan === "" ? I18n.tr("Custom") : ""
                    model: root.planLabels
                    currentIndex: Wellbeing.breakPlans.findIndex(plan => plan.id === root.plan)
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        root.applyPlan(Wellbeing.breakPlans[index]);
                    }
                }
            }
        }

        SettingsDeferred {
            SettingsCard {
                iconName: "schedule"
                title: I18n.tr("Break schedule", "settings card title, timing of break reminders")
                settingKey: "wellbeingBreakSchedule"
                tab: "wellbeing_breaks"
                tags: ["wellbeing", "break", "schedule", "interval", "duration"]

                SettingsSliderRow {
                    tab: "wellbeing_breaks"
                    tags: ["wellbeing", "break", "short", "interval", "every"]
                    settingKey: "wellbeingBreakInterval"
                    enabled: root.breaksEnabled
                    text: I18n.tr("Short break interval", "break reminder setting, time between breaks")
                    value: SettingsData.wellbeingBreakInterval
                    minimum: 5
                    maximum: 60
                    step: 5
                    unit: "min"
                    onSliderValueChanged: newValue => SettingsData.set("wellbeingBreakInterval", newValue)
                }

                SettingsSliderRow {
                    tab: "wellbeing_breaks"
                    tags: ["wellbeing", "break", "short", "duration", "length"]
                    settingKey: "wellbeingBreakDuration"
                    enabled: root.breaksEnabled
                    text: I18n.tr("Short break duration", "break reminder setting")
                    value: SettingsData.wellbeingBreakDuration
                    minimum: 5
                    maximum: 120
                    step: 5
                    unit: "s"
                    onSliderValueChanged: newValue => SettingsData.set("wellbeingBreakDuration", newValue)
                }

                SettingsSliderRow {
                    tab: "wellbeing_breaks"
                    tags: ["wellbeing", "break", "short", "long", "count", "cycle"]
                    settingKey: "wellbeingBreaksBeforeLong"
                    enabled: root.breaksEnabled
                    text: I18n.tr("Short breaks before long break", "break reminder setting, a number of breaks")
                    value: SettingsData.wellbeingBreaksBeforeLong
                    minimum: 1
                    maximum: 10
                    unit: ""
                    onSliderValueChanged: newValue => SettingsData.set("wellbeingBreaksBeforeLong", newValue)
                }

                SettingsSliderRow {
                    tab: "wellbeing_breaks"
                    tags: ["wellbeing", "break", "long", "duration", "length"]
                    settingKey: "wellbeingLongBreakDuration"
                    enabled: root.breaksEnabled
                    text: I18n.tr("Long break duration", "break reminder setting")
                    value: SettingsData.wellbeingLongBreakDuration
                    minimum: 1
                    maximum: 30
                    unit: "min"
                    onSliderValueChanged: newValue => SettingsData.set("wellbeingLongBreakDuration", newValue)
                }

                SettingsSliderRow {
                    tab: "wellbeing_breaks"
                    tags: ["wellbeing", "break", "warning", "heads-up", "notice", "before"]
                    settingKey: "wellbeingBreakWarning"
                    enabled: root.breaksEnabled
                    text: I18n.tr("Pre-break warning", "break reminder setting, a heads-up shown shortly before a break")
                    description: I18n.tr("How long before a break the heads-up appears", "pre-break warning setting description")
                    minimumLabel: I18n.tr("Off")
                    value: SettingsData.wellbeingBreakWarning
                    minimum: 0
                    maximum: 15
                    unit: "s"
                    onSliderValueChanged: newValue => SettingsData.set("wellbeingBreakWarning", newValue)
                }
            }
        }
    }
}
