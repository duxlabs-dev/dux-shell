import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../../Common/htmlElide.js" as HtmlElide

QtObject {
    id: root
    property string dismissText: I18n.tr("Dismiss")
    // null once the clicked notification closes; rule actions drop out with it
    property var notification: null
    readonly property string appName: notification?.appName ?? ""
    readonly property string ruleAppName: notification?.ruleAppName ?? ""
    readonly property string desktopEntry: notification?.desktopEntry ?? ""
    readonly property string copyText: [notification?.summary, notification?.body].map(text => HtmlElide.stripHtmlTags((text || "").replace(/<br\s*\/?>/gi, "\n")).trim()).filter(text => text).join("\n")
    // nowMs comes from NotificationService's ticking clock so these
    // bindings refresh every minute and flip the moment a timed mute lapses
    // (a raw Date.now() in a binding is not reactive and would freeze).
    readonly property bool isMuted: !!notification && SettingsData.isAppMuted(ruleAppName, desktopEntry, NotificationService.notificationRuleNowMs)
    // double, not int: epoch milliseconds exceed the 32-bit QML int range
    readonly property double muteExpiresAt: notification ? SettingsData.muteExpiresAt(ruleAppName, desktopEntry, NotificationService.notificationRuleNowMs) : 0
    readonly property bool isDndBypassed: !!notification && SettingsData.isAppDndBypassed(ruleAppName, desktopEntry)
    signal dismissRequested
    signal appMuted

    readonly property string muteRemainingSuffix: {
        if (!isMuted || muteExpiresAt <= 0)
            return "";
        const remainingText = NotificationService.formatRuleRemaining(muteExpiresAt);
        return remainingText ? I18n.tr(" (%1 left)", "notification menu, %1 = remaining time until a timed mute expires").arg(remainingText) : "";
    }

    readonly property var items: {
        const list = notification ? _ruleItems() : [];
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

    function _ruleItems() {
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
            const muteLabel = I18n.tr("Mute popups for %1", "notification menu action, %1 is the app name").arg(appName || I18n.tr("this app"));
            list.push({
                icon: "notifications_off",
                label: muteLabel + " (" + I18n.duration(3600) + ")",
                action: "mute_1h"
            });
            list.push({
                icon: "notifications_off",
                label: muteLabel + " (" + I18n.duration(14400) + ")",
                action: "mute_4h"
            });
            list.push({
                icon: "notifications_off",
                label: muteLabel,
                action: "mute"
            });
        }
        list.push({
            icon: isDndBypassed ? "do_not_disturb_on" : "do_not_disturb_off",
            label: isDndBypassed ? I18n.tr("Block %1 in Do Not Disturb", "notification menu action, %1 is the app name").arg(appName || I18n.tr("this app")) : I18n.tr("Allow %1 in Do Not Disturb", "notification menu action, %1 is the app name").arg(appName || I18n.tr("this app")),
            action: "dnd"
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
            SettingsData.requestNotificationRuleForNotification(ruleAppName, desktopEntry);
            PopoutService.openSettingsWithTab("notification_rules");
            return;
        case "mute":
            if (isMuted) {
                SettingsData.removeMuteRuleForApp(ruleAppName, desktopEntry);
                return;
            }
            SettingsData.addMuteRuleForApp(ruleAppName, desktopEntry);
            appMuted();
            return;
        case "mute_1h":
            SettingsData.addMuteRuleForApp(ruleAppName, desktopEntry, Date.now() + 60 * 60 * 1000);
            appMuted();
            return;
        case "mute_4h":
            SettingsData.addMuteRuleForApp(ruleAppName, desktopEntry, Date.now() + 4 * 60 * 60 * 1000);
            appMuted();
            return;
        case "dnd":
            SettingsData.setAppDndBypass(ruleAppName, desktopEntry, !isDndBypassed);
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
