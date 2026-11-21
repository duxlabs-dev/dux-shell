import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property string instanceId: ""
    property var instanceData: null
    property bool showOptions: true
    property bool showAppearance: true
    property bool showPlacement: true
    property bool backgroundOption: false
    readonly property var cfg: instanceData?.config ?? {}
    property var backgroundConfig: cfg
    property bool opacityUsed: true
    // Saved along with every change, so an outdated config gets rewritten in its current form.
    property var configFixups: ({})
    readonly property string listKey: SettingsData.widgetInstanceListKey(instanceId)
    readonly property bool lockScreenInstance: listKey !== "desktopWidgetInstances"
    readonly property bool greeterInstance: listKey === "greeterWidgetInstances"
    default property alias rows: optionsCard.content
    property alias optionsTitle: optionsCard.title
    property alias cards: extraCards.data

    function updateConfig(key, value) {
        const updates = Object.assign({}, configFixups);
        updates[key] = value;
        SettingsData.updateDesktopWidgetInstanceConfig(instanceId, updates);
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        id: optionsCard
        visible: root.showOptions
    }

    Column {
        id: extraCards
        width: parent.width
        spacing: Theme.spacingL
        visible: children.length > 0
    }

    SettingsCard {
        title: I18n.tr("Appearance")
        visible: root.showAppearance

        SettingsButtonGroupRow {
            visible: root.backgroundOption
            text: I18n.tr("Background", "desktop widget background style")
            model: [I18n.tr("Card", "desktop widget background option"), I18n.tr("None", "desktop widget background option")]
            values: ["card", "none"]
            value: root.backgroundConfig.background
            fallbackValue: "card"
            onValueSelected: value => root.updateConfig("background", value)
        }

        SettingsToggleRow {
            visible: root.backgroundOption && root.backgroundConfig.background === "none"
            text: I18n.tr("Shadow", "desktop widget text halo when there is no background")
            checked: root.backgroundConfig.textShadow ?? true
            onToggled: checked => root.updateConfig("textShadow", checked)
        }

        SettingsSliderRow {
            visible: root.opacityUsed
            text: I18n.tr("Opacity")
            minimum: 0
            maximum: 100
            value: Math.round((root.cfg.transparency ?? (root.lockScreenInstance ? 0 : 0.8)) * 100)
            onSliderValueChanged: newValue => root.updateConfig("transparency", newValue / 100)
        }

        SettingsColorPicker {
            showDefault: root.lockScreenInstance
            colorMode: root.cfg.colorMode ?? (root.lockScreenInstance ? "default" : "primary")
            customColor: root.cfg.customColor ?? "#ffffff"
            onColorModeSelected: mode => root.updateConfig("colorMode", mode)
            onCustomColorSelected: selectedColor => root.updateConfig("customColor", selectedColor.toString())
        }
    }

    SettingsCard {
        title: I18n.tr("Displays")
        visible: root.showPlacement

        SettingsDisplayPicker {
            displayPreferences: root.cfg.displayPreferences ?? ["all"]
            preferencesHandler: prefs => root.updateConfig("displayPreferences", prefs)
        }

        SettingsRow {
            iconName: "drag_pan"
            title: I18n.tr("Reset Position")
            clickable: true
            onClicked: SessionData.resetDesktopWidgetInstanceGeometry(root.instanceId, ["x", "y"])
        }

        SettingsRow {
            iconName: "open_in_full"
            title: I18n.tr("Reset Size")
            clickable: true
            onClicked: SessionData.resetDesktopWidgetInstanceGeometry(root.instanceId, ["width", "height"])
        }
    }
}
