import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var parentModal: null

    readonly property bool frameForcesOverlay: Quickshell.screens.length > 0 && Quickshell.screens.every(screen => CompositorService.frameWindowVisibleForScreen(screen))

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    function indexedRules(predicate) {
        return (SettingsData.notificationRules || []).map((rule, index) => ({
                    rule: rule,
                    index: index
                })).filter(entry => predicate(entry.rule));
    }

    readonly property var dndBypassRules: indexedRules(rule => rule.bypassDnd === true)

    readonly property var timeoutOptions: [
        {
            text: I18n.tr("Never"),
            value: 0
        },
        {
            text: I18n.duration(1),
            value: 1000
        },
        {
            text: I18n.duration(3),
            value: 3000
        },
        {
            text: I18n.duration(5),
            value: 5000
        },
        {
            text: I18n.duration(8),
            value: 8000
        },
        {
            text: I18n.duration(10),
            value: 10000
        },
        {
            text: I18n.duration(15),
            value: 15000
        },
        {
            text: I18n.duration(30),
            value: 30000
        },
        {
            text: I18n.duration(60),
            value: 60000
        },
        {
            text: I18n.duration(120),
            value: 120000
        },
        {
            text: I18n.duration(300),
            value: 300000
        },
        {
            text: I18n.duration(600),
            value: 600000
        }
    ]

    function getTimeoutText(value) {
        if (value === undefined || value === null || isNaN(value))
            return I18n.duration(5);
        for (let i = 0; i < timeoutOptions.length; i++) {
            if (timeoutOptions[i].value === value)
                return timeoutOptions[i].text;
        }
        if (value === 0)
            return I18n.tr("Never");
        return I18n.duration(value / 1000);
    }

    function applyTimeout(key, text) {
        const option = timeoutOptions.find(opt => opt.text === text);
        if (option)
            SettingsData.set(key, option.value);
    }

    SettingsCard {
        iconName: "notifications"
        title: I18n.tr("Popups", "notification settings card title, popup notifications")
        settingKey: "notificationPopups"

        headerActions: DButton {
            text: I18n.tr("Preview")
            buttonHeight: Theme.buttonHeightXS
            onClicked: NotificationService.sendTestNotifications()
        }

        SettingsDropdownRow {
            settingKey: "notificationPopupPosition"
            tags: ["notification", "popup", "position", "screen", "location"]
            text: I18n.tr("Position")
            currentValue: {
                if (SettingsData.notificationPopupPosition === -1)
                    return I18n.tr("Top Center", "screen position option");
                switch (SettingsData.notificationPopupPosition) {
                case SettingsData.Position.Top:
                    return I18n.tr("Top Right", "screen position option");
                case SettingsData.Position.Bottom:
                    return I18n.tr("Bottom Left", "screen position option");
                case SettingsData.Position.Left:
                    return I18n.tr("Top Left", "screen position option");
                case SettingsData.Position.Right:
                    return I18n.tr("Bottom Right", "screen position option");
                case SettingsData.Position.BottomCenter:
                    return I18n.tr("Bottom Center", "screen position option");
                default:
                    return I18n.tr("Top Right", "screen position option");
                }
            }
            options: [I18n.tr("Top Right", "screen position option"), I18n.tr("Top Left", "screen position option"), I18n.tr("Top Center", "screen position option"), I18n.tr("Bottom Center", "screen position option"), I18n.tr("Bottom Right", "screen position option"), I18n.tr("Bottom Left", "screen position option")]
            onValueChanged: value => {
                switch (value) {
                case I18n.tr("Top Right", "screen position option"):
                    SettingsData.set("notificationPopupPosition", SettingsData.Position.Top);
                    break;
                case I18n.tr("Top Left", "screen position option"):
                    SettingsData.set("notificationPopupPosition", SettingsData.Position.Left);
                    break;
                case I18n.tr("Top Center", "screen position option"):
                    SettingsData.set("notificationPopupPosition", -1);
                    break;
                case I18n.tr("Bottom Center", "screen position option"):
                    SettingsData.set("notificationPopupPosition", SettingsData.Position.BottomCenter);
                    break;
                case I18n.tr("Bottom Right", "screen position option"):
                    SettingsData.set("notificationPopupPosition", SettingsData.Position.Right);
                    break;
                case I18n.tr("Bottom Left", "screen position option"):
                    SettingsData.set("notificationPopupPosition", SettingsData.Position.Bottom);
                    break;
                }
                NotificationService.sendTestNotifications();
            }
        }

        SettingsToggleRow {
            settingKey: "notificationFocusedMonitor"
            tags: ["notification", "popup", "focused", "monitor", "display", "screen", "active"]
            text: I18n.tr("Focused display only")
            checked: SettingsData.notificationFocusedMonitor
            onToggled: checked => SettingsData.set("notificationFocusedMonitor", checked)
        }

        SettingsToggleRow {
            settingKey: "notificationOverlayEnabled"
            tags: ["notification", "overlay", "fullscreen", "priority"]
            text: I18n.tr("Over fullscreen")
            enabled: !root.frameForcesOverlay
            checked: root.frameForcesOverlay || SettingsData.notificationOverlayEnabled
            onToggled: checked => SettingsData.set("notificationOverlayEnabled", checked)
        }

        SettingsToggleRow {
            settingKey: "notificationCompactMode"
            tags: ["notification", "compact", "size", "display", "mode"]
            text: I18n.tr("Compact")
            checked: SettingsData.notificationCompactMode
            onToggled: checked => SettingsData.set("notificationCompactMode", checked)
        }

        SettingsToggleRow {
            settingKey: "notificationDedupeEnabled"
            tags: ["notification", "duplicate", "dedupe", "stack", "coalesce", "repeat"]
            text: I18n.tr("Suppress duplicates")
            checked: SettingsData.notificationDedupeEnabled
            onToggled: checked => SettingsData.set("notificationDedupeEnabled", checked)
        }

        SettingsToggleRow {
            settingKey: "notificationPopupBodyInvokesAction"
            tags: ["notification", "popup", "click", "body", "action", "invoke", "expand", "open"]
            text: I18n.tr("Body click runs default action")
            checked: SettingsData.notificationPopupBodyInvokesAction
            onToggled: checked => SettingsData.set("notificationPopupBodyInvokesAction", checked)
        }
    }

    SettingsCard {
        title: I18n.tr("Timeouts", "notification settings card title, popup dismiss times per urgency")
        settingKey: "notificationTimeouts"
        tags: ["notification", "timeout", "duration", "expire", "priority"]

        SettingsDropdownRow {
            settingKey: "notificationTimeoutLow"
            tags: ["notification", "timeout", "low", "priority", "duration"]
            text: I18n.tr("Low")
            currentValue: root.getTimeoutText(SettingsData.notificationTimeoutLow)
            options: root.timeoutOptions.map(opt => opt.text)
            onValueChanged: value => root.applyTimeout("notificationTimeoutLow", value)
        }

        SettingsDropdownRow {
            settingKey: "notificationTimeoutNormal"
            tags: ["notification", "timeout", "normal", "priority", "duration"]
            text: I18n.tr("Normal")
            currentValue: root.getTimeoutText(SettingsData.notificationTimeoutNormal)
            options: root.timeoutOptions.map(opt => opt.text)
            onValueChanged: value => root.applyTimeout("notificationTimeoutNormal", value)
        }

        SettingsDropdownRow {
            settingKey: "notificationTimeoutCritical"
            tags: ["notification", "timeout", "critical", "priority", "duration"]
            text: I18n.tr("Critical", "adjective, critical notification urgency row label")
            currentValue: root.getTimeoutText(SettingsData.notificationTimeoutCritical)
            options: root.timeoutOptions.map(opt => opt.text)
            onValueChanged: value => root.applyTimeout("notificationTimeoutCritical", value)
        }

        SettingsToggleRow {
            settingKey: "notificationIgnoreAppTimeout"
            tags: ["notification", "timeout", "expire", "app", "override", "duration"]
            text: I18n.tr("Ignore app-requested timeout")
            checked: SettingsData.notificationIgnoreAppTimeout
            onToggled: checked => SettingsData.set("notificationIgnoreAppTimeout", checked)
        }

        SettingsToggleRow {
            settingKey: "notificationShowTimeoutBar"
            tags: ["notification", "timeout", "progress", "bar", "timer", "countdown"]
            text: I18n.tr("Timeout progress bar")
            checked: SettingsData.notificationShowTimeoutBar
            onToggled: checked => SettingsData.set("notificationShowTimeoutBar", checked)
        }
    }

    SettingsCard {
        iconName: "notifications_off"
        title: I18n.tr("Do not disturb")
        settingKey: "doNotDisturb"

        SettingsToggleRow {
            settingKey: "doNotDisturb"
            tags: ["notification", "dnd", "mute", "silent", "suppress"]
            text: I18n.tr("Do not disturb")
            checked: SessionData.doNotDisturb
            onToggled: checked => SessionData.setDoNotDisturb(checked)
        }

        SettingsToggleRow {
            settingKey: "notificationDndWhileScreenSharing"
            tags: ["notification", "dnd", "screenshare", "sharing", "privacy"]
            text: I18n.tr("Automatically enable while screen sharing", "do not disturb auto enable while screen sharing toggle")
            checked: SettingsData.notificationDndWhileScreenSharing
            onToggled: checked => SettingsData.set("notificationDndWhileScreenSharing", checked)
        }

        SettingsToggleRow {
            settingKey: "notificationDndAllowCritical"
            tags: ["notification", "dnd", "critical", "priority", "urgent", "bypass"]
            text: I18n.tr("Allow critical")
            description: I18n.tr("Critical notifications still pop up", "do not disturb allow critical toggle description")
            checked: SettingsData.notificationDndAllowCritical
            onToggled: checked => SettingsData.set("notificationDndAllowCritical", checked)
        }

        SettingsRow {
            subtitle: I18n.tr("Right-click a notification and choose \"Allow in Do Not Disturb\" to add an app")
        }

        Repeater {
            model: root.dndBypassRules

            delegate: SettingsRow {
                required property var modelData

                title: modelData.rule?.pattern || I18n.tr("Unknown")
                singleLineTitle: true

                DActionButton {
                    iconName: "delete"
                    iconColor: Theme.error
                    tooltipText: I18n.tr("Remove")
                    onClicked: SettingsData.removeNotificationRule(modelData.index)
                }
            }
        }
    }

    SettingsCard {
        settingKey: "notificationLinks"

        SettingsNavRow {
            iconName: "rule_settings"
            title: I18n.tr("Rules")
            hint: SettingsTabs.page("notification_rules")?.hint ?? ""
            onClicked: keyboard => root.parentModal?.navigateTo("notification_rules", keyboard)
        }
    }

    SettingsCard {
        iconName: "visibility_off"
        title: I18n.tr("Privacy", "notification settings card title")
        settingKey: "notificationPrivacy"
        tags: ["notification", "privacy", "hide", "content", "lock"]

        SettingsToggleRow {
            settingKey: "notificationPopupPrivacyMode"
            tags: ["notification", "popup", "privacy", "body", "content", "hide"]
            text: I18n.tr("Privacy mode")
            description: I18n.tr("Popups hide the message until expanded", "notification privacy mode toggle description")
            checked: SettingsData.notificationPopupPrivacyMode
            onToggled: checked => SettingsData.set("notificationPopupPrivacyMode", checked)
        }

        SettingsDropdownRow {
            readonly property var lockNotifications: SettingsData.lockWidgetInstance("lockNotifications")
            readonly property int currentMode: !lockNotifications || lockNotifications.enabled === false ? 0 : (lockNotifications.config?.mode ?? 1)

            settingKey: "lockNotificationsMode"
            tags: ["lock", "screen", "notification", "notifications", "privacy"]
            visible: lockNotifications !== null
            text: I18n.tr("Lock screen content")
            options: [I18n.tr("Disabled", "lock screen notification mode option"), I18n.tr("Count only", "lock screen notification mode option"), I18n.tr("App names", "lock screen notification mode option"), I18n.tr("Full content", "lock screen notification mode option")]
            currentValue: options[currentMode] || options[0]
            onValueChanged: value => {
                const idx = options.indexOf(value);
                if (idx < 0)
                    return;
                SettingsData.updateDesktopWidgetInstance(lockNotifications.id, {
                    enabled: idx > 0
                });
                if (idx > 0)
                    SettingsData.updateDesktopWidgetInstanceConfig(lockNotifications.id, {
                        mode: idx
                    });
            }
        }
    }

    SettingsCard {
        iconName: "history"
        title: I18n.tr("History")
        settingKey: "notificationHistory"

        SettingsToggleRow {
            settingKey: "notificationHistoryEnabled"
            tags: ["notification", "history", "enable", "disable", "save"]
            text: I18n.tr("History")
            checked: SettingsData.notificationHistoryEnabled
            onToggled: checked => SettingsData.set("notificationHistoryEnabled", checked)
        }

        SettingsDropdownRow {
            settingKey: "notificationHistoryMaxAgeDays"
            tags: ["notification", "history", "max", "age", "days", "retention"]
            text: I18n.tr("Retention", "notification history setting label, how long entries are kept")
            readonly property var retentionDays: [0, 1, 3, 7, 14, 30]
            options: retentionDays.map(days => days === 0 ? I18n.tr("Forever", "notification history retention option") : I18n.duration(days * 86400))
            currentValue: {
                const index = retentionDays.indexOf(SettingsData.notificationHistoryMaxAgeDays);
                return index >= 0 ? options[index] : I18n.duration(SettingsData.notificationHistoryMaxAgeDays * 86400);
            }
            onValueChanged: value => {
                const index = options.indexOf(value);
                SettingsData.set("notificationHistoryMaxAgeDays", index >= 0 ? retentionDays[index] : 7);
            }
        }

        SettingsSliderRow {
            settingKey: "notificationHistoryMaxCount"
            tags: ["notification", "history", "max", "count", "limit"]
            text: I18n.tr("Maximum entries")
            value: SettingsData.notificationHistoryMaxCount
            minimum: 10
            maximum: 200
            step: 10
            unit: ""
            onSliderValueChanged: newValue => SettingsData.set("notificationHistoryMaxCount", newValue)
        }

        SettingsToggleRow {
            settingKey: "notificationHistorySaveLow"
            tags: ["notification", "history", "save", "low", "priority"]
            text: I18n.tr("Low")
            checked: SettingsData.notificationHistorySaveLow
            onToggled: checked => SettingsData.set("notificationHistorySaveLow", checked)
        }

        SettingsToggleRow {
            settingKey: "notificationHistorySaveNormal"
            tags: ["notification", "history", "save", "normal", "priority"]
            text: I18n.tr("Normal")
            checked: SettingsData.notificationHistorySaveNormal
            onToggled: checked => SettingsData.set("notificationHistorySaveNormal", checked)
        }

        SettingsToggleRow {
            settingKey: "notificationHistorySaveCritical"
            tags: ["notification", "history", "save", "critical", "priority"]
            text: I18n.tr("Critical")
            checked: SettingsData.notificationHistorySaveCritical
            onToggled: checked => SettingsData.set("notificationHistorySaveCritical", checked)
        }
    }

    SettingsCard {
        iconName: "palette"
        title: I18n.tr("Appearance")
        settingKey: "notificationAppearance"
        tags: ["notification", "font", "size", "layers", "animation", "speed"]

        SettingsDropdownRow {
            settingKey: "notificationSummaryFontSize"
            tags: ["notification", "font", "summary", "size"]
            text: I18n.tr("Summary font size")
            options: [I18n.tr("Unset"), "10", "12", "14", "16", "18"]
            currentValue: (SettingsData.notificationSummaryFontSize || I18n.tr("Unset")).toString()
            onValueChanged: value => {
                SettingsData.set("notificationSummaryFontSize", Number(value === I18n.tr("Unset") ? 0 : value));
                NotificationService.sendTestNotifications();
            }
        }

        SettingsDropdownRow {
            settingKey: "notificationBodyFontSize"
            tags: ["notification", "font", "body", "size"]
            text: I18n.tr("Body font size")
            options: [I18n.tr("Unset"), "10", "12", "14", "16", "18"]
            currentValue: (SettingsData.notificationBodyFontSize || I18n.tr("Unset")).toString()
            onValueChanged: value => {
                SettingsData.set("notificationBodyFontSize", Number(value === I18n.tr("Unset") ? 0 : value));
                NotificationService.sendTestNotifications();
            }
        }

        SettingsToggleRow {
            settingKey: "notificationForegroundLayers"
            tags: ["notification", "foreground", "layers", "surface", "blur", "glass", "contrast", "cards"]
            text: I18n.tr("Foreground layers")
            checked: SettingsData.notificationForegroundLayers ?? true
            onToggled: checked => SettingsData.set("notificationForegroundLayers", checked)
        }

        SettingsSliderRow {
            settingKey: "notificationAnimationDuration"
            tags: ["notification", "animation", "duration", "speed"]
            text: I18n.tr("Animation duration")
            minimumLabel: I18n.tr("Off")
            minimum: 0
            maximum: 800
            value: SettingsData.notificationAnimationDuration
            unit: "ms"
            onSliderValueChanged: newValue => SettingsData.set("notificationAnimationDuration", newValue)
        }
    }
}
