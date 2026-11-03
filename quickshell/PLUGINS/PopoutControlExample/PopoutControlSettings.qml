import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "popoutControlExample"

    StyledText {
        width: parent.width
        text: "Popout Control Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Choose which popout/modal will open when clicking the widget"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "selectedPopout"
        label: "Popout to Open"
        description: "Select which popout or modal opens when you click the widget"
        options: [
            {
                label: "Control Center",
                value: "controlCenter"
            },
            {
                label: "Notification Center",
                value: "notificationCenter"
            },
            {
                label: "App Drawer",
                value: "appDrawer"
            },
            {
                label: "Process List",
                value: "processList"
            },
            {
                label: "DankDash",
                value: "dankDash"
            },
            {
                label: "Battery Info",
                value: "battery"
            },
            {
                label: "VPN",
                value: "vpn"
            },
            {
                label: "System Update",
                value: "systemUpdate"
            },
            {
                label: "Settings",
                value: "settings"
            },
            {
                label: "Clipboard History",
                value: "clipboardHistory"
            },
            {
                label: "Spotlight",
                value: "spotlight"
            },
            {
                label: "Power Menu",
                value: "powerMenu"
            },
            {
                label: "Color Picker",
                value: "colorPicker"
            },
            {
                label: "Notepad",
                value: "notepad"
            }
        ]
        defaultValue: "controlCenter"
    }

    StyledText {
        width: parent.width
        text: "💡 Tip: The widget displays the name of the selected popout and opens it when clicked!"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
