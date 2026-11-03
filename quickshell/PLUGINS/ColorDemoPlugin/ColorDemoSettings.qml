import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.DCommon.Widgets

PluginSettings {
    id: root
    pluginId: "colorDemo"

    StyledText {
        width: parent.width
        text: "Color Demo Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Choose a custom color to display in the bar widget"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ColorSetting {
        settingKey: "customColor"
        label: "Custom Color"
        description: "Choose a custom color to display in the widget"
        defaultValue: Theme.primary
    }
}
