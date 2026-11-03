# Emoji Cycler Plugin

An example dms plugin that displays cycling emojis in your bar with an emoji picker popout.

## Features

- **Cycling Emojis**: Automatically rotates through your selected emoji set in the bar
- **Emoji Picker**: Click the widget to open a grid of 120+ emojis
- **Copy to Clipboard**: Click any emoji in the picker to copy it to clipboard
- **Customizable**: Choose emoji sets, cycle speed, and max emojis shown

## Installation

1. Copy this directory to `~/.config/dms/plugins/ExampleEmojiPlugin`
2. Open DMS Settings → Plugins
3. Click "Scan for Plugins"
4. Enable "Emoji Cycler"
5. Add `exampleEmojiPlugin` to your DankBar widget list

## Settings

### Emoji Set
Choose from different emoji collections:
- **Happy & Sad**: Mix of emotional faces
- **Hearts**: Various colored hearts
- **Hand Gestures**: Thumbs up, peace signs, etc.
- **All Mixed**: A bit of everything

### Cycle Speed
Control how fast emojis rotate (500ms - 10000ms)

### Max Bar Emojis
How many emojis to display at once (1-8)

## Usage

**In the bar**: Watch emojis cycle through automatically
**Click the widget**: Opens emoji picker with 120+ emojis
**Click any emoji**: Copies it to clipboard and shows toast

## Example Code Highlights

This plugin demonstrates:
- Using `PluginComponent` for bar integration
- `SelectionSetting`, `SliderSetting` for configuration
- Plugin-local translations (`translations/` + `I18n.trFor`)
- Timer-based animation
- Popout content with grid layout
- External command execution (`Quickshell.execDetached`)
- Toast notifications (`ToastService.show`)
- Dynamic settings loading/saving

Perfect template for creating your own DMS plugins!
