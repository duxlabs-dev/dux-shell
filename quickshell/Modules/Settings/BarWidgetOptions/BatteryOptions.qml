import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import "../../../Common/settings/SettingsSpec.js" as Spec

Column {
    id: root

    property var page: null

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

    Component.onCompleted: BatteryService.addRef()
    Component.onDestruction: BatteryService.removeRef()

    readonly property var layoutLabels: [I18n.tr("Grid", "battery settings: popout section layout option"), I18n.tr("Compact", "battery settings: popout section layout option, tighter than grid"), I18n.tr("Chips", "battery popout layout: small chips with icon and value"), I18n.tr("List", "battery settings: popout section layout option")]
    readonly property var deviceLayoutLabels: layoutLabels.concat([I18n.tr("Bars", "battery popout devices layout: rows filled to the battery level")])
    readonly property var detailLabels: [I18n.tr("Health", "noun, battery health percentage label"), I18n.tr("Temperature", "battery temperature"), I18n.tr("Capacity", "battery energy capacity stat label"), I18n.tr("Power", "battery stat label, charge or discharge rate in watts", true)]

    function shownDetailLabels() {
        const shown = SettingsData.batteryPopoutDetails;
        return detailLabels.filter((label, i) => shown.indexOf(Spec.BATTERY_POPOUT_DETAILS[i]) >= 0);
    }

    function setDetail(index, selected) {
        const shown = SettingsData.batteryPopoutDetails;
        SettingsData.set("batteryPopoutDetails", Spec.BATTERY_POPOUT_DETAILS.filter((key, i) => i === index ? selected : shown.indexOf(key) >= 0));
    }

    SettingsCard {
        settingKey: "barWidgetBattery"

        SettingsButtonGroupRow {
            settingKey: "batteryColorMode"
            tags: ["battery", "color", "level", "low", "charging", "theme", "icon", "meter", "indicator", "accent", "green", "red"]
            text: I18n.tr("Color", "battery bar widget: how the battery is colored")
            visible: (BatteryService.batteryAvailable || BatteryService.hasPeripherals) && !(root.page?.dockHosted ?? false)
            resetStore: root.barStore
            resetKeys: ["batteryColorMode"]
            model: [I18n.tr("Theme", "battery settings: plain widget colors, like other bar widgets"), I18n.tr("Low and charging", "battery settings: red when low, green while charging"), I18n.tr("Level", "battery settings: charge level indicator colors")]
            values: ["theme", "lowcharging", "level"]
            value: root.barConfig?.batteryColorMode ?? SettingsData.barConfigDefault("batteryColorMode")
            fallbackValue: SettingsData.barConfigDefault("batteryColorMode")
            onValueSelected: selected => SettingsData.updateBarConfig(root.page.barId, {
                    "batteryColorMode": selected
                })
        }

        SettingsButtonGroupRow {
            resetStore: root.page
            resetKeys: ["batterySeparator"]
            text: I18n.tr("Separator", "battery bar widget: what sits between its entries")
            model: [I18n.tr("Gap", "battery bar widget separator: plain space"), I18n.tr("Line", "battery bar widget separator: thin line"), I18n.tr("Dot", "battery bar widget separator: small dot"), I18n.tr("Separate", "battery bar widget separator: each entry gets its own background")]
            values: ["gap", "line", "dot", "separate"]
            value: root.page.value("batterySeparator")
            fallbackValue: SettingsData.widgetDefaults("battery").batterySeparator
            onValueSelected: selected => root.page.set("batterySeparator", selected)
        }

        SettingsNavRow {
            iconName: "battery_alert"
            title: I18n.tr("Low threshold")
            onClicked: keyboard => {
                SettingsSearchService.navigateToSection("batteryAlerts");
                root.page.parentModal?.navigateTo("battery", keyboard);
            }
        }
    }

    SettingsCard {
        settingKey: "barWidgetBatteryDevices"
        title: I18n.tr("Entries", "battery bar widget: ordered list of batteries and devices shown in the bar")

        BatteryDeviceEditor {
            saved: root.page.value("batteryDevices")
            devices: BatteryService.peripheralDevices
            onEntriesEdited: entries => root.page.set("batteryDevices", entries)

            systemDetails: Component {
                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    SettingsToggleRow {
                        width: parent.width
                        paintBackground: false
                        text: I18n.tr("Show percentage")
                        checked: root.page.value("showBatteryPercent")
                        onToggled: checked => root.page.set("showBatteryPercent", checked)
                    }

                    SettingsToggleRow {
                        width: parent.width
                        paintBackground: false
                        enabled: root.page.value("showBatteryPercent")
                        text: I18n.tr("Only on battery")
                        checked: root.page.value("showBatteryPercentOnlyOnBattery")
                        onToggled: checked => root.page.set("showBatteryPercentOnlyOnBattery", checked)
                    }

                    SettingsToggleRow {
                        width: parent.width
                        paintBackground: false
                        text: I18n.tr("Show remaining time")
                        checked: root.page.value("showBatteryTime")
                        onToggled: checked => root.page.set("showBatteryTime", checked)
                    }

                    SettingsToggleRow {
                        width: parent.width
                        paintBackground: false
                        enabled: root.page.value("showBatteryTime")
                        text: I18n.tr("Only on battery")
                        checked: root.page.value("showBatteryTimeOnlyOnBattery")
                        onToggled: checked => root.page.set("showBatteryTimeOnlyOnBattery", checked)
                    }

                    SettingsToggleRow {
                        width: parent.width
                        paintBackground: false
                        text: I18n.tr("Show charge rate", "Battery bar widget setting: show how many watts are going into the battery while charging")
                        checked: root.page.value("showBatteryPowerCharging")
                        onToggled: checked => root.page.set("showBatteryPowerCharging", checked)
                    }

                    SettingsToggleRow {
                        width: parent.width
                        paintBackground: false
                        text: I18n.tr("Show discharge rate", "Battery bar widget setting: show how many watts the system is drawing from the battery")
                        checked: root.page.value("showBatteryPowerDischarging")
                        onToggled: checked => root.page.set("showBatteryPowerDischarging", checked)
                    }

                    SettingsButtonGroupRow {
                        width: parent.width
                        paintBackground: false
                        resetStore: root.page
                        resetKeys: ["batteryStyle"]
                        text: I18n.tr("Battery style")
                        model: [I18n.tr("Icon", "battery widget: system battery glyph"), I18n.tr("Solid", "island settings: filled battery meter style"), I18n.tr("Circle", "island settings: circular battery meter style")]
                        values: ["icon", "solid", "circle"]
                        value: root.page.value("batteryStyle")
                        fallbackValue: SettingsData.widgetDefaults("battery").batteryStyle
                        onValueSelected: selected => root.page.set("batteryStyle", selected)
                    }

                    SettingsButtonGroupRow {
                        width: parent.width
                        paintBackground: false
                        resetStore: root.page
                        resetKeys: ["batteryDirection"]
                        text: I18n.tr("Direction", "battery bar widget: orientation of the battery glyph")
                        model: [I18n.tr("Horizontal", "battery bar widget direction"), I18n.tr("Vertical", "battery bar widget direction")]
                        values: ["horizontal", "vertical"]
                        value: root.page.value("batteryDirection")
                        fallbackValue: SettingsData.widgetDefaults("battery").batteryDirection
                        onValueSelected: selected => root.page.set("batteryDirection", selected)
                    }
                }
            }
        }
    }

    SettingsCard {
        iconName: "web_asset"
        title: I18n.tr("Popout", "battery settings: card title for the battery popout appearance")
        settingKey: "batteryPopout"
        tags: ["battery", "popout", "appearance", "color", "style", "wavy", "wave", "compact", "line", "ring", "card"]

        SettingsButtonGroupRow {
            settingKey: "batteryPopoutColor"
            tags: ["battery", "popout", "color", "primary", "theme", "low", "charging", "level"]
            text: I18n.tr("Color", "battery settings: color of the battery popout")
            model: [I18n.tr("Primary", "battery settings: popout color option, accent color"), I18n.tr("Theme", "battery settings: plain widget colors, like other bar widgets"), I18n.tr("Low and charging", "battery settings: red when low, green while charging"), I18n.tr("Level", "battery settings: charge level indicator colors")]
            values: Spec.BATTERY_POPOUT_COLORS
            value: SettingsData.batteryPopoutColor
            onValueSelected: value => SettingsData.set("batteryPopoutColor", value)
        }

        SettingsButtonGroupRow {
            settingKey: "batteryPopoutStyle"
            tags: ["battery", "popout", "style", "compact", "line", "ring", "card"]
            text: I18n.tr("Style", "battery settings: style of the battery popout gauge")
            model: [I18n.tr("Compact", "battery settings: popout style option, number beside the title without a card"), I18n.tr("Line", "battery settings: popout gauge style option"), I18n.tr("Ring", "noun, battery widget ring gauge style option"), I18n.tr("Card", "battery settings: popout gauge style option, filled card")]
            values: Spec.BATTERY_POPOUT_STYLES
            value: SettingsData.batteryPopoutStyle
            onValueSelected: value => SettingsData.set("batteryPopoutStyle", value)
        }

        SettingsButtonGroupRow {
            settingKey: "batteryPopoutBadge"
            tags: ["battery", "popout", "badge", "shape", "ring", "icon"]
            visible: SettingsData.batteryPopoutStyle === "line" || SettingsData.batteryPopoutStyle === "card"
            text: I18n.tr("Badge", "battery settings: shape behind the battery icon in the popout")
            model: [I18n.tr("Shape", "battery settings: popout badge option, filled shape"), I18n.tr("Ring", "noun, battery widget ring gauge style option")]
            values: Spec.BATTERY_POPOUT_BADGES
            value: SettingsData.batteryPopoutBadge
            onValueSelected: value => SettingsData.set("batteryPopoutBadge", value)
        }

        SettingsToggleRow {
            settingKey: "batteryPopoutWavy"
            tags: ["battery", "popout", "wavy", "wave", "charging", "animation"]
            text: I18n.tr("Wavy", "battery popout: wavy level indicator while charging")
            checked: SettingsData.batteryPopoutWavy
            onToggled: checked => SettingsData.set("batteryPopoutWavy", checked)
        }
    }

    SettingsCard {
        iconName: "battery_full"
        title: I18n.tr("Overview", "battery settings: card title for the popout battery section")
        settingKey: "batteryPopoutBatteryCard"
        tags: ["battery", "popout", "section", "size", "details", "layout", "health", "temperature", "capacity", "power"]
        visible: BatteryService.batteryAvailable

        SettingsToggleRow {
            settingKey: "batteryPopoutBattery"
            tags: ["battery", "popout", "section", "show", "hide"]
            text: I18n.tr("Show", "battery settings: show this popout section")
            checked: SettingsData.batteryPopoutBattery
            onToggled: checked => SettingsData.set("batteryPopoutBattery", checked)
        }

        SettingsButtonGroupRow {
            settingKey: "batteryPopoutDetailsLayout"
            tags: ["battery", "popout", "details", "layout", "grid", "compact", "chips", "list"]
            enabled: SettingsData.batteryPopoutBattery
            text: I18n.tr("Layout", "battery settings: layout of this popout section")
            model: root.layoutLabels
            values: Spec.BATTERY_POPOUT_LAYOUTS
            value: SettingsData.batteryPopoutDetailsLayout
            onValueSelected: value => SettingsData.set("batteryPopoutDetailsLayout", value)
        }

        SettingsButtonGroupRow {
            id: detailsRow
            settingKey: "batteryPopoutDetails"
            tags: ["battery", "popout", "details", "health", "temperature", "capacity", "power"]
            text: I18n.tr("Details", "battery settings: which detail tiles the popout shows")
            enabled: SettingsData.batteryPopoutBattery
            selectionMode: "multi"
            model: root.detailLabels
            checkEnabled: false
            onSelectionChanged: (index, selected) => root.setDetail(index, selected)

            Binding {
                target: detailsRow
                property: "currentSelection"
                value: root.shownDetailLabels()
            }
        }
    }

    SettingsCard {
        iconName: "speed"
        title: I18n.tr("Power profile", "battery settings: card title for the popout power profile section")
        settingKey: "batteryPopoutPowerCard"
        tags: ["battery", "popout", "section", "power", "profile", "style"]
        visible: PowerProfileWatcher.available

        SettingsToggleRow {
            settingKey: "batteryPopoutPower"
            tags: ["battery", "popout", "power", "profile", "show", "hide"]
            text: I18n.tr("Show", "battery settings: show this popout section")
            checked: SettingsData.batteryPopoutPower
            onToggled: checked => SettingsData.set("batteryPopoutPower", checked)
        }

        SettingsButtonGroupRow {
            settingKey: "batteryPopoutPowerStyle"
            tags: ["battery", "popout", "power", "profile", "style", "circle", "segments", "buttons", "slider"]
            enabled: SettingsData.batteryPopoutPower
            text: I18n.tr("Style", "battery settings: style of the popout power profile section")
            model: [I18n.tr("Circle", "battery settings: popout power profile style option"), I18n.tr("Segments", "battery settings: popout power profile style option"), I18n.tr("Buttons", "battery settings: popout power profile style option"), I18n.tr("Slider", "battery settings: popout power profile style option")]
            values: Spec.BATTERY_POPOUT_POWER_STYLES
            value: SettingsData.batteryPopoutPowerStyle
            onValueSelected: value => SettingsData.set("batteryPopoutPowerStyle", value)
        }

        SettingsButtonGroupRow {
            settingKey: "batteryPopoutPowerPlacement"
            tags: ["battery", "popout", "power", "profile", "placement", "card", "overview"]
            visible: SettingsData.batteryPopoutStyle !== "compact"
            enabled: SettingsData.batteryPopoutPower
            text: I18n.tr("Placement", "battery settings: where the popout power profile control sits")
            model: [I18n.tr("Separate", "battery settings: popout power profile placement option, own card"), I18n.tr("Overview", "battery settings: popout power profile placement option, inside the overview card")]
            values: Spec.BATTERY_POPOUT_POWER_PLACEMENTS
            value: SettingsData.batteryPopoutPowerPlacement
            onValueSelected: value => SettingsData.set("batteryPopoutPowerPlacement", value)
        }
    }

    SettingsCard {
        iconName: "devices"
        title: I18n.tr("Devices", "battery settings: card title for the popout devices section")
        settingKey: "batteryPopoutDevicesCard"
        tags: ["battery", "popout", "section", "devices", "peripherals", "mouse", "keyboard", "headphones", "size", "layout"]

        SettingsToggleRow {
            settingKey: "batteryPopoutDevices"
            tags: ["battery", "popout", "devices", "show", "hide"]
            text: I18n.tr("Show", "battery settings: show this popout section")
            checked: SettingsData.batteryPopoutDevices
            onToggled: checked => SettingsData.set("batteryPopoutDevices", checked)
        }

        SettingsButtonGroupRow {
            settingKey: "batteryPopoutDevicesLayout"
            tags: ["battery", "popout", "devices", "layout", "grid", "compact", "chips", "list", "bars"]
            enabled: SettingsData.batteryPopoutDevices
            text: I18n.tr("Layout", "battery settings: layout of this popout section")
            model: root.deviceLayoutLabels
            values: Spec.BATTERY_POPOUT_DEVICE_LAYOUTS
            value: SettingsData.batteryPopoutDevicesLayout
            onValueSelected: value => SettingsData.set("batteryPopoutDevicesLayout", value)
        }
    }
}
