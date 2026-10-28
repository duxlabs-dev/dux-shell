import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsCard {
    id: root

    required property var store
    property string keyPrefix: "island"
    property bool hosted: false
    property bool docked: true
    // A dot's compact face is a circle, so it never shows the media face.
    property bool isDot: false

    readonly property var routingValues: ["normal", "always", "last-used"]
    readonly property var interactionModeValues: ["click", "hybrid"]
    readonly property var routeActivities: ["launcher", "controlcenter", "notificationcenter", "clipboard", "powermenu", "home", "media", "weather", "wallpaper"]
    readonly property var routeKeys: routeActivities.map(activity => SettingsData.islandRouteKey(activity))
    readonly property string sharedRouting: SettingsData.islandSharedRoutingMode(root.store.config)

    iconName: "touch_app"
    title: I18n.tr("Behavior", "island settings: behavior card title")
    settingKey: root.keyPrefix + "Interaction"
    tags: ["island", "interaction", "click", "hybrid", "expand", "hover", "delay", "routing", "shortcuts"]

    SettingsDropdownRow {
        settingKey: root.keyPrefix + "SharedRouting"
        tags: ["island", "routing", "launcher", "dash", "control center", "ipc", "last used"]
        visible: !root.hosted
        resetStore: root.store
        resetKeys: ["islandSharedRouting"]
        text: I18n.tr("Shared shortcuts", "island settings dropdown label, which island handles global shortcuts")
        description: I18n.tr("Routes launcher, dash, control center and notification shortcuts. Bar widget clicks always open their own popout", "shared shortcuts dropdown description")
        options: [I18n.tr("Normal routing", "shared shortcuts option, shortcuts open where they normally would"), I18n.tr("Always here", "shared shortcuts option, shortcuts always open on this island"), I18n.tr("Last used on this screen", "shared shortcuts option, shortcuts open on the island last used on this display")]
        dropdownWidth: Theme.smallBreakpoint / 2
        currentValue: options[Math.max(0, root.routingValues.indexOf(root.sharedRouting))]
        onValueChanged: value => SettingsData.setIslandSharedRouting(root.store.config?.id ?? "", root.routingValues[options.indexOf(value)] ?? "normal")
    }

    SettingsRow {
        settingKey: root.keyPrefix + "RouteActivities"
        tags: ["island", "routing", "shortcuts", "launcher", "control center", "notification center", "clipboard", "power menu", "dashboard", "media", "weather", "wallpaper", "ipc"]
        visible: root.hosted || root.sharedRouting !== "always"
        resetStore: root.store
        resetKeys: root.routeKeys
        title: root.hosted ? I18n.tr("Open in the Island", "island widget settings: activities routed to the island") : I18n.tr("Always open here", "island settings: activities pinned to this island")
        subtitle: root.hosted ? I18n.tr("The rest open the bar's own popouts", "island widget settings: unselected activities use the bar") : I18n.tr("The rest follow the shared rule", "island settings: unselected activities follow shared shortcuts")
    }

    IslandRouteRow {
        settingKey: root.keyPrefix + "RouteLauncher"
        store: root.store
        hosted: root.hosted
        activity: "launcher"
        text: I18n.tr("Launcher")
    }

    IslandRouteRow {
        settingKey: root.keyPrefix + "RouteControlCenter"
        store: root.store
        hosted: root.hosted
        activity: "controlcenter"
        text: I18n.tr("Control Center")
    }

    IslandRouteRow {
        settingKey: root.keyPrefix + "RouteNotificationCenter"
        store: root.store
        hosted: root.hosted
        activity: "notificationcenter"
        text: I18n.tr("Notification Center")
    }

    IslandRouteRow {
        settingKey: root.keyPrefix + "RouteClipboard"
        store: root.store
        hosted: root.hosted
        activity: "clipboard"
        text: I18n.tr("Clipboard")
    }

    IslandRouteRow {
        settingKey: root.keyPrefix + "RoutePowerMenu"
        store: root.store
        hosted: root.hosted
        activity: "powermenu"
        text: I18n.tr("Power menu", "island settings: route the power menu to the island")
    }

    IslandRouteRow {
        settingKey: root.keyPrefix + "RouteDash"
        store: root.store
        hosted: root.hosted
        activity: "home"
        text: I18n.tr("Dashboard")
    }

    IslandRouteRow {
        settingKey: root.keyPrefix + "RouteMedia"
        store: root.store
        hosted: root.hosted
        activity: "media"
        text: I18n.tr("Media")
    }

    IslandRouteRow {
        settingKey: root.keyPrefix + "RouteWeather"
        store: root.store
        hosted: root.hosted
        activity: "weather"
        text: I18n.tr("Weather")
    }

    IslandRouteRow {
        settingKey: root.keyPrefix + "RouteWallpaper"
        store: root.store
        hosted: root.hosted
        activity: "wallpaper"
        text: I18n.tr("Wallpapers")
    }

    SettingsButtonGroupRow {
        settingKey: root.keyPrefix + "InteractionMode"
        tags: ["island", "interaction", "click", "hybrid", "expand"]
        visible: root.docked
        resetStore: root.store
        resetKeys: ["islandInteractionMode"]
        text: I18n.tr("Expansion mode", "island settings: click or hover expansion row")
        model: [I18n.tr("Click", "island settings: click expansion mode"), I18n.tr("Hybrid", "island settings: hover plus click expansion mode")]
        values: root.interactionModeValues
        value: root.store.setting("islandInteractionMode")
        fallbackValue: "hybrid"
        onValueSelected: value => root.store.apply("islandInteractionMode", value)
    }

    SettingsRow {
        visible: root.docked && root.store.setting("islandInteractionMode") !== "click"
        body: StyledText {
            width: parent.width
            text: I18n.tr("Hybrid peeks the current compact face on hover. Click pins a destination so it stays open", "island settings: hybrid mode hint")
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
        }
    }

    SettingsSliderRow {
        settingKey: root.keyPrefix + "HoverOpenDelay"
        tags: ["island", "interaction", "hover", "open", "delay"]
        resetStore: root.store
        resetKeys: ["islandHoverOpenDelay"]
        text: I18n.tr("Open delay", "island settings: hover open delay slider")
        unit: "ms"
        minimum: 0
        maximum: 1000
        step: 10
        value: root.store.setting("islandHoverOpenDelay")
        visible: root.docked && root.store.setting("islandInteractionMode") !== "click"
        onSliderDragFinished: value => root.store.apply("islandHoverOpenDelay", value)
    }

    SettingsSliderRow {
        settingKey: root.keyPrefix + "HoverCloseDelay"
        tags: ["island", "interaction", "hover", "close", "delay"]
        resetStore: root.store
        resetKeys: ["islandHoverCloseDelay"]
        text: I18n.tr("Hide delay", "island settings: hover hide delay slider")
        unit: "ms"
        minimum: 0
        maximum: 1000
        step: 10
        value: root.store.setting("islandHoverCloseDelay")
        visible: root.docked && root.store.setting("islandInteractionMode") !== "click"
        onSliderDragFinished: value => root.store.apply("islandHoverCloseDelay", value)
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "MediaClockVisible"
        tags: ["island", "media", "clock", "compact", "time"]
        visible: !root.isDot
        text: I18n.tr("Keep clock with media", "island settings: clock in media face toggle")
        checked: root.store.setting("islandMediaClockVisible")
        onToggled: checked => root.store.apply("islandMediaClockVisible", checked)
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "MediaLyrics"
        tags: ["island", "media", "lyrics", "compact"]
        visible: !root.isDot
        text: I18n.tr("Lyrics", "Media player lyrics button")
        description: I18n.tr("Shows the line being sung instead of the title and artist while synced lyrics are available", "media widget lyrics toggle description")
        checked: root.store.setting("islandMediaLyrics")
        onToggled: checked => root.store.apply("islandMediaLyrics", checked)
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "MediaAutoSwitch"
        tags: ["island", "media", "playback", "auto", "switch", "compact"]
        visible: !root.isDot
        text: I18n.tr("Switch to media when playback starts", "island settings: auto-switch the compact face to media toggle")
        checked: root.store.setting("islandMediaAutoSwitch")
        onToggled: checked => root.store.apply("islandMediaAutoSwitch", checked)
    }
}
