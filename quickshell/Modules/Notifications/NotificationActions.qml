import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../../Common/htmlElide.js" as HtmlElide

QtObject {
    id: root
    property string appName: ""
    property string desktopEntry: ""
    property string dismissText: I18n.tr("Dismiss")
    property var notification: null
    readonly property string copyText: [notification?.summary, notification?.body].map(text => HtmlElide.stripHtmlTags((text || "").replace(/<br\s*\/?>/gi, "\n")).trim()).filter(text => text).join("\n")
    // nowMs comes from NotificationService's ticking clock so these
    // bindings refresh every minute and flip the moment a timed mute lapses
    // (a raw Date.now() in a binding is not reactive and would freeze).
    readonly property bool isMuted: SettingsData.isAppMuted(appName, desktopEntry, NotificationService.notificationRuleNowMs)
    // double, not int: epoch milliseconds exceed the 32-bit QML int range
    readonly property double muteExpiresAt: SettingsData.muteExpiresAt(appName, desktopEntry, NotificationService.notificationRuleNowMs)
    readonly property bool isDndBypassed: SettingsData.isAppDndBypassed(appName, desktopEntry)
    signal dismissRequested
    signal appMuted

    readonly property string muteRemainingSuffix: {
        if (!isMuted || muteExpiresAt <= 0)
            return "";
        const remainingText = NotificationService.formatRuleRemaining(muteExpiresAt);
        return remainingText ? I18n.tr(" (%1 left)", "notification menu, %1 = remaining time until a timed mute expires").arg(remainingText) : "";
    }

    readonly property var items: {
        const list = [
            {
                icon: "tune",
                label: I18n.tr("Set notification rules"),
                action: "rules"
            }
        ];
        if (isMuted) {
            list.push({
                icon: "notifications",
                label: I18n.tr("Unmute popups for %1", "notification menu action, %1 is the app name").arg(appName || I18n.tr("this app")) + muteRemainingSuffix,
                action: "mute"
            });
        } else {
            list.push({
                icon: "notifications_off",
                label: I18n.tr("Mute popups for %1 (1 hour)", "notification menu action, %1 is the app name").arg(appName || I18n.tr("this app")),
                action: "mute_1h"
            });
            list.push({
                icon: "notifications_off",
                label: I18n.tr("Mute popups for %1 (4 hours)", "notification menu action, %1 is the app name").arg(appName || I18n.tr("this app")),
                action: "mute_4h"
            });
            list.push({
                icon: "notifications_off",
                label: I18n.tr("Mute popups for %1", "notification menu action, %1 is the app name").arg(appName || I18n.tr("this app")),
                action: "mute"
            });
        }
        list.push({
            icon: isDndBypassed ? "do_not_disturb_on" : "do_not_disturb_off",
            label: isDndBypassed ? I18n.tr("Block %1 in Do Not Disturb", "notification menu action, %1 is the app name").arg(appName || I18n.tr("this app")) : I18n.tr("Allow %1 in Do Not Disturb", "notification menu action, %1 is the app name").arg(appName || I18n.tr("this app")),
            action: "dnd"
        });
        if (root.copyText) {
            list.push({
                icon: "content_copy",
                label: I18n.tr("Copy"),
                action: "copy"
            });
        }
        list.push({
            icon: "close",
            label: root.dismissText,
            action: "dismiss"
        });
        return list;
    }

    function defaultAction(notification) {
        const actions = notification?.actions || [];
        return actions.find(action => action.identifier === "default") || actions[0] || null;
    }

    function trigger(action) {
        switch (action) {
        case "rules":
            SettingsData.requestNotificationRuleForNotification(appName, desktopEntry);
            PopoutService.openSettingsWithTab("notification_rules");
            return;
        case "mute":
            if (isMuted) {
                SettingsData.removeMuteRuleForApp(appName, desktopEntry);
                return;
            }
            SettingsData.addMuteRuleForApp(appName, desktopEntry);
            appMuted();
            return;
        case "mute_1h":
            SettingsData.addMuteRuleForApp(appName, desktopEntry, Date.now() + 60 * 60 * 1000);
            appMuted();
            return;
        case "mute_4h":
            SettingsData.addMuteRuleForApp(appName, desktopEntry, Date.now() + 4 * 60 * 60 * 1000);
            appMuted();
            return;
        case "dnd":
            SettingsData.setAppDndBypass(appName, desktopEntry, !isDndBypassed);
            return;
        case "copy":
            Quickshell.execDetached([Proc.dmsBin, "cl", "copy", copyText]);
            ToastService.showInfo(I18n.tr("Copied to clipboard"));
            return;
        case "dismiss":
            dismissRequested();
        }
    }
}
