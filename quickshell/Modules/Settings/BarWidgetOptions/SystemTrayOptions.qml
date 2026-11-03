import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    readonly property bool inlineExpansion: page.value("trayUseInlineExpansion")
    readonly property bool autoOverflow: page.value("trayAutoOverflow")
    readonly property bool trayTinted: ["primary", "secondary"].includes(SettingsData.systemTrayIconTintMode || "none")

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        settingKey: "barWidgetTray"

        SettingsToggleRow {
            text: I18n.tr("Use inline expansion")
            description: I18n.tr("Hidden icons expand in place instead of in a popup", "system tray inline expansion toggle description")
            checked: root.inlineExpansion
            onToggled: checked => root.page.set("trayUseInlineExpansion", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Single-line popup")
            enabled: !root.inlineExpansion
            checked: root.page.value("trayPopupSingleLine")
            onToggled: checked => root.page.set("trayPopupSingleLine", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Auto overflow")
            checked: root.autoOverflow
            onToggled: checked => root.page.set("trayAutoOverflow", checked)
        }

        SettingsSliderRow {
            resetStore: root.page
            resetKeys: ["trayMaxVisibleItems"]
            text: I18n.tr("Max visible")
            unit: ""
            minimumLabel: I18n.tr("Auto")
            enabled: root.autoOverflow
            value: root.page.value("trayMaxVisibleItems")
            minimum: 0
            maximum: 20
            onSliderValueChanged: newValue => root.page.set("trayMaxVisibleItems", newValue)
        }

        SettingsSliderRow {
            resetStore: root.page
            resetKeys: ["trayIconSpacing"]
            text: I18n.tr("Icon spacing")
            value: root.page.value("trayIconSpacing")
            minimum: 0
            maximum: 20
            unit: "px"
            onSliderValueChanged: newValue => root.page.set("trayIconSpacing", newValue)
        }

        SettingsButtonGroupRow {
            readonly property var modes: ["none", "monochrome", "primary", "secondary"]

            settingKey: "trayIconTint"
            tags: ["tray", "icon", "tint", "monochrome", "system tray", "color"]
            text: I18n.tr("Tray icon tint")
            resetKeys: ["systemTrayIconTintMode"]
            model: [I18n.tr("None"), I18n.tr("Monochrome"), I18n.tr("Primary"), I18n.tr("Secondary")]
            currentIndex: Math.max(0, modes.indexOf(SettingsData.systemTrayIconTintMode || "none"))
            onSelectionChanged: (index, selected) => {
                if (!selected)
                    return;
                SettingsData.set("systemTrayIconTintMode", modes[index]);
            }
        }

        SettingsSliderRow {
            text: I18n.tr("Tint saturation")
            tags: ["tray", "tint", "saturation"]
            visible: root.trayTinted
            resetKeys: ["systemTrayIconTintSaturation"]
            value: SettingsData.systemTrayIconTintSaturation ?? 50
            minimum: 0
            maximum: 100
            onSliderDragFinished: finalValue => SettingsData.set("systemTrayIconTintSaturation", finalValue)
        }

        SettingsSliderRow {
            text: I18n.tr("Tint strength")
            tags: ["tray", "tint", "strength"]
            visible: root.trayTinted
            resetKeys: ["systemTrayIconTintStrength"]
            value: SettingsData.systemTrayIconTintStrength ?? 135
            minimum: 0
            maximum: 200
            onSliderDragFinished: finalValue => SettingsData.set("systemTrayIconTintStrength", finalValue)
        }
    }
}
