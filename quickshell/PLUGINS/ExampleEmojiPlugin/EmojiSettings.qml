import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "exampleEmojiPlugin"

    // Header section to explain what this plugin does
    // I18n.trFor resolves from this plugin's translations/ dir first,
    // then falls back to the global catalog, then the English term
    StyledText {
        width: parent.width
        text: I18n.trFor("exampleEmojiPlugin", "Emoji Cycler Settings")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: I18n.trFor("exampleEmojiPlugin", "Configure which emojis appear in your bar, how quickly they cycle, and how many show at once.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // Dropdown to select which emoji set to use
    SelectionSetting {
        settingKey: "emojiSet"
        label: I18n.trFor("exampleEmojiPlugin", "Emoji Set")
        description: I18n.trFor("exampleEmojiPlugin", "Choose which collection of emojis to cycle through")
        options: [
            {
                label: I18n.trFor("exampleEmojiPlugin", "Happy & Sad"),
                value: "happySad"
            },
            {
                label: I18n.trFor("exampleEmojiPlugin", "Hearts"),
                value: "hearts"
            },
            {
                label: I18n.trFor("exampleEmojiPlugin", "Hand Gestures"),
                value: "hands"
            },
            {
                label: I18n.trFor("exampleEmojiPlugin", "All Mixed"),
                value: "mixed"
            }
        ]
        defaultValue: "happySad"

        // Update the actual emoji array when selection changes
        onValueChanged: {
            const sets = {
                "happySad": ["😊", "😢", "😂", "😭", "😍", "😡"],
                "hearts": ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍"],
                "hands": ["👍", "👎", "👊", "✌️", "🤘", "👌", "✋", "🤚"],
                "mixed": ["😊", "❤️", "👍", "🎉", "🔥", "✨", "🌟", "💯"]
            };
            const newEmojis = sets[value] || sets["happySad"];
            root.saveValue("emojis", newEmojis);
        }

        Component.onCompleted: {
            // Initialize the emojis array on first load
            const currentSet = value || defaultValue;
            const sets = {
                "happySad": ["😊", "😢", "😂", "😭", "😍", "😡"],
                "hearts": ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍"],
                "hands": ["👍", "👎", "👊", "✌️", "🤘", "👌", "✋", "🤚"],
                "mixed": ["😊", "❤️", "👍", "🎉", "🔥", "✨", "🌟", "💯"]
            };
            const emojis = sets[currentSet] || sets["happySad"];
            root.saveValue("emojis", emojis);
        }
    }

    // Slider to control how fast emojis cycle (in milliseconds)
    SliderSetting {
        settingKey: "cycleInterval"
        label: I18n.trFor("exampleEmojiPlugin", "Cycle Speed")
        description: I18n.trFor("exampleEmojiPlugin", "How quickly emojis rotate (in seconds)")
        defaultValue: 3000
        minimum: 500
        maximum: 10000
        unit: "ms"
        startIcon: "schedule"
    }

    // Slider to control max emojis shown in the bar
    SliderSetting {
        settingKey: "maxBarEmojis"
        label: I18n.trFor("exampleEmojiPlugin", "Max Bar Emojis")
        description: I18n.trFor("exampleEmojiPlugin", "Maximum number of emojis to display in the bar at once")
        defaultValue: 3
        minimum: 1
        maximum: 8
        unit: ""
        endIcon: "emoji_emotions"
    }

    StyledText {
        width: parent.width
        text: I18n.trFor("exampleEmojiPlugin", "💡 Tip: Click the emoji widget in your bar to open the emoji picker and copy any emoji to your clipboard!")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
