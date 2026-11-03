import QtQuick
import qs.Common
import qs.Services

SettingsCard {
    id: root

    required property var store
    property string keyPrefix: "island"
    // A dot has no home layout editor, so its badge row must not follow the notifications group.
    property bool badgeGated: true

    iconName: "notifications"
    title: I18n.tr("Notifications", "island settings: notifications card title")
    settingKey: root.keyPrefix + "Notifications"
    tags: ["island", "notifications", "popup", "badge", "expand", "osd"]

    SettingsToggleRow {
        settingKey: root.keyPrefix + "NotificationPopups"
        tags: ["island", "notifications", "popup", "standard", "bar", "stack", "arrival"]
        text: I18n.tr("Use standard popups", "island settings: show arriving notifications as stacked popups instead of in the island")
        description: I18n.tr("New notifications show as regular popups", "island standard popups toggle description")
        checked: root.store.setting("islandNotificationPopups")
        onToggled: checked => root.store.apply("islandNotificationPopups", checked)
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "SystemOsd"
        tags: ["island", "volume", "brightness", "microphone", "caps lock", "power profile", "idle inhibitor", "osd", "level", "standard"]
        text: I18n.tr("Use standard OSDs", "island settings: show volume and brightness changes as the regular on-screen displays instead of in the island")
        checked: !root.store.setting("islandSystemOsd")
        onToggled: checked => root.store.apply("islandSystemOsd", !checked)
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "ChargingPulse"
        tags: ["island", "battery", "charging", "plugged", "power", "pulse"]
        text: I18n.tr("Charging", "island settings: pulse the island when power is connected or removed")
        description: I18n.tr("Show the battery briefly when power is connected or removed", "island settings: charging pulse toggle description")
        visible: root.store.setting("islandSystemOsd") && BatteryService.batteryAvailable
        checked: root.store.setting("islandChargingPulse")
        onToggled: checked => root.store.apply("islandChargingPulse", checked)
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "NotificationExpand"
        tags: ["island", "notifications", "expand", "arrival", "size"]
        text: I18n.tr("Expand by default", "island settings: expanded notification toggle")
        checked: root.store.setting("islandNotificationExpand")
        onToggled: checked => root.store.apply("islandNotificationExpand", checked)
    }

    SettingsToggleRow {
        settingKey: root.keyPrefix + "NotificationBadgeClearOnOpen"
        tags: ["island", "home", "notifications", "badge", "unread", "clear", "dismiss", "open"]
        text: I18n.tr("Clear badge on open", "island settings: clear the notification badge when the center opens")
        checked: root.store.setting("islandNotificationBadgeClearOnOpen")
        enabled: !root.badgeGated || SettingsData.islandHomeGroupEnabled(root.store.config, "notifications")
        onToggled: checked => root.store.apply("islandNotificationBadgeClearOnOpen", checked)
    }
}
