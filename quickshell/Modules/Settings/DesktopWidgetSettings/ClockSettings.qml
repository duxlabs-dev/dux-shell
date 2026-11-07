import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

DesktopWidgetInstanceSettings {
    id: root

    readonly property var styles: ["digital", "analog", "stacked", "expressive", "overlap"]
    readonly property var styleLabels: [I18n.tr("Digital"), I18n.tr("Analog"), I18n.tr("Stacked", "desktop clock style option"), I18n.tr("Expressive"), I18n.tr("Overlapping", "clock style with overlapping digit rows")]
    readonly property string style: cfg.style ?? "analog"
    readonly property bool analog: style === "analog"
    readonly property bool overlap: style === "overlap"

    SettingsDropdownRow {
        text: I18n.tr("Clock style")
        options: root.styleLabels
        currentValue: root.styleLabels[Math.max(0, root.styles.indexOf(root.style))]
        onValueChanged: value => {
            const index = root.styleLabels.indexOf(value);
            if (index >= 0)
                root.updateConfig("style", root.styles[index]);
        }
    }

    SettingsFontDropdownRow {
        visible: !root.analog
        text: I18n.tr("Font")
        currentFont: root.cfg.fontFamily ?? ""
        defaultFamily: (root.lockScreenInstance ? SettingsData.lockScreenFontFamily : SettingsData.fontFamily) || Theme.defaultFontFamily
        onFontSelected: family => root.updateConfig("fontFamily", family)
    }

    SettingsSliderRow {
        visible: !root.analog
        text: I18n.tr("Weight")
        minimum: 0
        maximum: Font.Black
        step: 100
        minimumLabel: I18n.tr("Default")
        value: root.cfg.weight ?? 0
        onSliderValueChanged: newValue => root.updateConfig("weight", newValue)
    }

    SettingsToggleRow {
        visible: root.style === "expressive"
        text: I18n.tr("Rounded")
        checked: root.cfg.rounded ?? true
        onToggled: checked => root.updateConfig("rounded", checked)
    }

    SettingsToggleRow {
        visible: root.style === "digital"
        text: I18n.tr("Italic", "clock font style toggle")
        checked: root.cfg.italic ?? false
        onToggled: checked => root.updateConfig("italic", checked)
    }

    SettingsToggleRow {
        visible: !root.analog && !root.overlap
        text: I18n.tr("Accent minutes", "lock screen clock colors")
        checked: root.cfg.twoTone ?? root.lockScreenInstance
        onToggled: checked => root.updateConfig("twoTone", checked)
    }

    SettingsToggleRow {
        visible: root.analog
        text: I18n.tr("Show hour numbers")
        checked: root.cfg.showAnalogNumbers ?? false
        onToggled: checked => root.updateConfig("showAnalogNumbers", checked)
    }

    SettingsToggleRow {
        visible: root.analog
        text: I18n.tr("Show seconds")
        checked: root.cfg.showAnalogSeconds ?? true
        onToggled: checked => root.updateConfig("showAnalogSeconds", checked)
    }

    SettingsToggleRow {
        visible: !root.analog && !root.overlap
        text: I18n.tr("Show seconds")
        checked: root.cfg.showDigitalSeconds ?? false
        onToggled: checked => root.updateConfig("showDigitalSeconds", checked)
    }

    SettingsToggleRow {
        visible: !root.overlap
        text: I18n.tr("Show date")
        checked: root.cfg.showDate ?? !root.lockScreenInstance
        onToggled: checked => root.updateConfig("showDate", checked)
    }

    SettingsToggleRow {
        visible: root.lockScreenInstance
        text: I18n.tr("Automatic placement", "lock screen clock placement")
        description: I18n.tr("Choose a clear area of the background. Drag the clock to place it yourself.", "lock screen automatic clock placement")
        checked: root.cfg.autoPosition ?? true
        onToggled: checked => {
            if (checked)
                SessionData.resetDesktopWidgetInstanceGeometry(root.instanceId, ["x", "y"]);
            root.updateConfig("autoPosition", checked);
        }
    }
}
