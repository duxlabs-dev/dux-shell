pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var focusedColorOptions: []
    property var occupiedColorOptions: []
    property var unfocusedColorOptions: []
    property var urgentColorOptions: []

    property bool occupiedColorVisible: true
    property bool urgentColorVisible: true

    property string focusedColorModeKey: ""
    property string focusedCustomColorKey: ""
    property string occupiedColorModeKey: ""
    property string occupiedCustomColorKey: ""
    property string unfocusedColorModeKey: ""
    property string unfocusedCustomColorKey: ""
    property string urgentColorModeKey: ""
    property string urgentCustomColorKey: ""

    property var extraTags: []
    property var store: null

    width: parent?.width ?? 0
    spacing: Theme.spacingM

    ColorDropdownRow {
        text: I18n.tr("Focused color")
        settingKey: root.focusedColorModeKey
        tags: ["workspace", "focused", "color", "custom"].concat(root.extraTags)
        options: root.focusedColorOptions
        resetStore: root.store
        resetKeys: [root.focusedColorModeKey, root.focusedCustomColorKey]
        currentMode: root.store.get(root.focusedColorModeKey)
        customColor: root.store.get(root.focusedCustomColorKey) || "#6750A4"
        onModeSelected: mode => root.store.set(root.focusedColorModeKey, mode)
        onCustomColorSelected: selectedColor => root.store.set(root.focusedCustomColorKey, selectedColor.toString())
    }

    SettingsDivider {}

    ColorDropdownRow {
        text: I18n.tr("Occupied color")
        settingKey: root.occupiedColorModeKey
        tags: ["workspace", "occupied", "color", "custom"].concat(root.extraTags)
        visible: root.occupiedColorVisible
        options: root.occupiedColorOptions
        resetStore: root.store
        resetKeys: [root.occupiedColorModeKey, root.occupiedCustomColorKey]
        currentMode: root.store.get(root.occupiedColorModeKey)
        customColor: root.store.get(root.occupiedCustomColorKey) || "#625B71"
        onModeSelected: mode => root.store.set(root.occupiedColorModeKey, mode)
        onCustomColorSelected: selectedColor => root.store.set(root.occupiedCustomColorKey, selectedColor.toString())
    }

    SettingsDivider {
        visible: root.occupiedColorVisible
    }

    ColorDropdownRow {
        text: I18n.tr("Unfocused color")
        settingKey: root.unfocusedColorModeKey
        tags: ["workspace", "unfocused", "color", "custom"].concat(root.extraTags)
        options: root.unfocusedColorOptions
        defaultColor: Theme.surfaceText
        resetStore: root.store
        resetKeys: [root.unfocusedColorModeKey, root.unfocusedCustomColorKey]
        currentMode: root.store.get(root.unfocusedColorModeKey)
        customColor: root.store.get(root.unfocusedCustomColorKey) || "#49454E"
        onModeSelected: mode => root.store.set(root.unfocusedColorModeKey, mode)
        onCustomColorSelected: selectedColor => root.store.set(root.unfocusedCustomColorKey, selectedColor.toString())
    }

    SettingsDivider {
        visible: root.urgentColorVisible
    }

    ColorDropdownRow {
        text: I18n.tr("Urgent color")
        settingKey: root.urgentColorModeKey
        tags: ["workspace", "urgent", "color", "custom"].concat(root.extraTags)
        visible: root.urgentColorVisible
        options: root.urgentColorOptions
        defaultColor: Theme.error
        resetStore: root.store
        resetKeys: [root.urgentColorModeKey, root.urgentCustomColorKey]
        currentMode: root.store.get(root.urgentColorModeKey)
        customColor: root.store.get(root.urgentCustomColorKey) || "#B3261E"
        onModeSelected: mode => root.store.set(root.urgentColorModeKey, mode)
        onCustomColorSelected: selectedColor => root.store.set(root.urgentCustomColorKey, selectedColor.toString())
    }
}
