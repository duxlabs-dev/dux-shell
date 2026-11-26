import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

DContextMenu {
    id: root

    property alias notification: actions.notification
    readonly property string appName: notification?.appName ?? ""
    readonly property string ruleAppName: notification?.ruleAppName ?? ""
    readonly property string desktopEntry: notification?.desktopEntry ?? ""
    property bool canClear: false
    property bool blockArmed: false

    signal muted
    signal clearRequested

    minMenuWidth: NotificationMetrics.menuWidth
    onOpenStateChanged: {
        if (!openState) {
            blockArmed = false;
            durations.hide();
        }
    }
    menuItems: {
        const label = appName || I18n.tr("this app");
        const nowMs = NotificationService.notificationRuleNowMs;
        // Header actions only undo their own rules; a state set in the editor is changed there.
        const rulesItem = {
            type: "item",
            icon: "tune",
            text: I18n.tr("Set by a notification rule", "notification menu item, opens the rule that mutes or allows this app"),
            action: () => PopoutService.openSettingsWithTab("notification_rules")
        };
        const muteItems = SettingsData.hasOwnAppRule(ruleAppName, desktopEntry, "mute", false, nowMs) ? [
            {
                type: "item",
                icon: "notifications",
                text: I18n.tr("Unmute popups for %1", "notification menu action, %1 is the app name").arg(label),
                action: () => SettingsData.removeMuteRuleForApp(ruleAppName, desktopEntry)
            }
        ] : SettingsData.isAppMuted(ruleAppName, desktopEntry, nowMs) ? [rulesItem] : [
            {
                type: "item",
                icon: "notifications_off",
                text: I18n.tr("Mute Popups", "notification rule action option"),
                trailingIcon: I18n.isRtl ? "chevron_left" : "chevron_right",
                keepOpen: true,
                action: () => openDurations()
            }
        ];
        const ownDnd = SettingsData.hasOwnAppRule(ruleAppName, desktopEntry, "default", true, nowMs);
        const dndItem = !ownDnd && SettingsData.isAppDndBypassed(ruleAppName, desktopEntry) ? rulesItem : {
            type: "item",
            icon: "bedtime",
            text: ownDnd ? I18n.tr("Stop allowing %1 during Do Not Disturb", "notification menu action, %1 is the app name").arg(label) : I18n.tr("Allow %1 during Do Not Disturb", "notification menu action, %1 is the app name").arg(label),
            action: () => SettingsData.setAppDndBypass(ruleAppName, desktopEntry, !ownDnd)
        };
        return [
            ...muteItems,
            {
                type: "item",
                icon: "block",
                text: blockArmed ? I18n.tr("Click again to block %1", "notification header button, %1 is the app name").arg(label) : I18n.tr("Block %1", "notification header button, %1 is the app name").arg(label) + "…",
                keepOpen: !blockArmed,
                action: () => {
                    if (!blockArmed) {
                        blockArmed = true;
                        return;
                    }
                    SettingsData.addIgnoreRuleForApp(ruleAppName, desktopEntry);
                    hide();
                    muted();
                }
            },
            {
                type: "item",
                hidden: !canClear,
                icon: "cleaning_services",
                text: I18n.tr("Clear from history"),
                action: () => {
                    hide();
                    clearRequested();
                }
            },
            ...(muteItems[0] === rulesItem && dndItem === rulesItem ? [] : [dndItem]),
            {
                type: "separator"
            },
            ...actions.items.map(item => ({
                        type: "item",
                        icon: item.icon,
                        text: item.label,
                        action: () => actions.trigger(item.action)
                    }))
        ];
    }

    function openAt(anchor, popupSurface, x, y) {
        const window = anchor.QsWindow.window;
        const atPoint = x !== undefined;
        const px = atPoint ? x : 0;
        const py = atPoint ? y : anchor.height;
        // The popup band can be centred, anchored to neither edge, which screenPointOf reads as x = 0
        const local = popupSurface ? anchor.mapToItem(null, px, py) : null;
        const pos = local ? Qt.point(local.x + popupSurface.bandX, local.y + popupSurface.bandY) : QmlUtils.screenPointOf(window, anchor, px, py);
        if (!pos)
            return;
        open(window.screen, atPoint || I18n.isRtl ? pos.x : pos.x + anchor.width - effectiveMenuWidth, pos.y, false);
    }

    // Mirrors DContextMenu's on-screen clamp; the mute row is the first row, so the submenu shares the menu's top.
    function openDurations() {
        const x = Math.max(menuMargin, Math.min(contextWindow.width - effectiveMenuWidth - menuMargin, anchorX));
        const y = Math.max(menuMargin, Math.min(contextWindow.height - effectiveMenuHeight - menuMargin, anchorY));
        const fitsRight = x + effectiveMenuWidth + durations.effectiveMenuWidth <= contextWindow.width - menuMargin;
        const fitsLeft = x - durations.effectiveMenuWidth >= menuMargin;
        const toRight = I18n.isRtl ? fitsRight && !fitsLeft : fitsRight || !fitsLeft;
        durations.menuEdge = toRight ? "top" : "right";
        durations.open(targetScreen, toRight ? x + effectiveMenuWidth : x, toRight ? y : y + durations.effectiveMenuHeight / 2, keyboardNavigation);
    }

    function mute(minutes) {
        SettingsData.addMuteRuleForApp(ruleAppName, desktopEntry, minutes > 0 ? Date.now() + minutes * 60 * 1000 : 0);
        hide();
        muted();
    }

    DContextMenu {
        id: durations
        transientSurfaceTracker: root.transientSurfaceTracker
        // Its fullscreen backdrop covers the main menu, so any dismissal closes both.
        onOpenStateChanged: {
            if (!openState)
                root.hide();
        }
        menuItems: [
            {
                type: "item",
                icon: "schedule",
                text: I18n.tr("For 1 hour", "timed preset menu option"),
                action: () => root.mute(60)
            },
            {
                type: "item",
                icon: "schedule",
                text: I18n.tr("For %1", "timed preset menu option, %1 is a duration such as 15 minutes").arg(I18n.duration(14400)),
                action: () => root.mute(4 * 60)
            },
            {
                type: "item",
                icon: "notifications_off",
                text: I18n.tr("Forever"),
                action: () => root.mute(0)
            }
        ]
    }

    NotificationActions {
        id: actions
    }

    Timer {
        interval: 3000
        running: root.blockArmed
        onTriggered: root.blockArmed = false
    }

    Connections {
        target: PopoutManager

        function onPopoutOpening() {
            root.hide();
        }
    }
}
