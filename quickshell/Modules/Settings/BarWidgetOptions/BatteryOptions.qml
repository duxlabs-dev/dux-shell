import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    readonly property var styleValues: ["icon", "solid", "outline", "ring", "duo"]
    readonly property var barConfig: {
        SettingsData.barConfigs;
        return SettingsData.getBarConfig(page?.barId ?? "");
    }
    readonly property var barStore: ({
            "isDefault": keys => keys.every(key => (root.barConfig?.[key] ?? SettingsData.barConfigDefault(key)) === SettingsData.barConfigDefault(key)),
            "resetToDefault": keys => {
                // QV4 has no Object.fromEntries.
                const patch = {};
                for (const key of keys)
                    patch[key] = SettingsData.barConfigDefault(key);
                SettingsData.updateBarConfig(root.page.barId, patch);
            }
        })

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        settingKey: "barWidgetBattery"

        SettingsToggleRow {
            text: I18n.tr("Show percentage")
            checked: root.page.value("showBatteryPercent")
            onToggled: checked => root.page.set("showBatteryPercent", checked)
        }

        SettingsToggleRow {
            enabled: root.page.value("showBatteryPercent")
            text: I18n.tr("Only on battery")
            checked: root.page.value("showBatteryPercentOnlyOnBattery")
            onToggled: checked => root.page.set("showBatteryPercentOnlyOnBattery", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Show remaining time")
            checked: root.page.value("showBatteryTime")
            onToggled: checked => root.page.set("showBatteryTime", checked)
        }

        SettingsToggleRow {
            enabled: root.page.value("showBatteryTime")
            text: I18n.tr("Only on battery")
            checked: root.page.value("showBatteryTimeOnlyOnBattery")
            onToggled: checked => root.page.set("showBatteryTimeOnlyOnBattery", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Show charge rate", "Battery bar widget setting: show how many watts are going into the battery while charging")
            checked: root.page.value("showBatteryPowerCharging")
            onToggled: checked => root.page.set("showBatteryPowerCharging", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Show discharge rate", "Battery bar widget setting: show how many watts the system is drawing from the battery")
            checked: root.page.value("showBatteryPowerDischarging")
            onToggled: checked => root.page.set("showBatteryPowerDischarging", checked)
        }

        SettingsButtonGroupRow {
            resetStore: root.page
            resetKeys: ["batteryStyle"]
            text: I18n.tr("Battery style")
            model: [I18n.tr("Icon", "battery widget: system battery glyph"), I18n.tr("Solid", "island settings: filled battery meter style"), I18n.tr("Outline", "island settings: outlined battery meter style"), I18n.tr("Circle", "island settings: circular battery meter style"), I18n.tr("Duo", "battery meter style: open battery arc around the network glyph")]
            currentIndex: Math.max(0, root.styleValues.indexOf(root.page.value("batteryStyle")))
            onSelectionChanged: (index, selected) => {
                if (selected)
                    root.page.set("batteryStyle", root.styleValues[index]);
            }
        }

        SettingsButtonGroupRow {
            settingKey: "batteryColorMode"
            tags: ["battery", "color", "level", "theme", "icon", "meter", "indicator", "accent", "green", "red"]
            text: I18n.tr("Battery")
            visible: BatteryService.batteryAvailable && !(root.page?.dockHosted ?? false)
            resetStore: root.barStore
            resetKeys: ["batteryColorMode"]
            model: [I18n.tr("Theme", "battery settings: theme accent indicator colors"), I18n.tr("Level", "battery settings: charge level indicator colors")]
            currentIndex: (root.barConfig?.batteryColorMode ?? "theme") === "level" ? 1 : 0
            onSelectionChanged: (index, selected) => {
                if (!selected)
                    return;
                SettingsData.updateBarConfig(root.page.barId, {
                    batteryColorMode: index === 1 ? "level" : "theme"
                });
            }
        }
    }
}
