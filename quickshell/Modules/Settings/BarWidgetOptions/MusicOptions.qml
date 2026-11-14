import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    readonly property var scrollModes: ["volume", "song", "nothing"]
    readonly property var scrollLabels: [I18n.tr("Change Volume", "media scroll wheel option"), I18n.tr("Change Song", "media scroll wheel option"), I18n.tr("Nothing", "media scroll wheel option")]
    readonly property var styles: ["controls", "activity"]
    readonly property bool controls: root.page.value("mediaStyle") !== "activity"

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        settingKey: "barWidgetMusic"

        SettingsButtonGroupRow {
            resetStore: root.page
            resetKeys: ["mediaStyle"]
            text: I18n.tr("Style")
            model: [I18n.tr("Controls", "media widget style with play, previous and next buttons"), I18n.tr("Now playing", "media widget style showing only the cover, visualizer and title")]
            currentIndex: Math.max(0, root.styles.indexOf(root.page.value("mediaStyle")))
            onSelectionChanged: (index, selected) => {
                if (selected)
                    root.page.set("mediaStyle", root.styles[index]);
            }
        }

        SettingsButtonGroupRow {
            visible: root.controls
            resetStore: root.page
            resetKeys: ["mediaSize"]
            text: I18n.tr("Size")
            model: [I18n.tr("Small"), I18n.tr("Medium"), I18n.tr("Large"), I18n.tr("Largest")]
            currentIndex: Math.max(0, Math.min(3, root.page.value("mediaSize")))
            onSelectionChanged: (index, selected) => {
                if (selected)
                    root.page.set("mediaSize", index);
            }
        }

        SettingsToggleRow {
            visible: root.controls
            text: I18n.tr("Adaptive width")
            description: I18n.tr("Fits the song title instead of keeping a fixed width", "media widget adaptive width toggle description")
            checked: root.page.value("mediaAdaptiveWidthEnabled")
            onToggled: checked => root.page.set("mediaAdaptiveWidthEnabled", checked)
        }

        SettingsToggleRow {
            visible: root.controls
            text: I18n.tr("Lyrics", "Media player lyrics button")
            description: I18n.tr("Shows the line being sung instead of the title and artist while synced lyrics are available", "media widget lyrics toggle description")
            checked: root.page.value("mediaShowLyrics")
            onToggled: checked => root.page.set("mediaShowLyrics", checked)
        }

        SettingsToggleRow {
            visible: root.controls && root.page.value("mediaShowLyrics")
            text: I18n.tr("Smooth lyrics highlight", "Media player option that fills each sung word gradually instead of highlighting it at once")
            checked: root.page.value("mediaSmoothLyrics")
            onToggled: checked => root.page.set("mediaSmoothLyrics", checked)
        }

        SettingsToggleRow {
            visible: root.controls
            text: I18n.tr("Cover art", "media widget option showing the album cover in the pill")
            checked: root.page.value("mediaShowCoverArt")
            onToggled: checked => root.page.set("mediaShowCoverArt", checked)
        }

        SettingsButtonGroupRow {
            visible: !root.controls
            settingKey: "barWidgetMusicArtworkShape"
            tags: ["media", "music", "artwork", "album", "cover", "shape", "rounded", "circle", "square"]
            resetStore: root.page
            resetKeys: ["mediaArtworkShape"]
            text: I18n.tr("Artwork")
            description: I18n.tr("Shape of the album cover in the pill", "media widget artwork shape description")
            model: [I18n.tr("Rounded"), I18n.tr("Circle"), I18n.tr("Square")]
            values: ["rounded", "circle", "square"]
            value: root.page.value("mediaArtworkShape")
            fallbackValue: "rounded"
            onValueSelected: value => root.page.set("mediaArtworkShape", value)
        }

        SettingsButtonGroupRow {
            visible: !root.controls
            settingKey: "barWidgetMusicVisualizer"
            tags: ["media", "music", "visualizer", "cava", "bars", "paused", "idle"]
            resetStore: root.page
            resetKeys: ["mediaVisualizerMode"]
            text: I18n.tr("Audio visualizer")
            description: I18n.tr("While playing hides the meter when paused, so the pill narrows", "media widget visualizer mode description")
            model: [I18n.tr("Always show"), I18n.tr("While playing", "media widget visualizer option"), I18n.tr("Off")]
            values: ["always", "playing", "never"]
            value: root.page.value("mediaVisualizerMode")
            fallbackValue: "always"
            onValueSelected: value => root.page.set("mediaVisualizerMode", value)
        }

        SettingsButtonGroupRow {
            visible: !root.controls
            settingKey: "barWidgetMusicTitle"
            tags: ["media", "music", "song", "title", "track", "hide", "change"]
            resetStore: root.page
            resetKeys: ["mediaTitleMode"]
            text: I18n.tr("Title")
            description: I18n.tr("On change shows the song title for a moment when the track changes", "media widget title mode description")
            model: [I18n.tr("Always show"), I18n.tr("On change", "media widget title option"), I18n.tr("Never")]
            values: ["always", "changes", "never"]
            value: root.page.value("mediaTitleMode")
            fallbackValue: "always"
            onValueSelected: value => root.page.set("mediaTitleMode", value)
        }

        SettingsSliderRow {
            visible: !root.controls && root.page.value("mediaTitleMode") === "changes"
            settingKey: "barWidgetMusicTitleDuration"
            tags: ["media", "music", "song", "title", "duration", "timeout"]
            resetStore: root.page
            resetKeys: ["mediaTitleDuration"]
            text: I18n.tr("Duration")
            description: I18n.tr("How long the title stays after a track change", "media widget title duration description")
            minimum: 500
            maximum: 15000
            step: 100
            unit: "ms"
            value: root.page.value("mediaTitleDuration")
            onSliderValueChanged: value => root.page.set("mediaTitleDuration", value)
        }

        SettingsSliderRow {
            visible: !root.controls && root.page.value("mediaTitleMode") !== "never"
            settingKey: "barWidgetMusicTitleWidth"
            tags: ["media", "music", "song", "title", "width", "maximum", "limit", "truncate"]
            resetStore: root.page
            resetKeys: ["mediaTitleMaxWidth"]
            text: I18n.tr("Maximum title width", "media widget settings")
            description: I18n.tr("Longer titles scroll inside this width", "media widget title width description")
            minimumLabel: I18n.tr("Off")
            minimum: 0
            maximum: 480
            step: 20
            unit: "px"
            value: root.page.value("mediaTitleMaxWidth")
            onSliderValueChanged: value => root.page.set("mediaTitleMaxWidth", value)
        }

        SettingsDropdownRow {
            visible: root.controls
            resetStore: root.page
            resetKeys: ["audioScrollMode"]
            text: I18n.tr("Scroll wheel")
            options: root.scrollLabels
            currentValue: {
                const idx = root.scrollModes.indexOf(root.page.value("audioScrollMode"));
                return idx >= 0 ? root.scrollLabels[idx] : root.scrollLabels[0];
            }
            onValueChanged: value => {
                const idx = root.scrollLabels.indexOf(value);
                if (idx >= 0)
                    root.page.set("audioScrollMode", root.scrollModes[idx]);
            }
        }

        SettingsNavRow {
            iconName: "music_note"
            title: I18n.tr("Media player")
            hint: I18n.tr("Visualizer, album art, excluded players")
            onClicked: keyboard => root.page.parentModal?.navigateTo("media_player", keyboard)
        }
    }
}
