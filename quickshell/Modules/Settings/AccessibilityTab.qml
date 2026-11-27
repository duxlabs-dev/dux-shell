import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Item {
    SettingsPage {
        SettingsDeferred {
            SettingsCard {
                tab: "accessibility"
                tags: ["accessibility", "a11y", "motion", "density", "scrollbars", "switch", "toggle"]
                settingKey: "accessibility"
                iconName: "accessibility_new"

                SettingsToggleRow {
                    tab: "accessibility"
                    tags: ["animation", "spring", "physics", "accessibility", "reduce", "motion"]
                    settingKey: "reduceMotion"
                    enabled: !Theme.motionOff
                    text: I18n.tr("Reduce motion")
                    description: Theme.motionOff ? I18n.tr("Enabled automatically while Motion duration is Off", "reduce motion setting description when motion duration is off") : ""
                    checked: Theme.reduceMotion
                    onToggled: checked => SettingsData.set("reduceMotion", checked)
                }

                SettingsButtonGroupRow {
                    tab: "accessibility"
                    tags: ["density", "compact", "dense", "spacious", "comfortable", "spacing", "padding", "rows", "menus", "control center", "bar", "dock", "island", "frame", "size"]
                    settingKey: "density"
                    text: I18n.tr("Interface density", "interface density setting label")
                    model: [I18n.tr("Spacious", "interface density option with the most room between items"), I18n.tr("Comfortable", "interface density option with the default spacing"), I18n.tr("Compact", "interface density option fitting the most items on screen"), I18n.tr("Dense", "interface density option denser than compact for small text and tight rows")]
                    values: ["spacious", "comfortable", "compact", "dense"]
                    value: SettingsData.density
                    fallbackValue: "comfortable"
                    onValueSelected: value => SettingsData.set("density", value)
                }

                SettingsToggleRow {
                    tab: "accessibility"
                    tags: ["scroll", "scrollbar", "scrollbars", "list", "page", "hide"]
                    settingKey: "scrollbarsEnabled"
                    text: I18n.tr("Scrollbars", "theme settings toggle, show scrollbars on lists and pages")
                    checked: SettingsData.scrollbarsEnabled
                    onToggled: checked => SettingsData.set("scrollbarsEnabled", checked)
                }

                SettingsToggleRow {
                    tab: "accessibility"
                    tags: ["switch", "toggle", "indicator", "icon", "check", "checkmark", "on", "off", "state"]
                    settingKey: "switchStateIcons"
                    text: I18n.tr("Show on/off indicators", "accessibility toggle, marks switches in both states instead of only when on")
                    description: I18n.tr("Off switches show an X, on switches keep their check", "on/off indicators setting description")
                    checked: SettingsData.switchStateIcons
                    onToggled: checked => SettingsData.set("switchStateIcons", checked)
                }
            }
        }
    }
}
