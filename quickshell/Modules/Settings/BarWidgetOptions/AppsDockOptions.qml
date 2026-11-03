import QtQuick
import qs.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    readonly property bool dockHosted: page?.dockHosted ?? false
    readonly property var apps: page.appStore

    Component.onCompleted: TrashService.detectFileManagers()

    readonly property var activeColorOptions: [({
                "value": "primary",
                "label": I18n.tr("Primary")
            }), ({
                "value": "secondary",
                "label": I18n.tr("Secondary")
            }), ({
                "value": "primaryContainer",
                "label": I18n.tr("Primary Container")
            }), ({
                "value": "error",
                "label": I18n.tr("Error")
            }), ({
                "value": "success",
                "label": I18n.tr("Success", "noun, theme color name in active color dropdown")
            })]

    readonly property string compositorLabel: CompositorService.displayName || I18n.tr("Compositor")

    readonly property bool launcherLogoColorCustom: {
        const override = root.apps.get("launcherLogoColorOverride");
        return root.apps.get("launcherEnabled") && root.apps.get("launcherLogoMode") !== "apps" && override !== "" && override !== "primary" && override !== "surface";
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    FileBrowserModal {
        id: logoFileBrowser

        browserTitle: I18n.tr("Select Dock Launcher Logo")
        bucket: "logo"
        filters: ["*.svg", "*.png", "*.jpg", "*.jpeg", "*.webp"]
        onAccepted: paths => root.apps.set("launcherLogoCustomPath", paths[0])
    }

    SettingsCard {
        settingKey: "barWidgetAppsDock"

        SettingsToggleRow {
            text: I18n.tr("Compact mode")
            visible: !root.dockHosted
            checked: root.page.value("runningAppsCompactMode")
            onToggled: checked => root.page.set("runningAppsCompactMode", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Current workspace", "Running apps filter: only show apps from the active workspace")
            checked: root.page.value("runningAppsCurrentWorkspace")
            onToggled: checked => root.page.set("runningAppsCurrentWorkspace", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Group by app")
            visible: root.dockHosted
            checked: root.apps.get("groupByApp")
            onToggled: checked => root.apps.set("groupByApp", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Separate pinned and running apps")
            visible: root.dockHosted
            checked: root.apps.get("separatePinnedAndRunningApps")
            onToggled: checked => root.apps.set("separatePinnedAndRunningApps", checked)
        }
    }

    SettingsCard {
        title: I18n.tr("Overflow", "noun, card title for max visible apps settings")
        settingKey: "barWidgetAppsDockOverflow"

        SettingsSliderRow {
            resetStore: root.apps
            resetKeys: ["maxVisibleApps"]
            text: I18n.tr("Max pinned apps")
            minimumLabel: I18n.tr("All")
            value: root.apps.get("maxVisibleApps")
            minimum: 0
            maximum: 30
            onSliderValueChanged: value => root.apps.set("maxVisibleApps", value)
        }

        SettingsSliderRow {
            resetStore: root.apps
            resetKeys: ["maxVisibleRunningApps"]
            text: I18n.tr("Max running apps")
            minimumLabel: I18n.tr("All")
            value: root.apps.get("maxVisibleRunningApps")
            minimum: 0
            maximum: 30
            onSliderValueChanged: value => root.apps.set("maxVisibleRunningApps", value)
        }

        SettingsToggleRow {
            text: I18n.tr("Show badge")
            checked: root.apps.get("showOverflowBadge")
            onToggled: checked => root.apps.set("showOverflowBadge", checked)
        }
    }

    SettingsCard {
        title: I18n.tr("Launcher button")
        settingKey: "dockLauncher"

        SettingsToggleRow {
            text: I18n.tr("Show")
            checked: root.apps.get("launcherEnabled")
            onToggled: checked => root.apps.set("launcherEnabled", checked)
        }

        SettingsButtonGroupRow {
            resetStore: root.apps
            resetKeys: ["launcherLogoMode"]
            readonly property var modes: ["apps", "os", "dank", "compositor", "custom"]

            text: I18n.tr("Icon")
            enabled: root.apps.get("launcherEnabled")
            buttonPadding: Theme.spacingS
            minButtonWidth: 44
            textSize: Theme.fontSizeSmall
            model: [I18n.tr("Apps Icon"), I18n.tr("OS Logo"), "Dank", root.compositorLabel, I18n.tr("Custom")]
            currentIndex: Math.max(0, modes.indexOf(root.apps.get("launcherLogoMode")))
            onSelectionChanged: (index, selected) => {
                if (!selected)
                    return;
                root.apps.set("launcherLogoMode", modes[index]);
            }
        }

        SettingsTextFieldRow {
            resetStore: root.apps
            resetKeys: ["launcherLogoCustomPath"]
            text: I18n.tr("Custom")
            visible: root.apps.get("launcherEnabled") && root.apps.get("launcherLogoMode") === "custom"
            placeholderText: I18n.tr("Select an image file...")
            value: root.apps.get("launcherLogoCustomPath")
            onEditingFinished: value => root.apps.set("launcherLogoCustomPath", value.trim())

            actions: DActionButton {
                iconName: "folder_open"
                Accessible.name: I18n.tr("Select Dock Launcher Logo")
                onClicked: logoFileBrowser.open()
            }
        }

        ColorDropdownRow {
            resetStore: root.apps
            resetKeys: ["launcherLogoColorOverride"]
            text: I18n.tr("Color override")
            visible: root.apps.get("launcherEnabled") && root.apps.get("launcherLogoMode") !== "apps"
            options: [({
                        "value": "",
                        "label": I18n.tr("Default")
                    }), ({
                        "value": "primary",
                        "label": I18n.tr("Primary")
                    }), ({
                        "value": "surface",
                        "label": I18n.tr("Surface", "color option")
                    }), ({
                        "value": "custom",
                        "label": I18n.tr("Custom")
                    })]
            currentMode: {
                const override = root.apps.get("launcherLogoColorOverride");
                if (override === "" || override === "primary" || override === "surface")
                    return override;
                return "custom";
            }
            customColor: root.launcherLogoColorCustom ? root.apps.get("launcherLogoColorOverride") : "#ffffff"
            pickerTitle: I18n.tr("Choose Launcher Logo Color")
            onModeSelected: mode => {
                if (mode !== "custom") {
                    root.apps.set("launcherLogoColorOverride", mode);
                    return;
                }
                if (!root.launcherLogoColorCustom)
                    root.apps.set("launcherLogoColorOverride", "#ffffff");
            }
            onCustomColorSelected: selectedColor => root.apps.set("launcherLogoColorOverride", selectedColor)
        }

        SettingsSliderRow {
            resetStore: root.apps
            resetKeys: ["launcherLogoSizeOffset"]
            text: I18n.tr("Size offset")
            visible: root.apps.get("launcherEnabled") && root.apps.get("launcherLogoMode") !== "apps"
            value: root.apps.get("launcherLogoSizeOffset")
            minimum: -12
            maximum: 12
            onSliderValueChanged: value => root.apps.set("launcherLogoSizeOffset", value)
        }

        SettingsSliderRow {
            resetStore: root.apps
            resetKeys: ["launcherLogoBrightness"]
            text: I18n.tr("Brightness")
            visible: root.launcherLogoColorCustom
            value: Math.round(root.apps.get("launcherLogoBrightness") * 100)
            minimum: 0
            maximum: 100
            onSliderValueChanged: value => root.apps.set("launcherLogoBrightness", value / 100)
        }

        SettingsSliderRow {
            resetStore: root.apps
            resetKeys: ["launcherLogoContrast"]
            text: I18n.tr("Contrast")
            visible: root.launcherLogoColorCustom
            value: Math.round(root.apps.get("launcherLogoContrast") * 100)
            minimum: 0
            maximum: 200
            onSliderValueChanged: value => root.apps.set("launcherLogoContrast", value / 100)
        }
    }

    SettingsCard {
        title: I18n.tr("Trash")
        settingKey: "dockTrash"
        visible: root.dockHosted

        SettingsToggleRow {
            text: I18n.tr("Show")
            checked: root.apps.get("showTrash")
            onToggled: checked => root.apps.set("showTrash", checked)
        }

        SettingsDropdownRow {
            resetStore: root.apps
            resetKeys: ["trashFileManager"]
            text: I18n.tr("Open with", "trash setting label, which file manager opens the trash")
            enabled: root.apps.get("showTrash")
            currentValue: root.apps.get("trashFileManager")
            options: TrashService.availableFileManagers || []
            onValueChanged: value => root.apps.set("trashFileManager", value)
        }

        SettingsTextFieldRow {
            resetStore: root.apps
            resetKeys: ["trashCustomCommand"]
            text: I18n.tr("Custom command")
            visible: root.apps.get("showTrash") && root.apps.get("trashFileManager") === "custom"
            placeholderText: "pcmanfm trash:///"
            value: root.apps.get("trashCustomCommand")
            onEditingFinished: value => root.apps.set("trashCustomCommand", value.trim())
        }
    }

    SettingsCard {
        title: I18n.tr("Visual effects")
        settingKey: "barWidgetAppsDockEffects"
        visible: !root.dockHosted

        SettingsToggleRow {
            text: I18n.tr("Indicators")
            checked: !root.page.value("appsDockHideIndicators")
            onToggled: checked => root.page.set("appsDockHideIndicators", !checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Colorize active")
            checked: root.page.value("appsDockColorizeActive")
            onToggled: checked => root.page.set("appsDockColorizeActive", checked)
        }

        ColorDropdownRow {
            resetStore: root.page
            resetKeys: ["appsDockActiveColorMode"]
            text: I18n.tr("Active color")
            enabled: root.page.value("appsDockColorizeActive")
            options: root.activeColorOptions
            currentMode: root.page.value("appsDockActiveColorMode")
            onModeSelected: mode => root.page.set("appsDockActiveColorMode", mode)
        }

        SettingsToggleSliderRow {
            resetStore: root.page
            valueKeys: ["appsDockEnlargePercentage"]
            text: I18n.tr("Magnification", "dock setting: enlarge icons near the cursor")
            checked: root.page.value("appsDockEnlargeOnHover")
            value: root.page.value("appsDockEnlargePercentage")
            minimum: 100
            maximum: 150
            step: 5
            unit: "%"
            onToggled: checked => root.page.set("appsDockEnlargeOnHover", checked)
            onSliderValueChanged: newValue => root.page.set("appsDockEnlargePercentage", newValue)
        }

        SettingsSliderRow {
            resetStore: root.page
            resetKeys: ["appsDockIconSizePercentage"]
            text: I18n.tr("Icon size")
            value: root.page.value("appsDockIconSizePercentage")
            minimum: 50
            maximum: 200
            step: 5
            onSliderValueChanged: newValue => root.page.set("appsDockIconSizePercentage", newValue)
        }

        SettingsSliderRow {
            resetStore: root.page
            resetKeys: ["appsDockSpacing"]
            text: I18n.tr("Spacing")
            value: root.page.value("appsDockSpacing")
            minimum: 0
            maximum: 32
            unit: "px"
            onSliderValueChanged: value => root.page.set("appsDockSpacing", value)
        }
    }
}
