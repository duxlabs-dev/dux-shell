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

    readonly property string compositorLabel: CompositorService.displayName || I18n.tr("Compositor")
    readonly property bool logoShown: root.page.value("launcherLogoMode") !== "apps"
    readonly property bool colorCustom: {
        const override = root.page.value("launcherLogoColorOverride");
        return root.logoShown && override !== "" && override !== "primary" && override !== "surface";
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    FileBrowserModal {
        id: logoFileBrowser

        browserTitle: I18n.tr("Select Launcher Logo")
        bucket: "logo"
        filters: ["*.svg", "*.png", "*.jpg", "*.jpeg", "*.webp"]
        onAccepted: paths => root.page.set("launcherLogoCustomPath", paths[0])
    }

    SettingsCard {
        settingKey: "barWidgetLauncherButton"

        SettingsButtonGroupRow {
            readonly property var modes: ["apps", "os", "dank", "compositor", "custom"]

            resetStore: root.page
            resetKeys: ["launcherLogoMode"]
            text: I18n.tr("Icon")
            buttonPadding: Theme.spacingS
            minButtonWidth: 44
            textSize: Theme.fontSizeSmall
            model: [I18n.tr("Apps Icon"), I18n.tr("OS Logo"), "Dank", root.compositorLabel, I18n.tr("Custom")]
            currentIndex: Math.max(0, modes.indexOf(root.page.value("launcherLogoMode")))
            onSelectionChanged: (index, selected) => {
                if (!selected)
                    return;
                root.page.set("launcherLogoMode", modes[index]);
            }
        }

        SettingsTextFieldRow {
            resetStore: root.page
            resetKeys: ["launcherLogoCustomPath"]
            text: I18n.tr("Custom")
            visible: root.page.value("launcherLogoMode") === "custom"
            placeholderText: I18n.tr("Select an image file...")
            value: root.page.value("launcherLogoCustomPath")
            onEditingFinished: value => root.page.set("launcherLogoCustomPath", value.trim())

            actions: DActionButton {
                iconName: "folder_open"
                Accessible.name: I18n.tr("Select Launcher Logo")
                onClicked: logoFileBrowser.open()
            }
        }

        ColorDropdownRow {
            resetStore: root.page
            resetKeys: ["launcherLogoColorOverride"]
            text: I18n.tr("Color override")
            visible: root.logoShown
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
                const override = root.page.value("launcherLogoColorOverride");
                if (override === "" || override === "primary" || override === "surface")
                    return override;
                return "custom";
            }
            customColor: root.colorCustom ? root.page.value("launcherLogoColorOverride") : "#ffffff"
            pickerTitle: I18n.tr("Choose Launcher Logo Color")
            onModeSelected: mode => {
                if (mode !== "custom") {
                    root.page.set("launcherLogoColorOverride", mode);
                    return;
                }
                if (!root.colorCustom)
                    root.page.set("launcherLogoColorOverride", "#ffffff");
            }
            onCustomColorSelected: selectedColor => root.page.set("launcherLogoColorOverride", selectedColor)
        }

        SettingsSliderRow {
            resetStore: root.page
            resetKeys: ["launcherLogoSizeOffset"]
            text: I18n.tr("Size offset")
            unit: "px"
            visible: root.logoShown
            value: root.page.value("launcherLogoSizeOffset")
            minimum: -12
            maximum: 12
            onSliderValueChanged: value => root.page.set("launcherLogoSizeOffset", value)
        }

        SettingsSliderRow {
            resetStore: root.page
            resetKeys: ["launcherLogoBrightness"]
            text: I18n.tr("Brightness")
            visible: root.colorCustom
            value: Math.round(root.page.value("launcherLogoBrightness") * 100)
            minimum: 0
            maximum: 100
            onSliderValueChanged: value => root.page.set("launcherLogoBrightness", value / 100)
        }

        SettingsSliderRow {
            resetStore: root.page
            resetKeys: ["launcherLogoContrast"]
            text: I18n.tr("Contrast")
            visible: root.colorCustom
            value: Math.round(root.page.value("launcherLogoContrast") * 100)
            minimum: 0
            maximum: 200
            onSliderValueChanged: value => root.page.set("launcherLogoContrast", value / 100)
        }
    }
}
