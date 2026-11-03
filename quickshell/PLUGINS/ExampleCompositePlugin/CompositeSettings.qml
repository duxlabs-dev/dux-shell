import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "exampleComposite"

    StyledText {
        width: parent.width
        text: "Bar Widget — Emoji Cycler"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    SelectionSetting {
        settingKey: "emojiSet"
        label: "Emoji Set"
        description: "Choose which collection of emojis to cycle through"
        options: [
            {
                label: "Happy & Sad",
                value: "happySad"
            },
            {
                label: "Hearts",
                value: "hearts"
            },
            {
                label: "Hand Gestures",
                value: "hands"
            },
            {
                label: "All Mixed",
                value: "mixed"
            }
        ]
        defaultValue: "happySad"

        onValueChanged: {
            const sets = {
                "happySad": ["😊", "😢", "😂", "😭", "😍", "😡"],
                "hearts": ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍"],
                "hands": ["👍", "👎", "👊", "✌️", "🤘", "👌", "✋", "🤚"],
                "mixed": ["😊", "❤️", "👍", "🎉", "🔥", "✨", "🌟", "💯"]
            };
            root.saveValue("emojis", sets[value] || sets["happySad"]);
        }

        Component.onCompleted: {
            const currentSet = value || defaultValue;
            const sets = {
                "happySad": ["😊", "😢", "😂", "😭", "😍", "😡"],
                "hearts": ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍"],
                "hands": ["👍", "👎", "👊", "✌️", "🤘", "👌", "✋", "🤚"],
                "mixed": ["😊", "❤️", "👍", "🎉", "🔥", "✨", "🌟", "💯"]
            };
            root.saveValue("emojis", sets[currentSet] || sets["happySad"]);
        }
    }

    SliderSetting {
        settingKey: "cycleInterval"
        label: "Cycle Speed"
        description: "How quickly emojis rotate"
        defaultValue: 3000
        minimum: 500
        maximum: 10000
        unit: "ms"
        startIcon: "schedule"
    }

    SliderSetting {
        settingKey: "maxBarEmojis"
        label: "Max Bar Emojis"
        description: "Maximum number of emojis to display in the bar at once"
        defaultValue: 3
        minimum: 1
        maximum: 8
        endIcon: "emoji_emotions"
    }

    StyledText {
        width: parent.width
        text: "Desktop Widget — Clock"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    SelectionSetting {
        settingKey: "clockStyle"
        label: "Clock Style"
        options: [
            {
                label: "Analog",
                value: "analog"
            },
            {
                label: "Digital",
                value: "digital"
            }
        ]
        defaultValue: "analog"
    }

    ToggleSetting {
        settingKey: "showSeconds"
        label: "Show Seconds"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showDate"
        label: "Show Date"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "backgroundOpacity"
        label: "Background Opacity"
        defaultValue: 50
        minimum: 0
        maximum: 100
        unit: "%"
    }

    StyledText {
        width: parent.width
        text: "Daemon — Wallpaper Hook"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StringSetting {
        settingKey: "scriptPath"
        label: "Script Path"
        description: "Script executed when the wallpaper changes. The new wallpaper path is passed as the first argument."
        placeholder: "/path/to/your/script.sh"
        defaultValue: ""
    }
}
