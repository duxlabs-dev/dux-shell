import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

Column {
    id: root

    property string instanceId: ""
    property var instanceData: null
    property bool showBehavior: !lockScreenInstance
    property bool showAppearance: true
    property bool showPlacement: true
    readonly property var cfg: instanceData?.config ?? {}
    readonly property string listKey: SettingsData.widgetInstanceListKey(instanceId)
    readonly property bool lockScreenInstance: listKey !== "desktopWidgetInstances"
    readonly property bool greeterInstance: listKey === "greeterWidgetInstances"
    readonly property string currentLayer: {
        const raw = root.cfg.layer;
        if (raw === "wallpaper")
            return "background";
        if (raw === "background" || raw === "bottom" || raw === "overlay")
            return raw;
        return (root.cfg.showOnOverlay ?? false) ? "overlay" : "bottom";
    }
    default property alias rows: optionsCard.content

    function updateConfig(key, value) {
        const updates = {};
        updates[key] = value;
        SettingsData.updateDesktopWidgetInstanceConfig(instanceId, updates);
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        id: optionsCard
    }

    SettingsCard {
        title: I18n.tr("Appearance")
        visible: root.showAppearance

        SettingsSliderRow {
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

    SettingsCard {
        title: I18n.tr("Behavior")
        visible: root.showBehavior

        SettingsDropdownRow {
            visible: !root.lockScreenInstance
            text: I18n.tr("Layers")
            options: [I18n.tr("Background"), I18n.tr("Bottom"), I18n.tr("Overlay")]
            optionValues: ["background", "bottom", "overlay"]
            currentValue: root.currentLayer
            onValueChanged: value => {
                SettingsData.updateDesktopWidgetInstanceConfig(root.instanceId, {
                    layer: value,
                    showOnOverlay: value === "overlay"
                });
            }
        }

        SettingsToggleRow {
            visible: CompositorService.isNiri && !root.lockScreenInstance
            text: I18n.tr("Show on overview")
            checked: root.cfg.showOnOverview ?? false
            onToggled: checked => root.updateConfig("showOnOverview", checked)
        }

        SettingsToggleRow {
            visible: CompositorService.isNiri && !root.lockScreenInstance
            text: I18n.tr("Show on overview only")
            checked: root.cfg.showOnOverviewOnly ?? false
            onToggled: checked => root.updateConfig("showOnOverviewOnly", checked)
        }

        SettingsToggleRow {
            visible: !root.lockScreenInstance
            text: I18n.tr("Click through")
            checked: root.cfg.clickThrough ?? false
            onToggled: checked => root.updateConfig("clickThrough", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Sync position across displays")
            checked: root.cfg.syncPositionAcrossScreens ?? false
            onToggled: checked => {
                if (checked)
                    SessionData.syncDesktopWidgetPositionToAllScreens(root.instanceId);
                root.updateConfig("syncPositionAcrossScreens", checked);
            }
        }
    }
}
